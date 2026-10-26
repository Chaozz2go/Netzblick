function Initialize-ActivityLedger {
    if(-not $script:targetLedger){$script:targetLedger=@{}}
    if(-not $script:blockBaselines){$script:blockBaselines=@{}}
}
function Get-TargetKey([string]$path,[string]$address,$protocol,$port){
    if(-not [Netzblick.AccessQueue]::CanAllow($path) -or -not $address){return ''}
    $ip=$null;if(-not [Net.IPAddress]::TryParse($address,[ref]$ip)){return ''}
    if($ip.IsIPv4MappedToIPv6){$ip=$ip.MapToIPv4()}
    $number=switch -Regex ([string]$protocol){'^TCP' {6;break} '^UDP' {17;break} '^ICMPv6' {58;break} '^ICMP' {1;break} default {[int]$protocol}}
    return [Netzblick.ProcessLineage]::Normalize($path)+'|'+$ip.ToString()+'|'+$number+'|'+[int]$port
}
function Update-ActivityLedger {
    Initialize-ActivityLedger
    $dirty=$false;$now=[datetime]::UtcNow
    $observations=@($script:rows)+@($script:trafficPeers)
    if($script:setupStatus){$observations+=@($setupStatus.Attempts)}
    foreach($p in $observations){
        if(-not $p){continue}
        $key=Get-TargetKey $p.Path $p.Address $p.Protocol $p.Port
        if(-not $key){continue}
        if(-not $targetLedger.ContainsKey($key) -and $targetLedger.Count -lt 5000){
            $targetLedger[$key]=[pscustomobject]@{Key=$key;PathKey=[Netzblick.ProcessLineage]::Normalize($p.Path);Address=$p.Address;Protocol=$p.Protocol;Port=[int]$p.Port;Reviewed=$false;FirstUtc=$now};$dirty=$true
        }
    }
    if($dirty){$script:targetReviewCounts=$null;Save-UserState}
}
function Get-ProgramActivityReview([string]$path){
    Initialize-ActivityLedger
    $key=[Netzblick.ProcessLineage]::Normalize($path)
    if($null -eq $script:targetReviewCounts){$script:targetReviewCounts=@{};foreach($entry in $targetLedger.Values){if(-not $entry.Reviewed){$script:targetReviewCounts[$entry.PathKey]++}}}
    $fresh=[int]$script:targetReviewCounts[$key]
    $blocks=[long]0
    if($script:setupStatus){
        $epoch=$setupStatus.StartedUtc.ToUniversalTime().ToString('o')
        foreach($a in @($setupStatus.Attempts | Where-Object {[Netzblick.ProcessLineage]::Normalize($_.Path) -eq $key})){
            $baseline=$blockBaselines[$a.Key]
            $seen=if($baseline -and $baseline.Epoch -eq $epoch){[long]$baseline.Count}else{0}
            $blocks+=[Math]::Max(0,[long]$a.Count-$seen)
        }
    }
    [pscustomobject]@{NewTargets=$fresh;NewBlocks=$blocks;Summary=($fresh.ToString()+' neue Ziele · '+$blocks+' ungeprüfte Blockversuche in aktueller Erfassung')}
}
function Get-TargetReviewLabel([string]$path,$row){
    Initialize-ActivityLedger
    $key=Get-TargetKey $path $row.Address $row.Protocol $row.Port
    if($key -and $targetLedger.ContainsKey($key) -and -not $targetLedger[$key].Reviewed){return 'Neues Ziel'}
    return ''
}
function Mark-ProgramActivityReviewed([string]$path){
    Update-ActivityLedger
    $key=[Netzblick.ProcessLineage]::Normalize($path)
    foreach($entry in @($targetLedger.Values | Where-Object {$_.PathKey -eq $key})){$entry.Reviewed=$true}
    $script:targetReviewCounts=$null
    if($script:setupStatus){
        $epoch=$setupStatus.StartedUtc.ToUniversalTime().ToString('o')
        foreach($a in @($setupStatus.Attempts | Where-Object {[Netzblick.ProcessLineage]::Normalize($_.Path) -eq $key})){
            if($blockBaselines.Count -lt 2000 -or $blockBaselines.ContainsKey($a.Key)){$blockBaselines[$a.Key]=[pscustomobject]@{Key=$a.Key;PathKey=$key;Epoch=$epoch;Count=[long]$a.Count}}
        }
    }
}
function Read-ProgramSnapshot([string]$json){
    $serializer=New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $method=$serializer.GetType().GetMethods() | Where-Object {$_.Name -eq 'Deserialize' -and $_.IsGenericMethodDefinition} | Select-Object -First 1
    return $method.MakeGenericMethod([Netzblick.SetupProgramState]).Invoke($serializer,@($json))
}
function Save-ProgramChange([string]$path,$before,$after,[string]$label){
    $serializer=New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $script:changes.Insert(0,[pscustomobject]@{Version=2;Path=$path;Label=$label;BeforeJson=$serializer.Serialize($before);AfterJson=$serializer.Serialize($after);TimeUtc=[datetime]::UtcNow})
    while($changes.Count -gt 20){$changes.RemoveAt($changes.Count-1)}
    Save-UserState
}
function Undo-ProgramChange($change){
    $before=Read-ProgramSnapshot $change.BeforeJson;$expected=Read-ProgramSnapshot $change.AfterJson
    [void](Send-SetupCommand ([Netzblick.SetupCommand]@{Operation='RestoreProgram';BeforeProgram=$before;ExpectedProgram=$expected}))
    $script:changes.Remove($change);Save-UserState;Update-AccessMode;Refresh-Overview;Refresh-Detail
    $ui.UserNotice.Text='Rückgängig: '+[IO.Path]::GetFileName($change.Path)+' · vorherige Programmregeln wiederhergestellt.'
}
function Update-QuickActions {
    foreach($prefix in @('Overview','Program')){
        $p=if($prefix -eq 'Overview'){$ui.OverviewPrograms.SelectedItem}else{$ui.Programs.SelectedItem}
        $valid=$p -and [Netzblick.AccessQueue]::CanAllow($p.Path)
        $ready=$valid -and $script:setupStatus -and $setupStatus.Verified -and [IO.File]::Exists($p.Path) -and -not(Is-Protected $p.Path)
        $state=if($valid){Get-PermissionStatus $p.Path}else{$null}
        $lease=if($valid -and $script:setupStatus){$setupStatus.Config.ProgramLeases | Where-Object {[Netzblick.ProcessLineage]::Normalize($_.Path) -eq $p.Key} | Select-Object -First 1}else{$null}
        $ui[$prefix+'QuickBlock'].IsEnabled=[bool]$ready
        $ui[$prefix+'QuickAllow'].IsEnabled=[bool]($ready -and -not $state.Legacy)
        $ui[$prefix+'QuickTemporary'].IsEnabled=[bool]($ready -and -not $state.Legacy -and -not $lease)
        $ui[$prefix+'QuickReview'].IsEnabled=[bool]$valid
    }
    $ui.UndoNetwork.IsEnabled=$changes.Count -gt 0
    $p=$ui.Programs.SelectedItem
    $last=if($p){$changes | Where-Object {$_.Version -eq 2 -and [Netzblick.ProcessLineage]::Normalize($_.Path) -eq $p.Key} | Select-Object -First 1}else{$null}
    $ui.ProgramQuickUndo.IsEnabled=[bool]($last -and $script:setupStatus -and $setupStatus.Verified)
}
function Initialize-QuickActions {
    foreach($prefix in @('Overview','Program')){
        foreach($pair in @(@('QuickBlock','BlockProgram'),@('QuickAllow','AllowProgram'),@('QuickTemporary','TemporaryAllowProgram'))){
            $button=$ui[$prefix+$pair[0]];$button.Tag=[pscustomobject]@{Prefix=$prefix;Operation=$pair[1]}
            $button.Add_Click({param($sender,$e)
                $p=if($sender.Tag.Prefix -eq 'Overview'){$ui.OverviewPrograms.SelectedItem}else{$ui.Programs.SelectedItem}
                if($p){Confirm-PermissionChange $sender.Tag.Operation $p.Path}
            })
        }
        $button=$ui[$prefix+'QuickReview'];$button.Tag=$prefix
        $button.Add_Click({param($sender,$e)
            $p=if($sender.Tag -eq 'Overview'){$ui.OverviewPrograms.SelectedItem}else{$ui.Programs.SelectedItem}
            if($p){Save-ReviewDecision $p.Path;Refresh-Detail}
        })
    }
    $ui.ProgramQuickUndo.Add_Click({
        $p=$ui.Programs.SelectedItem;if(-not $p){return}
        $change=$changes | Where-Object {$_.Version -eq 2 -and [Netzblick.ProcessLineage]::Normalize($_.Path) -eq $p.Key} | Select-Object -First 1
        if($change){try{Undo-ProgramChange $change}catch{Show-Error $_.Exception.GetBaseException().Message}}
    })
    $ui.OverviewPrograms.Add_SelectionChanged({Update-QuickActions})
    Update-QuickActions
}

function Get-UnreviewedTargetRows([string]$path,$currentRows){
    Initialize-ActivityLedger
    $pathKey=[Netzblick.ProcessLineage]::Normalize($path);$present=@{}
    foreach($row in @($currentRows)){$k=Get-TargetKey $path $row.Address $row.Protocol $row.Port;if($k){$present[$k]=$true}}
    foreach($entry in $targetLedger.Values){
        if($entry.PathKey -ne $pathKey -or $entry.Reviewed -or -not $entry.Address -or $present.ContainsKey($entry.Key)){continue}
        [pscustomobject]@{Key=('REVIEW|'+$entry.Key);Pid='—';Protocol=[Netzblick.SetupRule]::ProtocolName([int]$(switch -Regex ([string]$entry.Protocol){'^TCP'{6;break} '^UDP'{17;break} '^ICMPv6'{58;break} '^ICMP'{1;break} default{[int]$entry.Protocol}}));Local='—';Remote=($entry.Address+':'+$entry.Port);Address=$entry.Address;Port=$entry.Port;State=('Früher beobachtet · '+([datetime]$entry.FirstUtc).ToLocalTime().ToString('dd.MM. HH:mm')+' · aktuell nicht bestätigt')}
    }
}

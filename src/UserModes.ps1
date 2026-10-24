function Read-NetworkRules([string]$path) {
    $base=Rule-Base $path
    foreach($rule in $policy.Rules){
        if($rule.Name -ne ($base+'.In') -and $rule.Name -ne ($base+'.Out')){continue}
        if($rule.Grouping -ne $group -or [Netzblick.ProcessLineage]::Normalize($rule.ApplicationName) -ne [Netzblick.ProcessLineage]::Normalize($path)){throw 'Der Regelname ist fremd belegt. Die Regel wird nicht verändert.'}
        [pscustomobject]@{Name=[string]$rule.Name;Path=[string]$rule.ApplicationName;Direction=[int]$rule.Direction;DirectionId=[int]$rule.Direction;Action=[int]$rule.Action;Enabled=[bool]$rule.Enabled;Profiles=[int]$rule.Profiles;Protocol=[int]$rule.Protocol;RemoteAddresses=[string]$rule.RemoteAddresses;LocalAddresses=[string]$rule.LocalAddresses;LocalPorts=[string]$rule.LocalPorts;RemotePorts=[string]$rule.RemotePorts;InterfaceTypes=[string]$rule.InterfaceTypes;ServiceName=[string]$rule.ServiceName;EdgeTraversal=[bool]$rule.EdgeTraversal;Interfaces=$rule.Interfaces}
    }
}
function Get-NetworkMode([string]$path,$snapshot=$null) {
    if($null -eq $snapshot){$snapshot=@(Read-NetworkRules $path)}
    if($snapshot.Count -eq 0){return 'Default'}
    if($snapshot.Count -ne 2){return 'Modified'}
    $mode=''
    foreach($rule in $snapshot){
        if(-not $rule.Enabled -or $rule.Action -ne 0 -or $rule.Protocol -ne 256 -or $rule.Profiles -ne 2147483647 -or $rule.LocalAddresses -notin @('','*') -or $rule.LocalPorts -notin @('','*') -or $rule.RemotePorts -notin @('','*') -or $rule.InterfaceTypes -notin @('','All') -or $rule.ServiceName -or $rule.EdgeTraversal -or $null -ne $rule.Interfaces -and $rule.Interfaces -isnot [DBNull] -and @($rule.Interfaces).Count -gt 0){return 'Modified'}
        $current=[Netzblick.NetworkPolicy]::ClassifyScope($rule.RemoteAddresses)
        if($current -eq 'Modified' -or $mode -and $mode -ne $current){return 'Modified'}
        $mode=$current
    }
    if(@($snapshot | Where-Object {$_.DirectionId -eq 1}).Count -ne 1 -or @($snapshot | Where-Object {$_.DirectionId -eq 2}).Count -ne 1){return 'Modified'}
    return $mode
}
function Network-ModeLabel([string]$mode) {
    switch($mode){'Default'{'Windows-Standard'} 'Blocked'{'Netzwerk gesperrt'} 'Private'{'Auf private Netze beschränkt'} default{'Eigene Regeln extern verändert'}}
}
function Get-NetworkFingerprint($rules) {
    $normalized=@($rules | Sort-Object -Property @('Name') | ForEach-Object {
        $scope=try{[Netzblick.NetworkPolicy]::CanonicalScope($_.RemoteAddresses)}catch{$_.Exception.Message}
        [ordered]@{Name=$_.Name;Path=[Netzblick.ProcessLineage]::Normalize($_.Path);Direction=$_.Direction;Action=$_.Action;Enabled=$_.Enabled;Profiles=$_.Profiles;Protocol=$_.Protocol;Remote=$scope;Local=$_.LocalAddresses;LocalPorts=$_.LocalPorts;RemotePorts=$_.RemotePorts;InterfaceTypes=$_.InterfaceTypes;Service=$_.ServiceName;Edge=$_.EdgeTraversal;Interfaces=$_.Interfaces}
    })
    return ConvertTo-Json -InputObject $normalized -Depth 5 -Compress
}
function Write-NetworkMode([string]$path,[string]$mode) {
    $base=Rule-Base $path
    # Restrictive changes go outbound first; own rules are updated in place.
    foreach($direction in @(2,1)){
        $name=$base+$(if($direction -eq 1){'.In'}else{'.Out'})
        $existing=$null
        foreach($candidate in $policy.Rules){if($candidate.Name -eq $name){$existing=$candidate;break}}
        if($mode -eq 'Default'){if($existing){$policy.Rules.Remove($name)};continue}
        $scope=if($mode -eq 'Blocked'){'*'}else{[Netzblick.NetworkPolicy]::PrivateOnlyBlockScope()}
        if($existing){$existing.RemoteAddresses=$scope;continue}
        $rule=New-Object -ComObject HNetCfg.FWRule
        $rule.Name=$name;$rule.Description='Manuell über Netzblick gesetzte Einschränkung';$rule.ApplicationName=$path
        $rule.Protocol=256;$rule.Direction=$direction;$rule.Action=0;$rule.Profiles=2147483647;$rule.Grouping=$group
        $rule.LocalAddresses='*';$rule.InterfaceTypes='All';$rule.RemoteAddresses=$scope;$rule.Enabled=$true;$policy.Rules.Add($rule)
    }
}
function Assert-NetworkChange([string]$path,[string]$mode) {
    if($script:accessActive){throw 'Im Kontrollmodus die Sitzungsfreigabe unter Zugriff entscheiden verwalten. Für dauerhafte Programmregeln den Kontrollmodus zuerst beenden.'}
    if($mode -notin @('Default','Private','Blocked')){throw 'Unbekannter Netzwerkzustand.'}
    if(Is-Protected $path){throw 'System-Sammelprozesse sind von pauschalen Änderungen ausgenommen.'}
    if($script:inspectionActive -and $mode -ne 'Blocked' -and ($inspection.Path -eq $path -or @($inspectionNodes | Where-Object {$_.Path -eq $path}).Count)){throw 'Die zugehörige Prüfung zuerst beenden, bevor die Einschränkung gelockert wird.'}
}
function Set-NetworkMode([string]$path,[string]$mode,[switch]$NoHistory) {
    Assert-NetworkChange $path $mode
    $before=@(Read-NetworkRules $path);$beforeMode=Get-NetworkMode $path $before
    if($beforeMode -eq 'Modified'){throw 'Eigene Regeln wurden außerhalb von Netzblick verändert. Bitte unter „Eigene Regeln“ prüfen; sie werden nicht automatisch überschrieben.'}
    if($beforeMode -eq $mode){return}
    try{
        Write-NetworkMode $path $mode
        $after=@(Read-NetworkRules $path)
        if((Get-NetworkMode $path $after) -ne $mode){throw 'Regeländerung konnte nicht vollständig bestätigt werden.'}
    }catch{
        $reason=$_.Exception.Message
        try{
            # Only the two owned rule names are involved. Restore the prior managed mode.
            Write-NetworkMode $path $beforeMode
            if((Get-NetworkMode $path) -ne $beforeMode){throw 'Vorheriger Zustand nicht bestätigt.'}
        }catch{$reason+=' Rücknahme unvollständig: '+$_.Exception.Message}
        Refresh-Rules;throw $reason
    }
    Refresh-Rules
    if(-not $NoHistory){
        $script:changes.Insert(0,[pscustomobject]@{Version=1;Path=$path;Before=$beforeMode;After=$mode;Fingerprint=(Get-NetworkFingerprint $after);TimeUtc=[datetime]::UtcNow})
        while($changes.Count -gt 20){$changes.RemoveAt($changes.Count-1)}
        Save-UserState
    }
    Add-Event 'Netzwerkzustand geändert' ([IO.Path]::GetFileName($path)) ((Network-ModeLabel $beforeMode)+' → '+(Network-ModeLabel $mode))
    $ui.UndoNetwork.IsEnabled=$changes.Count -gt 0
    Refresh-Detail;Refresh-Overview
}
function Save-UserState {
    try{
        [void][IO.Directory]::CreateDirectory($userStateDirectory)
        $state=@{Version=1;Seen=@($knownPrograms.Keys | Select-Object -First 10000);Changes=@($changes.ToArray())}
        $temp=$userStateFile+'.tmp'
        [IO.File]::WriteAllText($temp,($state | ConvertTo-Json -Depth 7),[Text.UTF8Encoding]::new($false))
        if([IO.File]::Exists($userStateFile)){[IO.File]::Replace($temp,$userStateFile,$null)}else{[IO.File]::Move($temp,$userStateFile)}
    }catch{$ui.UserNotice.Text='Einstellungen konnten nicht gespeichert werden: '+$_.Exception.Message}
}
function Initialize-UserModes {
    $script:allProgramItems=@();$script:policyReady=$true;$script:changes=New-Object 'System.Collections.Generic.List[object]'
    $script:knownPrograms=@{};$script:newPrograms=@{};$script:traffic=$null;$script:trafficProblem=''
    $script:trafficTotals=@{};$script:trafficSamples=@{};$script:trafficPeers=@();$script:trafficSampleUtc=[datetime]::UtcNow
    $script:sessionStartedUtc=[datetime]::UtcNow;$script:userBaseline=$false
    $script:userStateDirectory=Join-Path $env:LOCALAPPDATA 'Netzblick';$script:userStateFile=Join-Path $userStateDirectory 'user-state.json'
    try{
        if([IO.File]::Exists($userStateFile) -and (Get-Item -LiteralPath $userStateFile).Length -lt 2000000){
            $saved=Get-Content -LiteralPath $userStateFile -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach($path in @($saved.Seen)){if($path -is [string] -and $path.Length -lt 32768){$knownPrograms[$path]=$true}}
            foreach($change in @($saved.Changes | Select-Object -First 20)){if($change.Version -eq 1 -and $change.Path -is [string] -and $change.Before -in @('Default','Private','Blocked') -and $change.After -in @('Default','Private','Blocked') -and $change.Fingerprint -is [string]){$changes.Add($change)}}
            $script:userBaseline=$knownPrograms.Count -gt 0
        }
    }catch{$ui.UserNotice.Text='Gespeicherter Zustand konnte nicht gelesen werden: '+$_.Exception.Message}
    $ui.UndoNetwork.IsEnabled=$changes.Count -gt 0
    try{
        [Netzblick.RuntimeDependencies]::Install((Join-Path $appRoot 'lib'))
        [void][Reflection.Assembly]::LoadFrom((Join-Path $appRoot 'lib\Netzblick.Capture.dll'))
        $script:traffic=[Netzblick.Capture.NetworkCapture]::Start()
    }catch{$script:trafficProblem=$_.Exception.GetBaseException().Message}
    $ui.ModeDefault.Add_Click({Apply-SelectedMode 'Default'})
    $ui.ModePrivate.Add_Click({Apply-SelectedMode 'Private'})
    $ui.ModeBlocked.Add_Click({Apply-SelectedMode 'Blocked'})
    $ui.UndoNetwork.Add_Click({
        if($changes.Count -eq 0){return}
        $change=$changes[0]
        try{
            $current=@(Read-NetworkRules $change.Path)
            if((Get-NetworkFingerprint $current) -ne $change.Fingerprint){throw 'Die betroffenen Regeln haben sich seit der Änderung verändert. Rückgängig wurde zum Schutz dieser Änderung abgebrochen.'}
            Set-NetworkMode $change.Path $change.Before -NoHistory
            $changes.RemoveAt(0);$ui.UndoNetwork.IsEnabled=$changes.Count -gt 0;Save-UserState
            $ui.UserNotice.Text='Rückgängig: '+[IO.Path]::GetFileName($change.Path)+' · '+(Network-ModeLabel $change.Before)
            Refresh-Overview
        }catch{Show-Error $_.Exception.GetBaseException().Message}
    })
    $ui.AcknowledgeNew.Add_Click({$script:newPrograms.Clear();Refresh-Overview})
    $ui.OverviewPrograms.Add_MouseDoubleClick({
        $item=$ui.OverviewPrograms.SelectedItem;if($item){$ui.Search.Text='';Show-Panel 'LivePanel';$match=$ui.Programs.Items | Where-Object {$_.Key -eq $item.Key} | Select-Object -First 1;if($match){$ui.Programs.SelectedItem=$match}}
    })
    $ui.ShowProgramMap.Add_Click({
        $program=$ui.Programs.SelectedItem;Show-Panel 'WorldPanel'
        if($program){$match=$ui.WorldPrograms.Items | Where-Object {$_.Key -eq $program.Key} | Select-Object -First 1;if($match){$ui.WorldPrograms.SelectedItem=$match}}
    })
    $ui.ShowDiagnostics.Add_Click({Show-Panel 'TerminalPanel'})
    $ui.ShowOwnRules.Add_Click({Refresh-Rules;Show-Panel 'RulesPanel'})
    $ui.ShowHistory.Add_Click({Show-Panel 'HistoryPanel'})
    $ui.OverviewShowPrograms.Add_Click({Show-Panel 'LivePanel'})
    $window.Add_Closed({if($script:traffic){try{$script:traffic.Dispose()}catch{}}})
}
function Apply-SelectedMode([string]$mode) {
    $program=$ui.Programs.SelectedItem;if($null -eq $program){return}
    try{Set-NetworkMode $program.Path $mode}catch{Show-Error $_.Exception.GetBaseException().Message}
}
function Format-Bytes([double]$bytes) {
    if($bytes -ge 1073741824){return '{0:N2} GB' -f ($bytes/1073741824)}
    if($bytes -ge 1048576){return '{0:N1} MB' -f ($bytes/1048576)}
    if($bytes -ge 1024){return '{0:N1} KB' -f ($bytes/1024)}
    return '{0:N0} B' -f $bytes
}
function Update-Traffic {
    if($null -eq $traffic){return}
    $now=[datetime]::UtcNow;$seconds=($now-$trafficSampleUtc).TotalSeconds
    $values=$traffic.Snapshot();$result=@{}
    foreach($value in $values){
        $old=$trafficTotals[$value.Key]
        $sent=if($old -and $seconds -gt 0){[Math]::Max(0,$value.Sent-$old.Sent)/$seconds}else{0}
        $received=if($old -and $seconds -gt 0){[Math]::Max(0,$value.Received-$old.Received)/$seconds}else{0}
        $result[$value.Key]=[pscustomobject]@{Key=$value.Key;Path=$value.Path;Name=$value.Name;Sent=$value.Sent;Received=$value.Received;LastUtc=$value.LastUtc;SentRate=$sent;ReceivedRate=$received;RateReady=($null -ne $old)}
    }
    $script:trafficSamples=$result;$script:trafficTotals=@{};foreach($value in $values){$script:trafficTotals[$value.Key]=$value}
    $script:trafficPeers=@($traffic.Peers());$script:trafficSampleUtc=$now
    if(-not $traffic.Running){$script:trafficProblem='ETW-Erfassung beendet: '+$traffic.Error}
    elseif($traffic.Lost -lt 0){$script:trafficProblem='Vollständigkeit der ETW-Messung konnte nicht bestätigt werden.'}
    elseif($traffic.Lost -ne 0 -or $traffic.Uncounted -ne 0){$script:trafficProblem='Messung unvollständig · verlorene ETW-Ereignisse: '+$traffic.Lost+' · nicht gezählte Datensätze: '+$traffic.Uncounted}
}
function Track-ObservedPrograms($items) {
    $changed=$false
    $bootstrap=-not $userBaseline -and (([datetime]::UtcNow-$sessionStartedUtc).TotalSeconds -lt 15)
    foreach($item in $items){
        if(-not $item.Path){continue};$key=[Netzblick.ProcessLineage]::Normalize($item.Path)
        if(-not $knownPrograms.ContainsKey($key) -and $knownPrograms.Count -lt 10000){
            $knownPrograms[$key]=$true;$changed=$true
            if(-not $bootstrap){$newPrograms[$key]=[pscustomobject]@{Name=$item.Name;Path=$item.Path;FirstUtc=[datetime]::UtcNow};Add-Event 'Erstmals beobachtet' $item.Name 'Seit Beginn der gespeicherten Beobachtung · keine automatische Vorabsperre'}
        }
    }
    if($changed){Save-UserState}
}
function Refresh-Overview {
    if(-not $script:policyReady){return}
    $items=@()
    foreach($program in @($script:allProgramItems)){
        $sample=$trafficSamples[$program.Key]
        $mode=try{Get-NetworkMode $program.Path @($ownRules | Where-Object {$_.Path -eq $program.Path})}catch{'Modified'}
        $items+=[pscustomobject]@{Key=$program.Key;Name=$program.Name;Path=$program.Path;Status=(Network-ModeLabel $mode);Sent=$(if($sample){Format-Bytes $sample.Sent}else{'—'});Received=$(if($sample){Format-Bytes $sample.Received}else{'—'});Rate=$(if($sample -and $sample.RateReady){'↑ '+(Format-Rate $sample.SentRate)+' · ↓ '+(Format-Rate $sample.ReceivedRate)}elseif($sample){'Rate wird ermittelt …'}else{'Nicht gemessen'});Volume=$(if($sample){$sample.Sent+$sample.Received}else{0});New=$newPrograms.ContainsKey($program.Key)}
    }
    $ui.OverviewPrograms.ItemsSource=@($items | Sort-Object -Property @{Expression='New';Descending=$true},@{Expression='Volume';Descending=$true})
    $ui.OverviewNew.Text=[string]$newPrograms.Count
    $ui.OverviewStatus.Text=if($trafficProblem){'Datenmessung eingeschränkt: '+$trafficProblem}elseif($traffic){'TCP und UDP über IPv4/IPv6 · ETW-Bytes seit diesem Netzblick-Start · keine entschlüsselten Inhalte'}else{'Datenmessung nicht verfügbar.'}
    $ui.OverviewStatus.Foreground=if($trafficProblem){'#9C650A'}else{'#57677B'}
    if($newPrograms.Count){$ui.NewProgramsNotice.Text=($newPrograms.Count.ToString()+' erstmals beobachtete Programme · keine automatische Sperre. '+(($newPrograms.Values | Select-Object -First 5 -ExpandProperty Name)-join ', '))}else{$ui.NewProgramsNotice.Text='Keine neuen Programme gemeldet. Beim ersten Start werden 15 Sekunden als Ausgangsbestand erfasst.'}
    $ui.AcknowledgeNew.IsEnabled=$newPrograms.Count -gt 0
    $ui.LastNetworkChange.Text=if($changes.Count){[IO.Path]::GetFileName($changes[0].Path)+': '+(Network-ModeLabel $changes[0].Before)+' → '+(Network-ModeLabel $changes[0].After)}else{'Noch keine aufgezeichnete Änderung.'}
}


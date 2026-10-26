function Read-NetworkRules([string]$path) {
    foreach($rule in $policy.Rules){
        if(-not (Test-OwnedNetworkRule $rule $path)){continue}
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
    $normalized=@($rules | Sort-Object { (Rule-Base $_.Path)+$(if($_.Direction -eq 1){'.In'}else{'.Out'}) } | ForEach-Object {
        $scope=try{[Netzblick.NetworkPolicy]::CanonicalScope($_.RemoteAddresses)}catch{$_.Exception.Message}
        [ordered]@{Name=((Rule-Base $_.Path)+$(if($_.Direction -eq 1){'.In'}else{'.Out'}));Path=[Netzblick.ProcessLineage]::Normalize($_.Path);Direction=$_.Direction;Action=$_.Action;Enabled=$_.Enabled;Profiles=$_.Profiles;Protocol=$_.Protocol;Remote=$scope;Local=$_.LocalAddresses;LocalPorts=$_.LocalPorts;RemotePorts=$_.RemotePorts;InterfaceTypes=$_.InterfaceTypes;Service=$_.ServiceName;Edge=$_.EdgeTraversal;Interfaces=$_.Interfaces}
    })
    return ConvertTo-Json -InputObject $normalized -Depth 5 -Compress
}
function Write-NetworkMode([string]$path,[string]$mode) {
    if($mode -ne 'Default'){foreach($direction in @(2,1)){Assert-ReadableRuleNameAvailable $path $direction $mode}}
    # Restrictive changes go outbound first; update existing objects in place.
    foreach($direction in @(2,1)){
        $ownedMatches=@($policy.Rules | Where-Object {(Test-OwnedNetworkRule $_ $path) -and $_.Direction -eq $direction})
        if($ownedMatches.Count -gt 1){throw 'Mehrere eigene Regeln für dieselbe Richtung. Zuerst unter Regeln prüfen.'}
        $existing=if($ownedMatches.Count){$ownedMatches[0]}else{$null}
        if($mode -eq 'Default'){if($existing){$policy.Rules.Remove($existing.Name)};continue}
        $scope=if($mode -eq 'Blocked'){'*'}else{[Netzblick.NetworkPolicy]::PrivateOnlyBlockScope()}
        $name=Get-ReadableRuleName $path $direction $mode;$description=(Get-OwnedRuleMarker $path $direction)+' Programm: '+$path
        if($existing){$existing.RemoteAddresses=$scope;$existing.Description=$description;$existing.Name=$name;continue}
        $rule=New-Object -ComObject HNetCfg.FWRule
        $rule.Name=$name;$rule.Description=$description;$rule.ApplicationName=$path
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
    param([switch]$ThrowOnError)
    try{
        [void][IO.Directory]::CreateDirectory($userStateDirectory)
        $state=@{Version=2;NotifyObserved=$script:notifyObserved;DarkMode=[bool]$script:darkMode;DesignStyle=$script:designStyle;Pending=@($script:newPrograms.Values);Seen=@($knownPrograms.Keys | Select-Object -First 10000);Changes=@($changes.ToArray());Targets=@($script:targetLedger.Values);BlockBaselines=@($script:blockBaselines.Values)}
        $temp=$userStateFile+'.tmp'
        [IO.File]::WriteAllText($temp,($state | ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
        if([IO.File]::Exists($userStateFile)){[IO.File]::Replace($temp,$userStateFile,($userStateFile+'.bak'))}else{[IO.File]::Move($temp,$userStateFile)}
    }catch{if($ThrowOnError){throw};$ui.UserNotice.Text='Einstellungen konnten nicht gespeichert werden: '+$_.Exception.Message}
}
function Initialize-UserModes {
    $script:allProgramItems=@();$script:policyReady=$true;$script:changes=New-Object 'System.Collections.Generic.List[object]'
    $script:knownPrograms=@{};$script:newPrograms=@{};$script:notifyObserved=$true;$script:darkMode=$true;$script:designStyle='Clean';$script:traffic=$null;$script:trafficProblem=''
    $script:trafficTotals=@{};$script:trafficSamples=@{};$script:trafficPeers=@();$script:trafficSampleUtc=[datetime]::UtcNow
    $script:sessionStartedUtc=[datetime]::UtcNow;$script:userBaseline=$false
    $script:targetLedger=@{};$script:blockBaselines=@{};$script:targetReviewCounts=$null
    $script:userStateDirectory=Join-Path $env:LOCALAPPDATA 'Netzblick';$script:userStateFile=Join-Path $userStateDirectory 'user-state.json'
    if($StateDirectory){$script:userStateDirectory=$StateDirectory;$script:userStateFile=Join-Path $userStateDirectory 'user-state.json'}
    try{
        if([IO.File]::Exists($userStateFile) -and (Get-Item -LiteralPath $userStateFile).Length -lt 4000000){
            $saved=Get-Content -LiteralPath $userStateFile -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach($entry in @($saved.Targets | Select-Object -First 5000)){
                if($entry.Key -is [string] -and $entry.Key.Length -lt 32768 -and $entry.PathKey -is [string] -and [Netzblick.AccessQueue]::CanAllow($entry.PathKey)){$targetLedger[$entry.Key]=[pscustomobject]@{Key=$entry.Key;PathKey=$entry.PathKey;Address=$entry.Address;Protocol=$entry.Protocol;Port=[int]$entry.Port;Reviewed=[bool]$entry.Reviewed;FirstUtc=$entry.FirstUtc}}
            }
            foreach($entry in @($saved.BlockBaselines | Select-Object -First 2000)){
                if($entry.Key -is [string] -and $entry.Epoch -is [string] -and $entry.Count -ge 0){$blockBaselines[$entry.Key]=$entry}
            }
            if($saved.DesignStyle -in @('Clean','Future')){$script:designStyle=$saved.DesignStyle}
            if($saved.DarkMode -is [bool]){$script:darkMode=$saved.DarkMode}
            foreach($path in @($saved.Seen)){if($path -is [string] -and $path.Length -lt 32768){$knownPrograms[$path]=$true}}
            foreach($change in @($saved.Changes | Select-Object -First 20)){if($change.Version -eq 2 -and $change.Path -is [string] -and $change.BeforeJson -is [string] -and $change.AfterJson -is [string]){try{[void](Read-ProgramSnapshot $change.BeforeJson);[void](Read-ProgramSnapshot $change.AfterJson);$changes.Add($change)}catch{}}elseif($change.Version -eq 1 -and $change.Path -is [string] -and $change.Before -in @('Default','Private','Blocked') -and $change.After -in @('Default','Private','Blocked') -and $change.Fingerprint -is [string]){$changes.Add($change)}}
            if($null -ne $saved.NotifyObserved){$script:notifyObserved=[bool]$saved.NotifyObserved}
            foreach($pending in @($saved.Pending | Select-Object -First 1000)){
                if($pending.Path -is [string] -and [Netzblick.AccessQueue]::CanAllow($pending.Path)){
                    $key=[Netzblick.ProcessLineage]::Normalize($pending.Path)
                    $newPrograms[$key]=[pscustomobject]@{Key=$key;Name=[IO.Path]::GetFileName($pending.Path);Path=$pending.Path;FirstUtc=$pending.FirstUtc}
                }
            }
            $script:userBaseline=$knownPrograms.Count -gt 0
        }
    }catch{$ui.UserNotice.Text='Gespeicherter Zustand konnte nicht gelesen werden: '+$_.Exception.Message}
    $ui.UndoNetwork.IsEnabled=$changes.Count -gt 0
    try{
        if($Embedded){[void][Reflection.Assembly]::Load('Netzblick.Capture')}
        else{
            [Netzblick.RuntimeDependencies]::Install((Join-Path $appRoot 'lib'))
            [void][Reflection.Assembly]::LoadFrom((Join-Path $appRoot 'lib\Netzblick.Capture.dll'))
        }
        $script:traffic=[Netzblick.Capture.NetworkCapture]::Start()
    }catch{$script:trafficProblem=$_.Exception.GetBaseException().Message}
    $ui.ModeDefault.Add_Click({Apply-SelectedMode 'Default'})
    $ui.ModePrivate.Add_Click({Apply-SelectedMode 'Private'})
    $ui.ModeBlocked.Add_Click({Apply-SelectedMode 'Blocked'})
    $ui.UndoNetwork.Add_Click({
        if($changes.Count -eq 0){return}
        $change=$changes[0]
        try{
            if($change.Version -eq 2){Undo-ProgramChange $change;return}
            $current=@(Read-NetworkRules $change.Path)
            if((Get-NetworkFingerprint $current) -ne $change.Fingerprint){throw 'Die betroffenen Regeln haben sich seit der Änderung verändert. Rückgängig wurde zum Schutz dieser Änderung abgebrochen.'}
            Set-NetworkMode $change.Path $change.Before -NoHistory
            $changes.RemoveAt(0);$ui.UndoNetwork.IsEnabled=$changes.Count -gt 0;Save-UserState
            $ui.UserNotice.Text='Rückgängig: '+[IO.Path]::GetFileName($change.Path)+' · '+(Network-ModeLabel $change.Before)
            Refresh-Overview
        }catch{Show-Error $_.Exception.GetBaseException().Message}
    })
    $ui.AcknowledgeNew.Add_Click({if([Windows.MessageBox]::Show($window,'Alle Einträge als geprüft markieren? Firewallregeln bleiben unverändert.','Prüfliste','YesNo','Question') -eq 'Yes'){foreach($p in @($script:allProgramItems)){Mark-ProgramActivityReviewed $p.Path};$script:newPrograms.Clear();Save-UserState;Refresh-Overview}})
    $ui.OverviewPrograms.Add_MouseDoubleClick({
        Open-OverviewSelection
    })
    $ui.ShowProgramMap.Add_Click({
        $program=$ui.Programs.SelectedItem;Show-Panel 'WorldPanel'
        if($program){$match=$ui.WorldPrograms.Items | Where-Object {$_.Key -eq $program.Key} | Select-Object -First 1;if($match){$ui.WorldPrograms.SelectedItem=$match}}
    })
    $ui.ShowDiagnostics.Add_Click({Show-Panel 'TerminalPanel'})
    $ui.ShowOwnRules.Add_Click({Refresh-Rules;Show-Panel 'RulesPanel'})
    $ui.ShowHistory.Add_Click({Show-Panel 'HistoryPanel'})
    $ui.OverviewShowPrograms.Add_Click({Open-OverviewSelection})
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
function Track-ObservedPrograms($items,[switch]$AlwaysReview) {
    $changed=$false
    $bootstrap=-not $AlwaysReview -and -not $userBaseline -and (([datetime]::UtcNow-$sessionStartedUtc).TotalSeconds -lt 15)
    foreach($item in $items){
        if(-not $item.Path){continue};$key=[Netzblick.ProcessLineage]::Normalize($item.Path)
        if(-not $knownPrograms.ContainsKey($key) -and $knownPrograms.Count -lt 10000){
            $knownPrograms[$key]=$true;$changed=$true
            if(-not $bootstrap -and $newPrograms.Count -lt 1000){$newPrograms[$key]=[pscustomobject]@{Key=$key;Name=$item.Name;Path=$item.Path;FirstUtc=[datetime]::UtcNow};Add-Event 'Erstmals beobachtet' $item.Name 'Zur Prüfung vorgemerkt';if(Get-Command Show-ObservedNotice -ErrorAction SilentlyContinue){Show-ObservedNotice $newPrograms[$key]}}
        }
    }
    if($changed){Save-UserState}
}
function Refresh-Overview {
    if(-not $script:policyReady){return}
    Update-ActivityLedger
    $items=@()
    foreach($program in @($script:allProgramItems)){
        $sample=$trafficSamples[$program.Key]
        $reviewActivity=Get-ProgramActivityReview $program.Path
        $needsReview=$newPrograms.ContainsKey($program.Key) -or $reviewActivity.NewTargets -gt 0 -or $reviewActivity.NewBlocks -gt 0
        $signal=Get-PermissionStatus $program.Path
        $activity=Get-ProgramActivity $program $sample
        $mode=try{Get-NetworkMode $program.Path @($ownRules | Where-Object {$_.Path -eq $program.Path})}catch{'Modified'}
        $items+=[pscustomobject]@{Key=$program.Key;Name=$program.Name;AppIcon=(Get-ApplicationIcon $program.Path);FutureActivity=$(if($program.BlockCount){$program.BlockCount.ToString()+' Blockversuche'}elseif($sample -and $sample.RateReady){'↓ '+(Format-Rate $sample.ReceivedRate)}else{'Nicht gemessen'});Path=$program.Path;SignalColor=$signal.SignalColor;SignalHint=$signal.SignalHint;BlockSummary=$program.BlockSummary;ActivityReview=($reviewActivity.NewTargets.ToString()+' neue Ziele · '+$reviewActivity.NewBlocks+' neue Blockversuche');NeedsReview=$needsReview;NewBadge=$(if($newPrograms.ContainsKey($program.Key)){'NEU'}else{''});LastSeen=$activity.Label;Active=$activity.Active;Category=$signal.Category;Status=$(if(Get-Command Get-PermissionStatus -ErrorAction SilentlyContinue){(Get-PermissionStatus $program.Path).Status}else{Network-ModeLabel $mode});Review=$(if($newPrograms.ContainsKey($program.Key)){'Neues Programm'}elseif($needsReview){'Neue Ziele / Versuche'}else{'Keine Neuigkeiten'});Sent=$(if($sample){Format-Bytes $sample.Sent}else{'—'});Received=$(if($sample){Format-Bytes $sample.Received}else{'—'});Rate=$(if($sample -and $sample.RateReady){'↑ '+(Format-Rate $sample.SentRate)+' · ↓ '+(Format-Rate $sample.ReceivedRate)}elseif($sample){'Rate wird ermittelt …'}else{'Nicht gemessen'});Volume=$(if($sample){$sample.Sent+$sample.Received}else{0});New=$newPrograms.ContainsKey($program.Key)}
    }
    $oldKey=if($ui.PendingPrograms.SelectedItem){$ui.PendingPrograms.SelectedItem.Key}else{''}
    $ui.PendingPrograms.ItemsSource=@($newPrograms.Values | Sort-Object FirstUtc -Descending)
    $selected=$ui.PendingPrograms.Items | Where-Object {$_.Key -eq $oldKey} | Select-Object -First 1
    if($selected){$ui.PendingPrograms.SelectedItem=$selected}elseif($ui.PendingPrograms.Items.Count){$ui.PendingPrograms.SelectedIndex=0}
    if(Get-Command Refresh-ReviewSelection -ErrorAction SilentlyContinue){Refresh-ReviewSelection}
    $overviewKey=if($ui.OverviewPrograms.SelectedItem){$ui.OverviewPrograms.SelectedItem.Key}else{''}
    $allCount=$items.Count
    $ui.FutureProgramCount.Text=[string]$allCount;$ui.FutureBlockedCount.Text=[string](@($items | Where-Object Category -eq 'Blocked').Count);$ui.FutureReviewCount.Text=[string](@($items | Where-Object NeedsReview).Count)
    $query=$ui.OverviewSearch.Text.Trim()
    $filter=$ui.OverviewFilter.SelectedIndex
    $items=@($items | Where-Object {($filter -eq 0 -or ($filter -eq 1 -and $_.Category -eq 'Blocked') -or ($filter -eq 2 -and $_.NeedsReview) -or ($filter -eq 3 -and $_.Active)) -and (-not $query -or $_.Name.IndexOf($query,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or ([string]$_.Path).IndexOf($query,[StringComparison]::OrdinalIgnoreCase) -ge 0)})
    $ui.ProgramListCounts.Text=$items.Count.ToString()+' von '+$allCount+' Programmen'
    $ui.ProgramListEmpty.Text=if(-not $items.Count){'Keine Programme in dieser Auswahl. Filter oder Suche ändern.'}else{''}
    $script:overviewItemsChanging=$true
    try{
        $ui.OverviewPrograms.ItemsSource=@($items | Sort-Object -Property @{Expression='NeedsReview';Descending=$true},@{Expression='Volume';Descending=$true})
        if($overviewKey){$ui.OverviewPrograms.SelectedItem=$ui.OverviewPrograms.Items | Where-Object {$_.Key -eq $overviewKey} | Select-Object -First 1}
        if($script:designStyle -eq 'Future' -and -not $ui.OverviewPrograms.SelectedItem -and $ui.OverviewPrograms.Items.Count){$ui.OverviewPrograms.SelectedIndex=0}
    }finally{$script:overviewItemsChanging=$false}
    if($script:activePanel -in @('OverviewPanel','LivePanel')){Sync-FutureProgramSelection}
    if(Get-Command Refresh-Permissions -ErrorAction SilentlyContinue){Refresh-Permissions}
    Update-QuickActions
    $ui.OverviewNew.Text=[string]$newPrograms.Count
    $ui.OverviewStatus.Text=if($trafficProblem){'Datenmessung eingeschränkt: '+$trafficProblem}elseif($traffic){'TCP und UDP über IPv4/IPv6 · ETW-Bytes seit diesem Netzblick-Start · keine entschlüsselten Inhalte'}else{'Datenmessung nicht verfügbar.'}
    $ui.OverviewStatus.Foreground=if($trafficProblem){(Get-ThemeColor '#9C650A')}else{(Get-ThemeColor '#57677B')}
    if($newPrograms.Count){$ui.NewProgramsNotice.Text=($newPrograms.Count.ToString()+' Programme warten auf deine Prüfung. '+(($newPrograms.Values | Select-Object -First 5 -ExpandProperty Name)-join ', '))}else{$ui.NewProgramsNotice.Text='Prüfliste leer. Beim ersten Start werden 15 Sekunden als Ausgangsbestand erfasst.'}
    $ui.AcknowledgeNew.IsEnabled=$newPrograms.Count -gt 0
    $ui.LastNetworkChange.Text=if($changes.Count -and $changes[0].Version -eq 2){[IO.Path]::GetFileName($changes[0].Path)+': '+$changes[0].Label}elseif($changes.Count){[IO.Path]::GetFileName($changes[0].Path)+': '+(Network-ModeLabel $changes[0].Before)+' → '+(Network-ModeLabel $changes[0].After)}else{'Noch keine aufgezeichnete Änderung.'}
}



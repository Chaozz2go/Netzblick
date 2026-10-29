# A review run has a fixed order and an explicit, immutable evidence snapshot.
function New-GuideSnapshot([string]$path){
    Update-ActivityLedger
    $key=[Netzblick.ProcessLineage]::Normalize($path);$review=Get-ProgramReviewState $path
    $targets=@($targetLedger.Values | Where-Object {$_.PathKey -eq $key -and -not $_.Reviewed} | Sort-Object FirstUtc | ForEach-Object {[pscustomobject]@{Key=$_.Key;FirstUtc=$_.FirstUtc;Address=$_.Address;Protocol=$_.Protocol;Port=$_.Port}})
    $counts=@();$evidence=@()
    foreach($t in $targets){$evidence+=[pscustomobject]@{Kind='Ungeprüftes Ziel';Target=($t.Address+' · '+$t.Protocol+' '+$t.Port);Detail=('Erstmals erfasst '+([datetime]$t.FirstUtc).ToLocalTime().ToString('dd.MM. HH:mm:ss')+'. Aktuelle Verbindung und Dienstrichtung damit nicht bestätigt.')}}
    $epoch=if($script:setupStatus){$setupStatus.StartedUtc.ToString('o')}else{''}
    if($script:setupStatus){foreach($a in @($setupStatus.Attempts | Where-Object {[Netzblick.ProcessLineage]::Normalize($_.Path) -eq $key})){
        $baseline=$script:blockBaselines[$a.Key];$seen=if($baseline -and $baseline.Epoch -eq $epoch){[long]$baseline.Count}else{0}
        if($a.Count -gt $seen){$counts+=@([pscustomobject]@{Key=$a.Key;Count=[long]$a.Count});$evidence+=[pscustomobject]@{Kind='Neue Blockversuche';Target=$a.Target;Detail=(($a.Count-$seen).ToString()+' neue Versuche · '+$a.Direction+' · '+$a.Evidence+' · zuletzt '+$a.LastUtc.ToLocalTime().ToString('dd.MM. HH:mm:ss'))}}
    }}
    [pscustomobject]@{Path=$path;Key=$key;TimeUtc=[datetime]::UtcNow;Epoch=$epoch;RunEpoch=$script:guideEpoch;Reason=$review.Reason;NeedsReview=$review.NeedsReview;Targets=$targets;Counts=$counts;NewFirstUtc=$(if($newPrograms.ContainsKey($key)){$newPrograms[$key].FirstUtc}else{$null});Evidence=$evidence}
}
function Start-GuidedReview {
    $script:guideQueue=@($script:allProgramItems | Where-Object {$_.Path -and (Get-ProgramReviewState $_.Path).NeedsReview} | Sort-Object Name,Path | ForEach-Object {[pscustomobject]@{Path=$_.Path;Name=$_.Name;Done=$false}})
    $script:guideIndex=0;$script:guideSnapshot=$null;$script:guideEpoch=[guid]::NewGuid().ToString('N')
    Show-Panel 'WorkflowPanel';$ui.WorkflowViews.SelectedIndex=0
    Select-GuideItem
}
function Select-GuideItem {
    $script:guideSnapshot=if($script:guideIndex -ge 0 -and $script:guideIndex -lt $script:guideQueue.Count){New-GuideSnapshot $guideQueue[$guideIndex].Path}else{$null}
    Refresh-Guide
}
function Refresh-Guide {
    if(-not $script:workflowReady){return}
    $s=$script:guideSnapshot;$pending=@($script:allProgramItems | Where-Object {$_.Path -and (Get-ProgramReviewState $_.Path).NeedsReview}).Count
    $ui.GuideProgress.Text=if($s){'Programm '+($guideIndex+1)+' von '+$guideQueue.Count+' · '+@($guideQueue | Where-Object Done).Count+' in diesem Durchgang geprüft'}else{'Kein Programm ausgewählt · '+$pending+' Programme derzeit offen'}
    $ui.GuideBack.IsEnabled=$script:guideIndex -gt 0
    $ui.GuideNext.IsEnabled=[bool]($s -and $script:guideIndex -lt $script:guideQueue.Count-1)
    $ui.GuideDone.IsEnabled=[bool]($s -and $s.NeedsReview -and $s.RunEpoch -eq $script:guideEpoch)
    $ui.GuideReload.IsEnabled=[bool]$s;$ui.GuideRules.IsEnabled=[bool]$s;$ui.GuideDetails.IsEnabled=[bool]$s
    if(-not $s){$ui.GuideName.Text='Offene Punkte gemeinsam durchgehen';$ui.GuidePath.Text='„Durchgang starten / neu laden“ übernimmt alle offenen Programme, unabhängig vom Filter der Programmliste.';$ui.GuideReason.Text='Keine pauschale Freigabe: Als geprüft markieren ändert keine Firewallregel.';$ui.GuideEvidence.ItemsSource=@();$ui.GuideStatus.Text='';$ui.GuideTempBlock.IsEnabled=$false;$ui.GuideSnapshotHint.Text='Die Reihenfolge bleibt während des Durchgangs fest. Neue Beobachtungen bleiben für die nächste Prüfung erhalten.';return}
    $ui.GuideName.Text=$guideQueue[$guideIndex].Name;$ui.GuidePath.Text=$s.Path;$ui.GuideReason.Text=$s.Reason
    $state=Get-PermissionStatus $s.Path;$ui.GuideStatus.Text='Aktueller Zugriff: '+$state.Status+' · '+(Get-ProgramLeaseText $s.Path)
    $ui.GuideEvidence.ItemsSource=@($s.Evidence)
    $ui.GuideSnapshotHint.Text='Angezeigter Stand: '+$s.TimeUtc.ToLocalTime().ToString('HH:mm:ss')+'. „Geprüft“ bestätigt nur diese Beobachtungen. Später eingetroffene Ziele/Versuche bleiben offen.'+$(if(-not $s.Evidence.Count){' Keine Gegenstelle aufgezeichnet; das belegt keine Unbedenklichkeit.'})
    $lease=if($script:setupStatus){$setupStatus.Config.ProgramLeases | Where-Object {[Netzblick.ProcessLineage]::Normalize($_.Path) -eq $s.Key} | Select-Object -First 1}else{$null}
    $ui.GuideTempBlock.IsEnabled=[bool]($script:setupStatus -and $setupStatus.Verified -and [IO.File]::Exists($s.Path) -and -not(Is-Protected $s.Path) -and -not $lease)
}
function Complete-GuideSnapshot {
    $s=$script:guideSnapshot;if(-not $s -or $s.RunEpoch -ne $script:guideEpoch){return}
    $targetBefore=@{};$baselineBefore=@{};$newBefore=$newPrograms[$s.Key]
    foreach($t in $s.Targets){$entry=$targetLedger[$t.Key];if($entry -and [datetime]$entry.FirstUtc -eq [datetime]$t.FirstUtc){$targetBefore[$t.Key]=$entry.Reviewed;$entry.Reviewed=$true}}
    if($script:setupStatus -and $setupStatus.StartedUtc.ToString('o') -eq $s.Epoch){
        foreach($staleKey in @($blockBaselines.Keys | Where-Object {$blockBaselines[$_].Epoch -ne $s.Epoch})){$baselineBefore[$staleKey]=$blockBaselines[$staleKey];$blockBaselines.Remove($staleKey)}
        foreach($b in $s.Counts){
        $baselineBefore[$b.Key]=$blockBaselines[$b.Key];$prior=$blockBaselines[$b.Key]
        $count=if($prior -and $prior.Epoch -eq $s.Epoch){[Math]::Max([long]$prior.Count,[long]$b.Count)}else{[long]$b.Count}
        if($blockBaselines.Count -lt 2000 -or $blockBaselines.ContainsKey($b.Key)){$blockBaselines[$b.Key]=[pscustomobject]@{Key=$b.Key;PathKey=$s.Key;Epoch=$s.Epoch;Count=$count}}
    }}
    if($null -ne $s.NewFirstUtc -and $newBefore -and [datetime]$newBefore.FirstUtc -eq [datetime]$s.NewFirstUtc){$newPrograms.Remove($s.Key)}
    $script:targetReviewCounts=$null
    try{Save-UserState -ThrowOnError}catch{
        foreach($k in $targetBefore.Keys){$targetLedger[$k].Reviewed=$targetBefore[$k]}
        foreach($k in $baselineBefore.Keys){if($baselineBefore[$k]){$blockBaselines[$k]=$baselineBefore[$k]}else{$blockBaselines.Remove($k)}}
        if($newBefore){$newPrograms[$s.Key]=$newBefore};$script:targetReviewCounts=$null;throw
    }
    Add-ProgramTimeline $s.Path 'Beobachtungen geprüft' ('Angezeigter Stand '+$s.TimeUtc.ToLocalTime().ToString('dd.MM. HH:mm:ss')+' bestätigt. Keine Firewalländerung; spätere Beobachtungen bleiben offen.')
    $guideQueue[$guideIndex].Done=$true;$script:guideIndex++;$script:guideSnapshot=$null
    Refresh-Overview;Select-GuideItem
}
function Initialize-WorkflowMode {
    $script:workflowReady=$true;$script:guideQueue=@();$script:guideIndex=0;$script:guideSnapshot=$null;$script:guideEpoch=[guid]::NewGuid().ToString('N')
    $ui.WorkflowTab.Add_Click({Show-Panel 'WorkflowPanel';Refresh-Guide;Refresh-Favorites})
    $ui.StartGuide.Add_Click({Start-GuidedReview});$ui.OverviewGuide.Add_Click({Start-GuidedReview})
    $ui.GuideBack.Add_Click({if($guideIndex -gt 0){$script:guideIndex--;Select-GuideItem}})
    $ui.GuideNext.Add_Click({if($guideIndex -lt $guideQueue.Count-1){$script:guideIndex++;Select-GuideItem}})
    $ui.GuideReload.Add_Click({Select-GuideItem})
    $ui.GuideDone.Add_Click({try{Complete-GuideSnapshot}catch{Show-Error $_.Exception.Message}})
    $ui.GuideTempBlock.Add_Click({if($guideSnapshot){Confirm-PermissionChange 'TemporaryBlockProgram' $guideSnapshot.Path;Refresh-Guide}})
    $ui.GuideRules.Add_Click({if($guideSnapshot){Open-Permissions $guideSnapshot.Path}})
    $ui.GuideDetails.Add_Click({if($guideSnapshot){Show-ReviewProgram $guideSnapshot.Path}})
    Refresh-Guide
}

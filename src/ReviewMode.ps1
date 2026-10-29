function Normalize-ReviewPath([string]$path){return [Netzblick.ProcessLineage]::Normalize($path)}
function Save-ReviewDecision([string]$path){
    $key=Normalize-ReviewPath $path;Mark-ProgramActivityReviewed $path;$script:newPrograms.Remove($key);Add-ProgramTimeline $path 'Programm geprüft' 'Aktuelle Beobachtungen als geprüft markiert; keine Firewalländerung.';Save-UserState;Refresh-Overview
}
function Show-ReviewProgram([string]$path){
    Show-NetzblickWindow;$ui.Search.Text='';$ui.ConnectionDirectionFilter.SelectedIndex=0;$ui.ProgramDetailTabs.SelectedIndex=0;Show-Panel 'LivePanel'
    $key=Normalize-ReviewPath $path
    $match=$ui.Programs.Items | Where-Object {$_.Key -eq $key} | Select-Object -First 1
    if($match){$ui.Programs.SelectedItem=$match;Refresh-Detail}else{Show-Panel 'OverviewPanel';$ui.UserNotice.Text='Das Programm ist derzeit nicht erfasst. Die Prüfliste bleibt gespeichert.'}
}
function Block-ReviewProgram([string]$path){
    try{
        if(Is-Protected $path){throw 'System-Sammelprozesse bitte über Einrichten & testen gezielt bewerten.'}
        if(-not $script:setupStatus -or -not $setupStatus.Verified){throw 'Filtersteuerung nicht bestätigt. Keine Sperre als erfolgreich gemeldet.'}
        $preview=Show-ChangePreview (Get-ChangePreview $path 'BlockProgram')
        if(-not $preview){return}
        Set-PermissionProgram $path 'BlockProgram' 10 $preview.ExpectedConfigKey
        Update-AccessMode;Refresh-Overview
        $ui.UserNotice.Text='Externe neue Verbindungen für '+[IO.Path]::GetFileName($path)+' gesperrt. Bereits übertragene Daten werden nicht zurückgenommen.'
        Add-Event 'Programm gesperrt' ([IO.Path]::GetFileName($path)) 'Ein- und ausgehend; Loopback bleibt ausgenommen. Regeln unter Einrichten & testen.'
    }catch{Show-Error $_.Exception.GetBaseException().Message}
}
function Get-ReviewTargets([string]$path){
    $key=Normalize-ReviewPath $path;$targets=New-Object 'System.Collections.Generic.List[string]'
    foreach($row in @($script:rows | Where-Object {(Normalize-ReviewPath $_.Path) -eq $key})){if($row.Address){$targets.Add($row.Protocol+' '+$row.Remote)}}
    foreach($peer in @($script:trafficPeers | Where-Object {(Normalize-ReviewPath $_.Path) -eq $key})){$targets.Add($peer.Protocol+' '+$peer.Address+':'+$peer.Port)}
    if($script:setupStatus){foreach($attempt in @($setupStatus.Attempts | Where-Object {(Normalize-ReviewPath $_.Path) -eq $key})){$targets.Add('Blockversuch: '+$attempt.Target)}}
    $unique=@($targets | Select-Object -Unique)
    return $(if($unique.Count){($unique | Select-Object -First 5)-join ' · '}else{'Keine Gegenstelle in dieser Sitzung erfasst. Anzeigen öffnet die Programmübersicht.'})
}
function Update-OverviewReviewActions {
    $entry=$ui.OverviewPrograms.SelectedItem
    $ready=[bool]($entry -and $entry.NeedsReview)
    $ui.OverviewReviewDetails.IsEnabled=$ready;$ui.OverviewReviewDone.IsEnabled=$ready
}
function Open-OverviewReviewDetails {
    $entry=$ui.OverviewPrograms.SelectedItem
    if(-not $entry){return}
    Show-ReviewProgram $entry.Path
    $ui.OnlyProgramBlocks.IsChecked=$false;$ui.OnlyProgramUnreviewed.IsChecked=$true
    $ui.ProgramDetailTabs.SelectedIndex=1;Refresh-Detail
}
function Refresh-ReviewPolicy {
    if(-not $ui.ContainsKey('ReviewPolicy')){return}
    $script:reviewPolicyRefreshing=$true
    try{
        $ui.ReviewPolicy.IsEnabled=[bool]$script:accessVerified
        $ui.ReviewPolicy.SelectedIndex=if($script:accessActive){1}else{0}
        $ui.ReviewPolicyHint.Text=if(-not $script:accessVerified){'Filterstatus unbekannt. Aktuelle Sperrwirkung nicht bestätigt.'}elseif($script:accessActive){'Unbekannte externe Verbindungen werden vor der Freigabe blockiert. Das betrifft auch bekannte Programme mit neuen Zielen. Freigaben und Rückweg unter Einrichten & testen.'}else{'Standard: Neue Programme dürfen zunächst kommunizieren. Die Prüfung erfolgt nach der Beobachtung; bestehende Sperren bleiben aktiv.'}
    }finally{$script:reviewPolicyRefreshing=$false}
}
function Show-ObservedNotice($entry){
    if(-not $script:reviewReady -or -not $script:notifyObserved -or $script:reviewToast -or $script:SmokeTest){return}
    $script:reviewToastPath=$entry.Path
    $toast=New-Object Windows.Window;$toast.Title='Netzblick · neues Programm';$toast.Width=440;$toast.SizeToContent='Height';$toast.ResizeMode='NoResize';$toast.WindowStyle='ToolWindow';$toast.ShowInTaskbar=$false;$toast.ShowActivated=$false;$toast.Topmost=$true;$toast.Resources=$window.Resources;$toast.Foreground=(Get-ThemeColor '#19283C');$toast.Background=(Get-ThemeColor '#F4F7FA')
    $stack=New-Object Windows.Controls.StackPanel;$stack.Margin='18'
    $title=New-Object Windows.Controls.TextBlock;$title.Text='Neues Programm: '+$entry.Name;$title.FontSize=18;$title.FontWeight='SemiBold';$title.TextWrapping='Wrap';$stack.Children.Add($title) | Out-Null
    $description=New-Object Windows.Controls.TextBlock;$description.Text=$(if($script:accessActive){'Verbindungsversuche prüfen. Freigabe ist erforderlich.'}else{'Darf zunächst kommunizieren. Jetzt Gegenstellen prüfen oder sperren.'})+[Environment]::NewLine+(Get-ReviewTargets $entry.Path);$description.Margin='0,10,0,12';$description.TextWrapping='Wrap';$stack.Children.Add($description) | Out-Null
    $buttons=New-Object Windows.Controls.StackPanel;$buttons.Orientation='Horizontal'
    foreach($label in @('Anzeigen','Sperren','Später')){$b=New-Object Windows.Controls.Button;$b.Content=$label;$b.Padding='12,7';$b.Margin='0,0,8,0';$buttons.Children.Add($b) | Out-Null}
    $buttons.Children[0].Add_Click({$path=$script:reviewToastPath;$reviewToast.Close();Show-ReviewProgram $path})
    $buttons.Children[1].IsEnabled=-not(Is-Protected $entry.Path)
    $buttons.Children[1].Add_Click({$path=$script:reviewToastPath;$reviewToast.Close();Block-ReviewProgram $path})
    $buttons.Children[2].Add_Click({$reviewToast.Close()})
    $stack.Children.Add($buttons) | Out-Null;$toast.Content=$stack
    $toast.WindowStartupLocation='Manual';$toast.Left=[Math]::Max(0,[Windows.SystemParameters]::WorkArea.Right-460);$toast.Top=[Math]::Max(0,[Windows.SystemParameters]::WorkArea.Bottom-230)
    $toast.Add_Closed({$script:reviewToast=$null});$script:reviewToast=$toast;$toast.Show()
}
function Initialize-ReviewMode {
    $script:reviewReady=$true
    $script:reviewToast=$null;$script:reviewToastPath='';$script:reviewPolicyRefreshing=$false
    $ui.NotifyObservedPrograms.IsChecked=$script:notifyObserved
    $ui.NotifyObservedPrograms.Add_Click({$script:notifyObserved=[bool]$ui.NotifyObservedPrograms.IsChecked;Save-UserState;if(-not $notifyObserved -and $script:reviewToast){$reviewToast.Close()}})
    $ui.ReviewShow.Add_Click({Set-OverviewFilter 2})
    $ui.OverviewPrograms.Add_SelectionChanged({if(-not $script:overviewItemsChanging){Update-OverviewReviewActions}})
    $ui.OverviewReviewDetails.Add_Click({Open-OverviewReviewDetails})
    $ui.OverviewReviewDone.Add_Click({if($ui.OverviewPrograms.SelectedItem){Save-ReviewDecision $ui.OverviewPrograms.SelectedItem.Path;Refresh-Detail}})
    $ui.ProgramReviewDetails.Add_Click({if($ui.Programs.SelectedItem){$ui.OnlyProgramBlocks.IsChecked=$false;$ui.OnlyProgramUnreviewed.IsChecked=$true;$ui.ProgramDetailTabs.SelectedIndex=1;Refresh-Detail}})
    $ui.OnlyProgramUnreviewed.Add_Click({Refresh-Detail})
    $ui.ReviewPolicy.Add_SelectionChanged({
        if($script:reviewPolicyRefreshing){return}
        if($ui.ReviewPolicy.SelectedIndex -eq 1 -and -not $script:accessActive){Start-AccessMode;if($script:accessActive){Show-Panel 'AccessPanel'}}
        elseif($ui.ReviewPolicy.SelectedIndex -eq 0 -and $script:accessActive){[void](Stop-AccessMode)}
        Refresh-ReviewPolicy
    })
    $window.Add_Closed({if($script:reviewToast){$reviewToast.Close()}})
    Refresh-ReviewPolicy
}

# Read-only host/service inspection; firewall actions stay in existing guarded views.
function Get-HostSocketRows($hostProcess){
    if(-not $hostProcess -or $hostProcess.StartUtc -eq [datetime]::MinValue){return @()}
    @($script:rows | Where-Object {$_.Pid -eq $hostProcess.Pid -and $_.ProcessStartUtc -eq $hostProcess.StartUtc})
}
function Refresh-Hosts {
    if(-not $script:hostsReady -or $ui.HostsPanel.Visibility -ne 'Visible'){return}
    $key=if($ui.HostsList.SelectedItem){$ui.HostsList.SelectedItem.Key}else{$script:hostSelectedKey}
    $term=$ui.HostsSearch.Text.Trim();$filter=$ui.HostsFilter.SelectedIndex
    $items=@(foreach($h in @($script:hostSnapshot.Hosts)){
        if(-not $h){continue}
        $sockets=@(Get-HostSocketRows $h);$state=Get-PermissionStatus $h.Path;$review=Get-ProgramReviewState $h.Path
        $searchText=$h.Name+' '+$h.Pid+' '+$h.Path+' '+(($h.Services | ForEach-Object {$_.Name+' '+$_.DisplayName+' '+$_.Description}) -join ' ')
        if($term -and $searchText.IndexOf($term,[StringComparison]::OrdinalIgnoreCase) -lt 0){continue}
        if(($filter -eq 1 -and -not $sockets.Count) -or ($filter -eq 2 -and $state.Category -notin @('Blocked','Limited')) -or ($filter -eq 3 -and -not $review.NeedsReview)){continue}
        [pscustomobject]@{Key=$h.Key;HostProcess=$h;Path=$h.Path;Title=($h.Name+' · PID '+$h.Pid);ServiceNames=(($h.Services | ForEach-Object {$_.Name}) -join ', ');SignalColor=$state.SignalColor;Summary=($h.Services.Count.ToString()+' Dienste · '+$sockets.Count+' Sockets · '+$state.Status);Status=$state.Status;NeedsReview=$review.NeedsReview}
    })
    $items=@($items | Sort-Object Title)
    $script:hostsRefreshing=$true
    try{
        $ui.HostsList.ItemsSource=$items
        $match=$items | Where-Object Key -eq $key | Select-Object -First 1
        if($match){$ui.HostsList.SelectedItem=$match}elseif(-not $key -and $items.Count){$ui.HostsList.SelectedIndex=0}
        # Never silently replace an ended or filtered selection with another PID.
    }finally{$script:hostsRefreshing=$false}
    $stamp=if($script:hostSnapshot){$hostSnapshot.Time.ToLocalTime().ToString('HH:mm:ss')}else{'noch keine Erfassung'}
    $ui.HostsSummary.Text=$items.Count.ToString()+' von '+@($script:hostSnapshot.Hosts).Count+' Hostprozessen · Dienste: '+$stamp
    if($script:hostProblem){$ui.HostsSummary.Text+=' · '+$script:hostProblem}
    elseif(-not $items.Count){$ui.HostsSummary.Text+=' · Keine passenden Hostprozesse.'}
    Show-HostSelection
}
function Show-HostSelection {
    $p=$ui.HostsList.SelectedItem
    $known=$p -and @($ui.Programs.Items | Where-Object {[Netzblick.ProcessLineage]::Normalize($_.Path) -eq [Netzblick.ProcessLineage]::Normalize($p.Path)}).Count -gt 0
    $ui.HostProgramDetails.IsEnabled=[bool]$known;$ui.HostRules.IsEnabled=[bool]($p -and $p.Path)
    $ui.HostProgramDetails.ToolTip=if($known){'Gemeinsame Angaben zu allen Instanzen dieses Dateipfads'}else{'Noch kein Eintrag in der Netzwerk-Programmübersicht; Dienste sind hier bereits einsehbar.'}
    $ui.HostConnections.ItemsSource=@();$ui.HostBlocks.ItemsSource=@()
    if(-not $p){$ui.HostServices.ItemsSource=@();$ui.HostServices.Tag=$null;$ui.HostTitle.Text='Kein Hostprozess ausgewählt';$ui.HostPath.Text='Auswahl beendet, ausgefiltert oder noch nicht erfasst. Einen Eintrag auswählen.';$ui.HostScope.Text='';$ui.HostBlockHint.Text='';return}
    $script:hostSelectedKey=$p.Key;$h=$p.HostProcess
    $ui.HostTitle.Text=$p.Title;$ui.HostPath.Text=$(if($h.Path){$h.Path}else{'Dateipfad nicht lesbar'})+' · Gestartet '+$h.StartUtc.ToLocalTime().ToString('dd.MM.yyyy HH:mm:ss')
    $ui.HostScope.Text='Aktueller Zugriff (Dateipfad): '+$p.Status+'. Dienst nicht eindeutig zugeordnet. Regeln und Prüffreigaben für diesen Dateipfad können mehrere Hostinstanzen und Dienste betreffen.'
    if(-not [object]::ReferenceEquals($ui.HostServices.Tag,$h)){$ui.HostServices.ItemsSource=@($h.Services | Sort-Object DisplayName);$ui.HostServices.Tag=$h}
    $ui.HostConnections.ItemsSource=@(Get-HostSocketRows $h | ForEach-Object {$direction=Get-ConnectionDirection $_ $h.Path;[pscustomobject]@{Direction=$direction.Label;Protocol=$_.Protocol;Local=$_.Local;Remote=$_.Remote;State=$_.State}})
    $blocks=@(if($h.Path){Get-ProgramBlockRows $h.Path $script:setupStatus})
    $ui.HostBlocks.ItemsSource=$blocks
    $ui.HostBlockHint.Text='Gemeinsame Sperrereignisse für den Dateipfad, seit Dienststart der Netzblick-Erfassung. Keine sichere Zuordnung zu dieser PID oder einem einzelnen Windows-Dienst.'+$(if(-not $blocks.Count){' Keine Ereignisse erfasst; das beweist keinen freien Netzwerkzugriff.'})
}
function Update-HostCapture {
    if(-not $script:hostsReady -or $script:paused -or $ui.HostsPanel.Visibility -ne 'Visible'){return}
    if($script:hostJob -and $hostJob.IsCompleted){
        try{
            if($hostJob.IsFaulted){throw $hostJob.Exception.GetBaseException()}
            $expansion=@{};foreach($old in @($script:hostSnapshot.Hosts)){if($old){foreach($service in $old.Services){$expansion[$old.Key+'|'+$service.Name]=$service.Expanded}}}
            $script:hostSnapshot=$hostJob.Result
            foreach($fresh in $hostSnapshot.Hosts){foreach($service in $fresh.Services){$service.Expanded=[bool]$expansion[$fresh.Key+'|'+$service.Name]}}
            $script:hostProblem=$hostSnapshot.Errors -join '; '
        }catch{$script:hostSnapshot=$null;$script:hostProblem='Dienste konnten nicht ermittelt werden: '+$_.Exception.Message}
        finally{$script:hostJob=$null;$script:hostNextRead=[datetime]::UtcNow.AddSeconds(10)}
        Refresh-Hosts
    }
    if(-not $script:hostJob -and [datetime]::UtcNow -ge $script:hostNextRead){$script:hostJob=[Netzblick.HostReader]::Start()}
    $ui.HostsRefresh.IsEnabled=-not [bool]$script:hostJob
}
function Initialize-HostsMode {
    $script:hostsReady=$true;$script:hostNextRead=[datetime]::MinValue;$script:hostSnapshot=$null;$script:hostJob=$null;$script:hostSelectedKey='';$script:hostProblem=''
    $ui.HostsTab.Add_Click({Show-Panel 'HostsPanel'})
    $ui.HostsRefresh.Add_Click({$script:hostNextRead=[datetime]::MinValue;Update-HostCapture})
    $ui.HostsSearch.Add_TextChanged({Refresh-Hosts});$ui.HostsFilter.Add_SelectionChanged({Refresh-Hosts})
    $ui.HostsList.Add_SelectionChanged({if(-not $script:hostsRefreshing){Show-HostSelection}})
    $ui.HostProgramDetails.Add_Click({if($ui.HostsList.SelectedItem){Show-ReviewProgram $ui.HostsList.SelectedItem.Path}})
    $ui.HostRules.Add_Click({if($ui.HostsList.SelectedItem){$path=$ui.HostsList.SelectedItem.Path;Open-Permissions $path;$ui.PermissionSearch.Text=$path;Refresh-Permissions}})
}

function Get-WorkspaceArea([string]$panel){
    switch($panel){
        'DashboardPanel'{'Dashboard'}
        'WorkflowPanel'{if($ui.WorkflowViews.SelectedIndex -eq 1){'Programs'}else{'Review'}}
        'InspectionPanel'{'Review'}
        'AccessPanel'{switch($ui.AccessViews.SelectedIndex){1{'Rules'} 2{'History'} default{'Review'}}}
        'RulesPanel'{'Rules'}
        'HistoryPanel'{'History'}
        {$_ -in @('UpdatesPanel','BackupPanel')}{'Settings'}
        default{'Programs'}
    }
}
function Navigate-Workspace([string]$page){
    switch($page){
        'Programs'{Show-Panel 'OverviewPanel'}
        'Favorites'{$ui.WorkflowViews.SelectedIndex=1;Show-Panel 'WorkflowPanel';Refresh-Favorites}
        'Hosts'{Show-Panel 'HostsPanel'}
        'Groups'{Show-Panel 'GroupsPanel';Refresh-Groups}
        'Guide'{$ui.WorkflowViews.SelectedIndex=0;Show-Panel 'WorkflowPanel';Refresh-Guide}
        'BeforeStart'{Show-Panel 'InspectionPanel'}
        'Connections'{$ui.AccessViews.SelectedIndex=0;Show-Panel 'AccessPanel'}
        'Rules'{$ui.AccessViews.SelectedIndex=1;Show-Panel 'AccessPanel'}
        'LegacyRules'{Show-Panel 'RulesPanel'}
        'Activities'{Show-Panel 'HistoryPanel'}
        'History'{$ui.AccessViews.SelectedIndex=2;Show-Panel 'AccessPanel'}
        'Backups'{Show-Panel 'BackupPanel';Refresh-BackupView}
        'Updates'{Show-Panel 'UpdatesPanel'}
    }
}
function Update-WorkspaceNavigation([string]$panel){
    if(-not $ui.ContainsKey('WorkspaceNavigation')){return}
    if(-not $panel){$panel=$script:activePanel}
    $area=Get-WorkspaceArea $panel
    $primary=switch($area){'Dashboard'{'DashboardTab'} 'Programs'{'OverviewTab'} 'Review'{'WorkflowTab'} 'Rules'{'OpenSetupRules'} 'History'{'OpenSetupHistory'} 'Settings'{'SettingsTab'}}
    foreach($name in @('DashboardTab','OverviewTab','WorkflowTab','OpenSetupRules','OpenSetupHistory','SettingsTab')){
        $ui[$name].SetResourceReference([Windows.Controls.Control]::BackgroundProperty,$(if($name -eq $primary){'AccentSoft'}else{'Raised'}))
        $ui[$name].SetResourceReference([Windows.Controls.Control]::ForegroundProperty,'Text')
    }
    $pages=switch($area){'Programs'{@('Programs','Favorites','Hosts','Groups')} 'Review'{@('Guide','BeforeStart','Connections')} 'Rules'{@('Rules','LegacyRules')} 'History'{@('History','Activities')} 'Settings'{@('Backups','Updates')} default{@()}}
    $current=switch($panel){'OverviewPanel'{'Programs'} 'LivePanel'{'Programs'} 'HostsPanel'{'Hosts'} 'GroupsPanel'{'Groups'} 'InspectionPanel'{'BeforeStart'} 'AccessPanel'{$(switch($ui.AccessViews.SelectedIndex){1{'Rules'} 2{'History'} default{'Connections'}})} 'RulesPanel'{'LegacyRules'} 'HistoryPanel'{'Activities'} 'UpdatesPanel'{'Updates'} 'BackupPanel'{'Backups'} 'WorkflowPanel'{$(if($ui.WorkflowViews.SelectedIndex -eq 1){'Favorites'}else{'Guide'})} default{''}}
    foreach($page in @('Programs','Favorites','Hosts','Groups','Guide','BeforeStart','Connections','Rules','LegacyRules','History','Activities','Backups','Updates')){
        $button=$ui['Nav'+$page];$button.Visibility=if($page -in $pages){'Visible'}else{'Collapsed'}
        $button.SetResourceReference([Windows.Controls.Control]::BackgroundProperty,$(if($page -eq $current){'AccentSoft'}else{'Raised'}))
    }
    $ui.AccessIntroduction.Visibility=if($ui.AccessViews.SelectedIndex -eq 0){'Visible'}else{'Collapsed'}
    $ui.WorkflowTitle.Text=if($ui.WorkflowViews.SelectedIndex -eq 1){'Favoriten'}else{'Offene Programme bewerten'}
    $ui.WorkspaceNavigation.Visibility=if($pages.Count){'Visible'}else{'Collapsed'}
    $ui.MainShell.RowDefinitions[1].Height=if($pages.Count){[Windows.GridLength]::Auto}else{[Windows.GridLength]::new(0)}
}
function Initialize-NavigationMode {
    foreach($page in @('Programs','Favorites','Hosts','Groups','Guide','BeforeStart','Connections','Rules','LegacyRules','History','Activities','Backups','Updates')){$ui['Nav'+$page].Tag=$page;$ui['Nav'+$page].Add_Click({param($sender,$e) Navigate-Workspace $sender.Tag})}
    $ui.SettingsTab.Add_Click({Navigate-Workspace 'Backups'})
    $ui.AccessViews.Add_SelectionChanged({if($script:activePanel -eq 'AccessPanel'){Update-WorkspaceNavigation 'AccessPanel'}})
    $ui.WorkflowViews.Add_SelectionChanged({if($script:activePanel -eq 'WorkflowPanel'){Update-WorkspaceNavigation 'WorkflowPanel'}})
}

function Get-StartupDesignStyle($savedStyle){if($savedStyle -in @('Clean','Future')){return $savedStyle};return 'Future'}
function Get-EffectivePalette([bool]$dark){
    $palette=Get-ThemePalette $dark
    if($script:designStyle -eq 'Future'){
        $overrides=if($dark){@{AppBg='#07121C';Surface='#0C1B28';Sidebar='#08151F';Raised='#112A3B';Alternate='#0D202E';Input='#081824';Text='#EDF8FF';Muted='#ADC5D7';Border='#2B4F65';Accent='#10D9EC';AccentSoft='#103D49';OnAccent='#032029';Blue='#75CFFF';Danger='#FF7B87';DangerSoft='#3B222E';Warning='#FFC16B';WarningSoft='#372D20';Success='#63E5B0';SuccessSoft='#143C33'}}else{@{AppBg='#EAF2F8';Surface='#F9FDFF';Sidebar='#DFEDF4';Raised='#E0EEF6';Alternate='#EDF6FA';Input='#F5FBFF';Text='#102C40';Muted='#426276';Border='#9FBECD';Accent='#006A84';AccentSoft='#CAEAF1';OnAccent='#FFFFFF';Blue='#006D9B';Danger='#AD243B';DangerSoft='#F9DFE6';Warning='#835100';WarningSoft='#FFF0CE';Success='#006747';SuccessSoft='#D4EFE3'}}
        foreach($key in $overrides.Keys){$palette[$key]=$overrides[$key]}
    }
    return $palette
}
function Get-ApplicationIcon([string]$path,[switch]$Always){
    if(($script:designStyle -ne 'Future' -and -not $Always) -or -not [Netzblick.AccessQueue]::CanAllow($path)){return $null}
    if($null -eq $script:appIconCache){$script:appIconCache=@{}}
    $key=[Netzblick.ProcessLineage]::Normalize($path)
    if($appIconCache.ContainsKey($key)){return $appIconCache[$key]}
    if($appIconCache.Count -ge 256){return $null}
    $icon=$null;$bitmap=$null
    try{
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        if([IO.File]::Exists($path)){$icon=[Drawing.Icon]::ExtractAssociatedIcon($path)}
        if($icon){$bitmap=[Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon($icon.Handle,[Windows.Int32Rect]::Empty,[Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions());$bitmap.Freeze()}
    }catch{}finally{if($icon){$icon.Dispose()}}
    $appIconCache[$key]=$bitmap;return $bitmap
}
function Set-WorkspaceLayout([string]$panel){
    if(-not $ui.ContainsKey('ProgramWorkspace')){return}
    if(-not $panel){$panel='OverviewPanel'}
    $future=$script:designStyle -eq 'Future';$workspace=$panel -in @('OverviewPanel','LivePanel')
    $ui.ProgramWorkspace.Visibility=if($workspace){'Visible'}else{'Collapsed'}
    if(-not $workspace){return}
    $split=$future -and -not $script:futureDetailFocused
    $overview=$split -or $panel -eq 'OverviewPanel'
    $details=$split -or $panel -eq 'LivePanel'
    if($future -and $script:futureDetailFocused){$overview=$false;$details=$true}
    $ui.OverviewFrame.Visibility=if($overview){'Visible'}else{'Collapsed'};$ui.OverviewPanel.Visibility=$ui.OverviewFrame.Visibility
    $ui.DetailFrame.Visibility=if($details){'Visible'}else{'Collapsed'};$ui.LivePanel.Visibility=$ui.DetailFrame.Visibility
    $ui.WorkspaceSplitter.Visibility=if($split){'Visible'}else{'Collapsed'}
    $ui.ProgramWorkspace.ColumnDefinitions[0].Width=if($overview){[Windows.GridLength]::new($(if($split){54}else{1}),[Windows.GridUnitType]::Star)}else{[Windows.GridLength]::new(0)}
    $ui.ProgramWorkspace.ColumnDefinitions[1].Width=[Windows.GridLength]::new($(if($split){16}else{0}))
    $ui.ProgramWorkspace.ColumnDefinitions[2].Width=if($details){[Windows.GridLength]::new($(if($split){46}else{1}),[Windows.GridUnitType]::Star)}else{[Windows.GridLength]::new(0)}
    $ui.ProgramWorkspace.ColumnDefinitions[0].MinWidth=if($split){420}else{0}
    $ui.ProgramWorkspace.ColumnDefinitions[2].MinWidth=if($split){420}else{0}
    $ui.MainShell.RowDefinitions[2].Height=[Windows.GridLength]::new($(if($future){0}elseif($panel -eq 'LivePanel'){32}else{0}))
}
function Set-DesignAppearance {
    if(-not $ui.ContainsKey('DesignSelector')){return}
    $future=$script:designStyle -eq 'Future'
    $visible=if($future){[Windows.Visibility]::Visible}else{[Windows.Visibility]::Collapsed}
    $cleanVisible=if($future){[Windows.Visibility]::Collapsed}else{[Windows.Visibility]::Visible}
    $palette=Get-EffectivePalette ([bool]$script:darkMode)
    $window.Resources['AppIconVisibility']=$visible;$window.Resources['FutureChromeVisibility']=$visible;$window.Resources['CleanDetailVisibility']=$cleanVisible
    $window.Resources['CardCorner']=[Windows.CornerRadius]::new($(if($future){2}else{10}))
    $window.Resources['ButtonCorner']=[Windows.CornerRadius]::new($(if($future){2}else{6}))
    $window.Resources['WorkspaceBorder']=[Windows.Thickness]::new($(if($future){1}else{0}))
    $window.Resources['WorkspacePadding']=[Windows.Thickness]::new($(if($future){12}else{0}))
    $window.Resources['ChromeOutline']=if($future){$window.Resources['Border']}else{[Windows.Media.Brushes]::Transparent}
    $window.Resources['PanelBackdrop']=if($future){$window.Resources['Surface']}else{[Windows.Media.Brushes]::Transparent}
    $shell=[Windows.Media.LinearGradientBrush]::new();$shell.StartPoint=[Windows.Point]::new(0,0);$shell.EndPoint=[Windows.Point]::new(1,1)
    $shell.GradientStops.Add([Windows.Media.GradientStop]::new([Windows.Media.ColorConverter]::ConvertFromString($(if($future -and $script:darkMode){'#102839'}elseif($future){'#F5FCFF'}else{$palette.AppBg})),0))
    $shell.GradientStops.Add([Windows.Media.GradientStop]::new([Windows.Media.ColorConverter]::ConvertFromString($palette.AppBg),0.65));$shell.Freeze();$window.Resources['ShellBackground']=$shell
    $window.Resources['ActionsExpanderTemplate']=$window.Resources[$(if($future){'FutureActionsTemplate'}else{'CleanActionsTemplate'})]
    $script:designChanging=$true
    try{$ui.DesignSelector.SelectedIndex=if($future){1}else{0}}finally{$script:designChanging=$false}
    $ui.FutureLogo.Visibility=$visible;$ui.FutureStats.Visibility=$visible;$ui.FuturePrimaryActions.Visibility=$visible;$ui.FutureConnectionCard.Visibility=$visible;$ui.ProgramInfoToggle.Visibility=$visible;$ui.ExpandProgramDetails.Visibility=$visible
    $ui.ReviewSummaryCard.Visibility=$cleanVisible;
    $ui.BackToPrograms.Visibility=$cleanVisible;$ui.ProgramMapExpander.Visibility=$cleanVisible;$ui.OverviewQuickActions.Visibility=$cleanVisible
    if($future){$glow=[Windows.Media.Effects.DropShadowEffect]::new();$glow.Color=[Windows.Media.ColorConverter]::ConvertFromString($palette.Accent);$glow.BlurRadius=14;$glow.ShadowDepth=0;$glow.Opacity=0.35;$ui.FutureLogo.Effect=$glow}else{$ui.FutureLogo.Effect=$null}
    $ui.BrandTitle.Text=if($future){'NETZBLICK'}else{'◈ Netzblick'};$ui.BrandTitle.FontSize=if($future){19}else{24}
    $ui.BrandTitle.HorizontalAlignment=if($future){'Center'}else{'Left'}
    $ui.WorkspaceTitle.Text=if($future){'Dein Netzwerk. Klar im Blick.'}else{'Dein Netzwerk'};$ui.WorkspaceTitle.FontSize=if($future){26}else{24}
    $ui.ProgramListTitle.Text=if($future){'Programme'}else{'Deine Programme'};$ui.ProgramListTitle.FontSize=if($future){21}else{27}
    $ui.ProgramListHint.Text=if($future){'Ampel = aktueller Zugriff · App auswählen für Details'}else{'Ampel = aktueller Zugriff · Blockzähler = erfasste Ereignisse · Doppelklick öffnet die Details'}
    $ui.ProgramSearchHint.Visibility=$cleanVisible;$ui.OverviewStatus.Visibility=$cleanVisible
    $ui.ProgramPolicyCard.SetResourceReference([Windows.Controls.Border]::BackgroundProperty,'AccentSoft')
    $ui.ProgramExplanation.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,'Text')
    $ui.ProgramPolicyCard.Padding=[Windows.Thickness]::new($(if($future){14}else{20}));$ui.ProgramExplanation.FontSize=if($future){17}else{19}
    $ui.ProgramIcon.Source=Get-ApplicationIcon $(if($ui.Programs.SelectedItem){$ui.Programs.SelectedItem.Path}else{''})
    $ui.ProgramInfoGrid.Visibility=if(-not $future -or $ui.ProgramInfoToggle.IsExpanded){'Visible'}else{'Collapsed'}
    [Windows.Controls.DockPanel]::SetDock($ui.OverviewFooterButtons,$(if($future){'Top'}else{'Right'}))
    $ui.OverviewPrograms.RowHeight=if($future){78}else{90}
    $ui.OverviewPrograms.Columns[0].MinWidth=if($future){170}else{260}
    $ui.OverviewPrograms.Columns[1].Width=[Windows.Controls.DataGridLength]::new($(if($future){135}else{155}))
    for($i=2;$i -le 5;$i++){$ui.OverviewPrograms.Columns[$i].Visibility=$cleanVisible}
    $ui.OverviewPrograms.Columns[6].Visibility=$visible
    foreach($name in @('WorkflowTab','HostsTab','DashboardTab','OverviewTab','AccessTab','InspectionTab','OpenSetupRules','OpenSetupHistory','UpdatesTab')){
        $ui[$name].HorizontalContentAlignment=if($future){'Left'}else{'Center'}
        $ui[$name].FontSize=if($future){13}else{12};$ui[$name].Height=if($future){40}else{[double]::NaN}
    }
    Update-OverviewFilterChrome
    Set-WorkspaceLayout $script:activePanel
    if($script:dashboardReady){Draw-Dashboard}
    if($script:hostsReady){Refresh-Hosts}
    if($script:experienceReady){Refresh-Favorites;Update-FavoriteButtons}
}
function Set-DesignStyle([string]$style){
    if($style -notin @('Clean','Future')){throw 'Unbekanntes Design.'}
    $script:designStyle=$style;$script:futureDetailFocused=$false
    Set-NetzblickTheme ([bool]$script:darkMode)
    Refresh-Overview;Refresh-Detail;Save-UserState
}
function Sync-FutureProgramSelection {
    if($script:designStyle -ne 'Future' -or $script:overviewItemsChanging -or $script:futureSelectionChanging){return}
    $script:futureSelectionChanging=$true
    try{
        $p=$ui.OverviewPrograms.SelectedItem
        $previous=if($ui.Programs.SelectedItem){$ui.Programs.SelectedItem.Key}else{''}
        $match=if($p){$ui.Programs.Items | Where-Object {$_.Key -eq $p.Key} | Select-Object -First 1}else{$null}
        $ui.Programs.SelectedItem=$match
        if($match -and $match.Key -ne $previous){$ui.ProgramDetailTabs.SelectedIndex=0}
        Refresh-Detail
    }finally{$script:futureSelectionChanging=$false}
}
function Update-FutureProgramPresentation($program,$last,$lease){
    if($script:designStyle -ne 'Future'){return}
    $ui.ProgramIcon.Source=Get-ApplicationIcon $(if($program){$program.Path}else{''})
    $category=if($program){(Get-PermissionStatus $program.Path).Category}else{'Unknown'}
    $role=switch($category){'Blocked'{if($lease){'WarningSoft'}else{'DangerSoft'}} 'Allowed'{'SuccessSoft'} 'Limited'{'WarningSoft'} 'Unknown'{'Raised'} default{'AccentSoft'}}
    $ui.ProgramPolicyCard.SetResourceReference([Windows.Controls.Border]::BackgroundProperty,$role)
    $ui.FuturePrimaryEnd.Content=if($lease -and $lease.EffectiveAction -eq 'Block'){'Sperre beenden …'}else{'Freigabe beenden …'}
    foreach($name in @('FuturePrimaryBlock','FuturePrimaryTempBlock','FuturePrimaryAllow')){$ui[$name].Visibility=if($lease){'Collapsed'}else{'Visible'}}
    $ui.FutureLastBlockCard.Visibility=if($last){'Visible'}else{'Collapsed'}
    $ui.FutureBlockTarget.Text=if($last){$last.Target+' · '+$last.LastUtc.ToLocalTime().ToString('HH:mm:ss')}else{''}
    $ui.FutureBlockReason.Text=if($last){$last.Evidence}else{''}
}
function Draw-FutureProgramMap($program,$displayRows){
    if($script:designStyle -ne 'Future' -or -not $ui.ContainsKey('FutureProgramMap')){return}
    $canvas=$ui.FutureProgramMap;$overlay=New-Object Windows.Controls.Canvas;$overlay.Width=1000;$overlay.Height=500
    Initialize-WorldCanvas $canvas $overlay
    $origin=$ui.OriginCountry.SelectedItem
    if($origin){Add-CountryMarker $overlay $origin $origin.Code ('Manuell gewähltes Startland: '+$origin.Name) (Get-ThemeColor '#087F8C')}
    $plotted=0
    foreach($group in @($displayRows | Where-Object Address | Group-Object Address | Select-Object -First 30)){
        $location=Geo-Location $group.Name
        if(-not $location.CanPlot){continue}
        $blocked=@($group.Group | Where-Object IsBlock).Count -gt 0
        $color=if($blocked){Get-ThemeColor '#B32D40'}else{Get-ThemeColor '#1672B6'}
        if($origin){Add-CountryLine $overlay $origin $location $color $blocked}
        Add-CountryMarker $overlay $location $location.Code ($group.Name+' · '+$location.Country+$(if($blocked){' · Blockversuch'}else{' · Beobachtung'})) $color
        $plotted++
    }
    if(-not $plotted){Add-VisualText $overlay 'Keine zuordenbaren Ziele erfasst' 260 245 '#B8DAFA' 22}
}
function Initialize-DesignMode {
    $script:futureDetailFocused=$false;$script:overviewItemsChanging=$false;$script:futureSelectionChanging=$false
    Set-DesignAppearance
    $ui.DesignSelector.Add_SelectionChanged({if(-not $script:designChanging){Set-DesignStyle $(if($ui.DesignSelector.SelectedIndex -eq 1){'Future'}else{'Clean'})}})
    $ui.OverviewPrograms.Add_SelectionChanged({if($script:activePanel -in @('OverviewPanel','LivePanel')){Sync-FutureProgramSelection}})
    $ui.ExpandProgramDetails.Add_Click({$script:futureDetailFocused=-not $script:futureDetailFocused;Set-WorkspaceLayout 'LivePanel'})
    $ui.ProgramInfoToggle.Add_Expanded({$ui.ProgramInfoGrid.Visibility='Visible'})
    $ui.ProgramInfoToggle.Add_Collapsed({if($script:designStyle -eq 'Future'){$ui.ProgramInfoGrid.Visibility='Collapsed'}})
    foreach($pair in @(@('FuturePrimaryBlock','ProgramQuickBlock'),@('FuturePrimaryTempBlock','ProgramQuickTempBlock'),@('FuturePrimaryAllow','ProgramQuickAllow'),@('FuturePrimaryEnd','ProgramQuickEndTemporary'),@('FuturePrimaryReview','ProgramQuickReview'))){
        $ui[$pair[0]].Tag=$pair[1];$ui[$pair[0]].Add_Click({param($sender,$e) $ui[$sender.Tag].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))})
    }
    $ui.FutureOpenConnections.Add_Click({$ui.ProgramDetailTabs.SelectedIndex=1})
}

function Get-ThemePalette([bool]$dark){
    if($dark){return @{AppBg='#0D1420';Surface='#151F2E';Sidebar='#101A28';Raised='#202D40';Alternate='#192638';Input='#0F1928';Text='#E8EFF8';Muted='#A8B8CE';Border='#34455E';Accent='#61D5C9';AccentSoft='#193E43';OnAccent='#082023';Blue='#80BCFF';Inbound='#BEA0FF';Danger='#FF8496';DangerSoft='#462935';Warning='#F4C378';WarningSoft='#3B3020';Success='#70DCB4';SuccessSoft='#173E34';MapBg='#0A1B2C';MapBorder='#27405B';ConsoleBg='#08111C';ConsoleText='#B5F4DF'}}
    return @{AppBg='#F4F7FA';Surface='#FFFFFF';Sidebar='#EEF2F6';Raised='#EDF2F6';Alternate='#F0F5F8';Input='#F5F8FA';Text='#19283C';Muted='#57677B';Border='#D5E0E8';Accent='#087F8C';AccentSoft='#DDF0F2';OnAccent='#FFFFFF';Blue='#1672B6';Inbound='#713CB1';Danger='#B32D40';DangerSoft='#F9E5E7';Warning='#996000';WarningSoft='#FFF3D9';Success='#08704E';SuccessSoft='#E0F2EB';MapBg='#0A1B2C';MapBorder='#27405B';ConsoleBg='#08111C';ConsoleText='#69DAC3'}
}
function Get-ThemeColor([string]$color){
    if(-not $script:darkMode -and $script:designStyle -ne 'Future'){return $color}
    $role=switch($color.ToUpperInvariant()){
        '#19283C'{'Text'} '#57677B'{'Muted'} '#52657A'{'Muted'}
        '#B32D40'{'Danger'} '#AF3B4B'{'Danger'} '#C44152'{'Danger'}
        '#996000'{'Warning'} '#A4680B'{'Warning'} '#9C650A'{'Warning'}
        '#08704E'{'Success'} '#087F8C'{'Accent'} '#1672B6'{'Blue'}
        '#F4F7FA'{'AppBg'} '#EDF2F6'{'Raised'} '#DDF0F2'{'AccentSoft'}
        '#F9E5E7'{'DangerSoft'} '#FFF3D9'{'WarningSoft'} default{''}
    }
    if($role){return (Get-EffectivePalette ([bool]$script:darkMode))[$role]};return $color
}
function Set-NetzblickTheme([bool]$dark){
    $script:darkMode=$dark;$palette=Get-EffectivePalette $dark
    foreach($key in $palette.Keys){$window.Resources[$key]=[Windows.Media.SolidColorBrush]::new([Windows.Media.ColorConverter]::ConvertFromString($palette[$key]))}
    $window.Resources[[Windows.SystemColors]::WindowBrushKey]=$window.Resources['Surface']
    $window.Resources[[Windows.SystemColors]::WindowTextBrushKey]=$window.Resources['Text']
    $window.Resources[[Windows.SystemColors]::ControlBrushKey]=$window.Resources['Raised']
    $window.Resources[[Windows.SystemColors]::ControlTextBrushKey]=$window.Resources['Text']
    $window.Resources[[Windows.SystemColors]::HighlightBrushKey]=$window.Resources['AccentSoft']
    $window.Resources[[Windows.SystemColors]::HighlightTextBrushKey]=$window.Resources['Text']
    $ui.ThemeToggle.Content=if($dark){'☀ Hell'}else{'☾ Dunkel'}
    $ui.ThemeToggle.ToolTip='Farbschema umschalten · wird für den nächsten Start gespeichert'
    Set-DesignAppearance
}
function Initialize-Theme {
    Set-NetzblickTheme ([bool]$script:darkMode)
    $ui.ThemeToggle.Add_Click({
        Set-NetzblickTheme (-not $script:darkMode);Save-UserState
        if(Get-Command Refresh-ProgramSignals -ErrorAction SilentlyContinue){Refresh-ProgramSignals}
        Refresh-Overview;Refresh-Detail
        if(Get-Command Draw-Latency -ErrorAction SilentlyContinue){Draw-Latency}
        if($ui.WorldPanel.Visibility -eq 'Visible'){Refresh-World -Rebuild}
    })
}

function Set-NavigationTheme([string]$panel){
    $active=switch($panel){'WorkflowPanel'{'WorkflowTab'} 'HostsPanel'{'HostsTab'} 'DashboardPanel'{'DashboardTab'} 'OverviewPanel'{'OverviewTab'} 'InspectionPanel'{'InspectionTab'} 'UpdatesPanel'{'UpdatesTab'} 'AccessPanel'{'AccessTab'} 'RulesPanel'{'OpenSetupRules'} 'HistoryPanel'{'OpenSetupHistory'} default{'OverviewTab'}}
    foreach($name in @('WorkflowTab','HostsTab','DashboardTab','OverviewTab','LiveTab','AccessTab','InspectionTab','UpdatesTab','OpenSetupRules','OpenSetupHistory')){
        $button=$ui[$name]
        $button.SetResourceReference([Windows.Controls.Control]::BackgroundProperty,$(if($name -eq $active){'AccentSoft'}else{'Raised'}))
        $button.SetResourceReference([Windows.Controls.Control]::ForegroundProperty,'Text')
    }
}

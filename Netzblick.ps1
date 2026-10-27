#requires -Version 5.1
[CmdletBinding()]
param([switch]$Check,[Alias('Tray')][switch]$LaunchInTray,[switch]$SmokeTest,[switch]$Embedded,[switch]$Portable,[string]$StateDirectory)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName @('PresentationFramework','PresentationCore','WindowsBase')

try {
    if (-not $Check) {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            $exe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
            Start-Process -FilePath $exe -Verb RunAs -ArgumentList ('-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'+$(if($LaunchInTray){' -Tray'}else{''}))
            exit
        }
    }
    $script:appRoot=$PSScriptRoot
    $script:startInTray=[bool]$LaunchInTray
    if(-not $Check){
        $created=$false
        $script:uiMutex=New-Object Threading.Mutex($true,('Local\Netzblick.UI.'+$identity.User.Value),[ref]$created)
        if(-not $created){[void][Windows.MessageBox]::Show('Netzblick läuft bereits. Über das Tray-Symbol öffnen.','Netzblick');exit}
    }
    # Windows PowerShell 5.1 does not reference System.Xml automatically.
    $coreReferences = @('System.dll','System.Core.dll','System.Xml.dll','System.Web.Extensions.dll','System.ServiceProcess.dll','System.Security.dll')
    if(-not $Embedded){
        Add-Type -ReferencedAssemblies $coreReferences -Path @((Join-Path $appRoot 'src\NetworkReader.cs'),(Join-Path $appRoot 'src\GeoDatabase.cs'),(Join-Path $appRoot 'src\ProbeSession.cs'),(Join-Path $appRoot 'src\InspectionCore.cs'),(Join-Path $appRoot 'src\WindowsInspection.cs'),(Join-Path $appRoot 'src\NetworkPolicyCore.cs'),(Join-Path $appRoot 'src\EndpointInfo.cs'),(Join-Path $appRoot 'src\AccessCore.cs'),(Join-Path $appRoot 'src\WindowsAccess.cs'),(Join-Path $appRoot 'src\AccessWatch.cs'),(Join-Path $appRoot 'src\SetupCore.cs'),(Join-Path $appRoot 'src\SetupTransport.cs'),(Join-Path $appRoot 'src\ReleaseUpdates.cs'))
    }
    [xml]$xaml = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'src\MainWindow.xaml') -Raw -Encoding UTF8
    $reader = New-Object System.Xml.XmlNodeReader($xaml)
    $script:window = [Windows.Markup.XamlReader]::Load($reader)
    $window.Title='Netzblick 0.15.0'+$(if($Portable){' · Portabel'}else{''})
    $script:ui = @{}
    $xaml.GetElementsByTagName('*') | ForEach-Object {
        $name = $_.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml')
        if ($name) { $control=$window.FindName($name);if($null -ne $control){$script:ui[$name]=$control} }
    }
    foreach($panelName in @('World','Terminal','Inspection','Overview','Access','Updates')){
        [xml]$panelXaml=Get-Content -LiteralPath (Join-Path $appRoot ('src\'+$panelName+'Panel.xaml')) -Raw -Encoding UTF8
        $panelReader=New-Object System.Xml.XmlNodeReader($panelXaml)
        $panel=[Windows.Markup.XamlReader]::Load($panelReader)
        $ui[$panelName+'Panel'].Content=$panel
        $panelXaml.GetElementsByTagName('*') | ForEach-Object {
            $controlName=$_.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml')
            if($controlName){$ui[$controlName]=$panel.FindName($controlName)}
        }
    }
    if ($Check) {
        $snapshot = [Netzblick.Reader]::Collect()
        if ($snapshot.Errors.Count -gt 0) { throw ($snapshot.Errors -join '; ') }
        $checkGeo=New-Object Netzblick.GeoDatabase((Join-Path $appRoot 'data'))
        if(-not $checkGeo.Lookup('1.1.1.1').Code){throw 'Geo-Datenbanktest fehlgeschlagen.'}
        [void][Netzblick.ProbeCommand]::Parse('tracert -6 example.org')
        [void][Windows.Media.Geometry]::Parse([IO.File]::ReadAllText((Join-Path $appRoot 'data\world.path')))
        if([Netzblick.InspectionAuditFlags]::WithFailure(1) -ne 3){throw 'Audit-Logiktest fehlgeschlagen.'}
        if ($ui.get_Count() -lt 65) { throw 'UI-Elemente fehlen.' }
        Write-Output ('OK: XAML geladen, C# kompiliert, {0} Sockets, {1} Adapter. Keine Firewalländerung.' -f $snapshot.Rows.Count,$snapshot.Adapters.Count)
        if($Embedded){return}else{exit 0}
    }
    $script:policy = New-Object -ComObject HNetCfg.FwPolicy2
    $script:rows = @()
    $script:ownRules = @()
    $script:events = New-Object 'System.Collections.Generic.List[object]'
    $script:seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $script:previous = $null
    $script:job = $null
    $script:paused = $false
    $script:refreshing = $false
    $script:ruleError = ''
    $script:lastRuleRead = [datetime]::MinValue
    $script:group = 'Netzblick.Local.v1'

    . (Join-Path $appRoot 'src\ThemeMode.ps1')
    . (Join-Path $appRoot 'src\DesignMode.ps1')
    . (Join-Path $appRoot 'src\WorkspaceMode.ps1')
    . (Join-Path $appRoot 'src\ActivityReview.ps1')
    . (Join-Path $appRoot 'src\VisualModes.ps1')
    . (Join-Path $appRoot 'src\InspectionMode.ps1')
    . (Join-Path $appRoot 'src\FirewallNames.ps1')
    . (Join-Path $appRoot 'src\UserModes.ps1')
    . (Join-Path $appRoot 'src\EndpointNames.ps1')
    . (Join-Path $appRoot 'src\AccessMode.ps1')
    . (Join-Path $appRoot 'src\PermissionMode.ps1')
    . (Join-Path $appRoot 'src\ProgramCatalog.ps1')
    . (Join-Path $appRoot 'src\TrayMode.ps1')
    . (Join-Path $appRoot 'src\ReviewMode.ps1')
    . (Join-Path $appRoot 'src\UpdatesMode.ps1')
    . (Join-Path $appRoot 'src\SessionMode.ps1')
    . (Join-Path $appRoot 'src\WorldNavigation.ps1')

    function Show-Error([string]$message) {
        [void][Windows.MessageBox]::Show($window,$message,'Netzblick','OK','Error')
    }
    function Rule-Base([string]$path) {
        $hash = [Security.Cryptography.SHA256]::Create()
        try { $bytes = $hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($path.ToUpperInvariant())) }
        finally { $hash.Dispose() }
        return 'Netzblick.v1.' + ([BitConverter]::ToString($bytes).Replace('-',''))
    }
    function Add-Event([string]$kind,[string]$program,[string]$detail) {
        $script:events.Insert(0,[pscustomobject]@{ Time=(Get-Date -Format 'HH:mm:ss'); Event=$kind; Program=$program; Detail=$detail })
        while ($events.Count -gt 500) { $events.RemoveAt($events.Count-1) }
    }
    function Refresh-Rules {
        $list = New-Object 'System.Collections.Generic.List[object]'
        try {
            foreach ($rule in $policy.Rules) {
                if (-not (Test-OwnedNetworkRule $rule)) { continue }
                $list.Add([pscustomobject]@{ Name=$rule.Name; Path=$rule.ApplicationName; Program=[IO.Path]::GetFileName($rule.ApplicationName); Direction=$(if($rule.Direction -eq 1){'Eingehend'}else{'Ausgehend'}); Enabled=[bool]$rule.Enabled; Action=[int]$rule.Action; Protocol=[int]$rule.Protocol; Profiles=[int]$rule.Profiles; DirectionId=[int]$rule.Direction; RemoteAddresses=[string]$rule.RemoteAddresses; LocalAddresses=[string]$rule.LocalAddresses; LocalPorts=[string]$rule.LocalPorts; RemotePorts=[string]$rule.RemotePorts; InterfaceTypes=[string]$rule.InterfaceTypes; ServiceName=[string]$rule.ServiceName; EdgeTraversal=[bool]$rule.EdgeTraversal; Interfaces=$rule.Interfaces })
            }
            $script:ownRules = @($list.ToArray())
            $script:ruleError = ''
            $ui.Rules.ItemsSource = $script:ownRules
            $ui.BlockedCount.Text = [string](@($ownRules | Where-Object {$_.Enabled -and $_.Action -eq 0} | Select-Object -ExpandProperty Path -Unique).Count)
            $profiles = @(@{Id=1;Name='Domäne'},@{Id=2;Name='Privat'},@{Id=4;Name='Öffentlich'})
            $active = [int]$policy.CurrentProfileTypes
            $disabled = @($profiles | Where-Object { ($active -band $_.Id) -and -not $policy.FirewallEnabled($_.Id) })
            $restricted = [int]$policy.LocalPolicyModifyState
            if ($disabled.Count -gt 0) {
                $ui.FirewallStatus.Text = 'Firewall aus: '+(($disabled | ForEach-Object {$_.Name}) -join ', ')
                $ui.FirewallStatus.Foreground = (Get-ThemeColor '#AF3B4B')
            } elseif ($restricted -ne 0) {
                $ui.FirewallStatus.Text = 'Firewall aktiv · lokale Regeln eingeschränkt'
                $ui.FirewallStatus.Foreground = (Get-ThemeColor '#9C650A')
            } else {
                $ui.FirewallStatus.Text = 'Windows-Firewall aktiv'
                $ui.FirewallStatus.Foreground = (Get-ThemeColor '#087F8C')
            }
            $script:lastRuleRead = Get-Date
        } catch {
            $script:ruleError = $_.Exception.Message
            $ui.FirewallStatus.Text = 'Firewallstatus nicht verfügbar'
            $ui.FirewallStatus.Foreground = (Get-ThemeColor '#9C650A')
        }
    }
    function Is-Protected([string]$path) {
        if ([string]::IsNullOrWhiteSpace($path)) { return $true }
        $filename = [IO.Path]::GetFileName($path).ToLowerInvariant()
        return $filename -in @('svchost.exe','lsass.exe','services.exe','wininit.exe','winlogon.exe','smss.exe','system','msmpeng.exe','mpssvc.exe')
    }
    function Format-Rate([double]$value) {
        if ($value -ge 1048576) { return ('{0:N2} MB/s' -f ($value/1048576)) }
        if ($value -ge 1024) { return ('{0:N1} KB/s' -f ($value/1024)) }
        return ('{0:N0} B/s' -f $value)
    }
    function Map-Label([string]$text,[double]$x,[double]$y,[double]$width,[string]$color=(Get-ThemeColor '#19283C'),[int]$fontSize=13) {
        $label = New-Object Windows.Controls.TextBlock
        $label.Text=$text; $label.Width=$width; $label.FontSize=$fontSize; $label.Foreground=$color
        $label.TextTrimming='CharacterEllipsis'; $label.ToolTip=$text
        [Windows.Controls.Canvas]::SetLeft($label,$x); [Windows.Controls.Canvas]::SetTop($label,$y)
        [void]$ui.Map.Children.Add($label)
    }
    function Draw-Map($program,$sockets) {
        Draw-FutureProgramMap $program $sockets
        $ui.Map.Children.Clear()
        if ($null -eq $program) { Map-Label 'Keine passenden Programme gefunden.' 20 100 550; return }
        $peers = @($sockets | Where-Object {$_.Address} | Group-Object Remote | Sort-Object Count -Descending)
        Map-Label $program.Name 6 100 165 (Get-ThemeColor '#19283C') 18
        Map-Label ($sockets.Count.ToString()+' Beobachtungen') 6 128 160 (Get-ThemeColor '#57677B')
        if ($peers.Count -eq 0) { Map-Label 'Keine Gegenstelle erfasst' 230 105 350 (Get-ThemeColor '#57677B'); return }
        $limit=[Math]::Min(6,$peers.Count)
        for ($i=0;$i -lt $limit;$i++) {
            $y=18+$i*34
            $line=New-Object Windows.Shapes.Path
            $line.Stroke=(Get-ThemeColor '#1672B6'); $line.StrokeThickness=2
            $line.Data=[Windows.Media.Geometry]::Parse(('M 170,120 C 235,120 250,{0} 330,{0}' -f ($y+8)))
            [void]$ui.Map.Children.Add($line)
            $label=$peers[$i].Group[0].PeerName
            if(-not $label -or $label -notlike '*(Reverse-DNS)'){$label=$peers[$i].Name}
            Map-Label $label 342 $y 250 (Get-ThemeColor '#57677B')
        }
        if ($peers.Count -gt $limit) { Map-Label ('+ '+($peers.Count-$limit)+' weitere Gegenstellen in der Tabelle') 230 225 360 (Get-ThemeColor '#57677B') 11 }
    }
    function Refresh-Detail {
        $program=$ui.Programs.SelectedItem
        foreach($key in @('ModeDefault','ModePrivate','ModeBlocked')){$ui[$key].IsEnabled=$false}
        if($null -eq $program){$ui.ProgramTitle.Text='Programm auswählen';$ui.ProgramPath.Text='';$ui.ProgramStatus.Text='';$ui.ProgramTraffic.Text='';$ui.ProgramSignal.Fill=(Get-ThemeColor '#57677B');$ui.ProgramAccessRules.IsEnabled=$false;$ui.Connections.ItemsSource=@();$ui.BlockReasonText.Text='Programm auswählen.';$ui.ProgramExplanation.Text='Programm auswählen.';$ui.ProgramShortState.Text='';$ui.ProgramActivityReview.Text='';$ui.ProgramReviewDetails.Visibility='Collapsed';$ui.ProgramRules.ItemsSource=@();Update-FutureProgramPresentation $null $null $null;Update-QuickActions;Draw-Map $null @();return}
        $selected=$ui.Connections.SelectedItem;$socketKey=if($selected){$selected.Key}else{''}
        $ui.ProgramTitle.Text=$program.Name;$ui.ProgramPath.Text=$program.Path
        $signal=Get-PermissionStatus $program.Path;$ui.ProgramSignal.Fill=$signal.SignalColor;$ui.ProgramSignal.ToolTip=$signal.SignalHint;$ui.ProgramAccessRules.IsEnabled=[Netzblick.AccessQueue]::CanAllow($program.Path)
        $displayRows=@($program.Rows)
        foreach($peer in @($trafficPeers | Where-Object {[Netzblick.ProcessLineage]::Normalize($_.Path) -eq $program.Key})){$displayRows+=@([pscustomobject]@{Key=('ETW|'+$peer.Protocol+'|'+$peer.Address+'|'+$peer.Port);Pid='aggregiert';Protocol=$peer.Protocol;Local='— (ETW)';Remote=($peer.Address+':'+$peer.Port);Address=$peer.Address;Port=$peer.Port;State='ETW beobachtet'})}
        $blockRows=@(Get-ProgramBlockRows $program.Path $script:setupStatus)
        $ui.ShowProgramBlocks.Content='Blockversuche anzeigen ('+$blockRows.Count+' Ziele / Filter)';$ui.ShowProgramBlocks.IsEnabled=$blockRows.Count -gt 0
        $ui.ProgramBlockHint.Text=if($blockRows.Count){'Erfasste Sperren seit Dienststart. Aktuell: '+$signal.Status+'. Ein erlaubtes Programm kann frühere oder fremde Sperren in der Liste haben.'}else{'Keine erfassten Blockversuche für dieses Programm. Das beweist keinen fehlenden Netzwerkzugriff.'}
        if($ui.OnlyProgramBlocks.IsChecked){$displayRows=$blockRows}else{$displayRows=@($blockRows)+@($displayRows)}
        if(-not $ui.OnlyProgramBlocks.IsChecked){$displayRows+=@(Get-UnreviewedTargetRows $program.Path $displayRows)}
        $endpointIndex=0
        $displayRows=@($displayRows | ForEach-Object {
            $endpointIndex++
            [pscustomobject]@{Key=$_.Key;Pid=$_.Pid;Protocol=$_.Protocol;Local=$_.Local;Remote=$_.Remote;Address=$_.Address;Port=$_.Port;State=$_.State;TargetReview=(Get-TargetReviewLabel $program.Path $_);IsBlock=[bool]$_.IsBlock;BlockReason=$_.BlockReason;Count=$_.Count;FirstUtc=$_.FirstUtc;LastUtc=$_.LastUtc;FilterId=$_.FilterId;PeerName=$(if($ui.ResolveNames.IsChecked -and $endpointIndex -gt 100){'DNS: nur die ersten 100 Einträge'}else{Get-EndpointName $_.Address});ServiceHint=([Netzblick.EndpointInfo]::Service($_.Protocol,[int]$_.Port))}
        })
        if($ui.OnlyProgramUnreviewed.IsChecked){$displayRows=@($displayRows | Where-Object TargetReview);$ui.ProgramBlockHint.Text='Ungeprüfte Ziele und neue Blockversuche: '+$displayRows.Count+'. Frühere Ziele sind ausdrücklich gekennzeichnet. Nach der Prüfung kannst du das Programm als geprüft markieren.'}
        $ui.Connections.ItemsSource=$displayRows
        $restore=$displayRows | Where-Object {$_.Key -eq $socketKey} | Select-Object -First 1
        if($restore){$ui.Connections.SelectedItem=$restore}elseif($ui.OnlyProgramBlocks.IsChecked -and $displayRows.Count){$ui.Connections.SelectedIndex=0}
        Show-ConnectionDetails
        $mode=try{Get-NetworkMode $program.Path @($ownRules | Where-Object {$_.Path -eq $program.Path})}catch{'Modified'}
        $ui.ProgramStatus.Text=Network-ModeLabel $mode
        $ui.ProgramStatus.Text='Frühere Windows-Regeln: '+$ui.ProgramStatus.Text
        if($script:setupStatus -and $setupStatus.Verified){
            $watched=@($setupStatus.Config.WatchedPaths | Where-Object {[Netzblick.ProcessLineage]::Normalize($_) -eq [Netzblick.ProcessLineage]::Normalize($program.Path)}).Count -gt 0
            $ruleCount=@($setupStatus.Config.Rules | Where-Object {$_.Path -eq '*' -or [Netzblick.ProcessLineage]::Normalize($_.Path) -eq [Netzblick.ProcessLineage]::Normalize($program.Path)}).Count
            $ui.ProgramStatus.Text+=[Environment]::NewLine+'Dienst: '+$(if($watched){'Prüfsperre vorhanden'}elseif($accessActive){'Nachfragen aktiv'}else{'Beobachten'})+' · '+$ruleCount+' Einzelregeln; Details unter Regeln'
        }else{$ui.ProgramStatus.Text+=[Environment]::NewLine+'Dienststatus unbekannt'}
        foreach($key in @('ModeDefault','ModePrivate','ModeBlocked')){$ui[$key].IsEnabled=(-not (Is-Protected $program.Path)) -and (-not $ruleError) -and $mode -ne 'Modified' -and -not $script:accessActive}
        $sample=$trafficSamples[$program.Key]
        $ui.ProgramTraffic.Text=if($sample){'Seit Netzblick-Start (ETW):'+"`n↑ "+(Format-Bytes $sample.Sent)+' gesendet'+"`n↓ "+(Format-Bytes $sample.Received)+' empfangen'+"`n"+$(if($sample.RateReady){(Format-Rate $sample.SentRate)+' ↑ · '+(Format-Rate $sample.ReceivedRate)+' ↓'}else{'Rate wird ermittelt …'})}else{'Für diesen Programmpfad bisher keine Byte-Messung verfügbar.'}
        if($trafficProblem){$ui.ProgramTraffic.Text+="`nMessung eingeschränkt: "+$trafficProblem}
        Update-ProgramPresentation $program
        Draw-Map $program $displayRows
        if($socketKey){$match=$displayRows | Where-Object {$_.Key -eq $socketKey} | Select-Object -First 1;if($match){$ui.Connections.SelectedItem=$match}}
    }
    function Refresh-Programs {
        $selected=$ui.Programs.SelectedItem;$selectedKey=if($selected){$selected.Key}else{''}
        $script:allProgramItems=@(Get-ProgramCatalog $rows @($trafficSamples.Values) (@($script:newPrograms.Values)+@(Get-ReviewCatalogEntries)) $script:setupStatus $script:ownRules | Sort-Object Name)
        foreach($p in $allProgramItems){Set-ProgramSignal $p}
        Track-ObservedPrograms @($allProgramItems | Where-Object Observed)
        $term=$ui.Search.Text.Trim()
        $items=@($allProgramItems | Where-Object {-not $term -or $_.Name.IndexOf($term,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or $_.Path.IndexOf($term,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or @($_.Rows | Where-Object {$_.Remote.IndexOf($term,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or $_.Local.IndexOf($term,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or [string]$_.Pid -eq $term}).Count -gt 0 -or $_.BlockedTargets.IndexOf($term,[StringComparison]::OrdinalIgnoreCase) -ge 0})
        $script:refreshing=$true;$ui.Programs.ItemsSource=$items
        $match=$items | Where-Object {$_.Key -eq $selectedKey} | Select-Object -First 1
        if($match){$ui.Programs.SelectedItem=$match}elseif($items.Count){$ui.Programs.SelectedIndex=0}
        $script:refreshing=$false
        Refresh-Detail;Refresh-Overview
    }
    function Remove-ProgramRules([string]$path) {
        if($script:policyReady){Set-NetworkMode $path 'Default';return}
        if($script:inspectionActive -and ($inspection.Path -eq $path -or @($inspectionNodes | Where-Object {$_.Path -eq $path}).Count -gt 0)){throw 'Diese Datei gehört zur laufenden Prüfung. Bitte zuerst die Prüfung beenden.'}
        foreach($rule in @(Read-NetworkRules $path)){$policy.Rules.Remove($rule.Name)}
        Refresh-Rules
        if ($ruleError -or @($ownRules | Where-Object {$_.Path -eq $path}).Count -gt 0) { throw 'Sperre konnte nicht vollständig entfernt werden.' }
        Add-Event 'Eigene Sperre entfernt' ([IO.Path]::GetFileName($path)) $path
        Refresh-Detail
    }
    function Set-ProgramBlock([string]$path) {
        if($script:policyReady){Set-NetworkMode $path 'Blocked';return}
        if(Is-Protected $path){throw 'Dieser Prozess kann nicht pauschal gesperrt werden.'}
        Set-NetworkMode $path 'Blocked' -NoHistory
    }
    $ui.RemoveRule.Add_Click({
        $rule=$ui.Rules.SelectedItem
        if($null -eq $rule){return}
        try{Remove-ProgramRules $rule.Path}catch{Refresh-Rules;Show-Error $_.Exception.Message}
    })
    $ui.Programs.Add_SelectionChanged({if(-not $script:refreshing){Refresh-Detail}})
    $ui.Search.Add_TextChanged({Refresh-Programs})
    $ui.Connections.Add_SelectionChanged({Show-ConnectionDetails})
    function Show-Panel([string]$name) {
        $script:activePanel=$name;if($name -eq 'OverviewPanel'){$script:futureDetailFocused=$false}
        $compact=$name -in @('AccessPanel','OverviewPanel','UpdatesPanel','InspectionPanel','WorldPanel')
        $ui.MainShell.RowDefinitions[1].Height=[Windows.GridLength]::new(0)
        $ui.MainShell.RowDefinitions[2].Height=if($compact){[Windows.GridLength]::new(0)}else{[Windows.GridLength]::new(32)}
        $ui.SummaryMetrics.Visibility='Collapsed'
        Set-NavigationTheme $name
        foreach($key in @('OverviewPanel','LivePanel','WorldPanel','TerminalPanel','InspectionPanel','RulesPanel','HistoryPanel','AccessPanel','UpdatesPanel')){$ui[$key].Visibility=if($key -eq $name){'Visible'}else{'Collapsed'}}
        $ui.Search.Visibility='Collapsed'
        $ui.History.ItemsSource=$events.ToArray()
        if($name -eq 'WorldPanel'){Refresh-World -Rebuild}
        Set-WorkspaceLayout $name
        if($name -eq 'OverviewPanel'){Refresh-Overview}
    }
    $ui.OpenSetupRules.Add_Click({Show-Panel 'AccessPanel';$ui.AccessViews.SelectedIndex=1})
    $ui.OpenSetupHistory.Add_Click({Show-Panel 'AccessPanel';$ui.AccessViews.SelectedIndex=2})
    $ui.AccessTab.Add_Click({Show-Panel 'AccessPanel'})
    $ui.OverviewTab.Add_Click({Show-Panel 'OverviewPanel'})
    $ui.UpdatesTab.Add_Click({Show-Panel 'UpdatesPanel'})
    foreach($key in @('BackFromRules','BackFromHistory','BackFromWorld','BackFromTerminal')){$ui[$key].Add_Click({Show-Panel 'LivePanel'})}
    $ui.LiveTab.Add_Click({Show-Panel 'LivePanel'})
    $ui.InspectionTab.Add_Click({Show-Panel 'InspectionPanel'})
    $ui.Pause.Add_Click({
        $script:paused=-not $script:paused
        $ui.Pause.Content=if($paused){'▶ Ansicht fortsetzen'}else{'Ⅱ Ansicht pausieren'}
        if($paused){$ui.Status.Text='Aktivitätsansicht pausiert · Kontrollmodus und Prüfansicht aktualisieren weiter.'}
        else{$script:previous=$null;$script:seen.Clear()}
    })
    $ui.Export.Add_Click({
        $dialog=New-Object Microsoft.Win32.SaveFileDialog
        $dialog.Filter='CSV-Datei (*.csv)|*.csv';$dialog.FileName='Netzblick-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.csv'
        if($dialog.ShowDialog($window)) {
            try {
                if($ui.OverviewPanel.Visibility -eq 'Visible'){$data=@($ui.OverviewPrograms.Items | Select-Object -Property @('Name','Path','Status','Sent','Received','Rate'))}
                elseif($ui.HistoryPanel.Visibility -eq 'Visible'){$data=@($events.ToArray())}
                elseif($ui.RulesPanel.Visibility -eq 'Visible'){$data=@($ownRules)}
                elseif($ui.WorldPanel.Visibility -eq 'Visible'){$data=@($worldPeers | Select-Object -Property @('Program','Address','Country','Code','Count','Kind'))}
                elseif($ui.InspectionPanel.Visibility -eq 'Visible'){$data=@($inspectionRows | Select-Object -Property @('Program','Path','Direction','Address','Protocol','Port','Count','LastUtc','OwnBlock'))}
                elseif($ui.AccessPanel.Visibility -eq 'Visible'){$data=@($setupStatus.Attempts | Select-Object -Property @('Program','Path','Direction','Address','Protocol','Port','Count','LastUtc','OwnBlock'))}
                elseif($ui.TerminalPanel.Visibility -eq 'Visible'){$data=@($probeRows.ToArray() | Select-Object -Property @('Number','Attempt','Address','Latency','Status','Country','Code'))}
                else{$data=@($rows | Select-Object -Property @('Program','Pid','Path','Protocol','Local','Remote','State'))}
                if($data.Count -eq 0){throw 'Die gewählte Ansicht enthält noch keine Daten zum Exportieren.'}
                # Prevent spreadsheet formulas if a process or path starts with a formula marker.
                $safe=@($data | ForEach-Object {
                    $copy=[ordered]@{}
                    foreach($prop in $_.PSObject.Properties){$value=[string]$prop.Value;if($value -match '^[\s]*[=+@-]'){$value="'"+$value};$copy[$prop.Name]=$value}
                    [pscustomobject]$copy
                })
                $safe | Export-Csv -LiteralPath $dialog.FileName -NoTypeInformation -Delimiter ';' -Encoding UTF8
                $ui.Status.Text='Export gespeichert: '+$dialog.FileName
            }catch{Show-Error $_.Exception.Message}
        }
    })
    Initialize-VisualModes
    Refresh-Rules
    Initialize-UserModes
    Rename-OwnedNetworkRules
    Initialize-Theme
    Initialize-DesignMode
    Initialize-WorkspaceMode
    Initialize-EndpointNames
    Initialize-InspectionMode
    $script:programCatalogReady=$true
    Initialize-AccessMode
    Initialize-ReviewMode
    Initialize-QuickActions
    Initialize-BlockDetails
    Initialize-Updates
    $ui.ResetNetzblick.Add_Click({Reset-NetzblickSession})
    Initialize-TrayMode
    Show-Panel 'OverviewPanel'
    $timer=New-Object Windows.Threading.DispatcherTimer
    $timer.Interval=[timespan]::FromMilliseconds(250)
    $script:nextSample=[datetime]::MinValue
    $timer.Add_Tick({
        try {
            if($script:paused){return}
            if($null -ne $script:job -and $script:job.IsCompleted){
                if($script:job.IsFaulted){$failure=$script:job.Exception.GetBaseException().Message;$script:job=$null;throw $failure}
                $snapshot=$script:job.Result;$script:job=$null
                $script:rows=@($snapshot.Rows.ToArray())
                $current=New-Object 'System.Collections.Generic.HashSet[string]'
                foreach($row in $rows){[void]$current.Add($row.Key);if(-not $seen.Contains($row.Key)){Add-Event 'Socket beobachtet' $row.Program ($row.Protocol+' · '+$row.Remote+' · '+$row.State)}}
                $script:seen=$current
                if($null -ne $previous){
                    $seconds=($snapshot.Time-$previous.Time).TotalSeconds
                    if($seconds -gt 0){
                        [double]$rx=0;[double]$tx=0
                        foreach($adapter in $snapshot.Adapters){
                            $old=$previous.Adapters | Where-Object {$_.Id -eq $adapter.Id} | Select-Object -First 1
                            if($old){$rx += [Math]::Max(0,$adapter.Received-$old.Received);$tx += [Math]::Max(0,$adapter.Sent-$old.Sent)}
                        }
                        $ui.Download.Text=Format-Rate ($rx/$seconds);$ui.Upload.Text=Format-Rate ($tx/$seconds)
                    }
                }else{$ui.Download.Text='Messung …';$ui.Upload.Text='Messung …'}
                $script:previous=$snapshot
                $tcp=@($rows | Where-Object {$_.State -eq 'Verbunden'}).Count
                $udp=@($rows | Where-Object {$_.Protocol.StartsWith('UDP')}).Count
                $ui.Count.Text="$tcp / $udp"
                if(((Get-Date)-$lastRuleRead).TotalSeconds -gt 5){Refresh-Rules}
                Update-Traffic
                Refresh-Programs
                if($ui.WorldPanel.Visibility -eq 'Visible'){Refresh-World -Rebuild}
                if($ui.HistoryPanel.Visibility -eq 'Visible'){$ui.History.ItemsSource=$events.ToArray()}
                $ui.Status.Text='Aktualisiert '+(Get-Date -Format 'HH:mm:ss')+' · IPv4 + IPv6 · 2-Sekunden-Stichproben · Adapterwerte können VPN/virtuelle Adapter doppelt zählen.'
                if($snapshot.Errors.Count){$ui.Status.Text+=' Teilfehler: '+($snapshot.Errors -join '; ')}
                if($ruleError){$ui.Status.Text+=' Firewall: '+$ruleError}
                $script:nextSample=(Get-Date).AddSeconds(2)
            }
            if($null -eq $script:job -and (Get-Date) -ge $nextSample){$script:job=[Netzblick.Reader]::Start()}
        }catch{$ui.Status.Text='Erfassungsfehler: '+$_.Exception.Message;$script:nextSample=(Get-Date).AddSeconds(5)}
    })
    $window.Add_Closed({if($script:uiMutex){$uiMutex.ReleaseMutex();$uiMutex.Dispose()};$timer.Stop();$probeTimer.Stop();if($null -ne $script:probe){$script:probe.Cancel()}})
    $timer.Start()
    if($SmokeTest){
        $script:smokeTimer=New-Object Windows.Threading.DispatcherTimer
        $smokeTimer.Interval=[timespan]::FromSeconds(3)
        $smokeTimer.Add_Tick({$smokeTimer.Stop();$script:exitNetzblick=$true;$window.Close()})
        $smokeTimer.Start()
    }
    $script:application=New-Object Windows.Application
    $application.ShutdownMode='OnMainWindowClose'
    [void]$application.Run($window)
    if($SmokeTest){
        if($Embedded -and $script:trafficProblem){throw ('Datenmessung: '+$script:trafficProblem)}
        Write-Output 'PASS: full WPF/tray initialization and orderly close.'
        if($Embedded){return}else{exit 0}
    }
    if($Embedded){Write-Output 'NETZBLICK_UI_OK'}
} catch {
    $message=$_.Exception.Message
    if($Check -or $SmokeTest){Write-Error ($message+[Environment]::NewLine+$_.ScriptStackTrace);exit 1}
    [void][Windows.MessageBox]::Show("Netzblick konnte nicht starten.`n`n$message",'Netzblick','OK','Error')
    Write-Error $message
    exit 1
}



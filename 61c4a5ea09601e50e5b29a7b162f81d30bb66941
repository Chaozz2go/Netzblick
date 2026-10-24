#requires -Version 5.1
[CmdletBinding()]
param([switch]$Check)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName @('PresentationFramework','PresentationCore','WindowsBase')

try {
    if (-not $Check) {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            $exe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
            Start-Process -FilePath $exe -Verb RunAs -ArgumentList ('-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"')
            exit
        }
    }
    $script:appRoot=$PSScriptRoot
    # Windows PowerShell 5.1 does not reference System.Xml automatically.
    $coreReferences = @('System.dll','System.Core.dll','System.Xml.dll')
    Add-Type -ReferencedAssemblies $coreReferences -Path @((Join-Path $appRoot 'src\NetworkReader.cs'),(Join-Path $appRoot 'src\GeoDatabase.cs'),(Join-Path $appRoot 'src\ProbeSession.cs'),(Join-Path $appRoot 'src\InspectionCore.cs'),(Join-Path $appRoot 'src\WindowsInspection.cs'),(Join-Path $appRoot 'src\NetworkPolicyCore.cs'))
    [xml]$xaml = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'src\MainWindow.xaml') -Raw -Encoding UTF8
    $reader = New-Object System.Xml.XmlNodeReader($xaml)
    $script:window = [Windows.Markup.XamlReader]::Load($reader)
    $script:ui = @{}
    $xaml.GetElementsByTagName('*') | ForEach-Object {
        $name = $_.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml')
        if ($name) { $control=$window.FindName($name);if($null -ne $control){$script:ui[$name]=$control} }
    }
    foreach($panelName in @('World','Terminal','Inspection','Overview')){
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
        if ($ui.Count -lt 65) { throw 'UI-Elemente fehlen.' }
        Write-Output ('OK: XAML geladen, C# kompiliert, {0} Sockets, {1} Adapter. Keine Firewalländerung.' -f $snapshot.Rows.Count,$snapshot.Adapters.Count)
        exit 0
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

    . (Join-Path $appRoot 'src\VisualModes.ps1')
    . (Join-Path $appRoot 'src\InspectionMode.ps1')
    . (Join-Path $appRoot 'src\UserModes.ps1')

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
                if ($rule.Grouping -ne $group -or [string]::IsNullOrWhiteSpace($rule.ApplicationName)) { continue }
                $base = Rule-Base $rule.ApplicationName
                if ($rule.Name -ne ($base+'.In') -and $rule.Name -ne ($base+'.Out')) { continue }
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
                $ui.FirewallStatus.Foreground = '#FF7E85'
            } elseif ($restricted -ne 0) {
                $ui.FirewallStatus.Text = 'Firewall aktiv · lokale Regeln eingeschränkt'
                $ui.FirewallStatus.Foreground = '#F5C477'
            } else {
                $ui.FirewallStatus.Text = 'Windows-Firewall aktiv'
                $ui.FirewallStatus.Foreground = '#39DCC0'
            }
            $script:lastRuleRead = Get-Date
        } catch {
            $script:ruleError = $_.Exception.Message
            $ui.FirewallStatus.Text = 'Firewallstatus nicht verfügbar'
            $ui.FirewallStatus.Foreground = '#F5C477'
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
    function Map-Label([string]$text,[double]$x,[double]$y,[double]$width,[string]$color='#E5EDF7',[int]$fontSize=13) {
        $label = New-Object Windows.Controls.TextBlock
        $label.Text=$text; $label.Width=$width; $label.FontSize=$fontSize; $label.Foreground=$color
        $label.TextTrimming='CharacterEllipsis'; $label.ToolTip=$text
        [Windows.Controls.Canvas]::SetLeft($label,$x); [Windows.Controls.Canvas]::SetTop($label,$y)
        [void]$ui.Map.Children.Add($label)
    }
    function Draw-Map($program,$sockets) {
        $ui.Map.Children.Clear()
        if ($null -eq $program) { Map-Label 'Keine passenden Programme gefunden.' 20 100 550; return }
        $peers = @($sockets | Where-Object {$_.Address} | Group-Object Remote | Sort-Object Count -Descending)
        Map-Label $program.Name 6 100 165 '#E5EDF7' 18
        Map-Label ($sockets.Count.ToString()+' Beobachtungen') 6 128 160 '#91ADC8'
        if ($peers.Count -eq 0) { Map-Label 'Keine Gegenstelle erfasst' 230 105 350 '#91ADC8'; return }
        $limit=[Math]::Min(6,$peers.Count)
        for ($i=0;$i -lt $limit;$i++) {
            $y=18+$i*34
            $line=New-Object Windows.Shapes.Path
            $line.Stroke='#4EA5FF'; $line.StrokeThickness=2
            $line.Data=[Windows.Media.Geometry]::Parse(('M 170,120 C 235,120 250,{0} 330,{0}' -f ($y+8)))
            [void]$ui.Map.Children.Add($line)
            Map-Label $peers[$i].Name 342 $y 250 '#B8DAFA'
        }
        if ($peers.Count -gt $limit) { Map-Label ('+ '+($peers.Count-$limit)+' weitere Gegenstellen in der Tabelle') 230 225 360 '#91ADC8' 11 }
    }
    function Refresh-Detail {
        $program=$ui.Programs.SelectedItem
        foreach($key in @('ModeDefault','ModePrivate','ModeBlocked')){$ui[$key].IsEnabled=$false}
        if($null -eq $program){$ui.ProgramTitle.Text='Programm auswählen';$ui.ProgramPath.Text='';$ui.ProgramStatus.Text='';$ui.ProgramTraffic.Text='';$ui.Connections.ItemsSource=@();Draw-Map $null @();return}
        $selected=$ui.Connections.SelectedItem;$socketKey=if($selected){$selected.Key}else{''}
        $ui.ProgramTitle.Text=$program.Name;$ui.ProgramPath.Text=$program.Path
        $displayRows=@($program.Rows)
        foreach($peer in @($trafficPeers | Where-Object {[Netzblick.ProcessLineage]::Normalize($_.Path) -eq $program.Key})){$displayRows+=@([pscustomobject]@{Key=('ETW|'+$peer.Protocol+'|'+$peer.Address+'|'+$peer.Port);Pid='aggregiert';Protocol=$peer.Protocol;Local='— (ETW)';Remote=($peer.Address+':'+$peer.Port);Address=$peer.Address;State='ETW beobachtet'})}
        $ui.Connections.ItemsSource=$displayRows;$ui.SocketDetails.Text='Eine Tabellenzeile auswählen.'
        $mode=try{Get-NetworkMode $program.Path @($ownRules | Where-Object {$_.Path -eq $program.Path})}catch{'Modified'}
        $ui.ProgramStatus.Text=Network-ModeLabel $mode
        foreach($key in @('ModeDefault','ModePrivate','ModeBlocked')){$ui[$key].IsEnabled=(-not (Is-Protected $program.Path)) -and (-not $ruleError) -and $mode -ne 'Modified'}
        $sample=$trafficSamples[$program.Key]
        $ui.ProgramTraffic.Text=if($sample){'Seit Netzblick-Start (ETW):'+"`n↑ "+(Format-Bytes $sample.Sent)+' gesendet'+"`n↓ "+(Format-Bytes $sample.Received)+' empfangen'+"`n"+$(if($sample.RateReady){(Format-Rate $sample.SentRate)+' ↑ · '+(Format-Rate $sample.ReceivedRate)+' ↓'}else{'Rate wird ermittelt …'})}else{'Für diesen Programmpfad bisher keine Byte-Messung verfügbar.'}
        if($trafficProblem){$ui.ProgramTraffic.Text+="`nMessung eingeschränkt: "+$trafficProblem}
        Draw-Map $program $displayRows
        if($socketKey){$match=$displayRows | Where-Object {$_.Key -eq $socketKey} | Select-Object -First 1;if($match){$ui.Connections.SelectedItem=$match}}
    }
    function Refresh-Programs {
        $selected=$ui.Programs.SelectedItem;$selectedKey=if($selected){$selected.Key}else{''}
        $map=@{}
        foreach($g in @($rows | Group-Object {if($_.Path){$_.Path.ToUpperInvariant()}else{'PID:'+$_.Pid}})){
            $first=$g.Group[0];$map[$g.Name]=[pscustomobject]@{Key=$g.Name;Name=$first.Program;Path=$first.Path;Summary=($g.Count.ToString()+' Sockets');Rows=@($g.Group)}
        }
        foreach($sample in @($trafficSamples.Values)){
            if(-not $map.ContainsKey($sample.Key)){$map[$sample.Key]=[pscustomobject]@{Key=$sample.Key;Name=$sample.Name;Path=$sample.Path;Summary='In dieser Sitzung gemessen';Rows=@()}}
        }
        $script:allProgramItems=@($map.Values | Sort-Object Name)
        Track-ObservedPrograms $allProgramItems
        $term=$ui.Search.Text.Trim()
        $items=@($allProgramItems | Where-Object {-not $term -or $_.Name.IndexOf($term,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or $_.Path.IndexOf($term,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or @($_.Rows | Where-Object {$_.Remote.IndexOf($term,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or $_.Local.IndexOf($term,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or [string]$_.Pid -eq $term}).Count -gt 0})
        $script:refreshing=$true;$ui.Programs.ItemsSource=$items
        $match=$items | Where-Object {$_.Key -eq $selectedKey} | Select-Object -First 1
        if($match){$ui.Programs.SelectedItem=$match}elseif($items.Count){$ui.Programs.SelectedIndex=0}
        $script:refreshing=$false
        Refresh-Detail;Refresh-Overview
    }
    function Remove-ProgramRules([string]$path) {
        if($script:policyReady){Set-NetworkMode $path 'Default';return}
        if($script:inspectionActive -and ($inspection.Path -eq $path -or @($inspectionNodes | Where-Object {$_.Path -eq $path}).Count -gt 0)){throw 'Diese Datei gehört zur laufenden Prüfung. Bitte zuerst die Prüfung beenden.'}
        $base=Rule-Base $path
        foreach($name in @(($base+'.In'),($base+'.Out'))) {
            $owned=@($ownRules | Where-Object {$_.Name -eq $name -and $_.Path -eq $path})
            if($owned.Count -gt 0) { $policy.Rules.Remove($name) }
        }
        Refresh-Rules
        if ($ruleError -or @($ownRules | Where-Object {$_.Path -eq $path}).Count -gt 0) { throw 'Sperre konnte nicht vollständig entfernt werden.' }
        Add-Event 'Eigene Sperre entfernt' ([IO.Path]::GetFileName($path)) $path
        Refresh-Detail
    }
    function Set-ProgramBlock([string]$path) {
        if($script:policyReady){Set-NetworkMode $path 'Blocked';return}
        if(Is-Protected $path){throw 'Dieser Prozess kann nicht pauschal gesperrt werden.'}
        $created=New-Object 'System.Collections.Generic.List[string]'
        try {
            Refresh-Rules
            if($ruleError){throw $ruleError}
            $base=Rule-Base $path
            foreach($direction in @(1,2)) {
                $name=$base+$(if($direction -eq 1){'.In'}else{'.Out'})
                $existing=@($ownRules | Where-Object {$_.Name -eq $name})
                if($existing.Count -gt 0) {
                    if(-not $existing[0].Enabled -or $existing[0].Action -ne 0 -or $existing[0].Protocol -ne 256 -or $existing[0].Profiles -ne 2147483647 -or $existing[0].DirectionId -ne $direction){throw 'Eine eigene Regel wurde außerhalb der App verändert. Bitte zuerst in der Sperrenübersicht entfernen.'}
                    continue
                }
                # Do not overwrite a rule with the same name but different ownership.
                $collision=$null
                try{$collision=$policy.Rules.Item($name)}catch{}
                if($null -ne $collision){throw 'Regelname bereits belegt. Es wurden keine fremden Regeln ersetzt.'}
                $rule=New-Object -ComObject HNetCfg.FWRule
                $rule.Name=$name; $rule.Description='Manuell mit Netzblick gesetzte Programmsperre'
                $rule.ApplicationName=$path; $rule.Protocol=256; $rule.Direction=$direction
                $rule.Action=0; $rule.Profiles=2147483647; $rule.Grouping=$group; $rule.Enabled=$true
                $policy.Rules.Add($rule); $created.Add($name)
            }
            Refresh-Rules
            if($ruleError -or @($ownRules | Where-Object {$_.Path -eq $path -and $_.Enabled -and $_.Action -eq 0}).Count -ne 2){throw 'Regelüberprüfung fehlgeschlagen.'}
            Add-Event 'Eigene Sperre gesetzt' ([IO.Path]::GetFileName($path)) $path
            Refresh-Detail
        } catch {
            $reason=$_.Exception.Message
            $rollbackErrors=@()
            foreach($name in $created){try{$policy.Rules.Remove($name)}catch{$rollbackErrors += $_.Exception.Message}}
            Refresh-Rules; Refresh-Detail
            if($rollbackErrors.Count){$reason+="`nRücknahme unvollständig: "+($rollbackErrors -join '; ')}
            throw $reason
        }
    }
    $ui.RemoveRule.Add_Click({
        $rule=$ui.Rules.SelectedItem
        if($null -eq $rule){return}
        try{Remove-ProgramRules $rule.Path}catch{Refresh-Rules;Show-Error $_.Exception.Message}
    })
    $ui.Programs.Add_SelectionChanged({if(-not $script:refreshing){Refresh-Detail}})
    $ui.Search.Add_TextChanged({Refresh-Programs})
    $ui.Connections.Add_SelectionChanged({
        $row=$ui.Connections.SelectedItem
        if($row){$ui.SocketDetails.Text="Protokoll: $($row.Protocol)`nPID: $($row.Pid)`nLokal: $($row.Local)`nGegenstelle: $($row.Remote)`nStatus: $($row.State)`n`nInitiator / Datenrate: nicht erfasst"}
    })
    function Show-Panel([string]$name) {
        foreach($key in @('OverviewPanel','LivePanel','WorldPanel','TerminalPanel','InspectionPanel','RulesPanel','HistoryPanel')){$ui[$key].Visibility=if($key -eq $name){'Visible'}else{'Collapsed'}}
        $ui.Search.Visibility=if($name -eq 'LivePanel'){'Visible'}else{'Collapsed'}
        $ui.History.ItemsSource=$events.ToArray()
        if($name -eq 'WorldPanel'){Refresh-World -Rebuild}
        if($name -eq 'OverviewPanel'){Refresh-Overview}
    }
    $ui.OverviewTab.Add_Click({Show-Panel 'OverviewPanel'})
    foreach($key in @('BackFromRules','BackFromHistory','BackFromWorld','BackFromTerminal')){$ui[$key].Add_Click({Show-Panel 'LivePanel'})}
    $ui.LiveTab.Add_Click({Show-Panel 'LivePanel'})
    $ui.InspectionTab.Add_Click({Show-Panel 'InspectionPanel'})
    $ui.Pause.Add_Click({
        $script:paused=-not $script:paused
        $ui.Pause.Content=if($paused){'▶ Ansicht fortsetzen'}else{'Ⅱ Ansicht pausieren'}
        if($paused){$ui.Status.Text='Live-Ansicht pausiert · Hintergrundmessung und Firewall bleiben aktiv.'}
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
                elseif($ui.InspectionPanel.Visibility -eq 'Visible'){$data=@($inspectionRows.ToArray() | Select-Object -Property @('TimeUtc','RecordId','Program','Pid','Application','Direction','Protocol','Source','SourcePort','Destination','DestinationPort','Country','Kind'))}
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
    Initialize-InspectionMode
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
    $window.Add_Closed({$timer.Stop();$probeTimer.Stop();if($null -ne $script:probe){$script:probe.Cancel()}})
    $timer.Start()
    [void]$window.ShowDialog()
} catch {
    $message=$_.Exception.Message
    [void][Windows.MessageBox]::Show("Netzblick konnte nicht starten.`n`n$message",'Netzblick','OK','Error')
    Write-Error $message
    exit 1
}

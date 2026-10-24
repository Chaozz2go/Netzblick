# Dot-sourced by Netzblick.ps1. No background PowerShell callbacks are used.
function Initialize-VisualModes {
    $script:geo = $null
    $script:geoError = ''
    $script:geoCache = @{}
    $script:worldPeers = @()
    $script:worldRefreshing = $false
    $script:probe = $null
    $script:probeTarget = $null
    $script:probeRows = New-Object 'System.Collections.Generic.List[object]'
    $script:worldGeometry = $null
    try {
        $script:geo = New-Object Netzblick.GeoDatabase((Join-Path $appRoot 'data'))
        $script:worldGeometry = [Windows.Media.Geometry]::Parse([IO.File]::ReadAllText((Join-Path $appRoot 'data\world.path')))
        $script:worldGeometry.Freeze()
        $ui.OriginCountry.ItemsSource = $geo.Countries
        $initial = 'DE'
        $script:settingsFile = Join-Path $env:LOCALAPPDATA 'Netzblick\settings.json'
        if(Test-Path -LiteralPath $settingsFile){
            try {if((Get-Item -LiteralPath $settingsFile).Length -lt 8192){$saved=Get-Content -LiteralPath $settingsFile -Raw -Encoding UTF8 | ConvertFrom-Json;if($saved.OriginCountry -match '^[A-Z]{2}$'){$initial=$saved.OriginCountry}}}catch{}
        }
        $country=$geo.Countries | Where-Object {$_.Code -eq $initial} | Select-Object -First 1
        if($country){$ui.OriginCountry.SelectedItem=$country}else{$ui.OriginCountry.SelectedIndex=0}
    } catch {$script:geoError=$_.Exception.Message;$ui.WorldSummary.Text='Geo-Daten nicht verfügbar: '+$geoError}
    Initialize-WorldCanvas $ui.WorldMap $ui.WorldOverlay
    Initialize-WorldCanvas $ui.RouteMap $ui.RouteOverlay
    $ui.WorldPrograms.Add_SelectionChanged({if(-not $script:worldRefreshing){Refresh-World}})
    $ui.OriginCountry.Add_SelectionChanged({
        if($ui.OriginCountry.SelectedItem){
            try {
                [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($settingsFile))
                @{OriginCountry=$ui.OriginCountry.SelectedItem.Code} | ConvertTo-Json | Set-Content -LiteralPath $settingsFile -Encoding UTF8
            }catch{$ui.Status.Text='Ausgangsland konnte nicht gespeichert werden: '+$_.Exception.Message}
        }
        Refresh-World
        Draw-ProbeMap
    })
    $ui.WorldPeers.Add_SelectionChanged({
        $item=$ui.WorldPeers.SelectedItem
        $ui.WorldShowProgram.IsEnabled=($null -ne $item)
        $ui.WorldTrace.IsEnabled=($null -ne $item)
    })
    $ui.WorldShowProgram.Add_Click({
        $item=$ui.WorldPeers.SelectedItem
        if($null -eq $item){return}
        $ui.Search.Text='';Show-Panel 'LivePanel'
        $match=$ui.Programs.Items | Where-Object {$_.Key -eq $item.ProgramKey} | Select-Object -First 1
        if($match){$ui.Programs.SelectedItem=$match}else{$ui.Status.Text='Das Programm ist inzwischen nicht mehr in der aktuellen Erfassung.'}
    })
    $ui.WorldTrace.Add_Click({
        $item=$ui.WorldPeers.SelectedItem
        if($item){$ui.CommandInput.Text='tracert '+$item.Address;Show-Panel 'TerminalPanel';[void]$ui.CommandInput.Focus()}
    })
    $ui.RunProbe.Add_Click({Start-Probe})
    $ui.CommandInput.Add_KeyDown({param($sender,$e) if($e.Key -eq 'Return'){$e.Handled=$true;Start-Probe}})
    $ui.StopProbe.Add_Click({if($null -ne $script:probe){$script:probe.Cancel();$ui.ProbeSummary.Text='Abbruch angefordert … laufende ICMP-Probe endet spätestens nach dem Zeitlimit.'}})
    $ui.ClearProbe.Add_Click({
        if($null -ne $script:probe -and -not $script:probe.IsCompleted){return}
        $script:probeRows.Clear();$script:probeTarget=$null;$ui.ProbeRows.ItemsSource=@();$ui.TerminalOutput.Text=''
        $ui.ProbeSummary.Text='Bereit · ping [-4|-6] Ziel oder tracert [-4|-6] Ziel'
        $ui.RouteOverlay.Children.Clear();Draw-Latency
    })
    $script:probeTimer=New-Object Windows.Threading.DispatcherTimer
    $probeTimer.Interval=[timespan]::FromMilliseconds(150)
    $probeTimer.Add_Tick({try{Update-Probe}catch{$ui.ProbeSummary.Text='Darstellungsfehler: '+$_.Exception.Message}})
    $probeTimer.Start()
    Draw-Latency
}

function Initialize-WorldCanvas($canvas,$overlay) {
    $canvas.Children.Clear()
    if($null -ne $worldGeometry){
        $land=New-Object Windows.Shapes.Path
        $land.Data=$worldGeometry;$land.Fill='#213C50';$land.Stroke='#3D5C70';$land.StrokeThickness=0.65
        [void]$canvas.Children.Add($land)
    }
    for($x=0;$x -le 1000;$x+=100){Add-VisualLine $canvas $x 0 $x 500 '#193146' 0.5}
    for($y=0;$y -le 500;$y+=83.3333){Add-VisualLine $canvas 0 $y 1000 $y '#193146' 0.5}
    [void]$canvas.Children.Add($overlay)
}
function Add-VisualLine($canvas,[double]$x1,[double]$y1,[double]$x2,[double]$y2,[string]$color,[double]$thickness=1) {
    $line=New-Object Windows.Shapes.Line
    $line.X1=$x1;$line.Y1=$y1;$line.X2=$x2;$line.Y2=$y2;$line.Stroke=$color;$line.StrokeThickness=$thickness
    [void]$canvas.Children.Add($line)
}
function Add-VisualText($canvas,[string]$text,[double]$x,[double]$y,[string]$color='#B8DAFA',[double]$size=13) {
    $label=New-Object Windows.Controls.TextBlock
    $label.Text=$text;$label.Foreground=$color;$label.FontSize=$size
    [Windows.Controls.Canvas]::SetLeft($label,$x);[Windows.Controls.Canvas]::SetTop($label,$y)
    [void]$canvas.Children.Add($label)
}
function Geo-Location([string]$address) {
    if($geoCache.ContainsKey($address)){return $geoCache[$address]}
    if($null -eq $geo){return [pscustomobject]@{Address=$address;Code='';Country='Geo-Daten nicht verfügbar';Kind=$geoError;CanPlot=$false}}
    $result=$geo.Lookup($address)
    if($geoCache.Count -gt 20000){$script:geoCache.Clear()}
    $script:geoCache[$address]=$result
    return $result
}
function Map-Point($location) {
    return [Windows.Point]::new(($location.Longitude+180)/360*1000,(90-$location.Latitude)/180*500)
}
function Add-CountryLine($overlay,$from,$to,[string]$color,[bool]$dashed=$false) {
    $a=Map-Point $from;$b=Map-Point $to
    # Use schematic, straight projected segments. Split at the dateline rather than crossing the entire map.
    $segments=@()
    $dx=$b.X-$a.X
    if([Math]::Abs($dx) -gt 500){
        $endX=if($dx -gt 0){$b.X-1000}else{$b.X+1000}
        $edge=if($dx -gt 0){0}else{1000}
        $fraction=($edge-$a.X)/($endX-$a.X)
        $edgeY=$a.Y+($b.Y-$a.Y)*$fraction
        $segments=@([pscustomobject]@{X1=$a.X;Y1=$a.Y;X2=$edge;Y2=$edgeY},[pscustomobject]@{X1=(1000-$edge);Y1=$edgeY;X2=$b.X;Y2=$b.Y})
    }else{$segments=@([pscustomobject]@{X1=$a.X;Y1=$a.Y;X2=$b.X;Y2=$b.Y})}
    foreach($segment in $segments){
        $line=New-Object Windows.Shapes.Line
        $line.X1=$segment.X1;$line.Y1=$segment.Y1;$line.X2=$segment.X2;$line.Y2=$segment.Y2
        $line.Stroke=$color;$line.StrokeThickness=1.6;$line.Opacity=0.7
        if($dashed){$line.StrokeDashArray=[Windows.Media.DoubleCollection]::new([double[]]@(4,4))}
        [void]$overlay.Children.Add($line)
    }
}
function Add-CountryMarker($overlay,$location,[string]$label,[string]$tooltip,[string]$color='#1672B6',[bool]$selectable=$false) {
    $point=Map-Point $location
    $dot=New-Object Windows.Shapes.Ellipse
    $dot.Width=12;$dot.Height=12;$dot.Fill=$color;$dot.Stroke='#D0EDFF';$dot.StrokeThickness=1
    $dot.ToolTip=$tooltip;$dot.Tag=$location.Code
    [Windows.Controls.Canvas]::SetLeft($dot,$point.X-6);[Windows.Controls.Canvas]::SetTop($dot,$point.Y-6)
    if($selectable){
        $dot.Cursor='Hand'
        $dot.Add_MouseLeftButtonDown({param($sender,$e)
            $item=$script:worldPeers | Where-Object {$_.Code -eq $sender.Tag} | Select-Object -First 1
            if($item){$ui.WorldPeers.SelectedItem=$item;$ui.WorldPeers.ScrollIntoView($item)}
        })
    }
    [void]$overlay.Children.Add($dot)
    $lx=[Math]::Min(935,[Math]::Max(2,$point.X+9));$ly=[Math]::Min(477,[Math]::Max(2,$point.Y-20))
    Add-VisualText $overlay $label $lx $ly $color 13
}
function Draw-Origin($overlay) {
    $origin=$ui.OriginCountry.SelectedItem
    if($origin){Add-CountryMarker $overlay $origin ('Start: '+$origin.Code) ('Manuell gewähltes Ausgangsland: '+$origin.Name+' · keine automatische Standortmessung') '#087F8C'}
}
function Refresh-World([switch]$Rebuild) {
    if($Rebuild){
        $old=$ui.WorldPrograms.SelectedItem
        $key=if($old){$old.Key}else{'*'}
        $programs=@([pscustomobject]@{Key='*';Name='Alle Programme';Rows=@($rows)})
        $programs+=@($allProgramItems | Select-Object -Property @('Key','Name','Rows'))
        $script:worldRefreshing=$true
        $ui.WorldPrograms.ItemsSource=$programs
        $match=$programs | Where-Object {$_.Key -eq $key} | Select-Object -First 1
        if($match){$ui.WorldPrograms.SelectedItem=$match}else{$ui.WorldPrograms.SelectedIndex=0}
        $script:worldRefreshing=$false
    }
    $source=$ui.WorldPrograms.SelectedItem
    $selected=$ui.WorldPeers.SelectedItem
    $selectedKey=if($selected){$selected.Key}else{''}
    $sockets=if($source){@($source.Rows)}else{@()}
    foreach($peer in @($trafficPeers | Where-Object {$source -and ($source.Key -eq '*' -or [Netzblick.ProcessLineage]::Normalize($_.Path) -eq $source.Key)})){$sockets+=@([pscustomobject]@{Path=$peer.Path;Program=$peer.Name;Pid=0;Address=$peer.Address;Remote=($peer.Address+':'+$peer.Port);Protocol=$peer.Protocol;State='ETW beobachtet'})}
    $peers=@($sockets | Where-Object {$_.Address} | Group-Object {$(if($_.Path){$_.Path.ToUpperInvariant()}else{'PID:'+$_.Pid})+'|'+$_.Address} | ForEach-Object {
        $first=$_.Group[0];$location=Geo-Location $first.Address
        [pscustomobject]@{Key=$_.Name;Program=$first.Program;ProgramKey=$(if($first.Path){$first.Path.ToUpperInvariant()}else{'PID:'+$first.Pid});Path=$first.Path;Address=$first.Address;Country=$location.Country;Code=$location.Code;Count=$_.Count;Kind=$location.Kind;Location=$location}
    } | Sort-Object -Property @('Country','Program','Address'))
    $script:worldPeers=$peers
    $ui.WorldPeers.ItemsSource=$peers
    $match=$peers | Where-Object {$_.Key -eq $selectedKey} | Select-Object -First 1
    if($match){$ui.WorldPeers.SelectedItem=$match}
    $ui.WorldOverlay.Children.Clear()
    $groups=@($peers | Where-Object {$_.Location.CanPlot} | Group-Object Code)
    $origin=$ui.OriginCountry.SelectedItem
    foreach($countryGroup in $groups){
        $location=$countryGroup.Group[0].Location
        if($origin){Add-CountryLine $ui.WorldOverlay $origin $location '#1672B6'}
        $tooltip=$location.Country+' · '+$countryGroup.Count+' Programm-/IP-Zuordnungen · Länderpunkt, kein Serverstandort'
        Add-CountryMarker $ui.WorldOverlay $location ($location.Code+' · '+$countryGroup.Count) $tooltip '#1672B6' $true
    }
    Draw-Origin $ui.WorldOverlay
    $unplotted=@($peers | Where-Object {-not $_.Location.CanPlot}).Count
    $udp=@($sockets | Where-Object {$_.Protocol.StartsWith('UDP')}).Count
    $version=if($geo){$geo.Version}else{'Geo-Daten fehlen: '+$geoError}
    $ui.WorldSummary.Text=$groups.Count.ToString()+' Länder · '+$peers.Count+' Programm-/IP-Zuordnungen · '+$unplotted+' ohne Kartenpunkt · '+$udp+' UDP-Einträge; zusätzliche Gegenstellen über ETW · '+$version
}
function Start-Probe {
    if($null -ne $script:probe -and -not $script:probe.IsCompleted){$ui.ProbeSummary.Text='Es läuft bereits eine Messung. Zuerst stoppen.';return}
    try{
        [void][Netzblick.ProbeCommand]::Parse($ui.CommandInput.Text)
        if($null -ne $script:probe){$script:probe.Dispose()}
        $script:probeRows.Clear();$script:probeTarget=$null;$ui.ProbeRows.ItemsSource=@();$ui.RouteOverlay.Children.Clear()
        $ui.TerminalOutput.Text='> '+$ui.CommandInput.Text+"`r`n"
        $ui.ProbeSummary.Text='Messung läuft …';$ui.RunProbe.IsEnabled=$false;$ui.StopProbe.IsEnabled=$true;$ui.ClearProbe.IsEnabled=$false
        $script:probe=[Netzblick.ProbeSession]::Start($ui.CommandInput.Text)
        Draw-Latency
    }catch{$ui.ProbeSummary.Text=$_.Exception.GetBaseException().Message;$ui.RunProbe.IsEnabled=$true;$ui.StopProbe.IsEnabled=$false;$ui.ClearProbe.IsEnabled=$true}
}
function Update-Probe {
    if($null -eq $script:probe){return}
    $messages=$script:probe.Drain()
    foreach($message in $messages){
        $ui.TerminalOutput.AppendText($message.Text+"`r`n")
        if($message.Type -eq 'probe'){
            $location=if($message.Address){Geo-Location $message.Address}else{$null}
            $country=if($location){$location.Country}else{'Keine Antwortadresse'}
            $code=if($location){$location.Code}else{''}
            $script:probeRows.Add([pscustomobject]@{Number=$message.Number;Attempt=$message.Attempt;Address=$message.Address;Latency=$message.Latency;Milliseconds=$message.Milliseconds;HasLatency=$message.HasLatency;Status=$message.Status;Country=$country;Code=$code;Location=$location})
        }elseif($message.Type -eq 'target'){$script:probeTarget=Geo-Location $message.Address}
        elseif($message.Type -eq 'summary' -or $message.Type -eq 'error'){$ui.ProbeSummary.Text=$message.Text}
    }
    if($messages.Count){
        $ui.TerminalOutput.ScrollToEnd();$ui.ProbeRows.ItemsSource=$probeRows.ToArray()
        if($probeRows.Count){$ui.ProbeRows.ScrollIntoView($probeRows[$probeRows.Count-1])}
        Draw-ProbeMap;Draw-Latency
    }
    if($script:probe.IsCompleted){$ui.RunProbe.IsEnabled=$true;$ui.StopProbe.IsEnabled=$false;$ui.ClearProbe.IsEnabled=$true}
}
function Draw-ProbeMap {
    $ui.RouteOverlay.Children.Clear()
    $points=@($probeRows.ToArray() | Where-Object {$null -ne $_.Location -and $_.Location.CanPlot})
    $origin=$ui.OriginCountry.SelectedItem
    if($null -ne $script:probe -and $script:probe.Command.Mode -eq 'tracert'){
        $previous=$origin;$previousHop=0
        # Only connect consecutive responding TTLs; never bridge unknown/private hops as a known route.
        foreach($hopGroup in @($probeRows.ToArray() | Group-Object Number)){
            $responders=@($hopGroup.Group | Where-Object {$null -ne $_.Location -and $_.Location.CanPlot})
            if($responders.Count -eq 0){$previous=$null;continue}
            $point=$responders[0]
            if($previous -and ($previousHop+1) -eq $point.Number){Add-CountryLine $ui.RouteOverlay $previous $point.Location '#9C650A' $true}
            $previous=$point.Location;$previousHop=$point.Number
        }
    }elseif($origin){
        foreach($item in @($points | Group-Object Code)){Add-CountryLine $ui.RouteOverlay $origin $item.Group[0].Location '#087F8C'}
    }
    foreach($countryGroup in @($points | Group-Object Code)){
        $location=$countryGroup.Group[0].Location
        $numbers=($countryGroup.Group.Number | Select-Object -Unique)-join ','
        Add-CountryMarker $ui.RouteOverlay $location ($location.Code+' · '+$numbers) ($location.Country+' · Probe/Hop '+$numbers+' · nur Länderzuordnung') '#9C650A'
    }
    if($null -ne $probeTarget -and $probeTarget.CanPlot -and @($points | Where-Object {$_.Code -eq $probeTarget.Code}).Count -eq 0){
        Add-CountryMarker $ui.RouteOverlay $probeTarget ('Ziel: '+$probeTarget.Code) ('Aufgelöstes Ziel: '+$probeTarget.Address+' · noch keine ICMP-Antwort an diesem Länderpunkt bestätigt') '#57677B'
    }
    Draw-Origin $ui.RouteOverlay
}
function Draw-Latency {
    $canvas=$ui.LatencyChart;$canvas.Children.Clear()
    $successful=@($probeRows.ToArray() | Where-Object {$_.HasLatency})
    $max=1.0
    foreach($item in $successful){$max=[Math]::Max($max,$item.Milliseconds)}
    $max=[Math]::Max(1,[Math]::Ceiling($max*1.15))
    for($i=0;$i -le 2;$i++){
        $y=12+$i*44
        Add-VisualLine $canvas 55 $y 980 $y '#28425A'
        Add-VisualText $canvas (($max*(2-$i)/2).ToString('0.#')+' ms') 0 ($y-8) '#57677B' 11
    }
    $trace=$null -ne $script:probe -and $script:probe.Command.Mode -eq 'tracert'
    $slots=if($trace){30}else{10}
    $ui.LatencyTitle.Text=if($trace){'ICMP-RÜCKLAUFZEIT PRO HOP · keine Laufzeit einzelner Leitungsabschnitte'}else{'PING-ANTWORTZEITEN · Rot am unteren Rand = keine erfolgreiche Zeitmessung'}
    for($i=1;$i -le $slots;$i++){
        $x=55+($i-1)*925/($slots-1)
        if(-not $trace -or $i -eq 1 -or $i%5 -eq 0){Add-VisualText $canvas ([string]$i) ($x-3) 111 '#57677B' 11}
    }
    $last=$null
    foreach($item in $probeRows.ToArray()){
        $x=55+($item.Number-1)*925/($slots-1)
        if($trace){$x+=($item.Attempt-2)*3}
        if($item.HasLatency){
            $y=100-$item.Milliseconds/$max*88
            if(-not $trace -and $last -and $last.Number -eq ($item.Number-1)){Add-VisualLine $canvas $last.X $last.Y $x $y '#087F8C' 2}
            $dot=New-Object Windows.Shapes.Ellipse
            $dot.Width=6;$dot.Height=6;$dot.Fill='#087F8C';$dot.ToolTip='Nr. '+$item.Number+' · '+$item.Address+' · '+$item.Latency+' · '+$item.Status
            [Windows.Controls.Canvas]::SetLeft($dot,$x-3);[Windows.Controls.Canvas]::SetTop($dot,$y-3);[void]$canvas.Children.Add($dot)
            $last=@{Number=$item.Number;X=$x;Y=$y}
        }else{Add-VisualLine $canvas ($x-3) 97 ($x+3) 103 '#AF3B4B' 2;Add-VisualLine $canvas ($x-3) 103 ($x+3) 97 '#AF3B4B' 2;$last=$null}
    }
}


# Inspection UI. The selected executable is never launched by this script.
function Initialize-InspectionMode {
    $script:inspection=$null
    $script:inspectionActive=$false
    $script:inspectionPath=''
    $script:inspectionMetadata=$null
    $script:inspectionSessionMetadata=$null
    $script:inspectionMetadataTask=$null
    $script:inspectionRows=New-Object 'System.Collections.Generic.List[object]'
    $script:inspectionNodes=@()
    $script:inspectionLastProcess=[datetime]::MinValue
    $script:inspectionGuardWarning=''
    Initialize-WorldCanvas $ui.InspectionWorld $ui.InspectionOverlay
    Draw-InspectionGraphics
    try{
        $recovery=[Netzblick.InspectionAuditLease]::RecoverPending()
        if($recovery){$ui.InspectionStatus.Text=$recovery+' Die Programmsperren bleiben bestehen.'}
    }catch{$ui.InspectionStatus.Text='Audit-Wiederherstellung: '+$_.Exception.GetBaseException().Message}
    $ui.ChooseInspection.Add_Click({
        if($script:inspectionActive){return}
        $dialog=New-Object Microsoft.Win32.OpenFileDialog
        $dialog.Filter='Windows-Programme (*.exe)|*.exe';$dialog.CheckFileExists=$true
        if(-not $dialog.ShowDialog($window)){return}
        try{
            $path=[IO.Path]::GetFullPath($dialog.FileName)
            if($path -notmatch '^[A-Za-z]:\\' -or -not [IO.File]::Exists($path)){throw 'Bitte eine vorhandene EXE auf einem lokalen Laufwerk auswählen.'}
            if(Is-Protected $path){throw 'Dieser Windows-Sammel-/Systemprozess ist vom pauschalen Sperren ausgenommen.'}
            $script:inspectionPath=$path;$script:inspectionMetadata=$null
            $ui.InspectionPath.Text=$path;$ui.StartInspection.IsEnabled=$false
            $ui.InspectionMetadata.Text='Dateiinformationen und SHA-256 werden gelesen … Die Datei wird nicht ausgeführt.'
            $script:inspectionMetadataTask=[Netzblick.InspectionFile]::Start($path)
        }catch{Show-Error $_.Exception.GetBaseException().Message}
    })
    $ui.StartInspection.Add_Click({Start-Inspection})
    $ui.StopInspection.Add_Click({Stop-Inspection})
    $ui.InspectionProcesses.Add_SelectionChanged({
        $node=$ui.InspectionProcesses.SelectedItem
        $ui.BlockInspectionChild.IsEnabled=$script:inspectionActive -and $null -ne $node -and -not (Is-Protected $node.Path) -and -not (Test-InspectionBlock $node.Path)
    })
    $ui.BlockInspectionChild.Add_Click({
        $node=$ui.InspectionProcesses.SelectedItem
        if(-not $script:inspectionActive -or $null -eq $node -or (Is-Protected $node.Path)){return}
        $message="Diesen Prozesspfad ebenfalls dauerhaft in beide Richtungen sperren?`n`n$($node.Path)`n`nBetrifft alle Instanzen dieser Datei. Vor der Erkennung kann bereits Netzwerkverkehr stattgefunden haben."
        if([Windows.MessageBox]::Show($window,$message,'Hilfsprozess sperren','YesNo','Question') -ne 'Yes'){return}
        try{Set-ProgramBlock $node.Path;Update-InspectionProcesses}catch{Show-Error $_.Exception.GetBaseException().Message}
    })
    $ui.SaveInspectionReport.Add_Click({Save-InspectionReport})
    $script:inspectionTimer=New-Object Windows.Threading.DispatcherTimer
    $inspectionTimer.Interval=[timespan]::FromMilliseconds(250)
    $inspectionTimer.Add_Tick({try{Update-Inspection}catch{$ui.InspectionStatus.Text='Prüfansicht: '+$_.Exception.GetBaseException().Message}})
    $inspectionTimer.Start()
    $window.Add_Closing({
        if($script:inspectionActive){Stop-Inspection}
        $inspectionTimer.Stop()
    })
}
function Test-InspectionBlock([string]$path) {
    $matching=@($ownRules | Where-Object {$_.Path -eq $path -and $_.Enabled -and $_.Action -eq 0 -and $_.Protocol -eq 256 -and $_.Profiles -eq 2147483647})
    return @($matching | Where-Object {$_.DirectionId -eq 1}).Count -eq 1 -and @($matching | Where-Object {$_.DirectionId -eq 2}).Count -eq 1
}
function Assert-InspectionFirewall {
    Refresh-Rules
    if($ruleError){throw $ruleError}
    $active=[int]$policy.CurrentProfileTypes
    if($active -eq 0){throw 'Es konnte kein aktives Firewallprofil bestätigt werden.'}
    foreach($profileId in @(1,2,4)){if(($active -band $profileId) -and -not $policy.FirewallEnabled($profileId)){throw 'Mindestens ein aktives Windows-Firewallprofil ist ausgeschaltet.'}}
    if([int]$policy.LocalPolicyModifyState -ne 0){throw 'Lokale Firewallregeln sind durch Richtlinien eingeschränkt. Ein verlässlicher Prüfstart wurde deshalb abgebrochen.'}
}
function Start-Inspection {
    if($script:inspectionActive -or -not $inspectionMetadata -or $inspectionMetadata.Error){return}
    try{
        Assert-InspectionFirewall
        $running=@([Netzblick.WindowsProcesses]::Snapshot() | Where-Object {[Netzblick.ProcessLineage]::Normalize($_.Path) -eq [Netzblick.ProcessLineage]::Normalize($inspectionPath)})
        if($running.Count){throw 'Das gewählte Programm läuft bereits. Bitte selbst schließen und die Prüfung danach erneut starten.'}
        Set-ProgramBlock $inspectionPath
        if(-not (Test-InspectionBlock $inspectionPath)){throw 'Vollständige ein-/ausgehende Programmsperre konnte nicht bestätigt werden.'}
        $script:inspection=[Netzblick.InspectionSession]::Start($inspectionPath)
        $script:inspectionActive=$true;$script:inspectionSessionMetadata=$inspectionMetadata;$script:inspectionFinalStatus='';$script:inspectionRows.Clear();$script:inspectionNodes=@();$script:inspectionGuardWarning=''
        $script:inspectionLastProcess=[datetime]::MinValue
        $ui.InspectionEvents.ItemsSource=@();$ui.InspectionProcesses.ItemsSource=@()
        $ui.ChooseInspection.IsEnabled=$false;$ui.StartInspection.IsEnabled=$false;$ui.StopInspection.IsEnabled=$true
        $ui.SaveInspectionReport.IsEnabled=$true
        $ui.InspectionStatus.Text='Sperre gesetzt · Erfassung läuft. Jetzt die gewählte EXE selbst mit normalen Benutzerrechten starten. Hilfsprozesse werden zunächst nur beobachtet, nicht automatisch gesperrt.'
        $ui.InspectionStatus.Foreground='#F5C477'
        Add-Event 'Prüfung gestartet' ([IO.Path]::GetFileName($inspectionPath)) 'Vorab gesperrt · WFP-Fehlerüberwachung aktiv · keine Byte-Messung'
        Draw-InspectionGraphics
    }catch{
        Refresh-Rules
        $ui.InspectionStatus.Text='Prüfstart fehlgeschlagen: '+$_.Exception.GetBaseException().Message+' Eine bereits gesetzte Programmsperre bleibt bestehen; Aufheben unter Sperren.'
        $ui.InspectionStatus.Foreground='#FF7E85'
        Show-Error $ui.InspectionStatus.Text
    }
}
function Stop-Inspection {
    if(-not $script:inspectionActive){return}
    $errorText=''
    try{$script:inspection.Dispose()}catch{$errorText=$_.Exception.GetBaseException().Message}
    $script:inspectionActive=$false
    Update-Inspection
    $ui.StopInspection.IsEnabled=$false;$ui.ChooseInspection.IsEnabled=$true
    $ui.StartInspection.IsEnabled=$null -ne $inspectionMetadata -and -not $inspectionMetadata.Error
    $ui.BlockInspectionChild.IsEnabled=$false
    $summary='Prüfung beendet. Programmsperren bleiben aktiv. Vorherige Audit-Einstellung wurde wiederhergestellt beziehungsweise war bereits aktiv.'
    if($errorText){$summary='Prüfung beendet; Audit-Wiederherstellung benötigt Aufmerksamkeit: '+$errorText;$ui.InspectionStatus.Foreground='#FF7E85'}
    if(-not $inspection.Healthy -or $inspectionGuardWarning){$summary+=' Erfassung eingeschränkt: '+$inspection.Warning+' '+$inspectionGuardWarning}
    $script:inspectionFinalStatus=$summary
    $ui.InspectionStatus.Text=$summary
    Add-Event 'Prüfung beendet' ([IO.Path]::GetFileName($inspection.Path)) $summary
    if($errorText){Show-Error $summary}
}
function Update-InspectionProcesses {
    if($null -eq $inspection){return}
    $selected=$ui.InspectionProcesses.SelectedItem
    $selectedKey=if($selected){$selected.Key}else{''}
    $script:inspectionNodes=@($inspection.Processes() | ForEach-Object {
        $guard=if(Test-InspectionBlock $_.Path){'Eigene Sperre gesetzt'}else{'Nicht durch eigene Sperre abgedeckt'}
        [pscustomobject]@{Key=$_.Key;Caption=$_.Caption;Pid=$_.Pid;ParentPid=$_.ParentPid;Name=$_.Name;Path=$_.Path;StartUtc=$_.StartUtc;EndUtc=$_.EndUtc;Depth=$_.Depth;Root=$_.Root;State=$_.State;Guard=$guard}
    })
    $ui.InspectionProcesses.ItemsSource=$inspectionNodes
    $match=$inspectionNodes | Where-Object {$_.Key -eq $selectedKey} | Select-Object -First 1
    if($match){$ui.InspectionProcesses.SelectedItem=$match}
    $ui.InspectionProcessCount.Text=[string]$inspectionNodes.Count
}
function Update-Inspection {
    if($null -ne $inspectionMetadataTask -and $inspectionMetadataTask.IsCompleted){
        try{
            if($inspectionMetadataTask.IsFaulted){throw $inspectionMetadataTask.Exception.GetBaseException()}
            $script:inspectionMetadata=$inspectionMetadataTask.Result
            $meta=$inspectionMetadata
            $ui.InspectionMetadata.Text="Herstellerangabe der Datei: $($meta.Company) · Version: $($meta.Version)`n$($meta.Signer)`nSHA-256 bei Auswahl: $($meta.Hash)"
            if($meta.Error){$ui.InspectionMetadata.Text+=' · Lesefehler: '+$meta.Error}
            $ui.StartInspection.IsEnabled=-not $script:inspectionActive -and -not $meta.Error
        }catch{$ui.InspectionMetadata.Text=$_.Exception.GetBaseException().Message}
        $script:inspectionMetadataTask=$null
    }
    if($null -eq $inspection){return}
    $fresh=$inspection.Drain()
    foreach($entry in $fresh){
        $location=if($entry.Direction -eq 'Ausgehend'){Geo-Location $entry.Destination}else{$null}
        $country=if($location){$location.Country}else{'—'}
        $script:inspectionRows.Insert(0,[pscustomobject]@{Time=$entry.Time;TimeUtc=$entry.TimeUtc;RecordId=$entry.RecordId;Subject=($entry.Program+' / '+$entry.Pid);Program=$entry.Program;Pid=$entry.Pid;Application=$entry.Application;Direction=$entry.Direction;Protocol=$entry.Protocol;Source=$entry.Source;SourcePort=$entry.SourcePort;Destination=$entry.Destination;DestinationPort=$entry.DestinationPort;Endpoint=$entry.Endpoint;Country=$country;Code=$(if($location){$location.Code}else{''});Location=$location;Kind=$entry.Kind;Note=$entry.Note})
        while($inspectionRows.Count -gt 2000){$inspectionRows.RemoveAt($inspectionRows.Count-1)}
    }
    $ui.InspectionOutgoing.Text=[string]$inspection.Outgoing;$ui.InspectionIncoming.Text=[string]$inspection.Incoming
    if($fresh.Count){$ui.InspectionEvents.ItemsSource=$inspectionRows.ToArray();Draw-InspectionGraphics}
    if(((Get-Date)-$inspectionLastProcess).TotalSeconds -ge 1){
        Update-InspectionProcesses
        if($script:inspectionActive){
            try{Assert-InspectionFirewall;if(-not (Test-InspectionBlock $inspection.Path)){throw 'Die ausgewählte EXE ist nicht mehr durch die vollständige eigene Sperre abgedeckt.'}}catch{$script:inspectionGuardWarning=$_.Exception.GetBaseException().Message}
            if(-not $inspection.Healthy -or $inspectionGuardWarning){
                $ui.InspectionStatus.Text='Prüfung läuft mit Einschränkung: '+$inspection.Warning+' '+$inspectionGuardWarning+' Keine Aussage „kein Datentransfer“ möglich.'
                $ui.InspectionStatus.Foreground='#FF7E85'
            }
        }
        $script:inspectionLastProcess=Get-Date
        Draw-InspectionTimeline
    }
}
function Draw-InspectionGraphics {
    $canvas=$ui.InspectionGraph;$canvas.Children.Clear();$ui.InspectionOverlay.Children.Clear()
    $program=if($inspection){[IO.Path]::GetFileName($inspection.Path)}else{'Gewählte EXE'}
    Add-VisualText $canvas $program 8 82 '#E5EDF7' 18
    Add-VisualText $canvas 'Blockierte Versuche' 8 112 '#FF7E85' 12
    $peers=@($inspectionRows.ToArray() | Where-Object {$_.Direction -eq 'Ausgehend'} | Group-Object Destination | Sort-Object Count -Descending)
    if($peers.Count -eq 0){Add-VisualText $canvas 'Noch kein zugeordneter' 260 80 '#91ADC8' 14;Add-VisualText $canvas 'ausgehender Block beobachtet.' 260 102 '#91ADC8' 14}
    $limit=[Math]::Min(5,$peers.Count)
    for($i=0;$i -lt $limit;$i++){
        $y=12+$i*37
        $line=New-Object Windows.Shapes.Line
        $line.X1=175;$line.Y1=105;$line.X2=340;$line.Y2=$y+12;$line.Stroke='#FF6D7A';$line.StrokeThickness=2
        $line.StrokeDashArray=[Windows.Media.DoubleCollection]::new([double[]]@(4,3));[void]$canvas.Children.Add($line)
        $label=$peers[$i].Name+' · '+$peers[$i].Count
        Add-VisualText $canvas $label 350 $y '#FF9CA5' 13
        Add-VisualText $canvas $peers[$i].Group[0].Country 350 ($y+17) '#91ADC8' 11
    }
    foreach($countryGroup in @($inspectionRows.ToArray() | Where-Object {$null -ne $_.Location -and $_.Location.CanPlot} | Group-Object Code)){
        $location=$countryGroup.Group[0].Location
        $origin=$ui.OriginCountry.SelectedItem
        if($origin){Add-CountryLine $ui.InspectionOverlay $origin $location '#FF6D7A' $true}
        Add-CountryMarker $ui.InspectionOverlay $location ($location.Code+' · '+$countryGroup.Count) ($location.Country+' · blockierte Zielversuche, keine bestätigte Übertragung · IP Geolocation by DB-IP') '#FF7E85'
    }
    Draw-Origin $ui.InspectionOverlay
    Draw-InspectionTimeline
}
function Draw-InspectionTimeline {
    $canvas=$ui.InspectionTimeline;$canvas.Children.Clear()
    Add-VisualLine $canvas 0 38 1000 38 '#35516B'
    if($null -eq $inspection){Add-VisualText $canvas 'Letzte 60 Sekunden · Ereignisanzahl, kein Datenvolumen' 5 10 '#91ADC8' 12;return}
    $end=if($inspection.StoppedUtc){$inspection.StoppedUtc}else{[datetime]::UtcNow}
    $buckets=New-Object int[] 60
    foreach($entry in $inspectionRows.ToArray()){
        $ago=[int][Math]::Floor(($end-$entry.TimeUtc).TotalSeconds)
        if($ago -ge 0 -and $ago -lt 60){$buckets[59-$ago]++}
    }
    $maximum=[Math]::Max(1,($buckets | Measure-Object -Maximum).Maximum)
    for($i=0;$i -lt 60;$i++){
        if($buckets[$i] -le 0){continue}
        $bar=New-Object Windows.Shapes.Rectangle;$bar.Width=11;$bar.Height=31*$buckets[$i]/$maximum;$bar.Fill='#FF7E85'
        $bar.ToolTip=($buckets[$i].ToString()+' blockierte Versuche · vor '+(59-$i)+' Sekunden')
        [Windows.Controls.Canvas]::SetLeft($bar,($i*16.4));[Windows.Controls.Canvas]::SetTop($bar,(38-$bar.Height));[void]$canvas.Children.Add($bar)
    }
    Add-VisualText $canvas ('−60 s   ·   Max. '+$maximum+'/s · letzte 2000 Ereignisse') 3 37 '#91ADC8' 9
}
function Save-InspectionReport {
    if($null -eq $inspection){return}
    $dialog=New-Object Microsoft.Win32.SaveFileDialog
    $dialog.Filter='JSON-Prüfbericht (*.json)|*.json';$dialog.FileName='Netzblick-Pruefung-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.json'
    if(-not $dialog.ShowDialog($window)){return}
    try{
        Update-Inspection
        $report=[ordered]@{Version='0.4.1';ProgramPath=$inspection.Path;FileMetadata=$inspectionSessionMetadata;FinalStatus=$inspectionFinalStatus;StartedUtc=$inspection.StartedUtc;StoppedUtc=$inspection.StoppedUtc;Active=$inspectionActive;CapturedOutgoingBlocks=$inspection.Outgoing;CapturedIncomingBlocks=$inspection.Incoming;UnknownDirection=$inspection.UnknownDirection;Dropped=$inspection.Dropped;CaptureHealthy=$inspection.Healthy;CaptureWarning=$inspection.Warning;GuardWarning=$inspectionGuardWarning;SentBytes=$null;ReceivedBytes=$null;ByteMeasurement='Nicht vorhanden; blockierte Versuche sind keine gesendeten Nutzdaten.';EventRetentionLimit=2000;ProcessDetection='500-ms-Stichproben; kurzlebige Hilfsprozesse und delegierte Dienste können fehlen.';Processes=@($inspectionNodes);Events=@($inspectionRows.ToArray() | Select-Object -Property @('TimeUtc','RecordId','Program','Pid','Application','Direction','Protocol','Source','SourcePort','Destination','DestinationPort','Country','Code','Kind','Note'));GeoAttribution='IP Geolocation by DB-IP, db-ip.com, CC BY 4.0; Länderpunkte schematisch. Karte Natural Earth.'}
        $json=$report | ConvertTo-Json -Depth 7
        [IO.File]::WriteAllText($dialog.FileName,$json,[Text.UTF8Encoding]::new($false))
        $ui.Status.Text='Prüfbericht gespeichert: '+$dialog.FileName
    }catch{Show-Error $_.Exception.GetBaseException().Message}
}

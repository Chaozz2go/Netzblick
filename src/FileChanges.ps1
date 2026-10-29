function Get-FileReference([string]$path){$key=[Netzblick.ProcessLineage]::Normalize($path);$workspaceSettings.Files | Where-Object {[Netzblick.ProcessLineage]::Normalize($_.Path) -eq $key} | Select-Object -First 1}
function Get-FileChangeState([string]$path){
    if(-not $script:programWorkspaceReady){return [pscustomobject]@{Changed=$false;Label='';Current=$null;Baseline=$null;Error=''}}
    $key=[Netzblick.ProcessLineage]::Normalize($path);$reference=Get-FileReference $path;$current=$fileObservations[$key]
    $changed=$reference -and $current -and $current.File -and $reference.Hash -ne $current.File.Hash
    $label=if($changed){'Datei geändert · ansehen'}elseif($current -and $current.Error){'Dateiabgleich nicht verfügbar'}elseif($reference){'Vergleichsbasis vorhanden'}else{'Noch kein Datei-Vergleichsstand'}
    [pscustomobject]@{Changed=[bool]$changed;Label=$label;Current=$current;Baseline=$reference;Error=$(if($current){$current.Error}else{''})}
}
function Request-FileScan([string]$path,[string]$ackHash=''){
    if(-not [Netzblick.AccessQueue]::CanAllow($path) -or $path.Length -gt 1024){throw 'Für diesen Pfad ist kein Datei-Abgleich verfügbar.'}
    $script:fileScanRequest=[pscustomobject]@{Path=$path;AckHash=$ackHash;Epoch=$script:fileScanEpoch}
    $ui.UserNotice.Text=if($ackHash){'Datei wird vor dem Übernehmen der neuen Vergleichsbasis erneut vollständig gelesen …'}else{'Dateiabgleich im Hintergrund angefordert …'}
}
function Accept-FileObservation([string]$path,$result,[string]$ackHash=''){
    $key=[Netzblick.ProcessLineage]::Normalize($path)
    if($result.StampUnchanged){return}
    if($result.Error){
        $previous=$fileObservations[$key]
        $fileObservations[$key]=[pscustomobject]@{File=$(if($previous){$previous.File}else{$null});Error=$result.Error;StampUnchanged=$false}
        if($ackHash){$ui.UserNotice.Text='Neue Vergleichsbasis nicht übernommen: '+$result.Error};return
    }
    $fileObservations[$key]=$result
    $reference=Get-FileReference $path
    if($ackHash -and $result.File.Hash -ne $ackHash){$ui.UserNotice.Text='Datei erneut verändert. Neue Vergleichsbasis nicht übernommen; Angaben erneut ansehen.';return}
    if(-not $reference -or $ackHash){
        if($script:workspaceReadOnly){$ui.UserNotice.Text='Vergleichsbasis nicht gespeichert: Arbeitsbereich ist nicht lesbar.';return}
        if(-not $reference -and $workspaceSettings.Files.Count -ge 512){$ui.UserNotice.Text='Maximal 512 Datei-Vergleichsstände; dieser Abgleich wird nur vorübergehend angezeigt.';return}
        $before=Copy-WorkspaceSettings
        if($reference){[void]$workspaceSettings.Files.Remove($reference)}
        $workspaceSettings.Files.Add($result.File)
        try{Save-WorkspaceSettings}catch{$script:workspaceSettings=$before;$ui.UserNotice.Text='Datei-Vergleichsstand konnte nicht gespeichert werden: '+$_.Exception.Message;return}
        if($ackHash){Add-ProgramTimeline $path 'Neue Datei-Vergleichsbasis' 'Die angezeigte Datei wurde erneut gelesen und als Vergleichsbasis übernommen. Keine Sicherheitsfreigabe und keine Firewalländerung.';$ui.UserNotice.Text='Neue Vergleichsbasis gespeichert. Firewallregeln und Ziel-Prüfentscheidungen bleiben unverändert.'}
    }elseif($reference.Hash -ne $result.File.Hash){
        $prior=$script:fileAnnouncedHashes[$key]
        if($prior -ne $result.File.Hash){$script:fileAnnouncedHashes[$key]=$result.File.Hash;Add-ProgramTimeline $path 'Programmdatei geändert' ('Dateiinhalt unterscheidet sich von der gespeicherten Vergleichsbasis. Version '+$reference.FileVersion+' → '+$result.File.FileVersion+'. Ein Update ist eine mögliche Erklärung; keine automatische Sicherheitsbewertung.')}
    }
}
function Update-FileScans {
    if(-not $script:programWorkspaceReady -or $script:workspaceRestoring){return}
    if($script:fileScanJob -and $fileScanJob.Task.IsCompleted){
        $job=$script:fileScanJob;$script:fileScanJob=$null
        if($job.Epoch -eq $script:fileScanEpoch){try{if($job.Task.IsFaulted){throw $job.Task.Exception.GetBaseException()};Accept-FileObservation $job.Path $job.Task.Result $job.AckHash}catch{$ui.UserNotice.Text='Dateiabgleich fehlgeschlagen: '+$_.Exception.Message}}
        Update-ProgramFileCard
    }
    if($script:fileScanJob){return}
    $request=$script:fileScanRequest;$script:fileScanRequest=$null
    if(-not $request){
        $now=[datetime]::UtcNow
        $candidate=@(@($script:allProgramItems | Where-Object Path | ForEach-Object Path)+@($script:favoritePrograms.Values)+@(Get-GroupCatalogEntries | ForEach-Object Path) | Where-Object {[Netzblick.AccessQueue]::CanAllow($_) -and $_.Length -le 1024} | Select-Object -Unique | Where-Object {$key=[Netzblick.ProcessLineage]::Normalize($_);-not $fileNextChecks.ContainsKey($key) -or $fileNextChecks[$key] -le $now} | Select-Object -First 1)
        if(-not $candidate.Count){return}
        $request=[pscustomobject]@{Path=$candidate[0];AckHash='';Epoch=$script:fileScanEpoch;Automatic=$true}
    }
    $key=[Netzblick.ProcessLineage]::Normalize($request.Path);$fileNextChecks[$key]=[datetime]::UtcNow.AddMinutes(2)
    $current=$fileObservations[$key];$known=if($current -and $current.File){$current.File}else{Get-FileReference $request.Path}
    # A fresh application start reads content again; later automatic checks can reuse the in-memory stamp.
    $useStamp=$request.Automatic -and $current -and $current.File -and -not $current.Error
    $length=if($useStamp){$known.Length}else{-1};$write=if($useStamp){$known.LastWriteUtc}else{[datetime]::MinValue}
    $script:fileScanJob=[pscustomobject]@{Path=$request.Path;AckHash=$request.AckHash;Epoch=$request.Epoch;Task=[Netzblick.FileObservation]::Start($request.Path,$length,$write,(-not [bool]$useStamp))}
}
function Update-ProgramFileCard {
    if(-not $script:programWorkspaceReady){return}
    $p=$ui.Programs.SelectedItem;$state=if($p){Get-FileChangeState $p.Path}else{$null}
    $ui.FileCheckNow.IsEnabled=[bool]($p -and [Netzblick.AccessQueue]::CanAllow($p.Path) -and $p.Path.Length -le 1024 -and -not $script:fileScanRequest)
    $ui.FileCompare.IsEnabled=[bool]($state -and $state.Current -and $state.Current.File -and $state.Baseline)
    $ui.ProgramFileExpander.Header=if($state -and $state.Changed){'Datei geändert · Vergleich ansehen'}else{'Programmdatei vergleichen'}
    $ui.ProgramFileExpander.SetResourceReference([Windows.Controls.Control]::ForegroundProperty,$(if($state -and $state.Changed){'Warning'}else{'Text'}))
    $ui.ProgramFileHint.Text=if(-not $p){'Programm auswählen.'}elseif($state.Error){$state.Label+': '+$state.Error}elseif($state.Changed){'Programmdatei seit der Vergleichsbasis geändert. Angaben ansehen und bei Bedarf neu bewerten. Regeln bleiben unverändert.'}elseif($state.Baseline){'Datei-Vergleichsbasis vorhanden. Hintergrundprüfungen verwenden Dateigröße/Änderungszeit als Abkürzung; „Jetzt vollständig prüfen“ liest den Inhalt erneut.'}else{'Noch kein Datei-Vergleichsstand. Der erste erfolgreiche Abgleich legt eine Beobachtungsbasis an; das ist keine Sicherheitsfreigabe.'}
}
function New-FileComparison([string]$path){
    $state=Get-FileChangeState $path;if(-not $state.Current -or -not $state.Current.File -or -not $state.Baseline){throw 'Zuerst einen vollständigen Datei-Abgleich durchführen.'}
    [xml]$markup=Get-Content -LiteralPath (Join-Path $appRoot 'src\FileComparison.xaml') -Raw -Encoding UTF8
    $dialog=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($markup));$dialog.Resources=$window.Resources;if($window.IsLoaded){$dialog.Owner=$window}
    $dialog.Tag=[pscustomobject]@{Path=$path;Hash=$state.Current.File.Hash}
    $dialog.FindName('FilePath').Text=$path
    $rows=@(foreach($pair in @(@('Dateiversion','FileVersion'),@('Herstellerangabe','Company'),@('Eingebettete Signatur','Signer'),@('SHA-256','Hash'))){[pscustomobject]@{Field=$pair[0];Before=[string]$state.Baseline.($pair[1]);After=[string]$state.Current.File.($pair[1])}})
    $dialog.FindName('FileDifferences').ItemsSource=$rows
    $dialog.FindName('AcceptFile').IsEnabled=[bool]($state.Changed -and -not $state.Error -and -not $workspaceReadOnly)
    $dialog.FindName('AcceptFile').Add_Click({param($sender,$e) [Windows.Window]::GetWindow($sender).DialogResult=$true})
    $dialog
}
function Show-FileComparison([string]$path){
    try{$dialog=New-FileComparison $path;if($dialog.ShowDialog()){Request-FileScan $dialog.Tag.Path $dialog.Tag.Hash}}catch{Show-Error $_.Exception.Message}
}

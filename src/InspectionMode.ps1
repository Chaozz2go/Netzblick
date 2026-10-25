function Initialize-InspectionMode {
    $script:inspectionActive=$false;$script:inspectionPath='';$script:inspectionMetadata=$null;$script:inspectionMetadataTask=$null
    $script:inspectionNodes=@();$script:inspection=@{Path=''};$script:inspectionRows=@()
    $ui.ChooseInspection.Add_Click({
        $dialog=New-Object Microsoft.Win32.OpenFileDialog;$dialog.Filter='Windows-Programme (*.exe)|*.exe';$dialog.CheckFileExists=$true
        if(-not $dialog.ShowDialog($window)){return}
        try{Select-InspectionPath $dialog.FileName}catch{Show-Error $_.Exception.GetBaseException().Message}
    })
    $ui.RetryInspectionControl.Add_Click({Retry-InspectionControl})
    $ui.ShowInspectionControl.Add_Click({Show-Panel 'AccessPanel'})
    $ui.StartInspection.Add_Click({Start-Inspection});$ui.StopInspection.Add_Click({Stop-Inspection})
    $ui.ReleaseInspection.Add_Click({
        if([Windows.MessageBox]::Show($window,'Prüfsperre für diesen EXE-Pfad entfernen? Weitere Regeln und der globale Nachfragemodus bleiben maßgeblich.','Prüfsperre entfernen','YesNo','Question') -ne 'Yes'){return}
        try{[void](Send-SetupCommand ([Netzblick.SetupCommand]@{Operation='Unwatch';Path=$inspectionPath}));$script:inspectionActive=$false;Update-AccessMode}catch{Show-Error $_.Exception.GetBaseException().Message}
    })
    $ui.InspectionToSetup.Add_Click({Open-InspectionAttempt});$ui.InspectionEvents.Add_MouseDoubleClick({Open-InspectionAttempt})
    $ui.SaveInspectionReport.Add_Click({Save-InspectionReport})
}
function Start-Inspection {
    try{
        if(-not $inspectionMetadata -or $inspectionMetadata.Error){throw 'Dateiangaben sind noch nicht bereit.'}
        if(-not $setupStatus -or -not $setupStatus.Verified){throw 'Der Hintergrunddienst muss bereit sein.'}
        $running=@([Netzblick.WindowsProcesses]::Snapshot() | Where-Object {[Netzblick.ProcessLineage]::Normalize($_.Path) -eq [Netzblick.ProcessLineage]::Normalize($inspectionPath)})
        if($running.Count){throw 'Das Programm läuft bereits. Bitte selbst schließen und die Prüfung erneut starten.'}
        [void](Send-SetupCommand ([Netzblick.SetupCommand]@{Operation='Watch';Path=$inspectionPath}))
        if(-not $setupStatus.Verified -or -not ($setupStatus.Config.WatchedPaths -contains $inspectionPath)){throw 'Prüfsperre nicht bestätigt.'}
        $script:inspectionActive=$true;$script:inspectionStartedUtc=[datetime]::UtcNow;Update-AccessMode
    }catch{Show-Error $_.Exception.GetBaseException().Message}
}
function Stop-Inspection {$script:inspectionActive=$false;Update-Inspection}
function Open-InspectionAttempt {
    Show-Panel 'AccessPanel';$ui.AccessViews.SelectedIndex=0
    $a=$ui.InspectionEvents.SelectedItem
    if($a){$ui.AccessRequests.SelectedItem=$setupStatus.Attempts | Where-Object {$_.Key -eq $a.Key} | Select-Object -First 1}
}
function Update-Inspection {
    if($inspectionMetadataTask -and $inspectionMetadataTask.IsCompleted){
        try{$script:inspectionMetadata=$inspectionMetadataTask.GetAwaiter().GetResult();$ui.InspectionMetadata.Text='Herstellerangabe: '+$inspectionMetadata.Company+' · Version: '+$inspectionMetadata.Version+[Environment]::NewLine+'SHA-256: '+$inspectionMetadata.Hash+[Environment]::NewLine+$inspectionMetadata.Signer;if($inspectionMetadata.Error){$ui.InspectionMetadata.Text=$inspectionMetadata.Error}}
        catch{$ui.InspectionMetadata.Text=$_.Exception.GetBaseException().Message}
        $script:inspectionMetadataTask=$null
    }
    $ready=$setupStatus -and $setupStatus.Verified
    $watched=$ready -and $setupStatus.Config.WatchedPaths -contains $inspectionPath
    $ui.ChooseInspection.IsEnabled=-not $inspectionActive;$ui.StartInspection.IsEnabled=$ready -and $inspectionMetadata -and -not $inspectionMetadata.Error -and -not $inspectionActive
    $reason=if(-not $ready){if($setupStatus -and $setupStatus.Error){$setupStatus.Error}elseif($script:accessProblem){$script:accessProblem}else{'Dienst oder Filter noch nicht bestätigt. Erneut prüfen oder Dienstfehler anzeigen.'}}elseif(-not $inspectionPath){'Zuerst eine EXE auswählen.'}elseif(-not $inspectionMetadata){'Dateiangaben werden noch gelesen …'}elseif($inspectionMetadata.Error){$inspectionMetadata.Error}elseif($inspectionActive){'Prüfsperre aktiv. Das Programm jetzt selbst starten.'}else{''}
    $ui.InspectionBlockReason.Text=$reason;$ui.StartInspection.ToolTip=$reason
    $ui.StopInspection.IsEnabled=$inspectionActive;$ui.ReleaseInspection.IsEnabled=$watched
    $script:inspectionRows=if($setupStatus){@($setupStatus.Attempts | Where-Object {[Netzblick.ProcessLineage]::Normalize($_.Path) -eq [Netzblick.ProcessLineage]::Normalize($inspectionPath)})}else{@()}
    $ui.InspectionEvents.ItemsSource=$inspectionRows;$ui.SaveInspectionReport.IsEnabled=$inspectionRows.Count -gt 0
    $ui.InspectionStatus.Text=if(-not $ready){'Dienst nicht bestätigt · aktuelle Sperrwirkung unbekannt'}elseif($inspectionActive -and $watched){'Prüfung läuft · Programm selbst starten; bewusste Freigaben gelten'}elseif($watched){'Prüfung beendet · Prüfsperre bleibt aktiv'}else{'Keine Prüfsperre für diese Auswahl aktiv'}
    $ui.InspectionCount.Text=if($setupStatus.Warning){$setupStatus.Warning}else{[string]$inspectionRows.Count+' Gegenstellen/Dienste mit Blockereignissen seit Dienststart. Vorhandene Freigaben unter „Einrichten & testen“ prüfen.'}
}
function Save-InspectionReport {
    $dialog=New-Object Microsoft.Win32.SaveFileDialog;$dialog.Filter='JSON-Bericht (*.json)|*.json';$dialog.FileName='Netzblick-Pruefung.json'
    if($dialog.ShowDialog($window)){
        try{$report=@{Version='0.10.0';ProgramPath=$inspectionPath;Metadata=$inspectionMetadata;CheckedUtc=[datetime]::UtcNow;ServiceVerified=$setupStatus.Verified;Warning=$setupStatus.Warning;Attempts=$inspectionRows;Scope='Ausgewählter EXE-Pfad; keine Sandbox, keine automatische Hilfsprozesssperre.'};[IO.File]::WriteAllText($dialog.FileName,($report | ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($true)))}catch{Show-Error $_.Exception.Message}
    }
}


function Retry-InspectionControl {
    try{
        if(-not $Portable){Ensure-InstalledControl}
        $reply=[Netzblick.SetupClient]::Send([Netzblick.SetupCommand]@{Operation='Recheck'})
        $script:setupStatus=$reply
        if(-not $reply.Ok){throw $reply.Error}
        Update-AccessMode
    }catch{$script:accessProblem=$_.Exception.GetBaseException().Message;$ui.InspectionBlockReason.Text=$script:accessProblem;Update-Inspection}
}

function Select-InspectionPath([string]$selectedPath){
    $path=[Netzblick.WfpGate]::CanonicalPath([IO.Path]::GetFullPath($selectedPath))
    if(-not [Netzblick.AccessQueue]::CanAllow($path) -or -not [IO.File]::Exists($path)){throw 'Eine vorhandene lokale EXE auswählen.'}
    if(Is-Protected $path){throw 'Windows-Sammelprozesse nicht mit der Einzelprogramm-Prüfung sperren.'}
    $script:inspectionPath=$path;$script:inspection=@{Path=$path};$script:inspectionMetadata=$null;$script:inspectionActive=$false
    $ui.InspectionPath.Text=$path;$ui.InspectionMetadata.Text='Dateiangaben und SHA-256 werden gelesen …';$ui.StartInspection.IsEnabled=$false
    $script:inspectionMetadataTask=[Netzblick.InspectionFile]::Start($path)
}

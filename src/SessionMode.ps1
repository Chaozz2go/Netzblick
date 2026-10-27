function Ensure-InstalledControl {
    $service=New-Object ServiceProcess.ServiceController('NetzblickControl')
    try{
        if($service.Status -eq 'StopPending'){$service.WaitForStatus('Stopped',[timespan]::FromSeconds(20));$service.Refresh()}
        if($service.Status -eq 'Stopped'){$service.Start()}
        $service.WaitForStatus('Running',[timespan]::FromSeconds(20))
    }finally{$service.Dispose()}
}
function Hide-NetzblickWindow {
    $window.Hide()
}
function Stop-NetzblickCompletely {
    try{
        if($script:setupStatus -and ($setupStatus.Config.Ask -or $setupStatus.Config.Rules.Count -or $setupStatus.Config.WatchedPaths.Count)){
            if([Windows.MessageBox]::Show($window,'Netzblick vollständig beenden? Tray und Erfassung enden. Der installierte Dienst wird gestoppt; dynamische Netzblick-Filter entfallen. Gespeicherte Regeln werden beim nächsten Netzblick-Start wieder geladen.','Netzblick beenden','YesNo','Question') -ne 'Yes'){return}
        }
        if(-not $Portable){
            $service=Get-Service -Name NetzblickControl -ErrorAction SilentlyContinue
            if($service){try{if($service.Status -ne 'Stopped'){$service.Stop();$service.WaitForStatus('Stopped',[timespan]::FromSeconds(20))}}finally{$service.Dispose()}}
        }
        $script:exitNetzblick=$true;$window.Close()
    }catch{Show-Error ('Netzblick konnte nicht vollständig beendet werden: '+$_.Exception.GetBaseException().Message)}
}

function Reset-NetzblickSession {
    $text='Netzblick-Prüfungen und eigene Regeln zurücksetzen?'+[Environment]::NewLine+[Environment]::NewLine+'Entfernt werden Freigaben, Sperren, Programm-Prüfsperren, die Prüfliste und der gemerkte Programmbestand. Die aktuelle Netzwerkmessung beginnt neu. Alle derzeit erfassten Programme werden erneut zur Prüfung vorgemerkt. Standard danach: zulassen und prüfen.'+[Environment]::NewLine+[Environment]::NewLine+'Andere Windows-Firewallregeln, Exporte und dein GitHub-Zugang bleiben erhalten. Vor dem Zurücksetzen wird eine Sicherung erstellt.'
    if([Windows.MessageBox]::Show($window,$text,'Alles neu prüfen','YesNo','Question') -ne 'Yes'){return}
    try{Reset-NetzblickState;Show-Panel 'OverviewPanel'}catch{Show-Error ('Zurücksetzen nicht vollständig abgeschlossen: '+$_.Exception.GetBaseException().Message)}
}
function Reset-NetzblickState {
    Refresh-Rules
    if($script:ruleError){throw ('Eigene Windows-Regeln konnten nicht gelesen werden: '+$ruleError)}
    [void][IO.Directory]::CreateDirectory($userStateDirectory)
    $backup=Join-Path $userStateDirectory ('reset-'+[datetime]::UtcNow.ToString('yyyyMMddHHmmssfff')+'.json')
    $snapshot=@{UserState=$(if([IO.File]::Exists($userStateFile)){[IO.File]::ReadAllText($userStateFile)}else{''});LegacyRules=@($script:ownRules | Select-Object Name,Path,Direction,Action,Enabled,Profiles,Protocol,RemoteAddresses,LocalAddresses,LocalPorts,RemotePorts,InterfaceTypes,ServiceName,EdgeTraversal)}
    [IO.File]::WriteAllText($backup,($snapshot | ConvertTo-Json -Depth 9),(New-Object Text.UTF8Encoding($true)))
    $reply=[Netzblick.SetupClient]::Send([Netzblick.SetupCommand]@{Operation='Reset'})
    if(-not $reply.Ok){throw $reply.Error}
    foreach($rule in @($script:ownRules)){$policy.Rules.Remove($rule.Name)}
    Refresh-Rules
    if($script:ruleError -or $script:ownRules.Count){throw 'Nicht alle eigenen Windows-Regeln konnten zurückgenommen werden.'}
    if($script:reviewToast){$reviewToast.Close()}
    if($script:dashboardReady){Reset-DashboardHistory};$script:connectionDirectionIndex=@{}
    $script:targetLedger=@{};$script:targetReviewCounts=$null;$script:blockBaselines=@{};$script:knownPrograms.Clear();$script:newPrograms.Clear();$script:changes.Clear();$script:events.Clear();$script:seen.Clear();$script:previous=$null
    $script:userBaseline=$true;$script:sessionStartedUtc=[datetime]::UtcNow
    $script:inspectionActive=$false;$script:inspectionPath='';$script:inspectionMetadata=$null;$script:inspectionMetadataTask=$null;$ui.InspectionPath.Text='';$ui.InspectionMetadata.Text='Wähle eine lokale EXE.'
    $script:setupNotifiedPrograms.Clear();$script:setupNotifiedTargets.Clear();$script:setupPendingNotice=$null;$script:setupNoticeTarget=$null
    $script:trafficTotals=@{};$script:trafficSamples=@{};$script:trafficPeers=@();$script:trafficProblem='';$script:trafficSampleUtc=[datetime]::UtcNow
    if($script:traffic){try{$traffic.Dispose()}catch{$script:trafficProblem='Vorherige Messung konnte nicht geordnet beendet werden.'}finally{$script:traffic=$null}}
    try{$script:traffic=[Netzblick.Capture.NetworkCapture]::Start()}catch{$script:trafficProblem=$_.Exception.GetBaseException().Message}
    $notifyBefore=$script:notifyObserved;$script:notifyObserved=$false
    try{Refresh-Programs}finally{$script:notifyObserved=$notifyBefore}
    Save-UserState -ThrowOnError;Update-AccessMode;Refresh-Overview
    $ui.UserNotice.Text='Neu begonnen: alle aktuellen Programme erneut prüfen. Sicherung: '+$backup
    if(-not $script:accessVerified){$ui.UserNotice.Text+=' · Filterdienst weiterhin unbestätigt; Details unter Programm prüfen.'}
}

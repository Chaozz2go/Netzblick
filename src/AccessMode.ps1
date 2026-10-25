function Send-SetupCommand($command) {
    $reply=[Netzblick.SetupClient]::Send($command);$script:setupStatus=$reply
    if(-not $reply.Ok){throw $reply.Error};return $reply
}
function Initialize-AccessMode {
    $script:accessActive=$false;$script:accessVerified=$false;$script:accessProblem='';$script:setupStatus=$null
    $script:setupSelection='';$script:setupNotifiedPrograms=New-Object 'System.Collections.Generic.HashSet[string]'
    $script:setupNotifiedTargets=New-Object 'System.Collections.Generic.HashSet[string]';$script:setupLastNotice=[datetime]::MinValue
    $script:setupPreferencesPath=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Netzblick\notifications.json'
    if($StateDirectory){$script:setupPreferencesPath=Join-Path $StateDirectory 'notifications.json'}
    try{if(Test-Path -LiteralPath $setupPreferencesPath){$p=Get-Content -LiteralPath $setupPreferencesPath -Raw | ConvertFrom-Json;$ui.NotifyAttempts.IsChecked=[bool]$p.Enabled;$ui.NotifyTargets.IsChecked=[bool]$p.Targets}}catch{}
    foreach($n in @('NotifyAttempts','NotifyTargets')){$ui[$n].Add_Click({Save-SetupPreferences})}
    $ui.StartAccess.Add_Click({Start-AccessMode});$ui.StopAccess.Add_Click({[void](Stop-AccessMode)})
    $ui.InstallControlService.Add_Click({try{Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $appRoot 'Install-Netzblick.ps1')+'"')}catch{Show-Error $_.Exception.Message}})
    if($Embedded){$ui.InstallControlService.Visibility='Collapsed'}
    $ui.ConfirmSetup.Add_Click({try{[void](Send-SetupCommand ([Netzblick.SetupCommand]@{Operation='ConfirmRecovery'}));Update-AccessMode}catch{Show-Error $_.Exception.GetBaseException().Message}})
    $ui.AccessRequests.Add_SelectionChanged({Show-AccessRequest});$ui.SetupRuleScope.Add_SelectionChanged({Update-SetupDecisionButtons});$ui.SetupHostIcmp.Add_Click({Update-SetupDecisionButtons})
    $ui.TrySetupRule.Add_Click({Save-SetupRule -Temporary});$ui.SaveSetupRule.Add_Click({Save-SetupRule});$ui.KeepAccessBlocked.Add_Click({Save-SetupRule -Block})
    Initialize-PermissionMode
    $ui.RemoveSetupRule.Add_Click({
        $rule=$ui.SetupRules.SelectedItem;if(-not $rule){return}
        if([Windows.MessageBox]::Show($window,('Regel „'+$rule.Name+'“ zurücknehmen? Andere Regeln bleiben wirksam.'),'Regel zurücknehmen','YesNo','Question') -ne 'Yes'){return}
        try{Remove-PermissionEntry $rule;Update-AccessMode}catch{Show-Error $_.Exception.GetBaseException().Message}
    })
    $script:accessTimer=New-Object Windows.Threading.DispatcherTimer;$accessTimer.Interval=[timespan]::FromSeconds(2)
    $accessTimer.Add_Tick({Update-AccessMode});$accessTimer.Start();$window.Add_Closed({$accessTimer.Stop()});Update-AccessMode
}
function Save-SetupPreferences {
    try{[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($setupPreferencesPath)) | Out-Null;[IO.File]::WriteAllText($setupPreferencesPath,(@{Enabled=[bool]$ui.NotifyAttempts.IsChecked;Targets=[bool]$ui.NotifyTargets.IsChecked} | ConvertTo-Json))}catch{$ui.UserNotice.Text='Benachrichtigungsoptionen konnten nicht gespeichert werden.'}
}
function Start-AccessMode {
    if(-not $setupStatus -or -not $setupStatus.Verified){Show-Error 'Der Hintergrunddienst muss bereit sein.';return}
    $text='Neue Verbindungen zunächst ein- und ausgehend blockieren? Auch DNS, LAN, Updates und Fernwartung können ausfallen. Bestehende Regeln bleiben erhalten. Ohne Bestätigung in Netzblick werden nach 2 Minuten die vorherigen Regeln wiederhergestellt. Bitte auf einem lokal bedienten Testgerät beginnen.'
    if([Windows.MessageBox]::Show($window,$text,'Einrichten & testen','YesNo','Warning') -ne 'Yes'){return}
    try{[void](Send-SetupCommand ([Netzblick.SetupCommand]@{Operation='Ask';Enabled=$true;RecoveryMinutes=2}));Update-AccessMode}catch{Show-Error $_.Exception.GetBaseException().Message}
}
function Stop-AccessMode([switch]$Quiet) {
    if(-not $Quiet -and [Windows.MessageBox]::Show($window,'Nachfragen ausschalten? Die Grundsperre entfällt. Gespeicherte Einzelregeln und Programm-Prüfsperren bleiben aktiv.','Nur beobachten','YesNo','Question') -ne 'Yes'){return $false}
    try{[void](Send-SetupCommand ([Netzblick.SetupCommand]@{Operation='Ask';Enabled=$false}));Update-AccessMode;return $true}catch{if(-not $Quiet){Show-Error $_.Exception.GetBaseException().Message};return $false}
}
function Update-SetupDecisionButtons {
    $r=$ui.AccessRequests.SelectedItem;$ready=$setupStatus -and $setupStatus.Verified -and $r;$valid=$false
    if($ready){$valid=([Netzblick.AccessQueue]::CanAllow($r.Path) -and [IO.File]::Exists($r.Path)) -or ($r.Protocol -in @(1,58) -and $ui.SetupHostIcmp.IsChecked -and $ui.SetupRuleScope.SelectedIndex -eq 0)}
    foreach($n in @('TrySetupRule','SaveSetupRule','KeepAccessBlocked')){$ui[$n].IsEnabled=[bool]($ready -and $valid)}
}
function Show-AccessRequest {
    $r=$ui.AccessRequests.SelectedItem
    if(-not $r){$ui.AccessProgramTitle.Text='Versuch auswählen';$ui.AccessProgramPath.Text='';$ui.AccessProgramState.Text='Noch keine Anfrage ausgewählt.';Update-SetupDecisionButtons;return}
    $ui.AccessProgramTitle.Text=$r.Program;$ui.AccessProgramPath.Text=$r.Path;$ui.AccessProgramState.Text=$r.Evidence
    $port=if($r.Port){' · Port '+$r.Port}else{''};$hint=[Netzblick.EndpointInfo]::Service([Netzblick.SetupRule]::ProtocolName($r.Protocol),$r.Port)
    $ui.AccessTargetHint.Text=$r.Direction+[Environment]::NewLine+$r.Address+[Environment]::NewLine+[Netzblick.SetupRule]::ProtocolName($r.Protocol)+$port+[Environment]::NewLine+'Möglicher Dienst: '+$hint
    if($script:setupSelection -ne $r.Key){$script:setupSelection=$r.Key;$ui.SetupRuleName.Text=$r.Program+' – '+$r.Address;$ui.SetupRuleScope.SelectedIndex=0;$ui.SetupHostIcmp.IsChecked=$false}
    $ui.SetupHostIcmp.Visibility=if($r.Protocol -in @(1,58)){'Visible'}else{'Collapsed'}
    $ui.AccessDecisionNotice.Text=if(-not $setupStatus.Verified){'Dienst-/Filterstatus nicht bestätigt. Keine neue Freigabe möglich.'}elseif($ui.SetupRuleScope.SelectedIndex -eq 1){'Freigabe umfasst alle ausgehenden Ziele und Protokolle dieses EXE-Pfads.'}else{'Nur Programm, Richtung, genaue IP und Dienst. Eingehend wird der lokale Dienstport verwendet.'}
    Update-SetupDecisionButtons
}
function Save-SetupRule([switch]$Temporary,[switch]$Block) {
    $r=$ui.AccessRequests.SelectedItem;if(-not $r){return}
    try{
        $rule=New-Object Netzblick.SetupRule;$rule.Id=[guid]::NewGuid().ToString();$rule.Name=$ui.SetupRuleName.Text.Trim();$rule.Path=$r.Path;$rule.Direction=$r.Direction;$rule.Address=$r.Address;$rule.Protocol=$r.Protocol;$rule.Port=$r.Port
        $rule.Action=if($Block){'Block'}else{'Allow'}
        if($ui.SetupRuleScope.SelectedIndex -eq 1){$rule.Direction='Ausgehend';$rule.Address='*';$rule.Protocol=0;$rule.Port=0}
        elseif($ui.SetupHostIcmp.IsChecked -and $r.Protocol -in @(1,58)){$rule.Path='*'}
        if($Temporary){$rule.ExpiresUtc=[datetime]::UtcNow.AddMinutes(5)};$rule.Validate()
        $action=if($Block){'Sperren'}elseif($Temporary){'5 Minuten erlauben'}else{'Dauerhaft speichern'}
        $warning=if($rule.Path -eq '*'){'Die ICMP-Regel gilt für den gesamten Rechner und alle ICMP-Typen zu diesem Ziel.'}elseif(Is-Protected $rule.Path){'Windows-Sammelprozess: Mehrere Dienste können denselben EXE-Pfad nutzen.'}else{'Alle Instanzen dieses EXE-Pfads sind betroffen; keine Bindung an einen Datei-Hash.'}
        if([Windows.MessageBox]::Show($window,($action+': '+$rule.Name+[Environment]::NewLine+$rule.Scope+[Environment]::NewLine+$warning),'Regel prüfen','YesNo','Question') -ne 'Yes'){return}
        [void](Send-SetupCommand ([Netzblick.SetupCommand]@{Operation='Rule';Rule=$rule}));Add-Event 'Regel gespeichert' $r.Program $rule.Name;Update-AccessMode
    }catch{Show-Error $_.Exception.GetBaseException().Message}
}
function Update-AccessMode {
    try{
        if(-not $script:ruleError){$observation=[Netzblick.SetupClient]::Send([Netzblick.SetupCommand]@{Operation='ObserveBlocks';Enabled=(@($script:ownRules | Where-Object {$_.Enabled -and $_.Action -eq 0}).Count -gt 0)})}
        $script:setupStatus=[Netzblick.SetupClient]::Send([Netzblick.SetupCommand]@{Operation='Status'});if($observation -and -not $observation.Ok){$setupStatus.Warning+=' Blockanzeige: '+$observation.Error};$script:accessVerified=$setupStatus.Verified;$script:accessActive=$setupStatus.Config.Ask
        $ui.InstallControlService.Visibility='Collapsed';$ui.StartAccess.IsEnabled=$accessVerified -and -not $accessActive;$ui.StopAccess.IsEnabled=$accessVerified -and $accessActive
        $ui.AccessHeadline.Text=if(-not $accessVerified){'Filterstatus nicht bestätigt'}elseif($accessActive){'Nachfragen aktiv · unbekannte Zugriffe zunächst gesperrt'}else{'Beobachten · gezielte Einzelregeln bleiben aktiv'}
        $ui.AccessExplanation.Text=if(-not $accessVerified){$setupStatus.Error}elseif($Portable){'Portable Filtersteuerung läuft bis zum vollständigen Beenden von Netzblick. Loopback bleibt ausgenommen.'}else{'Der Hintergrunddienst arbeitet auch bei geschlossenem Fenster. Kommunikation auf diesem PC bleibt ausgenommen.'}
        $ui.AccessProof.Text='Filterprüfung: '+$setupStatus.CheckedUtc.ToLocalTime().ToString('HH:mm:ss')+' · '+$setupStatus.Warning;$ui.AccessGlobalStatus.Text=$ui.AccessHeadline.Text
        $ui.AccessGlobalStatus.Foreground=if(-not $accessVerified -or $setupStatus.Warning){'#A4680B'}else{'#087F8C'};$script:trayStatusText=$ui.AccessHeadline.Text
        $ui.RecoveryBanner.Visibility=if($setupStatus.RecoveryUtc){'Visible'}else{'Collapsed'}
        if($setupStatus.RecoveryUtc){$seconds=[Math]::Max(0,[int]($setupStatus.RecoveryUtc-[datetime]::UtcNow).TotalSeconds);$ui.RecoveryText.Text='Sicherheitsrückweg in '+$seconds+' Sekunden. Benötigte Zugriffe testen und die Einrichtung bestätigen.'}
        $selected=$ui.AccessRequests.SelectedItem;$key=if($selected){$selected.Key}else{''};$ui.AccessRequests.ItemsSource=@($setupStatus.Attempts)
        $match=$setupStatus.Attempts | Where-Object {$_.Key -eq $key} | Select-Object -First 1
        if($match){$ui.AccessRequests.SelectedItem=$match}elseif($setupStatus.Attempts.Count){$ui.AccessRequests.SelectedIndex=0}
        Refresh-Permissions
        $ui.SetupHistory.ItemsSource=@($setupStatus.History)
        $ui.AccessEmpty.Text=if($setupStatus.Attempts.Count){'Pro Programm, Gegenstelle und Dienst gesammelt. '+$setupStatus.Attempts.Count+' Einträge seit Dienststart.'}else{'Noch keine Blockereignisse angezeigt. Eine leere Liste beweist keinen fehlenden Netzwerkzugriff.'}
        if($script:policyReady -and (Get-Command Track-ObservedPrograms -ErrorAction SilentlyContinue)){$blocked=@($setupStatus.Attempts | Where-Object {[Netzblick.AccessQueue]::CanAllow($_.Path)} | ForEach-Object {[pscustomobject]@{Key=[Netzblick.ProcessLineage]::Normalize($_.Path);Name=$_.Program;Path=$_.Path}});Track-ObservedPrograms $blocked -AlwaysReview}
        Update-SetupNotifications
    }catch{
        $script:accessProblem=$_.Exception.GetBaseException().Message;$script:setupStatus=$null;$script:accessVerified=$false;$script:accessActive=$false;$ui.AccessHeadline.Text='Hintergrunddienst nicht erreichbar';$ui.AccessExplanation.Text=$_.Exception.GetBaseException().Message
        $ui.AccessProof.Text='Aktuelle Sperrwirkung nicht bestätigt. Dienststatus prüfen.';$ui.AccessGlobalStatus.Text='Dienst nicht erreichbar · Status unbekannt';$script:trayStatusText='Dienst nicht erreichbar';$ui.InstallControlService.Visibility='Visible';$ui.StartAccess.IsEnabled=$false;$ui.StopAccess.IsEnabled=$false
    };if(-not $script:setupStatus){Refresh-Permissions};if($script:programCatalogReady){Refresh-Programs}else{Refresh-ProgramSignals};Show-AccessRequest;if(Get-Command Update-Inspection -ErrorAction SilentlyContinue){Update-Inspection};if(Get-Command Refresh-ReviewPolicy -ErrorAction SilentlyContinue){Refresh-ReviewPolicy}
}
function Update-SetupNotifications {
    if(-not $script:tray){return};$fresh=@()
    foreach($a in $setupStatus.Attempts){$path=[Netzblick.ProcessLineage]::Normalize($a.Path);$newProgram=$setupNotifiedPrograms.Add($path);$newTarget=$setupNotifiedTargets.Add($a.Key);$decided=@($setupStatus.Config.Rules | Where-Object {$_.Matches($a)}).Count -gt 0;if(-not $decided -and ($newProgram -or ($ui.NotifyTargets.IsChecked -and $newTarget))){$fresh+=$a}}
    if($fresh.Count -and $ui.NotifyAttempts.IsChecked){$script:setupPendingNotice=$fresh[-1]}
    if($script:setupPendingNotice -and $ui.NotifyAttempts.IsChecked -and ([datetime]::UtcNow-$setupLastNotice).TotalSeconds -ge 15){$a=$script:setupPendingNotice;$tray.BalloonTipTitle='Netzblick · blockierter Verbindungsversuch';$tray.BalloonTipText=$a.Program+' → '+$a.Target+'. Zum Prüfen anklicken.';$script:setupNoticeTarget=$a;$tray.ShowBalloonTip(6000);$script:setupLastNotice=[datetime]::UtcNow;$script:setupPendingNotice=$null}
}


function Initialize-AccessMode {
    $script:accessActive=$false;$script:accessGate=$null;$script:accessWatch=$null
    $script:accessQueue=New-Object Netzblick.AccessQueue
    $script:accessProblem='';$script:accessVerified=$false;$script:accessLastVerified=[datetime]::MinValue
    $script:accessBaseline=New-Object 'System.Collections.Generic.HashSet[string]'
    $script:accessSocketFirstSeen=@{}
    $script:accessStartedUtc=$null
    $ui.StartAccess.Add_Click({Start-AccessMode})
    $ui.StopAccess.Add_Click({[void](Stop-AccessMode)})
    $ui.AccessRequests.Add_SelectionChanged({Show-AccessRequest})
    $ui.AllowAccess.Add_Click({Set-AccessDecision 'Allowed'})
    $ui.KeepAccessBlocked.Add_Click({Set-AccessDecision 'Blocked'})
    $ui.RevokeAccess.Add_Click({Set-AccessDecision 'Blocked'})
    $ui.AccessDecisions.Add_MouseDoubleClick({
        $chosen=$ui.AccessDecisions.SelectedItem
        if($chosen){$ui.AccessViews.SelectedIndex=0;$match=$ui.AccessRequests.Items | Where-Object {$_.Key -eq $chosen.Key} | Select-Object -First 1;if($match){$ui.AccessRequests.SelectedItem=$match}}
    })
    $script:accessTimer=New-Object Windows.Threading.DispatcherTimer
    $accessTimer.Interval=[timespan]::FromSeconds(1)
    $accessTimer.Add_Tick({try{Update-AccessMode}catch{$script:accessProblem=$_.Exception.GetBaseException().Message;$script:accessVerified=$false;Refresh-AccessState}})
    $accessTimer.Start()
    $window.Add_Closing({
        if($script:accessActive){
            if([Windows.MessageBox]::Show($window,'Netzblick schließen und den Kontrollmodus beenden? Alle vorübergehenden Sperren und Freigaben dieser Sitzung entfallen. Deine vorhandenen Windows-Firewallregeln bleiben wirksam.','Kontrollmodus beenden','YesNo','Question') -ne 'Yes'){$_.Cancel=$true;return}
            if(-not (Stop-AccessMode -Quiet)){$_.Cancel=$true}
        }
    })
    $window.Add_Closed({$accessTimer.Stop()})
    Refresh-AccessState
}
function Start-AccessMode {
    if($script:accessActive){return}
    if($script:inspectionActive){Show-Error 'Bitte zuerst die laufende Einzelprogramm-Prüfung beenden.';return}
    $nl=[Environment]::NewLine
    $message="Kontrollmodus für diese Sitzung aktivieren?$nl$nl Verbindungsaufbau außerhalb dieses PCs wird zunächst ein- und ausgehend gesperrt – auch LAN, DNS und Windows-Dienste können betroffen sein. Kommunikation auf diesem PC bleibt möglich.$nl$nl Du kannst Programme anschließend für ausgehenden Zugriff freigeben. Die Freigabe gilt für alle Instanzen des Programmpfads und alle Ziele. Vorhandene Windows-Regeln werden nicht geändert.$nl$nl Beim Beenden oder Absturz von Netzblick entfallen diese Sitzungsfilter. Bereits bestehende Verbindungen werden in der Anzeige nicht als sicher getrennt bestätigt.$nl$nl Testversion: zunächst lokal mit einem bekannten Programm ausprobieren."
    if([Windows.MessageBox]::Show($window,$message,'Erst blockieren, dann entscheiden','YesNo','Question') -ne 'Yes'){return}
    $watch=$null;$gate=$null
    try{
        $ui.AccessHeadline.Text='Sperre und Ereignisanzeige werden vorbereitet …'
        $ui.ResolveNames.IsChecked=$false
        $watch=[Netzblick.AccessWatch]::Start()
        $gate=[Netzblick.WfpGate]::Start()
        $script:accessWatch=$watch;$script:accessGate=$gate
        $script:accessQueue=New-Object Netzblick.AccessQueue
        $script:accessStartedUtc=$watch.StartedUtc;$script:accessProblem='';$script:accessVerified=$true
        $script:accessLastVerified=[datetime]::UtcNow;$script:accessActive=$true
        $script:accessSocketFirstSeen=@{}
        $script:accessBaseline.Clear()
        foreach($row in $script:rows){[void]$accessBaseline.Add($row.Key)}
        $ui.StartAccess.IsEnabled=$false;$ui.StopAccess.IsEnabled=$true
        Add-Event 'Kontrollmodus aktiviert' 'Netzblick' 'Dynamische WFP-Sitzung · ohne Freigaben · lokale Kommunikation auf diesem PC ausgenommen'
        Update-AccessMode
    }catch{
        $reason=$_.Exception.GetBaseException().Message
        $script:accessActive=$false;$script:accessGate=$null;$script:accessWatch=$null
        $failure=$_.Exception
        while($failure){if($failure.PSObject.Properties['RecoveryGate']){$gate=$failure.RecoveryGate;break};$failure=$failure.InnerException}
        if($gate){try{$gate.Dispose()}catch{$reason+=' Sitzungsende nicht bestätigt: '+$_.Exception.GetBaseException().Message;$script:accessGate=$gate;$script:accessActive=$true}}
        if($watch){try{$watch.Dispose()}catch{$reason+=' Audit-Wiederherstellung: '+$_.Exception.GetBaseException().Message}}
        $script:accessProblem=$reason;$script:accessVerified=$false
        $ui.ResolveNames.IsEnabled=$true
        Refresh-AccessState;Show-Error $reason
    }
}
function Stop-AccessMode([switch]$Quiet) {
    if(-not $script:accessActive){return $true}
    try{
        $accessGate.Dispose()
        $script:accessActive=$false;$script:accessVerified=$false;$script:accessGate=$null
    }catch{
        $script:accessProblem='Sitzungsfilter konnten nicht als beendet bestätigt werden: '+$_.Exception.GetBaseException().Message
        $script:accessVerified=$false;Refresh-AccessState
        if(-not $Quiet){Show-Error $accessProblem}
        return $false
    }
    $restoreError=''
    try{if($accessWatch){$accessWatch.Dispose()}}catch{$restoreError=$_.Exception.GetBaseException().Message}
    $script:accessWatch=$null
    $script:accessProblem=if($restoreError){'Sitzungsfilter beendet; Audit-Wiederherstellung prüfen: '+$restoreError}else{''}
    $ui.ResolveNames.IsEnabled=$true;$ui.StartAccess.IsEnabled=-not $restoreError;$ui.StopAccess.IsEnabled=$false
    Add-Event 'Kontrollmodus beendet' 'Netzblick' 'Sitzungsfilter entfernt; normale Windows-Firewallregeln wieder maßgeblich'
    Refresh-AccessState;Refresh-AccessLists;Show-AccessRequest
    if($restoreError -and -not $Quiet){Show-Error $accessProblem}
    return -not [bool]$restoreError
}
function Refresh-AccessState {
    $items=@($accessQueue.Snapshot())
    $pending=@($items | Where-Object {$_.Decision -eq 'Pending'}).Count
    $blocked=@($items | Where-Object {$_.Decision -eq 'Blocked'}).Count
    $allowed=if($accessGate){$accessGate.AllowedCount}else{0}
    $ui.AccessPendingLabel.Text=if(-not $accessActive){'ANFRAGEN DER LETZTEN SITZUNG'}elseif(-not $accessVerified -or $accessProblem){'ANFRAGEN · STATUS OFFEN'}else{'ANFRAGEN · NOCH BLOCKIERT'}
    $ui.AccessBlockedLabel.Text=if($accessActive -and $accessVerified -and -not $accessProblem){'BEWUSST WEITER BLOCKIERT'}else{'ENTSCHEIDUNG: BLOCKIEREN'}
    $ui.AccessPendingCount.Text=[string]$pending;$ui.AccessAllowedCount.Text=[string]$allowed;$ui.AccessBlockedCount.Text=[string]$blocked
    $ui.StopAccess.IsEnabled=$script:accessActive
    $ui.StartAccess.IsEnabled=-not $script:accessActive
    $ui.StartAccess.Content=if($accessProblem -and -not $accessActive){'Erneut versuchen'}else{'Kontrollmodus aktivieren'}
    if($script:accessActive -and $script:accessVerified -and -not $accessProblem){
        $ui.AccessHero.BorderBrush='#39DCC0';$ui.AccessHero.Background='#12302E'
        $ui.AccessHeadline.Text=if($allowed){'Kontrollmodus aktiv · '+$allowed+' bewusste Freigaben'}else{'Kontrollmodus aktiv · noch keine Programme freigegeben'}
        $ui.AccessExplanation.Text=if($pending){$pending.ToString()+' Programme haben ausgehenden Zugriff versucht. Ihre Anfragen bleiben bis zu deiner Freigabe blockiert.'}else{'Neue Verbindungen außerhalb dieses PCs werden ohne Freigabe zunächst blockiert. Benutze ein Programm und entscheide anhand seiner Anfragen.'}
        $ui.AccessProof.Text='Sitzungsfilter zuletzt geprüft: '+$accessLastVerified.ToLocalTime().ToString('HH:mm:ss')+' · Ereignisanzeige aktiv · '+$accessQueue.Incoming+' eingehende Blockereignisse · lokale Kommunikation ausgenommen'
        $ui.AccessGlobalStatus.Text='Kontrollmodus aktiv · '+$allowed+' Freigaben · '+$pending+' Anfragen';$ui.AccessGlobalStatus.Foreground='#39DCC0'
    }elseif($accessProblem){
        $ui.AccessHero.BorderBrush='#FF7E85';$ui.AccessHero.Background='#321F2A'
        $ui.AccessHeadline.Text=if($accessActive){'Schutzstatus / Anzeige nicht bestätigt'}else{'Kontrollmodus nicht aktiv · Hinweis prüfen'}
        $ui.AccessExplanation.Text=$accessProblem
        $ui.AccessProof.Text=if($accessActive){'Sitzungsfilter können weiter aktiv sein. Keine neue Freigabe möglich. Kontrollmodus beenden und Meldung prüfen.'}else{'Es wird kein aktiver Kontrollmodus angezeigt. Vorhandene Windows-Firewallregeln bleiben maßgeblich.'}
        $ui.AccessGlobalStatus.Text='Aufmerksamkeit erforderlich · Kontrollmodus prüfen';$ui.AccessGlobalStatus.Foreground='#FF7E85'
    }else{
        $ui.AccessHero.BorderBrush='#35516B';$ui.AccessHero.Background='#192C42'
        $ui.AccessHeadline.Text='Du beobachtest gerade – der Kontrollmodus ist aus'
        $ui.AccessExplanation.Text='Aktiviere den Kontrollmodus, um Verbindungsaufbau außerhalb dieses PCs zunächst zu blockieren. Anfragen und Entscheidungen der letzten Sitzung bleiben zur Ansicht erhalten.'
        $ui.AccessProof.Text='Keine Netzblick-Sitzungsfilter aktiv · keine aktuellen Sitzungsfreigaben · vorhandene Windows-Firewallregeln bleiben wirksam'
        $ui.AccessGlobalStatus.Text='Beobachten · Kontrollmodus aus';$ui.AccessGlobalStatus.Foreground='#A8C1D9'
    }
}
function Refresh-AccessLists {
    $selected=$ui.AccessRequests.SelectedItem;$key=if($selected){$selected.Key}else{''}
    $items=@($accessQueue.Snapshot())
    $ordered=@($items | Sort-Object -Property @{Expression={if($_.Decision -eq 'Pending'){0}elseif($_.Decision -eq 'Allowed'){1}else{2}}},@{Expression='LastUtc';Descending=$true})
    $ui.AccessRequests.ItemsSource=$ordered;$ui.AccessDecisions.ItemsSource=$items
    $match=$ordered | Where-Object {$_.Key -eq $key} | Select-Object -First 1
    if($match){$ui.AccessRequests.SelectedItem=$match}elseif($ordered.Count){$ui.AccessRequests.SelectedIndex=0}
    $ui.AccessEmpty.Text=if($ordered.Count){'Pro Programm gesammelt. Mehrere Versuche erzeugen keine Flut von Rückfragen.'}elseif($accessActive){'Noch kein ausgehender Blockversuch angezeigt. Nutze jetzt ein Programm. Eine leere Liste ist kein Sicherheitsnachweis.'}else{'Aktiviere den Kontrollmodus und benutze dann ein Programm. Noch keine Anfragen dieser Sitzung.'}
}
function Show-AccessRequest {
    $request=$ui.AccessRequests.SelectedItem
    foreach($name in @('AllowAccess','KeepAccessBlocked','RevokeAccess')){$ui[$name].IsEnabled=$false}
    if($null -eq $request){$ui.AccessProgramTitle.Text='Ein Programm möchte nach draußen';$ui.AccessProgramState.Text='Wähle eine Anfrage links. Ohne Freigabe bleibt sie im aktiven Kontrollmodus gesperrt.';$ui.AccessProgramPath.Text='';$ui.AccessTargets.ItemsSource=@();return}
    $ui.AccessProgramTitle.Text=$request.Name;$ui.AccessProgramPath.Text=$request.Path
    $ui.AccessProgramState.Text=if($accessActive -and (-not $accessVerified -or $accessProblem)){'Filterstatus unbestätigt · aktueller Zugriff nicht bestätigt'}elseif(-not $accessActive){'Vergangene Sitzung: '+$request.DecisionText+' · aktuell keine Sitzungsfreigabe aktiv'}elseif($request.Decision -eq 'Pending'){'Entscheidung offen · im Kontrollmodus zunächst blockiert'}elseif($request.Decision -eq 'Blocked'){'Deine Entscheidung: im Kontrollmodus weiter blockiert'}else{$request.DecisionText}
    $scope=[Netzblick.EndpointInfo]::Scope($request.LatestAddress)
    $hint=[Netzblick.EndpointInfo]::Service($request.Protocol,$request.LatestPort)
    $nl=[Environment]::NewLine
    $peerName=Get-EndpointName $request.LatestAddress
    $ui.AccessTargetHint.Text="Name: $peerName$nl Letztes Ziel: $($request.LatestAddress):$($request.LatestPort)$nl Bereich: $scope$nl Möglicher Dienst: $hint$nl Nachweis: $($request.Evidence)"
    $ui.AccessTargets.ItemsSource=@($request.Targets)
    $ready=$accessActive -and $accessVerified -and -not $accessProblem
    $ui.AllowAccess.IsEnabled=$ready -and $request.Decision -ne 'Allowed' -and [Netzblick.AccessQueue]::CanAllow($request.Path) -and [IO.File]::Exists($request.Path)
    $ui.KeepAccessBlocked.IsEnabled=$ready -and $request.Decision -ne 'Blocked'
    $ui.RevokeAccess.IsEnabled=$ready -and $request.Decision -eq 'Allowed'
    $ui.AccessDecisionNotice.Text=if($request.BlockedAfterAllow){'Nach der Freigabe wurde erneut blockiert. Eine andere Windows-Regel oder ein anderer beteiligter Prozess kann den Zugriff verhindern. Die Freigabe ist kein Nachweis einer erfolgreichen Verbindung.'}elseif(-not [Netzblick.AccessQueue]::CanAllow($request.Path)){'Der Programmpfad ist nicht eindeutig als lokale EXE zugeordnet. Keine pauschale Freigabe möglich.'}else{'Nur diese Sitzung · alle Ziele dieses Programmpfads · vorhandene Sperren bleiben wirksam.'}
}
function Set-AccessDecision([string]$decision) {
    $request=$ui.AccessRequests.SelectedItem
    if($null -eq $request -or -not $accessActive -or -not $accessVerified -or $accessProblem){return}
    if($decision -eq 'Allowed'){
        $nl=[Environment]::NewLine
        $extra=if(Is-Protected $request.Path){"$nl$nl Achtung: Windows-Sammelprozess. Die Freigabe betrifft alle Dienste/Instanzen unter diesem EXE-Pfad, nicht nur die angezeigte Anfrage."}else{''}
        $message="Diesem Programmpfad ausgehenden Netzwerkzugriff für diese Sitzung erlauben?$nl$nl$($request.Path)$nl$nl Gilt für alle Instanzen und alle Ziele. Vorhandene Windows-Sperren bleiben wirksam. Starte die gewünschte Online-Funktion anschließend erneut.$extra"
        if([Windows.MessageBox]::Show($window,$message,'Bewusste Sitzungsfreigabe','YesNo','Question') -ne 'Yes'){return}
    }
    try{
        if($decision -eq 'Allowed'){$accessGate.Allow($request.Path)}else{$accessGate.Revoke($request.Path)}
        $accessQueue.Decide($request.Key,$decision)
        $script:accessLastVerified=[datetime]::UtcNow
        Add-Event $(if($decision -eq 'Allowed'){'Sitzungszugriff erlaubt'}else{'Bleibt im Kontrollmodus blockiert'}) $request.Name $request.Path
        Refresh-AccessLists;Refresh-AccessState;Show-AccessRequest
    }catch{$script:accessProblem=$_.Exception.GetBaseException().Message;$script:accessVerified=$false;Refresh-AccessState;Show-AccessRequest;Show-Error $accessProblem}
}
function Refresh-AccessSockets {
    if($ui.AccessPanel.Visibility -ne 'Visible'){return}
    $list=@();$index=0
    foreach($row in $script:rows){
        if(-not $row.Address){continue}
        $index++;if($index -gt 1000){break}
        $request=$accessQueue.Find([Netzblick.ProcessLineage]::Normalize($row.Path))
        if(-not $accessSocketFirstSeen.ContainsKey($row.Key) -and $accessSocketFirstSeen.Count -lt 10000){$accessSocketFirstSeen[$row.Key]=[datetime]::UtcNow}
        $recent=$accessSocketFirstSeen.ContainsKey($row.Key) -and (([datetime]::UtcNow-$accessSocketFirstSeen[$row.Key]).TotalSeconds -lt 8)
        $observation=if($accessActive -and $accessBaseline.Contains($row.Key)){'Schon vor Aktivierung beobachtet'}elseif($recent){'Neu beobachtet · kein Transfernachweis'}elseif($row.State -eq 'Verbunden'){'TCP-Socket verbunden'}else{'Socket beobachtet'}
        $decision=if(-not $accessActive){'Kontrollmodus aus'}elseif($request -and $request.Decision -eq 'Allowed'){'Sitzungsfreigabe vorhanden'}else{'Keine Sitzungsfreigabe'}
        $list+=[pscustomobject]@{Program=$row.Program;Observation=$observation;Remote=$row.Remote;State=$row.State;Protocol=$row.Protocol;Decision=$decision}
    }
    $ui.AccessSockets.ItemsSource=$list
    $ui.AccessSocketNote.Text=if($paused){'Aktivitätsansicht pausiert. Sperrfilter und Anfragen werden weiter geprüft. Sichtbare Socket-Einträge sind veraltet.'}else{'Bis zu 1000 aktuelle Socket-Beobachtungen · keine Byte-Messung. Vorher vorhandene Einträge werden nicht als sicher getrennt bestätigt; Freigabe ist nicht gleich erfolgreicher Datentransfer.'}
}
function Update-AccessMode {
    if($script:accessActive -and $accessWatch){
        foreach($entry in $accessWatch.Drain()){$accessQueue.Observe($entry,$accessGate.OwnBlock($entry.FilterId))}
        try{
            $accessGate.Verify();$accessWatch.VerifyAudit()
            if(-not $accessWatch.Healthy){throw $accessWatch.Warning}
            if($accessQueue.Overflow -gt 0 -or $accessQueue.Unknown -gt 0){throw 'Anfragen nicht vollständig zugeordnet: '+$accessQueue.Unknown+' unbekannt, '+$accessQueue.Overflow+' wegen Kapazitätsgrenze nicht gelistet.'}
            $script:accessVerified=$true;$script:accessLastVerified=[datetime]::UtcNow
        }catch{$script:accessVerified=$false;$script:accessProblem=$_.Exception.GetBaseException().Message}
        Refresh-AccessLists
    }
    Refresh-AccessState;Show-AccessRequest;Refresh-AccessSockets
}

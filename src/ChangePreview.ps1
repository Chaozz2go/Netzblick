# Preview only known observations. Never infer initiation from receive/send bytes or port numbers.
function Get-PreviewObservations {
    $known=New-Object 'System.Collections.Generic.List[object]';$unknown=0;$seen=@{}
    foreach($row in @($script:rows)){
        if(-not $row.Path -or -not $row.Address){continue}
        $role=Get-ConnectionDirection $row $row.Path
        if($role.Label -notin @('Ausgehend','Eingehend')){$unknown++;continue}
        $protocol=switch -Regex ($row.Protocol){'^TCP'{6;break} '^UDP'{17;break} default{0}}
        if(-not $protocol){$unknown++;continue}
        $port=[int]$row.Port
        if($role.Label -eq 'Eingehend'){$m=[regex]::Match($row.Local,':(\d+)$');if(-not $m.Success){$unknown++;continue};$port=[int]$m.Groups[1].Value}
        $ip=$null;if(-not [Net.IPAddress]::TryParse($row.Address,[ref]$ip)){$unknown++;continue};if($ip.IsIPv4MappedToIPv6){$ip=$ip.MapToIPv4()}
        $a=[Netzblick.SetupAttempt]@{Path=$row.Path;Address=$ip.ToString();Direction=$role.Label;Protocol=$protocol;Port=$port}
        $key=([Netzblick.ProcessLineage]::Normalize($a.Path))+'|'+$a.Direction+'|'+$a.Address+'|'+$a.Protocol+'|'+$a.Port
        if(-not $seen.ContainsKey($key)){$seen[$key]=$true;$known.Add([pscustomobject]@{Attempt=$a;Source='Socket-Stichprobe';Evidence=$role.Source})}
    }
    if($script:setupStatus){foreach($a in $setupStatus.Attempts){if($a.Direction -in @('Ausgehend','Eingehend')){$known.Add([pscustomobject]@{Attempt=$a;Source='Früheres Blockereignis';Evidence=$a.Evidence})}}}
    [pscustomobject]@{Known=@($known.ToArray());Unknown=$unknown}
}
function Get-PreviewDecision($config,$attempt){
    $now=[datetime]::UtcNow
    $rules=@($config.Rules | Where-Object {(-not $_.ExpiresUtc -or $_.ExpiresUtc -gt $now) -and $_.Matches($attempt)})
    $deny=$rules | Where-Object Action -eq 'Block' | Select-Object -First 1
    if($deny){return 'Netzblick-Sperre: '+$deny.Name}
    $allow=$rules | Where-Object Action -eq 'Allow' | Select-Object -First 1
    if($allow){return 'Netzblick-Freigabe: '+$allow.Name}
    if($config.Ask -or @($config.WatchedPaths | Where-Object {[Netzblick.ProcessLineage]::Normalize($_) -eq [Netzblick.ProcessLineage]::Normalize($attempt.Path)}).Count){return 'Netzblick-Grundsperre / Prüfsperre'}
    'Windows-Standard; zusätzliche Filter unbekannt'
}
function Get-ChangePreview([string]$path,[string]$operation,$rule=$null,[int]$minutes=10){
    if(-not $script:setupStatus -or -not $setupStatus.Config){throw 'Regelzustand nicht verfügbar.'}
    $before=[Netzblick.SetupChanges]::CopyConfig($setupStatus.Config);$after=[Netzblick.SetupChanges]::CopyConfig($before)
    $key=if($rule){$rule.Path}else{$path};$error='';$now=[datetime]::UtcNow
    try{
        if($rule){[Netzblick.SetupChanges]::AssertNoProgramLease($after,$rule.Path);[Netzblick.SetupChanges]::Upsert($after,([Netzblick.SetupChanges]::CopyRule($rule)))}
        else{switch($operation){
            'BlockProgram' {[Netzblick.SetupChanges]::BlockProgram($after,$path)}
            'AllowProgram' {[Netzblick.SetupChanges]::AllowProgram($after,$path)}
            'ProgramDefault' {[Netzblick.SetupChanges]::ProgramDefault($after,$path)}
            'TemporaryBlockProgram' {[Netzblick.SetupChanges]::TemporaryBlockProgram($after,$path,$minutes,$now)}
            'TemporaryAllowProgram' {[Netzblick.SetupChanges]::TemporaryAllowProgram($after,$path,$now.AddMinutes(10),$now)}
            'EndProgramLease' {[Netzblick.SetupChanges]::EndProgramLease($after,$path,([Netzblick.SetupChanges]::CaptureProgram($after,$path)),$now)}
            default{throw 'Unbekannte Vorschauaktion.'}
        }}
        $after.Validate()
    }catch{$error=$_.Exception.GetBaseException().Message}
    $observations=Get-PreviewObservations;$matches=@()
    foreach($o in $observations.Known){
        $a=$o.Attempt;$hit=if($rule){$rule.Matches($a)}else{[Netzblick.ProcessLineage]::Normalize($a.Path) -eq [Netzblick.ProcessLineage]::Normalize($path)}
        if(-not $hit){continue}
        $matches+=[pscustomobject]@{Program=[IO.Path]::GetFileName($a.Path);Direction=$a.Direction;Target=$a.Target;Source=$o.Source;Before=(Get-PreviewDecision $before $a);After=$(if($error){'Änderung nicht anwendbar'}else{Get-PreviewDecision $after $a});Evidence=$o.Evidence}
    }
    $removed=@($before.Rules | Where-Object {$id=$_.Id;-not @($after.Rules | Where-Object Id -eq $id).Count})
    $added=@($after.Rules | Where-Object {$id=$_.Id;-not @($before.Rules | Where-Object Id -eq $id).Count})
    $protected=$key -ne '*' -and (Is-Protected $key)
    $warning='Gilt für alle Instanzen des Dateipfads, nicht nur die ausgewählte PID. Bestehende Verbindungen werden nicht garantiert beendet. Andere Windows-/Sicherheitsfilter werden nicht simuliert.'
    if($protected){$warning='Windows-Sammelprozess: Mehrere Dienste und Hostinstanzen können betroffen sein. Keine sichere Zuordnung zu einem einzelnen Dienst. '+$warning}
    if($key -eq '*'){$warning='Rechnerweite ICMP-Regel: betrifft alle Programme und alle ICMP-Typen zum gewählten Ziel. '+$warning}
    if($script:ownRules | Where-Object {[Netzblick.ProcessLineage]::Normalize($_.Path) -eq [Netzblick.ProcessLineage]::Normalize($key)}){$warning+=' Ältere Windows-Regeln dieses Dateipfads bleiben zusätzlich wirksam und werden hier nicht berechnet.'}
    if(-not $script:setupStatus.Verified){$error='Filterstatus unbestätigt; keine Änderung möglich.'}
    if(-not $rule -and $protected -and $operation -ne 'ProgramDefault'){$error='Windows-Sammelprozesse über einzelne Verbindungen verwalten.'}
    $state=if($key -ne '*'){Get-PermissionStatus $key}else{$null}
    if(-not $rule -and $state.Legacy -and $operation -notin @('BlockProgram','TemporaryBlockProgram','EndProgramLease')){$error='Zuerst die älteren Windows-Regeln dieses Programms prüfen.'}
    if(-not $rule -and $operation -ne 'ProgramDefault' -and -not [IO.File]::Exists($path)){$error='Programmdatei nicht mehr vorhanden.'}
    $scope=if($rule){$rule.Scope+' · '+$rule.Lifetime}else{$path+' · alle Ziele / Protokolle · ein- und ausgehend · Loopback ausgenommen'}
    $footprint=$removed.Count.ToString()+' bisherige Dienstregeln werden entfernt/ersetzt; '+$added.Count+' Regeln kommen hinzu.'
    if($key -ne '*'){
        $k=[Netzblick.ProcessLineage]::Normalize($key)
        $wasWatched=@($before.WatchedPaths | Where-Object {[Netzblick.ProcessLineage]::Normalize($_) -eq $k}).Count -gt 0
        $willWatch=@($after.WatchedPaths | Where-Object {[Netzblick.ProcessLineage]::Normalize($_) -eq $k}).Count -gt 0
        $footprint+=' Programm-Prüfsperre: '+$(if($wasWatched){'aktiv'}else{'keine'})+' → '+$(if($willWatch){'aktiv'}else{'keine'})+'.'
    }
    if($operation -in @('TemporaryAllowProgram','TemporaryBlockProgram')){$footprint+=' Vorherige Programmregeln werden für den Rückweg gespeichert.'}
    if($operation -eq 'EndProgramLease'){$footprint+=' Der vorherige Zustand wird wiederhergestellt; er kann ebenfalls eingeschränkt sein.'}
    [pscustomobject]@{Path=$key;Operation=$operation;Rule=$rule;Minutes=$minutes;ExpectedConfigKey=[Netzblick.SetupChanges]::ConfigKey($before);Matches=$matches;Unknown=$observations.Unknown;Scope=$scope;Footprint=$footprint;Warning=$warning;Problem=$error;TimeUtc=$now;CanApply=(-not [bool]$error)}
}
function New-ChangePreviewDialog($preview){
    [xml]$markup=Get-Content -LiteralPath (Join-Path $appRoot 'src\ChangePreview.xaml') -Raw -Encoding UTF8
    $dialog=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($markup));$dialog.Resources=$window.Resources
    if($window.IsLoaded){$dialog.Owner=$window}
    $dialog.Tag=$preview
    $dialog.FindName('PreviewScope').Text=$preview.Scope
    $dialog.FindName('PreviewFootprint').Text=$preview.Footprint
    $dialog.FindName('PreviewWarning').Text=$preview.Warning+$(if($preview.Problem){[Environment]::NewLine+'Änderung gesperrt: '+$preview.Problem})
    $dialog.FindName('PreviewMatches').ItemsSource=@($preview.Matches)
    $dialog.FindName('PreviewHint').Text=$preview.Matches.Count.ToString()+' passende Beobachtungen · '+$preview.Unknown+' Socket-Einträge ohne sichere Richtung nicht bewertet. Keine Treffer bedeuten nicht, dass die Regel wirkungslos wäre. Stand '+$preview.TimeUtc.ToLocalTime().ToString('HH:mm:ss')+'.'
    $dialog.FindName('ApplyPreview').IsEnabled=$preview.CanApply
    $dialog.FindName('ApplyPreview').Content=switch($preview.Operation){'Rule'{$(if($preview.Rule.Action -eq 'Block'){'Regel speichern: Sperren'}else{'Regel speichern: Erlauben'})} 'BlockProgram'{'Programm sperren'} 'TemporaryBlockProgram'{'Zeitweise sperren'} 'AllowProgram'{'Dauerhaft erlauben'} 'TemporaryAllowProgram'{'10 Minuten erlauben'} 'ProgramDefault'{'Auf Standard zurücksetzen'} 'EndProgramLease'{'Zeitweise Entscheidung beenden'} default{'Anwenden'}}
    $duration=$dialog.FindName('PreviewDuration');$duration.Visibility=if($preview.Operation -eq 'TemporaryBlockProgram'){'Visible'}else{'Collapsed'}
    $duration.SelectedIndex=switch($preview.Minutes){30{1} 60{2} 0{3} default{0}}
    $duration.Add_SelectionChanged({param($sender,$e) $owner=[Windows.Window]::GetWindow($sender);if($owner -and $owner.Tag){$owner.Tag.Minutes=[int]$sender.SelectedItem.Tag}})
    $dialog.FindName('ApplyPreview').Add_Click({param($sender,$e) [Windows.Window]::GetWindow($sender).DialogResult=$true})
    $dialog
}
function Show-ChangePreview($preview){
    $dialog=New-ChangePreviewDialog $preview
    if($dialog.ShowDialog()){return $dialog.Tag}
    return $null
}

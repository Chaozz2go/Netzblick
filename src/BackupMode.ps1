function Get-TextDigest([string]$text){$hash=[Security.Cryptography.SHA256]::Create();try{[Convert]::ToBase64String($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)))}finally{$hash.Dispose()}}
function Get-BackupBundle {
    if($script:experienceReadOnly -or $script:workspaceReadOnly){throw 'Nicht lesbare Benutzerdaten zuerst prüfen; keine unvollständige Sicherung als vollständig melden.'}
    $b=New-Object Netzblick.BackupBundle
    if($script:setupStatus -and $setupStatus.Verified){$b.Control=[Netzblick.SetupChanges]::CopyConfig($setupStatus.Config)}
    foreach($p in $favoritePrograms.Values){$b.Favorites.Add($p)}
    foreach($g in $workspaceSettings.Groups){$copy=New-Object Netzblick.ProgramGroup;$copy.Id=$g.Id;$copy.Name=$g.Name;foreach($p in $g.Paths){$copy.Paths.Add($p)};$b.Groups.Add($copy)}
    foreach($p in $knownPrograms.Keys){$b.Seen.Add($p)}
    foreach($p in $newPrograms.Values){$entry=New-Object Netzblick.BackupPending;$entry.Path=$p.Path;$entry.FirstUtc=([datetime]$p.FirstUtc).ToUniversalTime();$b.Pending.Add($entry)}
    foreach($t in $targetLedger.Values){$entry=New-Object Netzblick.BackupTarget;$entry.Path=$t.PathKey;$entry.Address=$t.Address;$entry.Protocol=switch -Regex ([string]$t.Protocol){'^TCP'{6;break} '^UDP'{17;break} '^ICMPv6'{58;break} '^ICMP'{1;break} default{[int]$t.Protocol}};$entry.Port=[int]$t.Port;$entry.Reviewed=[bool]$t.Reviewed;$entry.FirstUtc=([datetime]$t.FirstUtc).ToUniversalTime();$b.Targets.Add($entry)}
    $b.Validate();$b
}
function Export-NetzblickBackup([string]$path){$bundle=Get-BackupBundle;Write-LocalAtomic $path ((Get-LocalJson).Serialize($bundle));$bundle}
function Read-NetzblickBackup([string]$path){
    if(-not [IO.File]::Exists($path) -or (Get-Item -LiteralPath $path).Length -gt 8388608){throw 'Sicherung fehlt oder ist größer als 8 MB.'}
    $b=ConvertFrom-LocalJson ([IO.File]::ReadAllText($path)) ([Netzblick.BackupBundle]);$b.Validate();$b
}
function Get-RestoreCategoryKey([int]$category){
    switch($category){
        0{if(-not $script:setupStatus -or -not $setupStatus.Verified){throw 'Filterstatus unbestätigt.'};[Netzblick.SetupChanges]::ConfigKey($setupStatus.Config)}
        1{Get-TextDigest ((@($favoritePrograms.Values | Sort-Object)) | ConvertTo-Json -Compress)}
        2{Get-TextDigest ((Get-LocalJson).Serialize(@($workspaceSettings.Groups | Sort-Object Id)))}
        3{Get-TextDigest (@{Seen=@($knownPrograms.Keys | Sort-Object);Pending=@($newPrograms.Values | Sort-Object Path);Targets=@($targetLedger.Values | Sort-Object Key);Blocks=@($blockBaselines.Values | Sort-Object Key)} | ConvertTo-Json -Depth 8 -Compress)}
        default{throw 'Unbekannte Wiederherstellungskategorie.'}
    }
}
function Get-RestorePreview($bundle,[int]$category){
    $bundle.Validate();$rows=@();$problem='';$key=''
    try{$key=Get-RestoreCategoryKey $category}catch{$problem=$_.Exception.Message}
    switch($category){
        0{
            $title='Eigene Dienstregeln';$next=$null
            if(-not $bundle.Control){$problem='Diese Sicherung enthält keine bestätigten Dienstregeln.'}
            elseif($script:setupStatus){$next=[Netzblick.SetupChanges]::RestoreOwnedConfig($setupStatus.Config,$bundle.Control,[datetime]::UtcNow)
                foreach($rule in $next.Rules){$rows+=[pscustomobject]@{Name=$rule.Name;Detail=($(if($rule.Action -eq 'Block'){'Sperren'}else{'Erlauben'})+' · '+$rule.Scope+' · '+$rule.Lifetime)}}
                foreach($p in $next.WatchedPaths){$rows+=[pscustomobject]@{Name='Programm-Prüfsperre';Detail=$p}}
            }
            $effect='Ersetzt sämtliche eigenen Dienstregeln, Programm-Prüfsperren und zeitweisen Rückwege. Abgelaufene Entscheidungen werden nicht neu gestartet. Der aktuelle allgemeine Nachfragemodus bleibt erhalten. Ältere Windows-Regeln und fremde Filter werden nicht verändert.'
            if($script:setupStatus -and $setupStatus.RecoveryUtc){$problem='Zuerst die laufende Einrichtung bestätigen oder den Sicherheitsrückweg abwarten.'}
            $counts=if($next){$setupStatus.Config.Rules.Count.ToString()+' aktuelle Dienstregeln → '+$next.Rules.Count+' aus der Sicherung; '+$next.WatchedPaths.Count+' Programm-Prüfsperren; '+$next.ProgramLeases.Count+' zeitweise Rückwege.'}else{''}
        }
        1{$title='Favoriten';foreach($p in $bundle.Favorites){$rows+=[pscustomobject]@{Name=[IO.Path]::GetFileName($p);Detail=$p}};$effect='Ersetzt nur die Favoritenliste. Zeitstrahl, Gruppen, Dateivergleichsstände, Prüfentscheidungen und Firewallregeln bleiben erhalten.';$counts=$favoritePrograms.Count.ToString()+' aktuelle Favoriten → '+$bundle.Favorites.Count+' aus der Sicherung.';if($experienceReadOnly){$problem='Favoritendatei nicht lesbar; vorhandene Datei wird nicht überschrieben.'}}
        2{$title='Programmgruppen';foreach($g in $bundle.Groups){foreach($p in $g.Paths){$rows+=[pscustomobject]@{Name=$g.Name;Detail=$p}}};$effect='Ersetzt nur bestätigte Gruppenzuordnungen. Führt keine Gruppenaktion aus und verändert keine Firewallregel. Datei-Vergleichsstände bleiben erhalten.';$counts=$workspaceSettings.Groups.Count.ToString()+' aktuelle Gruppen → '+$bundle.Groups.Count+' aus der Sicherung.';if($workspaceReadOnly){$problem='Arbeitsbereich nicht lesbar; vorhandene Datei wird nicht überschrieben.'}}
        3{$title='Prüfentscheidungen';foreach($t in $bundle.Targets){$rows+=[pscustomobject]@{Name=[IO.Path]::GetFileName($t.Path);Detail=($t.Address+' · '+$t.Protocol+' '+$t.Port+' · '+$(if($t.Reviewed){'geprüft'}else{'noch offen'}))}};foreach($p in $bundle.Pending){$rows+=[pscustomobject]@{Name='Programm noch offen';Detail=$p.Path}};$effect='Ersetzt gemerkte Programme, offene Programmprüfungen und Ziel-Prüfentscheidungen. Blockversuche der laufenden Dienst-Erfassung werden danach erneut geprüft. Keine Firewalländerung. Design, Favoriten, Gruppen und Datei-Vergleichsstände bleiben erhalten.';$counts=$bundle.Seen.Count.ToString()+' gemerkte Programme; '+$bundle.Pending.Count+' offene Programme; '+$bundle.Targets.Count+' Ziel-Prüfentscheidungen.'}
    }
    [pscustomobject]@{Bundle=$bundle;Category=$category;ExpectedKey=$key;Title=$title;Effect=$effect;Counts=$counts;Rows=$rows;Problem=$problem;CanApply=(-not [bool]$problem)}
}
function Apply-RestorePreview($preview){
    if($null -eq $preview -or $preview -is [array] -or $null -eq $preview.PSObject.Properties['CanApply']){throw ('Ungültige Wiederherstellungsvorschau: '+$(if($null -eq $preview){'leer'}else{$preview.GetType().FullName}))}
    if(-not $preview.CanApply){throw ('Wiederherstellung nicht anwendbar: '+$preview.Problem)}
    if((Get-RestoreCategoryKey $preview.Category) -ne $preview.ExpectedKey){throw 'Diese Kategorie hat sich seit der Vorschau verändert. Vorschau erneut öffnen.'}
    $preview.Bundle.Validate()
    $rescue=Join-Path (Join-Path $userStateDirectory 'backups') ('Vor-Wiederherstellung-'+[datetime]::UtcNow.ToString('yyyyMMdd-HHmmssfff')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)+'.netzblick.json')
    [void](Export-NetzblickBackup $rescue)
    $script:workspaceRestoring=$true
    try{
        switch($preview.Category){
            0{[void](Send-SetupCommand ([Netzblick.SetupCommand]@{Operation='RestoreOwnedConfig';RestoreConfig=$preview.Bundle.Control;ExpectedConfigKey=$preview.ExpectedKey}));Update-AccessMode}
            1{$before=$script:favoritePrograms;$script:favoritePrograms=@{};foreach($p in $preview.Bundle.Favorites){$favoritePrograms[[Netzblick.ProcessLineage]::Normalize($p)]=$p};try{Save-ExperienceState -ThrowOnError}catch{$script:favoritePrograms=$before;throw}}
            2{$before=Copy-WorkspaceSettings;$workspaceSettings.Groups.Clear();foreach($g in $preview.Bundle.Groups){$workspaceSettings.Groups.Add($g)};try{Save-WorkspaceSettings}catch{$script:workspaceSettings=$before;throw}}
            3{
                $before=@{Known=$knownPrograms;Pending=$newPrograms;Targets=$targetLedger;Blocks=$blockBaselines;Baseline=$userBaseline}
                $script:knownPrograms=@{};$script:newPrograms=@{};$script:targetLedger=@{};$script:blockBaselines=@{}
                foreach($p in $preview.Bundle.Seen){$knownPrograms[[Netzblick.ProcessLineage]::Normalize($p)]=$true}
                foreach($p in $preview.Bundle.Pending){$k=[Netzblick.ProcessLineage]::Normalize($p.Path);$newPrograms[$k]=[pscustomobject]@{Key=$k;Path=$p.Path;Name=[IO.Path]::GetFileName($p.Path);FirstUtc=$p.FirstUtc}}
                foreach($t in $preview.Bundle.Targets){$k=Get-TargetKey $t.Path $t.Address $t.Protocol $t.Port;$targetLedger[$k]=[pscustomobject]@{Key=$k;PathKey=[Netzblick.ProcessLineage]::Normalize($t.Path);Address=$t.Address;Protocol=$t.Protocol;Port=$t.Port;Reviewed=$t.Reviewed;FirstUtc=$t.FirstUtc}}
                $script:userBaseline=$true;$script:targetReviewCounts=$null
                try{Save-UserState -ThrowOnError}catch{$script:knownPrograms=$before.Known;$script:newPrograms=$before.Pending;$script:targetLedger=$before.Targets;$script:blockBaselines=$before.Blocks;$script:userBaseline=$before.Baseline;$script:targetReviewCounts=$null;throw}
                $script:guideEpoch=[guid]::NewGuid().ToString('N');$script:guideSnapshot=$null;$script:guideQueue=@()
            }
        }
    }finally{$script:workspaceRestoring=$false}
    Add-ProgramTimeline '*' 'Eigene Sicherung wiederhergestellt' ($preview.Title+' gezielt wiederhergestellt. Andere Kategorien bleiben erhalten.')
    $ui.BackupNotice.Text=$preview.Title+' wiederhergestellt. Vorheriger Zustand gesichert: '+$rescue
    Refresh-Programs;Refresh-Favorites;Refresh-Groups;Refresh-Guide;Update-ProgramFileCard
    $rescue
}
function New-RestoreDialog($preview){
    [xml]$markup=Get-Content -LiteralPath (Join-Path $appRoot 'src\RestorePreview.xaml') -Raw -Encoding UTF8
    $dialog=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($markup));$dialog.Resources=$window.Resources;if($window.IsLoaded){$dialog.Owner=$window}
    $dialog.FindName('RestoreTitle').Text=$preview.Title+' wiederherstellen?'
    $dialog.FindName('RestoreEffect').Text=$preview.Effect
    $dialog.FindName('RestoreCounts').Text=$preview.Counts
    $dialog.FindName('RestoreEntries').ItemsSource=@($preview.Rows)
    $dialog.FindName('RestoreProblem').Text=$preview.Problem
    $dialog.FindName('RestoreApply').IsEnabled=$preview.CanApply
    $dialog.FindName('RestoreApply').Add_Click({param($sender,$e) [Windows.Window]::GetWindow($sender).DialogResult=$true})
    $dialog
}
function Refresh-BackupView {
    if(-not $script:programWorkspaceReady){return}
    $ui.BackupSave.IsEnabled=-not ($workspaceReadOnly -or $experienceReadOnly)
    $ui.BackupPreview.IsEnabled=[bool]$script:loadedBackup
    $ui.BackupSummary.Text=if($loadedBackup){'Sicherung vom '+$loadedBackup.CreatedUtc.ToLocalTime().ToString('dd.MM.yyyy HH:mm:ss')+' · '+$loadedBackup.Favorites.Count+' Favoriten · '+$loadedBackup.Groups.Count+' Gruppen · '+$loadedBackup.Targets.Count+' Ziel-Prüfentscheidungen · '+$(if($loadedBackup.Control){$loadedBackup.Control.Rules.Count.ToString()+' Dienstregeln'}else{'keine bestätigten Dienstregeln enthalten'})}else{'Noch keine Sicherung zum Wiederherstellen ausgewählt.'}
}
function Initialize-BackupMode {
    $script:loadedBackup=$null
    $ui.BackupSave.Add_Click({
        $dialog=New-Object Microsoft.Win32.SaveFileDialog;$dialog.Filter='Netzblick-Sicherung (*.netzblick.json)|*.netzblick.json';$dialog.FileName='Netzblick-Sicherung-'+(Get-Date -Format 'yyyy-MM-dd')+'.netzblick.json'
        if($dialog.ShowDialog($window)){try{$b=Export-NetzblickBackup $dialog.FileName;$ui.BackupNotice.Text='Sicherung gespeichert: '+$dialog.FileName+$(if(-not $b.Control){' · Dienststatus unbestätigt: keine Dienstregeln enthalten.'})}catch{Show-Error $_.Exception.GetBaseException().Message}}
    })
    $ui.BackupLoad.Add_Click({
        $dialog=New-Object Microsoft.Win32.OpenFileDialog;$dialog.Filter='Netzblick-Sicherung (*.netzblick.json)|*.netzblick.json'
        if($dialog.ShowDialog($window)){try{$script:loadedBackup=Read-NetzblickBackup $dialog.FileName;$ui.BackupNotice.Text='Sicherung geprüft. Jetzt eine Kategorie wählen und die Vorschau öffnen.'}catch{$script:loadedBackup=$null;Show-Error $_.Exception.GetBaseException().Message};Refresh-BackupView}
    })
    $ui.BackupPreview.Add_Click({if($loadedBackup){try{$preview=Get-RestorePreview $loadedBackup $ui.BackupCategory.SelectedIndex;$dialog=New-RestoreDialog $preview;if($dialog.ShowDialog()){[void](Apply-RestorePreview $preview)}}catch{Show-Error $_.Exception.GetBaseException().Message}}})
    Refresh-BackupView
}

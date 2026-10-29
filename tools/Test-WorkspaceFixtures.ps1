# Runs in the existing WPF fixture process with FakeSetupClient only.
$programsBeforeWorkspace=$script:allProgramItems;$rowsBeforeWorkspace=$script:rows;$peersBeforeWorkspace=$script:trafficPeers
[Netzblick.SetupClient]::Scenario($testExe,0);Update-AccessMode
# Six visible primary areas; context navigation is independent of the old internal panel names.
foreach($page in @('Programs','Favorites','Hosts','Groups','Guide','BeforeStart','Connections','Rules','History','Backups','Updates')){
 Navigate-Workspace $page
 $panel=switch($page){'Programs'{'OverviewPanel'} 'Favorites'{'WorkflowPanel'} 'Hosts'{'HostsPanel'} 'Groups'{'GroupsPanel'} 'Guide'{'WorkflowPanel'} 'BeforeStart'{'InspectionPanel'} 'Connections'{'AccessPanel'} 'Rules'{'AccessPanel'} 'History'{'AccessPanel'} 'Backups'{'BackupPanel'} 'Updates'{'UpdatesPanel'}}
 Show-RealPanel $panel
 $expected=switch($page){'Guide'{'Review'} 'BeforeStart'{'Review'} 'Connections'{'Review'} 'Rules'{'Rules'} 'History'{'History'} 'Backups'{'Settings'} 'Updates'{'Settings'} default{'Programs'}}
 if((Get-WorkspaceArea $panel) -ne $expected){throw ('Falscher Navigationsbereich: '+$page)}
}
if($ui.HostsTab.Visibility -ne 'Collapsed' -or $ui.AccessTab.Visibility -ne 'Collapsed' -or $ui.InspectionTab.Visibility -ne 'Collapsed' -or $ui.UpdatesTab.Visibility -ne 'Collapsed'){throw 'Alte doppelte Hauptnavigation bleibt sichtbar.'}
if(@($ui.WorkspaceNavigation.Children | Where-Object Visibility -eq 'Visible').Count -ne 2){throw 'Einstellungen enthalten fremde Navigationspunkte.'}
# Explicit membership is saved locally, including inactive paths, and never changes policy.
$group=New-Object Netzblick.ProgramGroup;$group.Id=[guid]::NewGuid().ToString();$group.Name='Browser & Hilfsprogramm';$group.Paths.Add($testExe);$group.Paths.Add((Join-Path $env:SystemRoot 'System32\cmd.exe'))
$policyBeforeGroups=[Netzblick.SetupChanges]::ConfigKey($setupStatus.Config)
Save-ProgramGroup $group;Refresh-Groups
if($ui.GroupMembers.Items.Count -ne 2 -or [Netzblick.SetupChanges]::ConfigKey($setupStatus.Config) -ne $policyBeforeGroups){throw 'Gruppenansicht verliert Mitglieder oder verändert Regeln.'}
$groupDisk=ConvertFrom-LocalJson ([IO.File]::ReadAllText($workspaceFile)) ([Netzblick.WorkspaceSettings]);$groupDisk.Validate()
if($groupDisk.Groups.Count -ne 1 -or $groupDisk.Groups[0].Paths.Count -ne 2){throw 'Bestätigte Gruppenmitglieder werden nicht gespeichert.'}
$editor=New-GroupEditor $group
if(@($editor.Tag.Entries | Where-Object Include).Count -ne 2){throw 'Gruppeneditor wählt unbestätigte Hilfsprogramme automatisch aus.'}
$editor.Close()
$preview=Get-GroupChangePreview $group 'GroupTemporaryBlock';$groupDialog=New-ChangePreviewDialog $preview
if(-not $preview.CanApply -or $preview.Paths.Count -ne 2 -or $groupDialog.FindName('PreviewDuration').Visibility -ne 'Visible'){throw 'Gruppenvorschau verliert Reichweite oder Dauer.'}
$groupDialog.Close();Apply-GroupChange $preview
if($setupStatus.Config.ProgramLeases.Count -ne 2 -or (Get-PermissionStatus $testExe).Category -ne 'Blocked'){throw 'Bestätigte Gruppe wird nicht vollständig zeitweise gesperrt.'}
$conflict=Get-GroupChangePreview $group 'GroupTemporaryBlock'
if($conflict.CanApply){throw 'Vorhandene zeitweise Entscheidung wird unbemerkt überschrieben.'}
$end=Get-GroupChangePreview $group 'GroupEndLeases';Apply-GroupChange $end
if([Netzblick.SetupChanges]::ConfigKey($setupStatus.Config) -ne $policyBeforeGroups){throw 'Gruppen-Rückweg verliert vorherige Einzelregeln.'}
# Native read-only metadata worker: same version but changed bytes must be noticed on a full read.
$fileFixture=Join-Path $userStateDirectory 'File-Change-Fixture.exe';Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\where.exe') -Destination $fileFixture
function Wait-FixtureFile($task){if(-not $task.Wait(10000)){throw 'Dateiabgleich wartet zu lange.'};if($task.Result.Error){throw $task.Result.Error};$task.Result}
$first=Wait-FixtureFile ([Netzblick.FileObservation]::Start($fileFixture,-1,[datetime]::MinValue,$true));Accept-FileObservation $fileFixture $first
if((Get-FileChangeState $fileFixture).Changed -or -not (Get-FileReference $fileFixture)){throw 'Erste Beobachtungsbasis ist bereits eine Änderung oder wird nicht gespeichert.'}
$bytes=[IO.File]::ReadAllBytes($fileFixture);$bytes[$bytes.Length-1]=$bytes[$bytes.Length-1] -bxor 1;[IO.File]::WriteAllBytes($fileFixture,$bytes);[IO.File]::SetLastWriteTimeUtc($fileFixture,$first.File.LastWriteUtc)
$stampOnly=Wait-FixtureFile ([Netzblick.FileObservation]::Start($fileFixture,$first.File.Length,$first.File.LastWriteUtc,$false))
if(-not $stampOnly.StampUnchanged){throw 'Metadaten-Abkürzung wird nicht als solche gekennzeichnet.'}
$changed=Wait-FixtureFile ([Netzblick.FileObservation]::Start($fileFixture,-1,[datetime]::MinValue,$true));Accept-FileObservation $fileFixture $changed
if(-not (Get-FileChangeState $fileFixture).Changed -or $changed.File.Hash -eq $first.File.Hash){throw 'Geänderte Bytes bei gleicher Version und Dateizeit bleiben unbemerkt.'}
$comparison=New-FileComparison $fileFixture
if(-not $comparison.FindName('AcceptFile').IsEnabled -or $comparison.FindName('FileDifferences').Items.Count -ne 4){throw 'Dateivergleich zeigt keine nachvollziehbare Gegenüberstellung.'}
$comparison.Close()
Accept-FileObservation $fileFixture $changed ('0'*64)
if(-not (Get-FileChangeState $fileFixture).Changed){throw 'Falscher bestätigter Hash übernimmt neue Vergleichsbasis.'}
Accept-FileObservation $fileFixture $changed $changed.File.Hash
if((Get-FileChangeState $fileFixture).Changed -or [Netzblick.SetupChanges]::ConfigKey($setupStatus.Config) -ne $policyBeforeGroups){throw 'Neue Vergleichsbasis ändert Regeln oder bleibt falsch markiert.'}
# Export/import has a typed bounded schema. Invalid input must not mutate anything.
$backupPath=Join-Path $userStateDirectory 'Roundtrip.netzblick.json';$bundle=Export-NetzblickBackup $backupPath;$loaded=Read-NetzblickBackup $backupPath
if($loaded.Groups.Count -ne 1 -or $loaded.Favorites.Count -ne $favoritePrograms.Count -or [Netzblick.SetupChanges]::ConfigKey($loaded.Control) -ne $policyBeforeGroups){throw 'Sicherung verliert eigene Einstellungen.'}
$invalidPath=Join-Path $userStateDirectory 'Invalid.netzblick.json';[IO.File]::WriteAllText($invalidPath,'{"Format":"Netzblick.Backup","Version":99}')
$rejected=$false;try{[void](Read-NetzblickBackup $invalidPath)}catch{$rejected=$true};if(-not $rejected){throw 'Ungültige Sicherung akzeptiert.'}
# Restore only favorites; policy and confirmed groups remain identical.
$favoritesOriginal=@($favoritePrograms.Values);Set-ProgramFavorite (Join-Path $env:SystemRoot 'System32\cmd.exe') $true
$favPreview=Get-RestorePreview $loaded 1;$restoreDialog=New-RestoreDialog $favPreview
if(-not $restoreDialog.FindName('RestoreApply').IsEnabled){throw 'Gültige Wiederherstellung lässt sich nicht prüfen.'}
$restoreDialog.Close();$rescuePath=Apply-RestorePreview $favPreview
if(-not [IO.File]::Exists($rescuePath) -or $favoritePrograms.Count -ne $loaded.Favorites.Count -or $workspaceSettings.Groups.Count -ne 1 -or [Netzblick.SetupChanges]::ConfigKey($setupStatus.Config) -ne $policyBeforeGroups){throw 'Favoriten-Wiederherstellung verändert andere Kategorien oder hat keine vorherige Sicherung.'}
# A stale local preview cannot overwrite a later explicit change.
$staleLocal=Get-RestorePreview $loaded 2;$other=New-Object Netzblick.ProgramGroup;$other.Id=[guid]::NewGuid().ToString();$other.Name='Später angelegt';$other.Paths.Add($testExe);Save-ProgramGroup $other
$rejected=$false;try{[void](Apply-RestorePreview $staleLocal)}catch{$rejected=$true};if(-not $rejected -or $workspaceSettings.Groups.Count -ne 2){throw 'Veraltete Gruppen-Wiederherstellung überschreibt spätere Änderungen.'}
$freshGroupRestore=Get-RestorePreview $loaded 2
Write-Output ('RESTORE_DIAGNOSTIC: '+($freshGroupRestore | ConvertTo-Json -Depth 2 -Compress))
if(-not $freshGroupRestore.CanApply){throw ('Frische Gruppenvorschau: '+($freshGroupRestore | ConvertTo-Json -Depth 2 -Compress))}
[void](Apply-RestorePreview $freshGroupRestore)
# Disk failure rolls local restore back, while preserving the rescue backup and firewall state.
Set-ProgramFavorite (Join-Path $env:SystemRoot 'System32\cmd.exe') $true;$favoriteCountBefore=$favoritePrograms.Count;$failPreview=Get-RestorePreview $loaded 1
$experiencePathBefore=$experienceFile;$badExperience=Join-Path $userStateDirectory 'Backup-Not-A-File';[void][IO.Directory]::CreateDirectory($badExperience);$script:experienceFile=$badExperience
$rejected=$false;try{[void](Apply-RestorePreview $failPreview)}catch{$rejected=$true}finally{$script:experienceFile=$experiencePathBefore}
if(-not $rejected -or $favoritePrograms.Count -ne $favoriteCountBefore -or [Netzblick.SetupChanges]::ConfigKey($setupStatus.Config) -ne $policyBeforeGroups){throw 'Fehlgeschlagene lokale Wiederherstellung verliert Zustand.'}
[void](Apply-RestorePreview (Get-RestorePreview $loaded 1))
# Review category keeps favorites/groups and resets only the selected review data, never policy.
[void](Apply-RestorePreview (Get-RestorePreview $loaded 3))
if($workspaceSettings.Groups.Count -ne 1 -or $favoritePrograms.Count -ne $loaded.Favorites.Count -or [Netzblick.SetupChanges]::ConfigKey($setupStatus.Config) -ne $policyBeforeGroups){throw 'Prüfentscheidungs-Wiederherstellung verändert andere Kategorien.'}
# Own rules can be restored only with the exact current preview; current global mode is retained.
$bundleWithRules=Read-NetzblickBackup $backupPath;[Netzblick.SetupChanges]::BlockProgram($bundleWithRules.Control,$testExe);$bundleWithRules.Control.Ask=$true
[void](Apply-RestorePreview (Get-RestorePreview $bundleWithRules 0))
if($setupStatus.Config.Ask -or (Get-PermissionStatus $testExe).Category -ne 'Blocked'){throw 'Regel-Wiederherstellung verändert allgemeinen Modus oder verliert Sperre.'}
[void](Apply-RestorePreview (Get-RestorePreview $loaded 0))
$script:loadedBackup=$loaded;Refresh-BackupView
$script:allProgramItems=$programsBeforeWorkspace;$ui.Programs.ItemsSource=$programsBeforeWorkspace;$script:rows=$rowsBeforeWorkspace;$script:trafficPeers=$peersBeforeWorkspace
# Representative changed-file badge without touching fixture executable metadata further.
$displayReference=New-Object Netzblick.FileReference;$displayReference.Path=$testExe;$displayReference.Hash='A'*64;$displayReference.Company='Beispielhersteller';$displayReference.FileVersion='1.0';$displayReference.Signer='Eingebetteter Unterzeichner: Beispiel · Vertrauen nicht geprüft';$displayReference.Length=100;$displayReference.LastWriteUtc=[datetime]::UtcNow.AddDays(-1);$displayReference.CapturedUtc=$displayReference.LastWriteUtc
$existingReference=Get-FileReference $testExe;if($existingReference){[void]$workspaceSettings.Files.Remove($existingReference)};$workspaceSettings.Files.Add($displayReference)
$displayCurrent=New-Object Netzblick.FileReference;$displayCurrent.Path=$testExe;$displayCurrent.Hash='B'*64;$displayCurrent.Company='Beispielhersteller';$displayCurrent.FileVersion='1.1';$displayCurrent.Signer=$displayReference.Signer;$displayCurrent.Length=110;$displayCurrent.LastWriteUtc=[datetime]::UtcNow;$displayCurrent.CapturedUtc=[datetime]::UtcNow
$script:fileObservations[[Netzblick.ProcessLineage]::Normalize($testExe)]=[Netzblick.FileObservation]@{File=$displayCurrent}
Refresh-Overview;$ui.OverviewFilter.SelectedIndex=4
if(-not $ui.OverviewPrograms.Items.Count -or @($ui.OverviewPrograms.Items | Where-Object {-not $_.FileChanged}).Count){throw 'Filter für Dateiänderungen fehlt.'}
$ui.OverviewFilter.SelectedIndex=0
Start-GuidedReview;Show-RealPanel 'OverviewPanel'
Write-Output 'PASS: sechs Hauptbereiche und klare Kontextnavigation; explizite persistente Gruppen und atomare Vorschau/Rückwege; read-only Dateiänderung trotz gleicher Metadaten beim Vollabgleich; typisierte Sicherung, kategorieweise Wiederherstellung, Schutz vor veralteter Vorschau und Speicherfehler-Rollback ohne fremde Regeländerungen.'

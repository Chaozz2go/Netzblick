# Called inside Test-UI: all rule commands use FakeSetupClient; no native changes.
$originalPrograms=$script:allProgramItems;$originalRows=$script:rows;$originalPeers=$script:trafficPeers
[Netzblick.SetupClient]::Scenario($testExe,0);Update-AccessMode
$script:allProgramItems=$originalPrograms;$ui.Programs.ItemsSource=$originalPrograms
$policyBeforeExperience=[Netzblick.SetupChanges]::ConfigKey($setupStatus.Config)
Set-ProgramFavorite $testExe $true
if($ui.FavoritesList.Items.Count -ne 1 -or -not [IO.File]::Exists($experienceFile)){throw 'Favoriten werden nicht gespeichert.'}
$savedExperienceFile=$experienceFile;$badFile=Join-Path $userStateDirectory 'not-a-file';[void][IO.Directory]::CreateDirectory($badFile)
$script:experienceFile=$badFile
try{Set-ProgramFavorite (Join-Path $env:SystemRoot 'System32\cmd.exe') $true;throw 'Speicherfehler wurde verschluckt.'}catch{if($favoritePrograms.Count -ne 1){throw 'Fehlgeschlagenes Merken hinterlässt falschen Favoritenstatus.'}}finally{$script:experienceFile=$savedExperienceFile}
$script:rows=@();$script:allProgramItems=@(Get-ProgramCatalog @() @() @(Get-FavoriteCatalogEntries) $setupStatus @());$ui.Programs.ItemsSource=$allProgramItems
Refresh-Favorites
if($allProgramItems.Count -ne 1 -or $allProgramItems[0].Observed -or $ui.FavoritesList.Items.Count -ne 1){throw 'Inaktiver Favorit verschwindet oder erfindet Aktivität.'}
[Netzblick.SetupChanges]::TemporaryBlockProgram($setupStatus.Config,$testExe,30,[datetime]::UtcNow);Refresh-Favorites
if($ui.FavoritesList.Items[0].LeaseText -notlike 'Gesperrt*noch*' -or -not $ui.FavoriteResume.IsEnabled -or $ui.FavoriteBlock.IsEnabled){throw 'Favorit zeigt keine Restzeit oder falsche Aktionen.'}
$setupStatus.Config.ProgramLeases[0].ExpiresUtc=[datetime]::UtcNow.AddSeconds(-1);Refresh-Favorites
if($ui.FavoritesList.Items[0].LeaseText -notlike '*Dienstbestätigung*'){throw 'Abgelaufene Frist behauptet Wiederfreigabe ohne Dienstbestätigung.'}
[Netzblick.SetupClient]::Scenario($testExe,3);Update-AccessMode;Refresh-Favorites
if($ui.FavoriteBlock.IsEnabled -or $ui.FavoriteResume.IsEnabled -or $ui.FavoritesList.Items[0].LeaseText -notlike '*unbestätigt*'){throw 'Unbestätigter Dienst erlaubt Favoriten-Sperränderung.'}
[Netzblick.SetupClient]::Scenario($testExe,0);Update-AccessMode
# Fixed queue + immutable acknowledged observations, even when new evidence arrives while reading.
$script:targetLedger=@{};$script:targetReviewCounts=$null;$script:blockBaselines=@{};$script:newPrograms=@{}
$script:trafficPeers=@([pscustomobject]@{Path=$testExe;Protocol='TCPv4';Address='198.51.100.10';Port=443})
$guideOther=Join-Path $env:SystemRoot 'System32\cmd.exe'
$script:allProgramItems=@([pscustomobject]@{Key=[Netzblick.ProcessLineage]::Normalize($testExe);Path=$testExe;Name='Browser';Rows=@()},[pscustomobject]@{Key=[Netzblick.ProcessLineage]::Normalize($guideOther);Path=$guideOther;Name='Zweites Programm';Rows=@()})
$ui.Programs.ItemsSource=$allProgramItems
foreach($p in $allProgramItems){$newPrograms[$p.Key]=[pscustomobject]@{Path=$p.Path;Name=$p.Name;FirstUtc=[datetime]::UtcNow}}
$guideAttempt=[Netzblick.SetupAttempt]@{Key='guide-evidence';Path=$testExe;Program='Browser';Direction='Ausgehend';Address='198.51.100.10';Protocol=6;Port=443;Count=3;FirstUtc=[datetime]::UtcNow;LastUtc=[datetime]::UtcNow;BlockReason='Beispiel: gezielte Netzblick-Sperre'}
$setupStatus.Attempts.Add($guideAttempt)
Start-GuidedReview
if($guideQueue.Count -ne 2 -or $guideSnapshot.Counts[0].Count -ne 3 -or $ui.GuideEvidence.Items.Count -ne 2){throw 'Prüfassistent erfasst nicht alle Prüfgründe.'}
$oldSnapshot=$guideSnapshot;$oldPath=$guideSnapshot.Path
$guideAttempt.Count=5;$script:trafficPeers+=@([pscustomobject]@{Path=$testExe;Protocol='TCPv4';Address='203.0.113.20';Port=443});Update-ActivityLedger;Refresh-Guide
if(-not [object]::ReferenceEquals($oldSnapshot,$guideSnapshot) -or $guideSnapshot.Path -ne $oldPath -or $guideSnapshot.Counts[0].Count -ne 3){throw 'Aktualisierung ersetzt den gelesenen Prüfstand.'}
Complete-GuideSnapshot
$review=Get-ProgramReviewState $testExe
if(-not $review.NeedsReview -or $review.NewTargets -ne 1 -or $review.NewBlocks -ne 2 -or $guideIndex -ne 1 -or $guideSnapshot.Path -ne $guideOther){throw 'Prüfung bestätigt unbemerkt neue Ziele/Blockversuche oder springt falsch.'}
if([Netzblick.SetupChanges]::ConfigKey($setupStatus.Config) -ne $policyBeforeExperience){throw 'Geführte Prüfung verändert Firewallregeln.'}
$ui.GuideBack.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
if($guideSnapshot.Path -ne $testExe -or $guideSnapshot.Reason -notlike '*2 neue Blockversuche*'){throw 'Zurück zeigt nicht den aktuellen offenen Rest.'}
# Rule previews: incoming local service port, unknown directions, conflicts, exact replacement, no native/policy changes.
$script:rows=@(
 [Netzblick.SocketRow]@{Path=$testExe;Pid=9911;ProcessStartUtc=[datetime]::UtcNow.AddMinutes(-5);Protocol='TCPv4';Local='192.0.2.10:8443';Remote='198.51.100.30:51000';Address='198.51.100.30';Port=51000;State='SYN empfangen'},
 [Netzblick.SocketRow]@{Path=$testExe;Pid=9911;ProcessStartUtc=[datetime]::UtcNow.AddMinutes(-5);Protocol='TCPv4';Local='192.0.2.10:51001';Remote='198.51.100.31:443';Address='198.51.100.31';Port=443;State='Verbunden'})
$rule=[Netzblick.SetupRule]@{Id=[guid]::NewGuid().ToString();Name='Beispiel: lokaler Webdienst';Path=$testExe;Direction='Eingehend';Address='198.51.100.30';Protocol=6;Port=8443;Action='Allow'}
$beforePreview=[Netzblick.SetupChanges]::ConfigKey($setupStatus.Config)
$preview=Get-ChangePreview $testExe 'Rule' $rule
if($preview.Matches.Count -ne 1 -or $preview.Unknown -ne 1 -or $preview.Matches[0].Target -notlike '*8443*' -or [Netzblick.SetupChanges]::ConfigKey($setupStatus.Config) -ne $beforePreview){throw 'Vorschau verwechselt Dienstport, rät Richtung oder verändert Konfiguration.'}
$broad=[Netzblick.SetupRule]@{Id=[guid]::NewGuid().ToString();Name='Übergeordnete Sperre';Path=$testExe;Direction='Eingehend';Address='*';Protocol=0;Port=0;Action='Block'}
$setupStatus.Config.Rules.Add($broad)
$conflict=Get-ChangePreview $testExe 'Rule' $rule
if($conflict.CanApply -or $conflict.Problem -notlike '*Sperrregel*'){throw 'Vorschau verschweigt Konflikt mit breiter Sperre.'}
$setupStatus.Config.Rules.Clear();$same=[Netzblick.SetupChanges]::CopyRule($rule);$same.Id=[guid]::NewGuid().ToString();$same.Action='Block';$setupStatus.Config.Rules.Add($same)
$replacement=Get-ChangePreview $testExe 'Rule' $rule
if(-not $replacement.CanApply -or $replacement.Footprint -notlike '1 bisherige*' -or $replacement.Matches[0].After -notlike 'Netzblick-Freigabe*'){throw 'Gleicher Geltungsbereich wird nicht als Ersatz berechnet.'}
$setupStatus.Config.Rules.Clear()
$programPreview=Get-ChangePreview $testExe 'TemporaryBlockProgram'
if(-not $programPreview.CanApply -or $programPreview.Matches.Count -ne 1){throw 'Programm-Vorschau fehlt oder bewertet unbekannte Richtung.'}
$dialog=New-ChangePreviewDialog $programPreview
if(-not $dialog.FindName('ApplyPreview').IsEnabled -or $dialog.FindName('PreviewDuration').Visibility -ne 'Visible'){throw 'Echte Vorschau bietet zeitweise Sperre nicht an.'}
$dialog.FindName('PreviewDuration').SelectedIndex=3
if($dialog.Tag.Minutes -ne 0){throw 'Dauer bis aufgehoben geht in Vorschau verloren.'}
# Render a real preview at a fixed size without executing it.
$previewRoot=$dialog.Content;$dialog.Content=$null;$previewHost=New-Object Windows.Controls.Border;$previewHost.Resources=$window.Resources;$previewHost.Child=$previewRoot;$previewHost.SetResourceReference([Windows.Controls.Border]::BackgroundProperty,'AppBg');$previewHost.Width=850;$previewHost.Height=690
$previewHost.Measure([Windows.Size]::new(850,690));$previewHost.Arrange([Windows.Rect]::new(0,0,850,690));$previewHost.UpdateLayout()
$previewImage=New-Object Windows.Media.Imaging.RenderTargetBitmap(850,690,96,96,[Windows.Media.PixelFormats]::Pbgra32);$previewImage.Render($previewHost);$previewEncoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$previewEncoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($previewImage));$previewFile=[IO.File]::Create((Join-Path $OutputDirectory 'ChangePreview.png'));try{$previewEncoder.Save($previewFile)}finally{$previewFile.Dispose();$dialog.Close()}
# Snapshot guarded inside the fake as in the native service; failed command creates no success history.
$stale=Get-ChangePreview $testExe 'BlockProgram';$setupStatus.Config.Ask=$true
$historyBeforeFailure=$programTimeline.Count
try{Set-PermissionProgram $testExe 'BlockProgram' 10 $stale.ExpectedConfigKey;throw 'Veraltete Vorschau akzeptiert.'}catch{if($_.Exception.Message -notlike '*Vorschau*'){throw}}
if($programTimeline.Count -ne $historyBeforeFailure -or $setupStatus.Config.Rules.Count){throw 'Abgelehnte Änderung wird als erfolgreich aufgezeichnet.'}
$setupStatus.Config.Ask=$false
# Round-trip local pins/history and bound the total, without inventing causal events.
Add-ProgramTimeline $testExe 'Test: beobachtet' 'Beobachtung ohne behauptete Ursache.'
Save-ExperienceState -ThrowOnError
Read-ExperienceState
if($favoritePrograms.Count -ne 1 -or -not @($programTimeline | Where-Object Kind -eq 'Test: beobachtet').Count){throw 'Favoriten/Zeitstrahl gehen beim erneuten Laden verloren.'}
for($i=0;$i -lt 410;$i++){Add-ProgramTimeline $testExe 'Begrenzungstest' ('Ereignis '+$i)}
if($programTimeline.Count -ne 400){throw 'Zeitstrahl ist nicht begrenzt.'}
Reset-ExperienceHistory
if($favoritePrograms.Count -ne 1 -or $programTimeline.Count -ne 1 -or $guideSnapshot){throw 'Reset verliert Favoriten oder lässt alte Prüfauswahl stehen.'}
# Representative fictional data for the screenshot matrix, independent of later setup scenarios.
$script:allProgramItems=$originalPrograms;$ui.Programs.ItemsSource=$originalPrograms;$script:rows=$originalRows;$script:trafficPeers=$originalPeers
$script:trafficPeers+=@([pscustomobject]@{Path=$testExe;Protocol='TCPv4';Address='198.51.100.10';Port=443});Update-ActivityLedger
Start-GuidedReview
Add-ProgramTimeline $testExe 'Programm erkannt' 'Beispieldaten: Programm erstmals im Netzwerkkatalog beobachtet.'
Add-ProgramTimeline $testExe 'Blockversuche erfasst' 'Beispieldaten: 2 ausgehende Versuche zu 198.51.100.10, TCP 443. Aufgezeichneter Grund: gezielte Netzblick-Sperre.'
Add-ProgramTimeline $testExe 'Programmregeln geändert' 'Beispieldaten: Regeländerung bestätigt. Das beweist keinen späteren Verbindungserfolg.'
$ui.Programs.SelectedItem=$originalPrograms | Where-Object Path -eq $testExe | Select-Object -First 1;Update-ProgramTimeline
Refresh-Favorites;Save-ExperienceState
Write-Output 'PASS: feste Prüfreihenfolge und gezählte Momentaufnahme; späte Ziele/Blockversuche bleiben offen; Favoriten/Restzeit/Speicher-Rollback; Regelvorschau mit lokalem eingehendem Port und Konflikten; begrenzter persistenter Zeitstrahl ohne erfundene Ursachen.'

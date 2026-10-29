#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory=(Join-Path $PSScriptRoot 'ui-preview'),[switch]$LogPreview)
$ErrorActionPreference='Stop'
trap {Write-Output $_.ScriptStackTrace;Write-Output $_.InvocationInfo.PositionMessage;throw}
Add-Type -AssemblyName @('PresentationFramework','PresentationCore','WindowsBase')
$appRoot=Split-Path $PSScriptRoot -Parent
$sources=@('NetworkReader.cs','GeoDatabase.cs','ProbeSession.cs','InspectionCore.cs','WindowsInspection.cs','NetworkPolicyCore.cs','EndpointInfo.cs','AccessCore.cs','WindowsAccess.cs','AccessWatch.cs','SetupCore.cs','ReleaseUpdates.cs','TrafficCore.cs') | ForEach-Object {Join-Path $appRoot ('src\'+$_)}
$sources+=Join-Path $PSScriptRoot 'FakeSetupClient.cs'
Add-Type -ReferencedAssemblies @('System.dll','System.Core.dll','System.Xml.dll','System.Web.Extensions.dll','System.Security.dll') -Path $sources
[xml]$xaml=Get-Content -LiteralPath (Join-Path $appRoot 'src\MainWindow.xaml') -Raw -Encoding UTF8
$window=[Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader($xaml)))
$ui=@{}
$xaml.GetElementsByTagName('*') | ForEach-Object {$name=$_.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml');if($name){$control=$window.FindName($name);if($control){$ui[$name]=$control}}}
foreach($panelName in @('World','Terminal','Inspection','Overview','Access','Updates','Dashboard','Hosts','Workflow')){
 [xml]$panelXaml=Get-Content -LiteralPath (Join-Path $appRoot ('src\'+$panelName+'Panel.xaml')) -Raw -Encoding UTF8
 $panel=[Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader($panelXaml)));$ui[$panelName+'Panel'].Content=$panel
 $panelXaml.GetElementsByTagName('*') | ForEach-Object {$name=$_.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml');if($name){$ui[$name]=$panel.FindName($name)}}
}
function Show-Error([string]$message){throw $message}
function Is-Protected([string]$path){return $false}
. (Join-Path $appRoot 'src\ThemeMode.ps1')
. (Join-Path $appRoot 'src\DesignMode.ps1')
. (Join-Path $appRoot 'src\DirectionMode.ps1')
. (Join-Path $appRoot 'src\ExperienceState.ps1')
    . (Join-Path $appRoot 'src\GuideMode.ps1')
    . (Join-Path $appRoot 'src\ChangePreview.ps1')
    . (Join-Path $appRoot 'src\HostsMode.ps1')
    . (Join-Path $appRoot 'src\DashboardMode.ps1')
    . (Join-Path $appRoot 'src\DashboardNavigation.ps1')
. (Join-Path $appRoot 'src\WorkspaceMode.ps1')
. (Join-Path $appRoot 'src\ActivityReview.ps1')
. (Join-Path $appRoot 'src\AccessMode.ps1')
. (Join-Path $appRoot 'src\PermissionMode.ps1')
. (Join-Path $appRoot 'src\ProgramCatalog.ps1')
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$testExe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
[Netzblick.SetupClient]::Scenario($testExe,0)
Initialize-AccessMode
# Exercise review actions against UI fixtures only. FakeSetupClient rejects
# mutations operate only on in-memory fixture configuration, never native filters.
. (Join-Path $appRoot 'src\UserModes.ps1')
. (Join-Path $appRoot 'src\ReviewMode.ps1')
$script:SmokeTest=$true;$script:policyReady=$true;$script:notifyObserved=$false
$script:knownPrograms=@{};$script:newPrograms=@{};$script:trafficSamples=@{};$script:trafficPeers=@([pscustomobject]@{Path=$testExe;Protocol='TCPv4';Address='8.8.8.8';Port=443})
$script:rows=@();$script:ownRules=@();$script:userBaseline=$true;$script:sessionStartedUtc=[datetime]::UtcNow
$script:events=New-Object 'System.Collections.Generic.List[object]'
$script:trafficProblem='';$script:traffic=$null;$script:changes=New-Object 'System.Collections.Generic.List[object]'
$script:userStateDirectory=Join-Path $env:TEMP ('NetzblickReview-'+[guid]::NewGuid().ToString('N'));$script:userStateFile=Join-Path $userStateDirectory 'user-state.json'
function Add-Event($kind,$program,$detail){}
function Show-NetzblickWindow {}
function Show-Panel($name){$script:lastPanel=$name}
function Refresh-Detail {}
. (Join-Path $appRoot 'src\EndpointNames.ps1')
Initialize-BlockDetails
$script:allProgramItems=@([pscustomobject]@{Key=[Netzblick.ProcessLineage]::Normalize($testExe);Path=$testExe;Name='Neue Test-App';Rows=@()})
$ui.Programs.ItemsSource=$allProgramItems
Initialize-ReviewMode
Initialize-WorkspaceMode
Initialize-DirectionMode
Initialize-ExperienceState
Initialize-WorkflowMode
Track-ObservedPrograms $allProgramItems
Refresh-Overview
if($newPrograms.Count -ne 1 -or $ui.FutureReviewCount.Text -ne '1' -or $ui.OverviewPrograms.Items[0].ReviewReason -notmatch 'Neues Programm' -or (Get-ReviewTargets $testExe) -notmatch '8.8.8.8'){throw 'Einheitliche Prüfliste oder Gegenstellen fehlen.'}
Show-ReviewProgram $testExe
if($lastPanel -ne 'LivePanel' -or $ui.Programs.SelectedItem.Path -ne $testExe){throw 'Anzeigen öffnet nicht das ausgewählte Programm.'}
$saved=Get-Content -LiteralPath $userStateFile -Raw | ConvertFrom-Json
if(@($saved.Pending).Count -ne 1 -or $saved.Pending[0].Path -ne $testExe){throw 'Offene Prüfung wurde nicht gespeichert.'}
$rulesBefore=$setupStatus.Config.Rules.Count
Save-ReviewDecision $testExe
if($newPrograms.Count -ne 0 -or $setupStatus.Config.Rules.Count -ne $rulesBefore){throw 'Prüfmarkierung verändert Regeln oder lässt Eintrag stehen.'}
$savedAfter=Get-Content -LiteralPath $userStateFile -Raw | ConvertFrom-Json
if(@($savedAfter.Pending).Count -ne 0 -or $ui.UserNotice.Text -like '*nicht gespeichert*'){throw 'Erneutes Speichern der Prüfliste fehlgeschlagen.'}
# Management must include saved, non-running apps, inspection/global gates,
# independent review state, and refresh selections after atomic changes.
[Netzblick.SetupClient]::Scenario($testExe,0);Update-AccessMode
Set-PermissionProgram $testExe 'BlockProgram'
Refresh-ProgramSignals
if((Get-PermissionStatus $testExe).SignalColor -ne '#B32D40' -or $ui.OverviewPrograms.Items[0].SignalColor -ne '#B32D40'){throw 'Rote Ampel am Programmnamen fehlt.'}
if($ui.PermissionPrograms.Items.Count -ne 1 -or $ui.PermissionPrograms.Items[0].Category -ne 'Blocked'){throw 'Gespeicherte Programmsperre fehlt.'}
$ui.PermissionFilter.SelectedIndex=1
if($ui.PermissionPrograms.Items.Count -ne 1){throw 'Gesperrt-Filter fehlt.'}
Set-PermissionProgram $testExe 'AllowProgram'
if($ui.PermissionPrograms.Items.Count -ne 0){throw 'Erlaubtes Programm bleibt unter Gesperrt.'}
if((Get-PermissionStatus $testExe).SignalColor -ne '#08704E'){throw 'Grüne Freigabeampel fehlt.'}
$ui.PermissionFilter.SelectedIndex=3
if($ui.PermissionPrograms.Items.Count -ne 1 -or $setupStatus.Config.Rules.Count -ne 2){throw 'Atomare Programmfreigabe fehlt.'}
$setupStatus.Config.Ask=$true
Set-PermissionProgram $testExe 'ProgramDefault'
$ui.PermissionFilter.SelectedIndex=0
if($ui.PermissionPrograms.Items[0].Category -ne 'Blocked'){throw 'Standard bei Nachfragen wird fälschlich als erlaubt gemeldet.'}
[Netzblick.SetupClient]::Scenario($testExe,0);Update-AccessMode
$setupStatus.Config.WatchedPaths.Add($testExe);Refresh-Permissions
if($ui.PermissionPrograms.Items[0].Category -ne 'Blocked' -or @($ui.SetupRules.Items | Where-Object Kind -eq 'Watch').Count -ne 1){throw 'Prüfsperre fehlt in Verwaltung.'}
Remove-PermissionEntry ($ui.SetupRules.Items | Where-Object Kind -eq 'Watch' | Select-Object -First 1);Refresh-Permissions
if($setupStatus.Config.WatchedPaths.Count -ne 0){throw 'Prüfsperre kann nicht entfernt werden.'}
$missing='C:\Fixture\NotRunning.exe';[Netzblick.SetupChanges]::BlockProgram($setupStatus.Config,$missing);Refresh-Permissions
if(@($ui.PermissionPrograms.Items | Where-Object Path -eq $missing).Count -ne 1){throw 'Nicht laufende gespeicherte App fehlt.'}
$ui.PermissionSearch.Text='NotRunning';$ui.PermissionPrograms.SelectedIndex=0;Show-PermissionSelection
if($ui.PermissionPrograms.Items.Count -ne 1 -or $ui.PermissionAllow.IsEnabled -or -not $ui.PermissionDefault.IsEnabled){throw 'Suche oder Bereinigung nicht vorhandener App fehlerhaft.'}
Set-PermissionProgram $missing 'ProgramDefault'
$ui.PermissionSearch.Text=''
[Netzblick.SetupClient]::Scenario($testExe,3);Update-AccessMode
if($ui.PermissionPrograms.Items[0].Category -ne 'Unknown' -or $ui.PermissionAllow.IsEnabled -or $ui.PermissionDefault.IsEnabled){throw 'Unbestätigter Dienst erlaubt Änderungen oder meldet Sperrwirkung.'}
if((Get-PermissionStatus $testExe).SignalColor -ne '#57677B'){throw 'Unbestätigte Ampel ist nicht grau.'}
[Netzblick.SetupClient]::Scenario($testExe,0);Update-AccessMode
if((Get-PermissionStatus $testExe).SignalColor -ne '#08704E'){throw 'Beobachten-Standard ist nicht grün.'}
Write-Output 'PASS: Sperren/Freigaben-Filter, atomare Programmfreigabe, Standard im Nachfragemodus, Prüfsperre, beendete Apps, Suche und unbestätigter Status.'
# Reproduce: reviewed and blocked EXE, no socket and no sent bytes. A saved
# policy keeps it visible; actual 5157 evidence adds counts/targets independently.
$catalogStatus=[Netzblick.SetupStatus]@{Ok=$true;Verified=$true;Config=(New-Object Netzblick.SetupConfig);Attempts=(New-Object 'System.Collections.Generic.List[Netzblick.SetupAttempt]')}
[Netzblick.SetupChanges]::BlockProgram($catalogStatus.Config,$testExe)
$catalog=@(Get-ProgramCatalog @() @() @() $catalogStatus @())
if($catalog.Count -ne 1 -or $catalog[0].Observed -or $catalog[0].Rows.Count -or $catalog[0].BlockCount){throw 'Gespeicherte Sperre verschwindet ohne Socket oder erfindet einen Versuch.'}
$a=[Netzblick.SetupAttempt]@{FilterId=101;BlockReason='Netzblick-Regel: Fixture-Sperre';Key='blocked-only';Path=$testExe;Program='BlockedOnly.exe';Direction='Ausgehend';Address='1.1.1.1';Protocol=6;Port=443;Count=3;OwnBlock=$true;LastUtc=[datetime]::UtcNow;FirstUtc=[datetime]::UtcNow}
$catalogStatus.Attempts.Add($a)
$b=[Netzblick.SetupAttempt]@{FilterId=102;BlockReason='Windows-Netzwerkfilter: Fixture-Fremdfilter';Key='second-target';Path=$testExe.ToUpperInvariant();Program='BlockedOnly.exe';Direction='Ausgehend';Address='8.8.8.8';Protocol=17;Port=53;Count=2;OwnBlock=$true;LastUtc=[datetime]::UtcNow;FirstUtc=[datetime]::UtcNow}
$catalogStatus.Attempts.Add($b)
$catalog=@(Get-ProgramCatalog @() @() @() $catalogStatus @())
if($catalog.Count -ne 1 -or $catalog[0].BlockCount -ne 5 -or -not $catalog[0].Observed -or $catalog[0].BlockSummary -notlike '5 blockierte Versuche*'){throw 'Blockversuche ohne Socket fehlen oder doppelte Programmpfade.'}
$blockRows=@(Get-ProgramBlockRows $testExe $catalogStatus)
if($blockRows.Count -ne 2 -or $blockRows[0].State -notlike '*3 Versuche*' -or $blockRows[0].Remote -notlike '*1.1.1.1*'){throw 'Blockierte Ziele/Zähler fehlen in den Programmdetails.'}
$ui.Connections.ItemsSource=$blockRows;$ui.Connections.SelectedIndex=0;Show-ConnectionDetails
if($ui.BlockReasonText.Text -notlike '*Fixture-Sperre*' -or $ui.BlockReasonText.Text -notlike '*1.1.1.1*'){throw 'Sperrgrund/Ziel nicht direkt sichtbar.'}
$ui.Connections.SelectedIndex=1;Show-ConnectionDetails
if($ui.BlockReasonText.Text -notlike '*Fixture-Fremdfilter*'){throw 'Fremder Sperrgrund nicht sichtbar.'}
# Feed the actual Activity/Programs data bindings with only block evidence.
$script:setupStatus=$catalogStatus;$script:allProgramItems=$catalog;$ui.Programs.ItemsSource=$catalog;Refresh-Overview;Refresh-ProgramSignals
# Execute the production detail renderer, not the fixture's earlier stub.
$parseTokens=$null;$parseErrors=$null
$appAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $appRoot 'Netzblick.ps1'),[ref]$parseTokens,[ref]$parseErrors)
$detailFunction=$appAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Refresh-Detail'},$true)
if(-not $detailFunction -or $parseErrors.Count){throw 'Produktive Programmdetailfunktion konnte nicht geladen werden.'}
Invoke-Expression $detailFunction.Extent.Text
function Draw-Map($program,$displayRows){}
Open-ProgramBlocks $testExe
if($ui.Connections.Items.Count -ne 2 -or @($ui.Connections.Items | Where-Object {-not $_.IsBlock}).Count -or $ui.BlockReasonText.Text -notmatch 'Fixture-(Sperre|Fremdfilter)'){throw ('Produktive Detailansicht: Zeilen='+$ui.Connections.Items.Count+'; Auswahl='+$ui.Connections.SelectedItem.BlockReason+'; Detail='+$ui.BlockReasonText.Text)}
if(-not $ui.OnlyProgramBlocks.IsChecked -or $ui.ProgramDetailTabs.SelectedIndex -ne 1 -or $lastPanel -ne 'LivePanel'){throw 'Direkter Blockversuch-Weg öffnet nicht den Programmfilter.'}
$ui.OnlyProgramBlocks.IsChecked=$false
if($ui.Programs.Items.Count -ne 1 -or $ui.OverviewPrograms.Items.Count -ne 1 -or $ui.OverviewPrograms.Items[0].BlockSummary -notlike '5 blockierte Versuche*' -or $ui.OverviewPrograms.Items[0].SignalColor -ne '#B32D40'){throw 'Gesperrte App mit Versuchen fehlt in Aktivität/Programme.'}
$catalogStatus.Config.Rules.Clear()
Refresh-Detail
if($ui.ProgramExplanation.Text -notlike '*Standardmodus*' -or $ui.ProgramBlockHint.Text -notlike '*Windows-Standard*' -or @($ui.Connections.Items | Where-Object IsBlock).Count -ne 2){throw 'Freigabe und historische Sperrgründe werden nicht getrennt angezeigt.'}
function Refresh-Detail {}
$catalog=@(Get-ProgramCatalog @() @() @() $catalogStatus @())
if($catalog.Count -ne 1 -or $catalog[0].BlockCount -ne 5){throw 'Freigabe entfernt historische Blockversuche.'}
$catalogStatus.Attempts.Clear()
if(@(Get-ProgramCatalog @() @() @() $catalogStatus @()).Count){throw 'Leere Quellen erzeugen ein Phantomprogramm.'}
[Netzblick.SetupClient]::Scenario($testExe,0);Update-AccessMode
$script:allProgramItems=@([pscustomobject]@{Key=[Netzblick.ProcessLineage]::Normalize($testExe);Path=$testExe;Name='Neue Test-App';Rows=@()})
$ui.Programs.ItemsSource=$allProgramItems
Write-Output 'PASS: gespeicherte gesperrte App und echte Blockereignis-Fixtures ohne Socket in Aktivität/Programme; Ziel, Anzahl, Zeitpunkt, keine erfundenen Verbindungen.'
# Central-list filtering and saved theme preference are separate from policy.
Save-ReviewDecision $testExe
$ui.OverviewFilter.SelectedIndex=2;Refresh-Overview
if($ui.OverviewPrograms.Items.Count){throw 'Zu-prüfen-Filter enthält bereits geprüfte App.'}
$ui.OverviewFilter.SelectedIndex=0;$ui.OverviewSearch.Text='does-not-exist';Refresh-Overview
if($ui.OverviewPrograms.Items.Count -or $ui.ProgramListEmpty.Text -notlike '*Keine Programme*'){throw 'Zentrale Suche/Leerzustand fehlt.'}
$ui.OverviewSearch.Text='';Refresh-Overview
Initialize-Theme
$ui.ThemeToggle.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
$savedTheme=Get-Content -LiteralPath $userStateFile -Raw | ConvertFrom-Json
if(-not $darkMode -or -not $savedTheme.DarkMode -or $window.Resources['Text'].Color.ToString() -ne '#FFE8EFF8' -or (Get-PermissionStatus $testExe).SignalColor -ne '#70DCB4'){throw 'Dark Mode oder gespeicherte Einstellung fehlerhaft.'}
Set-NetzblickTheme $false;Save-UserState
if($window.Resources['Text'].Color.ToString() -ne '#FF19283C'){throw 'Helles Design lässt sich nicht wiederherstellen.'}
Write-Output 'PASS: zentrale Filter/Suche, gespeicherter Dark Mode, kontrastreiche Ampel und Rückkehr zu Hell.'
# Exercise production navigation, including changing the theme after navigating.
$panelFunction=$appAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Show-Panel'},$true)
Invoke-Expression ($panelFunction.Extent.Text.Replace('function Show-Panel','function Show-RealPanel'))
function Get-TestLuminance($c){
 $channels=@($c.R,$c.G,$c.B) | ForEach-Object {$n=[double]$_/255;if($n -le 0.04045){$n/12.92}else{[math]::Pow(($n+0.055)/1.055,2.4)}}
 return 0.2126*$channels[0]+0.7152*$channels[1]+0.0722*$channels[2]
}
foreach($panel in @('DashboardPanel','OverviewPanel','AccessPanel','InspectionPanel','UpdatesPanel','LivePanel')){
 Show-RealPanel $panel
 foreach($dark in @($true,$false,$true,$false)){
  Set-NetzblickTheme $dark
  foreach($name in @('OverviewTab','AccessTab','InspectionTab','UpdatesTab','OpenSetupRules','OpenSetupHistory')){
   $button=$ui[$name];$bg=Get-TestLuminance $button.Background.Color;$fg=Get-TestLuminance $button.Foreground.Color
   if(([math]::Max($bg,$fg)+0.05)/([math]::Min($bg,$fg)+0.05) -lt 4.5){throw ('Navigation nach Themewechsel nicht lesbar: '+$name)}
  }
 }
}
$pauseDialog=New-TemporaryBlockDialog $testExe
if($pauseDialog.FindName('Duration').Items.Count -ne 4 -or $pauseDialog.FindName('Duration').SelectedItem.Tag -ne '10' -or $pauseDialog.FindName('Duration').Items[3].Tag -ne '0' -or $pauseDialog.FindName('PathLabel').Text -ne $testExe){throw 'Auswahl der zeitweisen Sperrdauer fehlt oder falsches Programm.'}
$pauseDialog.Close()
Write-Output 'PASS: produktive Navigation und mehrfacher Hell-/Dunkelwechsel behalten lesbaren Kontrast; Sperrdialog hat Dauer und eindeutigen Programmpfad.'
# Review baseline distinguishes old denials from new attempts without changing policy.
$script:targetLedger=@{};$script:blockBaselines=@{};$script:trafficPeers=@()
[Netzblick.SetupClient]::Scenario($testExe,0);Update-AccessMode
$attempt=[Netzblick.SetupAttempt]@{Key='review-one';Path=$testExe;Program='Test';Direction='Ausgehend';Address='1.1.1.1';Protocol=6;Port=443;Count=3;FirstUtc=[datetime]::UtcNow;LastUtc=[datetime]::UtcNow}
$setupStatus.Attempts.Add($attempt);Update-ActivityLedger
if((Get-ProgramActivityReview $testExe).NewTargets -ne 1 -or (Get-ProgramActivityReview $testExe).NewBlocks -ne 3){throw 'Neue Ziele oder ungeprüfte Blockversuche fehlen.'}
Save-ReviewDecision $testExe
if((Get-ProgramActivityReview $testExe).NewTargets -or (Get-ProgramActivityReview $testExe).NewBlocks){throw 'Prüfmarke lässt alte Ereignisse neu erscheinen.'}
$attempt.Count=5
if((Get-ProgramActivityReview $testExe).NewBlocks -ne 2 -or (Get-TargetReviewLabel $testExe $attempt)){throw 'Wiederholter Versuch wird als neues Ziel statt neuem Versuch angezeigt.'}
$other=[Netzblick.SetupAttempt]@{Key='review-two';Path=$testExe;Address='8.8.8.8';Protocol=17;Port=53;Count=1;FirstUtc=[datetime]::UtcNow;LastUtc=[datetime]::UtcNow}
$setupStatus.Attempts.Add($other);Update-ActivityLedger
if((Get-ProgramActivityReview $testExe).NewTargets -ne 1 -or (Get-TargetReviewLabel $testExe $other) -ne 'Neues Ziel'){throw 'Neues Ziel nach Prüfung nicht hervorgehoben.'}
Refresh-Overview;$ui.OverviewFilter.SelectedIndex=2;Refresh-Overview
if($ui.OverviewPrograms.Items.Count -ne 1){throw 'Bekanntes Programm mit neuem Ziel fehlt unter Zu prüfen.'}
$ui.OverviewFilter.SelectedIndex=0;Refresh-Overview
Save-UserState
$activityState=Get-Content -LiteralPath $userStateFile -Raw | ConvertFrom-Json
if(@($activityState.Targets).Count -ne 2 -or @($activityState.BlockBaselines).Count -ne 1){throw 'Prüfmarken nicht gespeichert.'}
$ui.Programs.SelectedIndex=0;$ui.OverviewPrograms.SelectedIndex=0
Initialize-QuickActions
Set-PermissionProgram $testExe 'BlockProgram'
$blockedBefore=[Netzblick.SetupChanges]::CaptureProgram($setupStatus.Config,$testExe)
Set-PermissionProgram $testExe 'TemporaryAllowProgram'
if(-not $ui.OverviewQuickBlock.IsEnabled -or $ui.ProgramQuickTemporary.IsEnabled -or -not $ui.ProgramQuickUndo.IsEnabled){throw 'Direkte Aktionen berücksichtigen zeitweise Freigabe nicht.'}
$ui.ProgramQuickUndo.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
if(-not [Netzblick.SetupChanges]::SameProgram($blockedBefore,[Netzblick.SetupChanges]::CaptureProgram($setupStatus.Config,$testExe))){throw 'Direktes Rückgängig stellt Programmsperre nicht wieder her.'}
$historyCount=$changes.Count;Set-PermissionProgram $testExe 'AllowProgram'
$change=$changes[0]
Set-PermissionProgram $testExe 'BlockProgram'
try{Undo-ProgramChange $change;throw 'Veraltetes Rückgängig akzeptiert.'}catch{if($_.Exception.GetBaseException().Message -notlike '*inzwischen geändert*'){throw}}
if((Get-PermissionStatus $testExe).Category -ne 'Blocked'){throw 'Veraltetes Rückgängig verändert Zugriff.'}
Set-PermissionProgram $testExe 'AllowProgram'
$online=[Netzblick.SetupChanges]::CaptureProgram($setupStatus.Config,$testExe)
foreach($minutes in @(30,0)){
 Set-PermissionProgram $testExe 'TemporaryBlockProgram' $minutes
 if((Get-PermissionStatus $testExe).Category -ne 'Blocked' -or $ui.ProgramQuickEndTemporary.Visibility -ne 'Visible' -or -not $ui.ProgramQuickEndTemporary.IsEnabled -or $ui.ProgramQuickTempBlock.IsEnabled){throw 'Zeitweise Sperre oder Beenden-Aktion fehlt.'}
 Set-PermissionProgram $testExe 'EndProgramLease'
 if(-not [Netzblick.SetupChanges]::SameProgram($online,[Netzblick.SetupChanges]::CaptureProgram($setupStatus.Config,$testExe)) -or $ui.ProgramQuickEndTemporary.Visibility -ne 'Collapsed'){throw 'Zeitweise Sperre beenden stellt frühere Freigabe nicht wieder her.'}
}
Write-Output 'PASS: direkte Programm-Aktionen, gespeichertes Rückgängig, neue Ziele und getrennte Wiederholungszähler.'
[Netzblick.SetupClient]::Scenario($testExe,0);Update-AccessMode
# Retain a fixture entry for the activity rendering.
$entry=[pscustomobject]@{Key=[Netzblick.ProcessLineage]::Normalize($testExe);Path=$testExe;Name='Neue Test-App';FirstUtc=[datetime]::UtcNow}
$newPrograms[$entry.Key]=$entry;Refresh-Overview
Write-Output 'PASS: neue App, Gegenstellen, direkter Anzeigenweg, gespeicherte Prüfliste und Markierung ohne Filteränderung.'
# Reproduce a single real SocketRow plus ETW peer when switching maps.
. (Join-Path $appRoot 'src\VisualModes.ps1')
. (Join-Path $appRoot 'src\WorldNavigation.ps1')
. (Join-Path $appRoot 'src\InspectionMode.ps1')
. (Join-Path $appRoot 'src\SessionMode.ps1')
$script:Portable=$true
Initialize-VisualModes
$socket=New-Object Netzblick.SocketRow;$socket.Path=$testExe;$socket.Program='Neue Test-App';$socket.Protocol='TCPv4';$socket.Address='8.8.8.8';$socket.Remote='8.8.8.8:443';$socket.Local='127.0.0.1:50000';$socket.State='Verbunden'
$script:rows=@($socket)
$single=[pscustomobject]@{Key=[Netzblick.ProcessLineage]::Normalize($testExe);Path=$testExe;Name='Ein Socket';Rows=@($socket)}
$empty=[pscustomobject]@{Key='EMPTY';Path='C:\Fixture\empty.exe';Name='Keine Sockets';Rows=@()}
$script:allProgramItems=@($single,$empty)
Refresh-World -Rebuild
foreach($selection in @($single.Key,'EMPTY','*',$single.Key)){
 $ui.WorldPrograms.SelectedItem=$ui.WorldPrograms.Items | Where-Object {$_.Key -eq $selection} | Select-Object -First 1
 Refresh-World
 if($ui.WorldSummary.Text -like '*konnte nicht*'){throw ('Kartenwechsel fehlgeschlagen: '+$ui.WorldSummary.Text)}
}
if($ui.WorldPeers.Items.Count -lt 1){throw 'Einzel-Socket/ETW-Gegenstelle fehlt auf der Karte.'}
Zoom-World 120 500 250
if($worldScale -le 1 -or $ui.WorldMap.RenderTransform.Matrix.M11 -le 1){throw ('Mausrad-Zoom verändert die Karte nicht: Scale='+$worldScale+'; Matrix='+$ui.WorldMap.RenderTransform.Matrix)}
Zoom-World 12000 500 250
if($worldScale -ne 8){throw 'Zoom-Obergrenze fehlt.'}
Set-WorldTransform 2 -99999 99999
if($worldOffsetX -ne -1000 -or $worldOffsetY -ne 0){throw 'Kartengrenzen beim Verschieben falsch.'}
Set-WorldTransform 1 0 0
if(-not $ui.WorldMap.RenderTransform.Matrix.IsIdentity){throw 'Zoom zurücksetzen nicht identisch.'}
# The inspection button must be enabled only with metadata and verified filters.
Initialize-InspectionMode
[Netzblick.SetupClient]::Scenario($testExe,0);$script:setupStatus=[Netzblick.SetupClient]::Send([Netzblick.SetupCommand]@{Operation='Status'})
$inspectionFixture=Join-Path $userStateDirectory 'NotRunningFixture.exe'
Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\where.exe') -Destination $inspectionFixture
Select-InspectionPath $inspectionFixture
$clock=[Diagnostics.Stopwatch]::StartNew()
while($inspectionMetadataTask -and -not $inspectionMetadataTask.IsCompleted -and $clock.ElapsedMilliseconds -lt 5000){Start-Sleep -Milliseconds 40}
Update-Inspection
if(-not $ui.StartInspection.IsEnabled){throw ('Gesunde Prüfsperre bleibt deaktiviert: '+$ui.InspectionBlockReason.Text)}
Start-Inspection
if(-not $inspectionActive -or -not($setupStatus.Config.WatchedPaths -contains $inspectionPath)){throw 'Prüfsperre wurde nicht angefordert.'}
Stop-Inspection
[Netzblick.SetupClient]::Scenario($testExe,3);$script:setupStatus=[Netzblick.SetupClient]::Send([Netzblick.SetupCommand]@{Operation='Status'});Update-Inspection
if($ui.StartInspection.IsEnabled -or $ui.InspectionBlockReason.Text -notlike '*Filterprüfung fehlgeschlagen*'){throw 'Unbestätigte Filter werden nicht erklärt oder erlauben Prüfstart.'}
[Netzblick.SetupClient]::Scenario($testExe,0);Retry-InspectionControl
if(-not $ui.StartInspection.IsEnabled){throw 'Erneute Dienstprüfung aktiviert gesunden Prüfstart nicht.'}
# Reset all review decisions, without native filters in this fixture.
function Refresh-Rules {$script:ruleError='';$script:ownRules=@()}
function Refresh-Programs {Track-ObservedPrograms $script:allProgramItems;Refresh-Overview}
$script:events=New-Object 'System.Collections.Generic.List[object]';$events.Add([pscustomobject]@{Event='alt'})
$script:seen=New-Object 'System.Collections.Generic.HashSet[string]';[void]$seen.Add('alt')
$changes.Add([pscustomobject]@{Path=$testExe})
Reset-NetzblickState
if($setupStatus.Config.Ask -or $setupStatus.Config.Rules.Count -or $setupStatus.Config.WatchedPaths.Count -or $changes.Count -or $events.Count){throw 'Zurücksetzen lässt Regeln oder Entscheidungen stehen.'}
if($newPrograms.Count -ne $allProgramItems.Count){throw 'Zurücksetzen prüft laufende Programme nicht erneut.'}
if(@(Get-ChildItem -LiteralPath $userStateDirectory -Filter 'reset-*.json').Count -lt 1){throw 'Zurücksetzen hat keine Sicherung erzeugt.'}
$script:trafficProblem='';Refresh-Overview
Write-Output 'PASS: Einzel-Socket-Kartenwechsel, Zoom/Pan-Grenzen, Prüfsperre bei bestätigtem Dienst, erklärter Sperrgrund, erneute Prüfung und frischer Reset.'
# Design choice is independent of brightness, selection and firewall permissions.
$script:activePanel='OverviewPanel';$script:designStyle='Clean'
Initialize-DesignMode
$ui.Programs.ItemsSource=$allProgramItems
Invoke-Expression $detailFunction.Extent.Text
function Draw-Map($program,$displayRows){Draw-FutureProgramMap $program $displayRows}
$serializer=New-Object System.Web.Script.Serialization.JavaScriptSerializer
$configurationBefore=$serializer.Serialize($setupStatus.Config)
foreach($design in @('Future','Clean','Future','Clean')){
 Set-DesignStyle $design
 foreach($dark in @($true,$false)){
  Set-NetzblickTheme $dark;Refresh-Overview;Refresh-Detail
  if($serializer.Serialize($setupStatus.Config) -ne $configurationBefore){throw 'Designwechsel ändert Firewallregeln.'}
  foreach($name in @('OverviewTab','AccessTab','InspectionTab','UpdatesTab','OpenSetupRules','OpenSetupHistory')){
   $button=$ui[$name];$bg=Get-TestLuminance $button.Background.Color;$fg=Get-TestLuminance $button.Foreground.Color
   if(([math]::Max($bg,$fg)+0.05)/([math]::Min($bg,$fg)+0.05) -lt 4.5){throw ('Design-Kontrast zu niedrig: '+$design+' / '+$name)}
  }
  if($design -eq 'Future' -and ($ui.OverviewPanel.Visibility -ne 'Visible' -or $ui.LivePanel.Visibility -ne 'Visible' -or $ui.WorkspaceSplitter.Visibility -ne 'Visible')){throw 'Future zeigt Liste und Details nicht nebeneinander.'}
  if($design -eq 'Clean' -and $ui.LivePanel.Visibility -ne 'Collapsed'){throw 'Clean erhält keine eigene Programmübersicht.'}
 }
}
Set-DesignStyle 'Future';$ui.OverviewPrograms.SelectedIndex=0;Sync-FutureProgramSelection
if($ui.Programs.SelectedItem.Key -ne $ui.OverviewPrograms.SelectedItem.Key){throw 'Future-Programmwechsel zeigt falsche App.'}
$ui.ExpandProgramDetails.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
if($ui.OverviewFrame.Visibility -ne 'Collapsed' -or $ui.LivePanel.Visibility -ne 'Visible'){throw 'Future-Details können nicht vergrößert werden.'}
$ui.ExpandProgramDetails.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
if($ui.OverviewFrame.Visibility -ne 'Visible'){throw 'Future kehrt nicht zur geteilten Ansicht zurück.'}
$ui.OverviewSearch.Text='does-not-exist';Refresh-Overview
if($ui.Programs.SelectedItem -or $ui.ProgramTitle.Text -ne 'Programm auswählen'){throw 'Leere Future-Suche zeigt ein anderes Programm weiter an.'}
$ui.OverviewSearch.Text='';Refresh-Overview
Save-UserState;$savedDesign=Get-Content -LiteralPath $userStateFile -Raw | ConvertFrom-Json
if($savedDesign.DesignStyle -ne 'Future' -or $savedDesign.DarkMode){throw 'Design und Helligkeit werden nicht unabhängig gespeichert.'}
$ui.DesignSelector.SelectedIndex=0
if($script:designStyle -ne 'Clean'){throw 'Designauswahl wechselt nicht zu Clean.'}
Write-Output 'PASS: Clean/Future plus Hell/Dunkel, sichere Auswahl, geteilte/vergrößerte Details, Leerzustand und gespeicherte unabhängige Auswahl ohne Regeländerung.'

if((Get-StartupDesignStyle $null) -ne 'Future' -or (Get-StartupDesignStyle 'invalid') -ne 'Future' -or (Get-StartupDesignStyle 'Clean') -ne 'Clean'){throw 'Future-Standard überschreibt gespeichertes Clean oder fehlt.'}
# Reproduce the screenshot: no new program, but an existing app has an unreviewed target.
[Netzblick.SetupClient]::Scenario($testExe,0);Update-AccessMode
$script:newPrograms=@{};$script:targetLedger=@{};$script:blockBaselines=@{};$script:targetReviewCounts=$null
$script:rows=@();$script:trafficSamples=@{}
$script:trafficPeers=@([pscustomobject]@{Path=$testExe;Protocol='TCPv4';Address='8.8.8.8';Port=443})
$blockedPath='C:\Beispiel\Gesperrt.exe';$newPath='C:\Beispiel\Neue-App.exe'
[Netzblick.SetupChanges]::BlockProgram($setupStatus.Config,$blockedPath)
$script:allProgramItems=@(
 [pscustomobject]@{Key=[Netzblick.ProcessLineage]::Normalize($testExe);Path=$testExe;Name='Bekannte App';Rows=@()},
 [pscustomobject]@{Key=[Netzblick.ProcessLineage]::Normalize($blockedPath);Path=$blockedPath;Name='Gesperrte App';Rows=@()},
 [pscustomobject]@{Key=[Netzblick.ProcessLineage]::Normalize($newPath);Path=$newPath;Name='Neue App';Rows=@()}
)
$ui.Programs.ItemsSource=$allProgramItems
Set-DesignStyle 'Future';Set-NetzblickTheme $false;Refresh-Overview
$beforeReviewConfig=$serializer.Serialize($setupStatus.Config)
$ui.OverviewSearch.Text='does-not-exist';$ui.ReviewOptions.IsExpanded=$true
$ui.FutureReviewFilter.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
if($ui.OverviewFilter.SelectedIndex -ne 2 -or $ui.OverviewSearch.Text -or $ui.ReviewOptions.IsExpanded -or $ui.OverviewPrograms.Items.Count -ne 1 -or $ui.FutureReviewCount.Text -ne '1' -or $ui.OverviewNew.Text -ne '1 Programm zu prüfen' -or $ui.NewProgramsNotice.Text -like '*leer*'){throw 'Kartenfilter/Prüfzähler widersprüchlich bei neuer Gegenstelle einer bekannten App.'}
if($ui.OverviewPrograms.SelectedItem.ReviewReason -ne '1 neues Ziel' -or $ui.ReviewListActions.Visibility -ne 'Visible'){throw 'Prüfgrund oder direkte Prüfaktionen fehlen.'}
$ui.OverviewReviewDetails.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
if($ui.ProgramDetailTabs.SelectedIndex -ne 1 -or -not $ui.OnlyProgramUnreviewed.IsChecked -or $ui.OnlyProgramBlocks.IsChecked -or $ui.Connections.Items.Count -ne 1 -or $ui.Connections.Items[0].TargetReview -ne 'Neues Ziel'){throw 'Prüfdetails führen nicht zur neuen Gegenstelle.'}
$ui.OverviewReviewDone.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
if($ui.FutureReviewCount.Text -ne '0' -or $ui.OverviewPrograms.Items.Count -ne 0 -or $ui.OverviewNew.Text -ne 'Alles geprüft'){throw 'Geprüfte Gegenstelle verbleibt in der Prüfliste.'}
$ui.FutureBlockedFilter.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
if($ui.OverviewFilter.SelectedIndex -ne 1 -or $ui.OverviewPrograms.Items.Count -ne 1 -or $ui.OverviewPrograms.Items[0].Path -ne $blockedPath){throw 'Gesperrt-Karte zeigt falsche Programme.'}
$ui.FutureAllFilter.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
if($ui.OverviewFilter.SelectedIndex -ne 0 -or $ui.OverviewPrograms.Items.Count -ne 3 -or $serializer.Serialize($setupStatus.Config) -ne $beforeReviewConfig){throw 'Alle-Karte oder Filter/Prüfmarke verändert Firewallkonfiguration.'}
# Persisted unreviewed targets keep an inactive app visible without inventing sockets.
$script:trafficPeers=@([pscustomobject]@{Path=$testExe;Protocol='TCPv4';Address='1.1.1.1';Port=443});Update-ActivityLedger
$historical=@(Get-ProgramCatalog @() @() @(Get-ReviewCatalogEntries) $null @())
if($historical.Count -ne 1 -or $historical[0].Rows.Count -ne 0 -or $historical[0].Observed -or $historical[0].Summary -notlike 'Früher beobachtet*'){throw 'Gespeicherte offene Prüfung einer beendeten App fehlt oder erfindet Aktivität.'}
$attempt=New-Object Netzblick.SetupAttempt;$attempt.Key='review-repeat';$attempt.Path=$testExe;$attempt.Address='8.8.8.8';$attempt.Protocol=6;$attempt.Port=443;$attempt.Count=3;$attempt.FirstUtc=[datetime]::UtcNow;$attempt.LastUtc=[datetime]::UtcNow
$setupStatus.Attempts.Add($attempt)
Mark-ProgramActivityReviewed $testExe
$attempt.Count=5
$blockRow=Get-ProgramBlockRows $testExe $setupStatus | Select-Object -First 1
if((Get-TargetReviewLabel $testExe $blockRow) -ne 'Neue Blockversuche' -or (Get-ProgramReviewState $testExe).Reason -ne '2 neue Blockversuche'){throw 'Neue Versuche eines bereits geprüften Ziels fehlen als Prüfgrund.'}
$ui.Programs.SelectedItem=$allProgramItems[0];$ui.OnlyProgramUnreviewed.IsChecked=$true;Refresh-Detail
if($ui.Connections.Items.Count -ne 1 -or -not $ui.Connections.Items[0].IsBlock){throw 'Ungeprüft-Filter verschluckt wiederholte Blockversuche.'}
$ui.OnlyProgramUnreviewed.IsChecked=$false
$script:newPrograms[[Netzblick.ProcessLineage]::Normalize($newPath)]=[pscustomobject]@{Key=[Netzblick.ProcessLineage]::Normalize($newPath);Name='Neue App';Path=$newPath;FirstUtc=[datetime]::UtcNow}
Refresh-Overview
if($ui.FutureReviewCount.Text -ne '2'){throw 'Neue Programme und neue Blockversuche sind nicht in einer gemeinsamen Prüfliste.'}
$ui.ReviewShow.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
if($ui.OverviewPrograms.Items.Count -ne 2 -or $ui.OverviewFilter.SelectedIndex -ne 2){throw 'Prüfliste-Knopf zeigt nicht alle offenen Prüfgründe.'}
Write-Output 'PASS: Future-Standard, anklickbare Zähler, gemeinsame Prüfliste für Programme/Ziele/Blockversuche, historische Prüfungen und Detailfilter ohne Regeländerung.'


$rateFunction=$appAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Format-Rate'},$true)
Invoke-Expression $rateFunction.Extent.Text
# Real dashboard widgets, measured-rate history and truthful initiation directions.
[Netzblick.SetupClient]::Scenario($testExe,0);Update-AccessMode
$script:newPrograms=@{};$script:targetLedger=@{};$script:targetReviewCounts=$null;$script:blockBaselines=@{};$script:trafficPeers=@();$script:trafficProblem=''
$start=[datetime]::UtcNow.AddMinutes(-2);$script:connectionDirectionIndex=@{}
$flowStore=New-Object Netzblick.Capture.FlowStore
$fixtureRows=@();$script:trafficSamples=@{}
$fixturePaths=@($testExe,(Join-Path $env:SystemRoot 'System32\cmd.exe'),(Join-Path $env:SystemRoot 'System32\notepad.exe'),'C:\Beispiel\Musik.exe','C:\Beispiel\Chat.exe')
$fixtureNames=@('Browser','Lokaler Server','Unbekannter Aufbau','Musik','Chat')
for($i=0;$i -lt 5;$i++){
 $path=$fixturePaths[$i];$pidValue=7100+$i;$localPort=50000+$i;$remote='203.0.113.'+(10+$i);$remotePort=443
 if($i -eq 1){$localPort=8443;$remote='10.0.0.15';$remotePort=53000}
 $row=[Netzblick.SocketRow]@{Pid=$pidValue;ProcessStartUtc=$start;Path=$path;Program=$fixtureNames[$i];Protocol='TCPv4';Local=('192.0.2.5:'+$localPort);Remote=($remote+':'+$remotePort);Address=$remote;Port=$remotePort;State='Verbunden'}
 $fixtureRows+=@($row)
 if($i -ne 2){$identity=[Netzblick.Capture.ProcessIdentity]@{Pid=$pidValue;Path=$path;Name=$fixtureNames[$i];StartUtc=$start};$flowStore.Observe($identity,[datetime]::UtcNow,'TCPv4','192.0.2.5',$localPort,$remote,$remotePort,($i -eq 1),$false)}
 $key=[Netzblick.ProcessLineage]::Normalize($path);$script:trafficSamples[$key]=[pscustomobject]@{Key=$key;Path=$path;Name=$fixtureNames[$i];ReceivedRate=(8200000/($i+1));SentRate=(240000/($i+1));Received=82000000;Sent=2400000;RateReady=$true;LastUtc=[datetime]::UtcNow}
}
foreach($flow in $flowStore.Snapshot()){$script:connectionDirectionIndex[$flow.Key]=$flow.Direction}
if((Get-ConnectionDirection $fixtureRows[0] $fixturePaths[0]).Label -ne 'Ausgehend' -or (Get-ConnectionDirection $fixtureRows[1] $fixturePaths[1]).Label -ne 'Eingehend' -or (Get-ConnectionDirection $fixtureRows[2] $fixturePaths[2]).Label -ne 'Unbekannt'){throw 'TCP-Rollen verwechselt oder Port-Heuristik für unbekannten Aufbau.'}
$udp=[Netzblick.SocketRow]@{Path=$testExe;Pid=7100;Protocol='UDPv4';Local='0.0.0.0:12345';State='UDP-Endpunkt'}
$listen=[Netzblick.SocketRow]@{Path=$testExe;Pid=7100;Protocol='TCPv4';Local='0.0.0.0:443';State='Lauscht'}
if((Get-ConnectionDirection $udp $testExe).Label -ne 'Unbekannt' -or (Get-ConnectionDirection $listen $testExe).Label -ne 'Lauschend'){throw 'UDP oder lauschender Socket wird als eingehende Verbindung erfunden.'}
$script:rows=$fixtureRows
$attempt=[Netzblick.SetupAttempt]@{Key='dashboard-block';Path=$testExe;Program='Browser';Direction='Ausgehend';Address='198.51.100.50';Protocol=6;Port=443;Count=2;FirstUtc=[datetime]::UtcNow;LastUtc=[datetime]::UtcNow;BlockReason='Fixture: gezielte Sperre'};$setupStatus.Attempts.Add($attempt)
$script:allProgramItems=@(Get-ProgramCatalog $fixtureRows @($trafficSamples.Values) @() $setupStatus @() | Sort-Object Name);$ui.Programs.ItemsSource=$allProgramItems
$script:activePanel='DashboardPanel';Initialize-DashboardMode
$now=[datetime]::UtcNow
for($i=0;$i -lt 400;$i++){Add-DashboardSample $now.AddSeconds(($i-400)*2) 1000 200 $true}
if($dashboardHistory.Count -gt 154){throw 'Dashboard-Historie ist nicht zeitlich begrenzt.'}
Reset-DashboardHistory
for($i=0;$i -lt 61;$i++){Add-DashboardSample $now.AddSeconds(($i-61)*2) (2000000+[Math]::Abs([Math]::Sin($i/5))*6000000) (120000+[Math]::Abs([Math]::Sin($i/7))*300000) $true}
Set-DesignStyle 'Future';Show-RealPanel 'DashboardPanel';Update-Dashboard
if($dashboardFrame.ActiveCount -ne 5 -or $dashboardFrame.Programs.Count -ne 5 -or $ui.DashboardActiveCount.Text -ne '5' -or $ui.DashboardBlockedCount.Text -ne '2' -or $script:dashboardNodeVisuals.Count -ne 5){throw 'Dashboard zählt nicht die aktive Erfassung oder zeichnet keine anklickbaren App-Knoten.'}
$internetNode=$ui.DashboardLinks.Children | Where-Object {$_ -is [Windows.Controls.Border] -and $_.Child -is [Windows.Controls.TextBlock] -and $_.Child.Text -eq "Internet`n2 Gegenstellen"}
if(-not $internetNode){throw 'Internet-Ziele werden im Dashboard falsch als LAN oder nur einzeln zusammengefasst.'}
$flowModel=$dashboardFrame.Programs | Where-Object Path -eq $testExe | Select-Object -First 1
if($flowModel.Outgoing -ne 1 -or $flowModel.Incoming -ne 0 -or $flowModel.Rx -le $flowModel.Tx -or -not @($flowModel.Edges | Where-Object Blocked).Count){throw 'Download wird als eingehender Aufbau dargestellt oder Blockkante fehlt.'}
$node=$script:dashboardNodeVisuals.Values | ForEach-Object {$_.Button} | Select-Object -Last 1;$nodeKey=$node.Tag;$node.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
if($dashboardSelectedKey -ne $nodeKey -or $ui.DashboardProgramName.Text -eq 'Programm auswählen'){throw 'App-Knoten öffnet keine Dashboard-Details.'}
$policyBeforeDashboard=$serializer.Serialize($setupStatus.Config)
$ui.DashboardFreeze.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent));$frozenFrame=$dashboardFrame
Add-DashboardSample ([datetime]::UtcNow) 99999999 99999999 $true;Update-Dashboard
if(-not $dashboardFrozen -or -not [object]::ReferenceEquals($frozenFrame,$dashboardFrame) -or $ui.DashboardTemporaryBlock.IsEnabled){throw 'Eingefrorenes Dashboard verändert seine Daten oder bietet eine veraltete Sperraktion.'}
$ui.DashboardPeriod.SelectedIndex=2
if(-not [object]::ReferenceEquals($frozenFrame,$dashboardFrame)){throw 'Zeitraumwahl hebt Dashboard-Freeze auf.'}
$ui.DashboardFreeze.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent));$ui.DashboardPeriod.SelectedIndex=0
if($dashboardFrozen -or [object]::ReferenceEquals($frozenFrame,$dashboardFrame) -or $serializer.Serialize($setupStatus.Config) -ne $policyBeforeDashboard){throw 'Dashboard setzt nicht fort oder verändert Firewallregeln.'}
$ui.OnlyProgramUnreviewed.IsChecked=$false;$ui.OnlyProgramBlocks.IsChecked=$false;$ui.Programs.SelectedItem=$allProgramItems | Where-Object Path -eq $testExe | Select-Object -First 1
$ui.ConnectionDirectionFilter.SelectedIndex=1;Refresh-Detail
if(-not $ui.Connections.Items.Count -or @($ui.Connections.Items | Where-Object ConnectionDirection -ne 'Ausgehend').Count){throw 'Ausgehend-Filter zeigt andere Richtungen.'}
$ui.ConnectionDirectionFilter.SelectedIndex=2;Refresh-Detail
if($ui.Connections.Items.Count){throw 'Download-App erhält erfundene eingehende Verbindungen.'}
$ui.Programs.SelectedItem=$allProgramItems | Where-Object Path -eq $fixturePaths[1] | Select-Object -First 1;Refresh-Detail
if($ui.Connections.Items.Count -ne 1 -or $ui.Connections.Items[0].ConnectionDirection -ne 'Eingehend'){throw 'Eingehende Serververbindung fehlt im Richtungsfilter.'}
$ui.ConnectionDirectionFilter.SelectedIndex=0

# More than six apps, stable slots/controls, independent camera and retained selection.
$originalDashboardItems=@($script:allProgramItems);$extraDashboardItems=@()
for($i=1;$i -le 24;$i++){
 $path='C:\Beispiel\Programm-'+$i.ToString('00')+'.exe';$key=[Netzblick.ProcessLineage]::Normalize($path)
 $socket=[Netzblick.SocketRow]@{Path=$path;Program=('Programm '+$i.ToString('00'));Pid=(8000+$i);Protocol='TCPv4';Local=('192.0.2.5:'+(51000+$i));Address='198.51.100.70';Remote='198.51.100.70:443';Port=443;State='Verbunden'}
 $extraDashboardItems+=@(Get-ProgramCatalog @($socket) @() @() $setupStatus @() | Where-Object Path -eq $path)
}
$script:allProgramItems=$originalDashboardItems+$extraDashboardItems
$ui.DashboardViewport.Measure([Windows.Size]::new(800,400));$ui.DashboardViewport.Arrange([Windows.Rect]::new(0,0,800,400));$ui.DashboardViewport.UpdateLayout()
Update-Dashboard
if($dashboardFrame.ActiveCount -ne 29 -or $dashboardFrame.Programs.Count -ne 29 -or $dashboardNodeVisuals.Count -ne 29){throw 'Dashboard blendet Programme oberhalb der bisherigen Sechsergrenze aus.'}
$target=$extraDashboardItems[17];$key=$target.Key;$posBefore=Get-DashboardPosition $key;$buttonBefore=$dashboardNodeVisuals[$key].Button
$buttonBefore.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
Set-DashboardTransform 0.8 120 -40
$anchorX=(250-$dashboardOffsetX)/$dashboardScale;$anchorY=(150-$dashboardOffsetY)/$dashboardScale
Zoom-Dashboard 120 250 150
if([Math]::Abs((250-$dashboardOffsetX)/$dashboardScale-$anchorX) -gt 0.0001 -or [Math]::Abs((150-$dashboardOffsetY)/$dashboardScale-$anchorY) -gt 0.0001){throw 'Dashboard-Zoom hält den Weltpunkt unter dem Mauszeiger nicht fest.'}
$cameraBefore=@($dashboardScale,$dashboardOffsetX,$dashboardOffsetY)
$script:trafficSamples[[Netzblick.ProcessLineage]::Normalize($testExe)].ReceivedRate=99999999
$script:allProgramItems=@($script:allProgramItems | Sort-Object Name -Descending);Update-Dashboard
$posAfter=Get-DashboardPosition $key
if($dashboardSelectedKey -ne $key -or $posBefore.X -ne $posAfter.X -or $posBefore.Y -ne $posAfter.Y -or -not [object]::ReferenceEquals($buttonBefore,$dashboardNodeVisuals[$key].Button) -or $dashboardScale -ne $cameraBefore[0] -or $dashboardOffsetX -ne $cameraBefore[1] -or $dashboardOffsetY -ne $cameraBefore[2]){throw 'Datenrate/Sortierung versetzt Knoten, Kamera oder Auswahl.'}
$script:allProgramItems=@($script:allProgramItems | Where-Object Key -ne $key);Update-Dashboard
if($dashboardSelectedKey -ne $key -or $ui.DashboardProgramName.Text -ne $target.Name -or $ui.DashboardProgramStatus.Text -notlike '*nicht aktiv*' -or $ui.DashboardTemporaryBlock.IsEnabled){throw 'Inaktive Auswahl springt auf ein anderes Programm oder zeigt veraltete Sperraktion.'}
$script:allProgramItems+=@($target);Update-Dashboard
$posAfter=Get-DashboardPosition $key
if($posBefore.X -ne $posAfter.X -or $posBefore.Y -ne $posAfter.Y){throw 'Zurückgekehrtes Programm verliert seinen festen Platz.'}
$ui.DashboardFit.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent));$b=Get-DashboardBounds
if($b.Left*$dashboardScale+$dashboardOffsetX -lt -1 -or $b.Right*$dashboardScale+$dashboardOffsetX -gt $ui.DashboardViewport.ActualWidth+1 -or $b.Top*$dashboardScale+$dashboardOffsetY -lt -1 -or $b.Bottom*$dashboardScale+$dashboardOffsetY -gt $ui.DashboardViewport.ActualHeight+1){throw 'Alles anzeigen umfasst nicht alle aktiven Knoten.'}
$ui.DashboardCenter.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
if($dashboardScale -lt 1 -or $dashboardSelectedKey -ne $key){throw 'Auswahl zentrieren macht das gewählte Programm nicht lesbar.'}
Zoom-Dashboard 100000 250 150;if($dashboardScale -ne 8){throw 'Dashboard-Zoom hat keine obere Grenze.'}
Zoom-Dashboard -100000 250 150;if($dashboardScale -ne 0.002){throw 'Dashboard-Zoom hat keine untere Grenze.'}
if($serializer.Serialize($setupStatus.Config) -ne $policyBeforeDashboard){throw 'Dashboard-Navigation verändert Firewallregeln.'}
$script:allProgramItems=$originalDashboardItems+@($extraDashboardItems | Select-Object -First 7);$ui.Programs.ItemsSource=$script:allProgramItems
$script:trafficSamples[[Netzblick.ProcessLineage]::Normalize($testExe)].ReceivedRate=8200000
Write-Output 'PASS: 29 aktive Programme ohne Auswahlgrenze, stabile Knoten und Controls, Kameraanker, Fit/Zoom/Fokus und erhaltene inaktive Auswahl ohne Regeländerung.'

# Restore representative graph samples after freeze tests; no fixture values enter production.
Reset-DashboardHistory
for($i=0;$i -lt 61;$i++){Add-DashboardSample $now.AddSeconds(($i-61)*2) (2000000+[Math]::Abs([Math]::Sin($i/5))*6000000) (120000+[Math]::Abs([Math]::Sin($i/7))*300000) $true}
$ui.UserNotice.Text='UI-Testdaten · keine realen Netzwerkverbindungen dargestellt.'
Show-RealPanel 'DashboardPanel';Update-Dashboard
Write-Output 'PASS: echtes Dashboard-XAML mit App-Auswahl, getrennten Daten-/Aufbaurichtungen, bounded Historie, Freeze/Fortsetzen und Richtungsfiltern ohne Firewalländerung.'


Initialize-HostsMode
$hostPolicyBefore=$serializer.Serialize($setupStatus.Config)
$hostFixture=New-Object Netzblick.HostSnapshot
$hostStart=[datetime]::UtcNow.AddMinutes(-5)
foreach($n in @(1,2)){
 $h=New-Object Netzblick.HostProcess;$h.Pid=4200+$n;$h.StartUtc=$hostStart;$h.Name='svchost';$h.Path=$testExe
 foreach($serviceName in @('Dnscache','Beispieldienst')){$service=New-Object Netzblick.HostedService;$service.Name=$serviceName+$n;$service.DisplayName=$(if($serviceName -eq 'Dnscache'){'DNS-Client'}else{'Beispieldienst für Netzblick-Vorschau'});$service.Description='Windows-Beschreibung: Dieser Dienst stellt Funktionen für andere Programme bereit. Die Netzwerkverbindung ist nur dem gemeinsamen Hostprozess zugeordnet.';$service.State='Läuft';$h.Services.Add($service)}
 $hostFixture.Hosts.Add($h)
}
$script:hostSnapshot=$hostFixture
$hostRowsBefore=$script:rows
$script:rows=@(
 [pscustomobject]@{Pid=4201;ProcessStartUtc=$hostStart;Path=$testExe;Protocol='TCPv4';Local='192.0.2.10:51001';Remote='198.51.100.4:443';Address='198.51.100.4';Port=443;State='SYN gesendet'},
 [pscustomobject]@{Pid=4202;ProcessStartUtc=$hostStart;Path=$testExe;Protocol='TCPv4';Local='192.0.2.10:443';Remote='198.51.100.5:51002';Address='198.51.100.5';Port=51002;State='SYN empfangen'},
 [pscustomobject]@{Pid=4201;ProcessStartUtc=$hostStart.AddMinutes(1);Path=$testExe;Protocol='TCPv4';Local='192.0.2.10:51003';Remote='203.0.113.6:443';Address='203.0.113.6';Port=443;State='Verbunden'})
$script:hostNextRead=[datetime]::UtcNow.AddHours(1)
$hostPreviewRows=@($script:rows)
Show-RealPanel 'HostsPanel'
# Do not start a native background scan in the fictional UI fixture.
$script:hostJob=$null;$script:hostNextRead=[datetime]::UtcNow.AddHours(1);Refresh-Hosts
if($ui.HostsList.Items.Count -ne 2 -or $ui.HostServices.Items.Count -ne 2 -or $ui.HostConnections.Items.Count -ne 1 -or $ui.HostConnections.Items[0].Direction -ne 'Ausgehend'){throw 'Hostansicht vermischt PID, Startzeit oder Dienste.'}
$key=$ui.HostsList.SelectedItem.Key
$ui.HostsList.SelectedIndex=1
if($ui.HostConnections.Items.Count -ne 1 -or $ui.HostConnections.Items[0].Direction -ne 'Eingehend' -or $ui.HostBlocks.Items.Count -lt 1 -or $ui.HostBlockHint.Text -notlike '*Keine sichere Zuordnung*'){throw 'Hostansicht erfindet Dienstzuordnung oder verliert gemeinsame Blockbelege.'}
$ui.HostsList.SelectedItem.HostProcess.Services[0].Expanded=$true
$expandedService=$ui.HostServices.Items[0]
Refresh-Hosts
if(-not [object]::ReferenceEquals($expandedService,$ui.HostServices.Items[0]) -or -not $ui.HostsList.SelectedItem.HostProcess.Services[0].Expanded){throw 'Socket-Aktualisierung setzt Dienstbeschreibung zurück.'}
$ui.HostsFilter.SelectedIndex=2
if($ui.HostsList.Items.Count -ne 0){throw 'Host-Sperrfilter verwechselt vergangene Versuche mit aktueller Sperre.'}
$ui.HostsFilter.SelectedIndex=3
if($ui.HostsList.Items.Count -ne 2){throw 'Offene Prüfungen werden für gemeinsamen Host-Dateipfad nicht angezeigt.'}
$ui.HostsFilter.SelectedIndex=0
$ui.HostsSearch.Text='Dnscache2'
if($ui.HostsList.Items.Count -ne 1){throw 'Dienstsuche fehlt.'}
$ui.HostsSearch.Text='nicht vorhanden'
if($ui.HostServices.Items.Count -ne 0 -or $ui.HostConnections.Items.Count -ne 0 -or $ui.HostProgramDetails.IsEnabled -or $ui.HostRules.IsEnabled){throw 'Leere Hostauswahl zeigt alte Details oder aktive Aktionen.'}
$ui.HostsSearch.Text='';$ui.HostsList.SelectedIndex=0
$script:rows=@();$ui.HostsFilter.SelectedIndex=1
if($ui.HostsList.Items.Count -ne 0){throw 'Host-Netzwerkfilter zeigt inaktive Sockets.'}
$script:rows=$hostRowsBefore;$ui.HostsFilter.SelectedIndex=0
$hostFixture.Hosts[0].StartUtc=$hostStart.AddMinutes(2);Refresh-Hosts
if($ui.HostsList.SelectedItem -or $ui.HostServices.Items.Count){throw 'Wiederverwendete Host-PID übernimmt alte Auswahl.'}
if($serializer.Serialize($setupStatus.Config) -ne $hostPolicyBefore){throw 'Hostansicht verändert Firewallregeln.'}
$ui.HostsList.SelectedIndex=0
Write-Output 'PASS: Hostprozesse mit Dienstsuche, PID-/Startzeit-Isolation, Richtungen, ehrlichen gemeinsamen Sperrbelegen und sicherer leerer Auswahl; keine Firewalländerung.'

. (Join-Path $PSScriptRoot 'Test-ExperienceFixtures.ps1')

# Render the real WPF content independently of the runner's screen resolution.
$renderRoot=$window.Content;$window.Content=$null
$renderHost=New-Object Windows.Controls.Border
$renderHost.Resources=$window.Resources;$renderHost.SetResourceReference([Windows.Controls.Border]::BackgroundProperty,'AppBg');$renderHost.Child=$renderRoot
try{
 foreach($scenario in @(0,1,2,3)){
  [Netzblick.SetupClient]::Scenario($testExe,$scenario);Update-AccessMode
  if($scenario -eq 0 -and -not $ui.StartAccess.IsEnabled){throw 'Beobachten: Start fehlt.'}
  if($scenario -eq 1 -and -not $ui.TrySetupRule.IsEnabled){throw 'Blockversuch: Testfreigabe fehlt.'}
  if($scenario -eq 2 -and ($ui.SetupRules.Items.Count -ne 2 -or $ui.RecoveryBanner.Visibility -ne 'Visible')){throw 'Regel oder Sicherheitsrückweg fehlt.'}
  if($scenario -eq 3 -and $ui.SaveSetupRule.IsEnabled){throw 'Unbestätigter Zustand erlaubt Änderungen.'}
  foreach($size in @(@(1480,920),@(1280,800))){
   $renderHost.Width=$size[0];$renderHost.Height=$size[1];$renderHost.Measure((New-Object Windows.Size($size[0],$size[1])));$renderHost.Arrange((New-Object Windows.Rect(0,0,$size[0],$size[1])));$renderHost.UpdateLayout()
   if($designPreview -eq 'Future' -and $panelName -eq 'Review' -and $ui.OverviewPrograms.ActualHeight -lt 220){throw 'Prüfliste bietet im kleinen Future-Fenster zu wenig Platz.'}
   if($panelName -eq 'Workflow' -and $ui.GuideEvidence.ActualHeight -lt 160){throw 'Prüfassistent bietet zu wenig Platz für Beobachtungen.'}
   if($panelName -eq 'Hosts' -and $ui.HostsList.Columns[0].ActualWidth -lt 280){throw 'Hostprozess-Spalte ist nicht lesbar.'}
   if($panelName -eq 'Access' -and $ui.PermissionPrograms.Columns[0].ActualWidth -lt 250){throw 'Programmspalte in Zugriffsübersicht abgeschnitten.'}
   if($panelName -like 'Dashboard*'){Draw-Dashboard;$renderHost.UpdateLayout();if($panelName -eq 'DashboardFocus'){Center-DashboardSelection}else{Fit-Dashboard};$renderHost.UpdateLayout();$renderedNode=$script:dashboardNodeVisuals.Values | ForEach-Object {$_.Button} | Select-Object -First 1;if(-not $renderedNode -or $renderedNode.ActualHeight -lt 60){throw 'Dashboard-Knoten wurden nicht arrangiert.'};if($panelName -eq 'Dashboard'){$point=$renderedNode.TransformToAncestor($ui.DashboardViewport).Transform([Windows.Point]::new(33,33));$hit=[Windows.Media.VisualTreeHelper]::HitTest($ui.DashboardViewport,$point);$target=if($hit){$hit.VisualHit}else{$null};while($target -and $target -ne $renderedNode){$target=[Windows.Media.VisualTreeHelper]::GetParent($target)};if(-not $target){throw 'Sichtbarer Dashboard-Knoten ist nach Zoom nicht anklickbar.'}}}
   $image=New-Object Windows.Media.Imaging.RenderTargetBitmap($size[0],$size[1],96,96,[Windows.Media.PixelFormats]::Pbgra32);$image.Render($renderHost)
   $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($image))
   $file=[IO.File]::Create((Join-Path $OutputDirectory ('setup-'+$scenario+'-'+$size[0]+'.png')));try{$encoder.Save($file)}finally{$file.Dispose()}
  }
 }
 foreach($designPreview in @('Clean','Future')){
 Set-DesignStyle $designPreview
 foreach($darkPreview in @($false,$true)){
 Set-NetzblickTheme $darkPreview
 if($window.Background.Color.ToString() -ne $window.Resources['AppBg'].Color.ToString() -or $renderHost.Background.Color.ToString() -ne $window.Background.Color.ToString()){throw 'Fenster und Vorschau übernehmen die Hintergrundfarbe nicht.'}
 Refresh-ProgramSignals;Refresh-Overview
 foreach($panelName in @('Workflow','Favorites','Hosts','Dashboard','DashboardFocus','Overview','Review','Updates','World','Inspection','Access','Live','LiveOverview','LiveRules','LiveTimeline')){
  $renderPanel=if($panelName -like 'Live*'){'Live'}elseif($panelName -eq 'Review'){'Overview'}elseif($panelName -eq 'Favorites'){'Workflow'}elseif($panelName -like 'Dashboard*'){'Dashboard'}else{$panelName}
  $ui.OverviewFilter.SelectedIndex=if($panelName -eq 'Review'){2}else{0};Refresh-Overview
  if($panelName -eq 'Review'){Set-OverviewFilter 2}
  if($panelName -like 'Dashboard*'){[Netzblick.SetupClient]::Scenario($testExe,0);Update-AccessMode;$setupStatus.Attempts.Add($attempt)}
  Set-NavigationTheme ($renderPanel+'Panel')
  if($renderPanel -eq 'Live'){$ui.ProgramDetailTabs.SelectedIndex=switch($panelName){'LiveOverview'{0} 'LiveRules'{2} 'LiveTimeline'{3} default{1}}}
  if($renderPanel -eq 'Hosts'){$script:rows=$hostPreviewRows;$hostFixture.Hosts[0].StartUtc=$hostStart;$hostFixture.Hosts[0].Services[0].Expanded=$true}
  Show-RealPanel ($renderPanel+'Panel')
  if($renderPanel -eq 'Workflow'){$ui.WorkflowViews.SelectedIndex=if($panelName -eq 'Favorites'){1}else{0};Refresh-Favorites;Refresh-Guide}
  if($renderPanel -eq 'Hosts'){Refresh-Hosts;$ui.HostsList.SelectedIndex=0;$script:rows=$hostRowsBefore}
  if($panelName -eq 'Access'){
   [Netzblick.SetupClient]::Scenario($testExe,0);Update-AccessMode
   [Netzblick.SetupChanges]::BlockProgram($setupStatus.Config,'C:\Beispiel\Gesperrte-App.exe')
   [Netzblick.SetupChanges]::AllowProgram($setupStatus.Config,'C:\Beispiel\Erlaubte-App.exe')
   $partial=New-Object Netzblick.SetupRule;$partial.Id=[guid]::NewGuid().ToString();$partial.Name='Ein Ziel gesperrt';$partial.Path='C:\Beispiel\Teilweise-App.exe';$partial.Direction='Ausgehend';$partial.Address='10.0.0.10';$partial.Protocol=6;$partial.Port=443;$partial.Action='Block';$setupStatus.Config.Rules.Add($partial)
   Refresh-Permissions
  }
  $ui.AccessViews.SelectedIndex=1
  $ui.MainShell.RowDefinitions[1].Height=[Windows.GridLength]::new(0);$ui.MainShell.RowDefinitions[2].Height=[Windows.GridLength]::new(0)
  foreach($size in @(@(1480,920),@(1280,800))){
   $renderHost.Width=$size[0];$renderHost.Height=$size[1];$renderHost.Measure((New-Object Windows.Size($size[0],$size[1])));$renderHost.Arrange((New-Object Windows.Rect(0,0,$size[0],$size[1])));$renderHost.UpdateLayout()
   if($designPreview -eq 'Future' -and $panelName -eq 'Review' -and $ui.OverviewPrograms.ActualHeight -lt 220){throw 'Prüfliste bietet im kleinen Future-Fenster zu wenig Platz.'}
   if($panelName -eq 'Workflow' -and $ui.GuideEvidence.ActualHeight -lt 160){throw 'Prüfassistent bietet zu wenig Platz für Beobachtungen.'}
   if($panelName -eq 'Hosts' -and $ui.HostsList.Columns[0].ActualWidth -lt 280){throw 'Hostprozess-Spalte ist nicht lesbar.'}
   if($panelName -eq 'Access' -and $ui.PermissionPrograms.Columns[0].ActualWidth -lt 250){throw 'Programmspalte in Zugriffsübersicht abgeschnitten.'}
   if($panelName -like 'Dashboard*'){Draw-Dashboard;$renderHost.UpdateLayout();if($panelName -eq 'DashboardFocus'){Center-DashboardSelection}else{Fit-Dashboard};$renderHost.UpdateLayout();$renderedNode=$script:dashboardNodeVisuals.Values | ForEach-Object {$_.Button} | Select-Object -First 1;if(-not $renderedNode -or $renderedNode.ActualHeight -lt 60){throw 'Dashboard-Knoten wurden nicht arrangiert.'};if($panelName -eq 'Dashboard'){$point=$renderedNode.TransformToAncestor($ui.DashboardViewport).Transform([Windows.Point]::new(33,33));$hit=[Windows.Media.VisualTreeHelper]::HitTest($ui.DashboardViewport,$point);$target=if($hit){$hit.VisualHit}else{$null};while($target -and $target -ne $renderedNode){$target=[Windows.Media.VisualTreeHelper]::GetParent($target)};if(-not $target){throw 'Sichtbarer Dashboard-Knoten ist nach Zoom nicht anklickbar.'}}}
   $image=New-Object Windows.Media.Imaging.RenderTargetBitmap($size[0],$size[1],96,96,[Windows.Media.PixelFormats]::Pbgra32);$image.Render($renderHost)
   $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($image))
   $file=[IO.File]::Create((Join-Path $OutputDirectory ($(if($designPreview -eq 'Future'){'Future-'}else{''})+$(if($darkPreview){'Dark-'}else{''})+$panelName+'-'+$size[0]+'.png')));try{$encoder.Save($file)}finally{$file.Dispose()}
  }
 }
 }
 }
 Set-DesignStyle 'Clean';Set-NetzblickTheme $false
 if($LogPreview){
  $encoded=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $OutputDirectory 'Dark-Overview-1280.png')))
  for($i=0;$i -lt $encoded.Length;$i+=2048){Write-Output ('NETZBLICK_UI_'+$i.ToString('D7')+'='+$encoded.Substring($i,[Math]::Min(2048,$encoded.Length-$i)))}
 }
 # Hide keeps both tray and process alive; complete quit closes the window.
 . (Join-Path $appRoot 'src\TrayMode.ps1')
 $script:setupStatus=$null;Initialize-TrayMode;$window.Show()
 $trayHideItem.PerformClick()
 if($window.IsVisible -or -not $tray.Visible -or $script:exitNetzblick){throw 'Fenster schließen beendet die Tray-Sitzung.'}
 $trayQuitItem.PerformClick()
 if(-not $script:exitNetzblick -or $tray.Visible){throw 'Vollständig beenden lässt das Tray offen.'}
 Write-Output 'PASS: Fenster schließen erhält das Tray; vollständig beenden entfernt es.'
 Write-Output 'PASS: vier UI-Zustände und fünf gerenderte Ansichten. Nur Fakes, keine WFP-/Firewall-/Audit-Änderungen.'
}finally{$accessTimer.Stop();$window.Close();Remove-Item -LiteralPath $userStateDirectory -Recurse -Force -ErrorAction SilentlyContinue}


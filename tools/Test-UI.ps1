#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory=(Join-Path $PSScriptRoot 'ui-preview'),[switch]$LogPreview)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName @('PresentationFramework','PresentationCore','WindowsBase')
$appRoot=Split-Path $PSScriptRoot -Parent
$sources=@('NetworkReader.cs','GeoDatabase.cs','ProbeSession.cs','InspectionCore.cs','WindowsInspection.cs','NetworkPolicyCore.cs','EndpointInfo.cs','AccessCore.cs','WindowsAccess.cs','AccessWatch.cs','SetupCore.cs','ReleaseUpdates.cs') | ForEach-Object {Join-Path $appRoot ('src\'+$_)}
$sources+=Join-Path $PSScriptRoot 'FakeSetupClient.cs'
Add-Type -ReferencedAssemblies @('System.dll','System.Core.dll','System.Xml.dll','System.Web.Extensions.dll','System.Security.dll') -Path $sources
[xml]$xaml=Get-Content -LiteralPath (Join-Path $appRoot 'src\MainWindow.xaml') -Raw -Encoding UTF8
$window=[Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader($xaml)))
$ui=@{}
$xaml.GetElementsByTagName('*') | ForEach-Object {$name=$_.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml');if($name){$control=$window.FindName($name);if($control){$ui[$name]=$control}}}
foreach($panelName in @('World','Terminal','Inspection','Overview','Access','Updates')){
 [xml]$panelXaml=Get-Content -LiteralPath (Join-Path $appRoot ('src\'+$panelName+'Panel.xaml')) -Raw -Encoding UTF8
 $panel=[Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader($panelXaml)));$ui[$panelName+'Panel'].Content=$panel
 $panelXaml.GetElementsByTagName('*') | ForEach-Object {$name=$_.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml');if($name){$ui[$name]=$panel.FindName($name)}}
}
function Show-Error([string]$message){throw $message}
function Is-Protected([string]$path){return $false}
. (Join-Path $appRoot 'src\AccessMode.ps1')
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$testExe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
[Netzblick.SetupClient]::Scenario($testExe,0)
Initialize-AccessMode
# Exercise review actions against UI fixtures only. FakeSetupClient rejects
# every mutation, so marking/reviewing cannot accidentally change filters.
. (Join-Path $appRoot 'src\UserModes.ps1')
. (Join-Path $appRoot 'src\ReviewMode.ps1')
$script:SmokeTest=$true;$script:policyReady=$true;$script:notifyObserved=$false
$script:knownPrograms=@{};$script:newPrograms=@{};$script:trafficSamples=@{};$script:trafficPeers=@([pscustomobject]@{Path=$testExe;Protocol='TCPv4';Address='8.8.8.8';Port=443})
$script:rows=@();$script:ownRules=@();$script:userBaseline=$true;$script:sessionStartedUtc=[datetime]::UtcNow
$script:trafficProblem='';$script:traffic=$null;$script:changes=New-Object 'System.Collections.Generic.List[object]'
$script:userStateDirectory=Join-Path $env:TEMP ('NetzblickReview-'+[guid]::NewGuid().ToString('N'));$script:userStateFile=Join-Path $userStateDirectory 'user-state.json'
function Add-Event($kind,$program,$detail){}
function Show-NetzblickWindow {}
function Show-Panel($name){$script:lastPanel=$name}
function Refresh-Detail {}
$script:allProgramItems=@([pscustomobject]@{Key=[Netzblick.ProcessLineage]::Normalize($testExe);Path=$testExe;Name='Neue Test-App';Rows=@()})
$ui.Programs.ItemsSource=$allProgramItems
Initialize-ReviewMode
Track-ObservedPrograms $allProgramItems
Refresh-Overview
if($newPrograms.Count -ne 1 -or $ui.PendingPrograms.Items.Count -ne 1 -or $ui.ReviewTargets.Text -notmatch '8.8.8.8'){throw 'Prüfliste oder Gegenstellen fehlen.'}
Show-ReviewProgram $testExe
if($lastPanel -ne 'LivePanel' -or $ui.Programs.SelectedItem.Path -ne $testExe){throw 'Anzeigen öffnet nicht das ausgewählte Programm.'}
$saved=Get-Content -LiteralPath $userStateFile -Raw | ConvertFrom-Json
if(@($saved.Pending).Count -ne 1 -or $saved.Pending[0].Path -ne $testExe){throw 'Offene Prüfung wurde nicht gespeichert.'}
$rulesBefore=$setupStatus.Config.Rules.Count
Save-ReviewDecision $testExe
if($newPrograms.Count -ne 0 -or $setupStatus.Config.Rules.Count -ne $rulesBefore){throw 'Prüfmarkierung verändert Regeln oder lässt Eintrag stehen.'}
$savedAfter=Get-Content -LiteralPath $userStateFile -Raw | ConvertFrom-Json
if(@($savedAfter.Pending).Count -ne 0 -or $ui.UserNotice.Text -like '*nicht gespeichert*'){throw 'Erneutes Speichern der Prüfliste fehlgeschlagen.'}
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
# Render the real WPF content independently of the runner's screen resolution.
$renderRoot=$window.Content;$window.Content=$null
$renderHost=New-Object Windows.Controls.Border
$renderHost.Background=$window.Background;$renderHost.Resources=$window.Resources;$renderHost.Child=$renderRoot
try{
 foreach($scenario in @(0,1,2,3)){
  [Netzblick.SetupClient]::Scenario($testExe,$scenario);Update-AccessMode
  if($scenario -eq 0 -and -not $ui.StartAccess.IsEnabled){throw 'Beobachten: Start fehlt.'}
  if($scenario -eq 1 -and -not $ui.TrySetupRule.IsEnabled){throw 'Blockversuch: Testfreigabe fehlt.'}
  if($scenario -eq 2 -and ($ui.SetupRules.Items.Count -ne 1 -or $ui.RecoveryBanner.Visibility -ne 'Visible')){throw 'Regel oder Sicherheitsrückweg fehlt.'}
  if($scenario -eq 3 -and $ui.SaveSetupRule.IsEnabled){throw 'Unbestätigter Zustand erlaubt Änderungen.'}
  foreach($size in @(@(1480,920),@(1280,800))){
   $renderHost.Width=$size[0];$renderHost.Height=$size[1];$renderHost.Measure((New-Object Windows.Size($size[0],$size[1])));$renderHost.Arrange((New-Object Windows.Rect(0,0,$size[0],$size[1])));$renderHost.UpdateLayout()
   $image=New-Object Windows.Media.Imaging.RenderTargetBitmap($size[0],$size[1],96,96,[Windows.Media.PixelFormats]::Pbgra32);$image.Render($renderHost)
   $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($image))
   $file=[IO.File]::Create((Join-Path $OutputDirectory ('setup-'+$scenario+'-'+$size[0]+'.png')));try{$encoder.Save($file)}finally{$file.Dispose()}
  }
 }
 foreach($panelName in @('Overview','Updates','World','Inspection')){
  foreach($n in @('Access','Overview','Updates','World','Inspection')){$ui[$n+'Panel'].Visibility=if($n -eq $panelName){'Visible'}else{'Collapsed'}}
  $ui.MainShell.RowDefinitions[1].Height=[Windows.GridLength]::new(0);$ui.MainShell.RowDefinitions[2].Height=[Windows.GridLength]::new(0)
  foreach($size in @(@(1480,920),@(1280,800))){
   $renderHost.Width=$size[0];$renderHost.Height=$size[1];$renderHost.Measure((New-Object Windows.Size($size[0],$size[1])));$renderHost.Arrange((New-Object Windows.Rect(0,0,$size[0],$size[1])));$renderHost.UpdateLayout()
   $image=New-Object Windows.Media.Imaging.RenderTargetBitmap($size[0],$size[1],96,96,[Windows.Media.PixelFormats]::Pbgra32);$image.Render($renderHost)
   $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($image))
   $file=[IO.File]::Create((Join-Path $OutputDirectory ($panelName+'-'+$size[0]+'.png')));try{$encoder.Save($file)}finally{$file.Dispose()}
  }
 }
 if($LogPreview){
  $encoded=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $OutputDirectory 'Overview-1280.png')))
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
 Write-Output 'PASS: vier UI-Zustände; acht Renderings. Nur Fakes, keine WFP-/Firewall-/Audit-Änderungen.'
}finally{$accessTimer.Stop();$window.Close();Remove-Item -LiteralPath $userStateDirectory -Recurse -Force -ErrorAction SilentlyContinue}


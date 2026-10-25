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
# Retain a fixture entry for the activity rendering.
$entry=[pscustomobject]@{Key=[Netzblick.ProcessLineage]::Normalize($testExe);Path=$testExe;Name='Neue Test-App';FirstUtc=[datetime]::UtcNow}
$newPrograms[$entry.Key]=$entry;Refresh-Overview
Write-Output 'PASS: neue App, Gegenstellen, direkter Anzeigenweg, gespeicherte Prüfliste und Markierung ohne Filteränderung.'
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
 foreach($panelName in @('Overview','Updates')){
  foreach($n in @('Access','Overview','Updates')){$ui[$n+'Panel'].Visibility=if($n -eq $panelName){'Visible'}else{'Collapsed'}}
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
 Write-Output 'PASS: vier UI-Zustände; acht Renderings. Nur Fakes, keine WFP-/Firewall-/Audit-Änderungen.'
}finally{$accessTimer.Stop();$window.Close();Remove-Item -LiteralPath $userStateDirectory -Recurse -Force -ErrorAction SilentlyContinue}


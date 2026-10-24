#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory=(Join-Path $PSScriptRoot 'ui-preview'))
$ErrorActionPreference='Stop'
Add-Type -AssemblyName @('PresentationFramework','PresentationCore','WindowsBase')
$appRoot=Split-Path $PSScriptRoot -Parent
$sources=@('NetworkReader.cs','GeoDatabase.cs','ProbeSession.cs','InspectionCore.cs','WindowsInspection.cs','NetworkPolicyCore.cs','EndpointInfo.cs','AccessCore.cs','WindowsAccess.cs','AccessWatch.cs','SetupCore.cs') | ForEach-Object {Join-Path $appRoot ('src\'+$_)}
$sources+=Join-Path $PSScriptRoot 'FakeSetupClient.cs'
Add-Type -ReferencedAssemblies @('System.dll','System.Core.dll','System.Xml.dll') -Path $sources
[xml]$xaml=Get-Content -LiteralPath (Join-Path $appRoot 'src\MainWindow.xaml') -Raw -Encoding UTF8
$window=[Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader($xaml)))
$ui=@{}
$xaml.GetElementsByTagName('*') | ForEach-Object {$name=$_.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml');if($name){$control=$window.FindName($name);if($control){$ui[$name]=$control}}}
foreach($panelName in @('World','Terminal','Inspection','Overview','Access')){
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
try{
 foreach($scenario in @(0,1,2,3)){
  [Netzblick.SetupClient]::Scenario($testExe,$scenario);Update-AccessMode
  if($scenario -eq 0 -and -not $ui.StartAccess.IsEnabled){throw 'Beobachten: Start fehlt.'}
  if($scenario -eq 1 -and -not $ui.TrySetupRule.IsEnabled){throw 'Blockversuch: Testfreigabe fehlt.'}
  if($scenario -eq 2 -and ($ui.SetupRules.Items.Count -ne 1 -or $ui.RecoveryBanner.Visibility -ne 'Visible')){throw 'Regel oder Sicherheitsrückweg fehlt.'}
  if($scenario -eq 3 -and $ui.SaveSetupRule.IsEnabled){throw 'Unbestätigter Zustand erlaubt Änderungen.'}
  foreach($size in @(@(1480,920),@(1280,800))){
   $window.Width=$size[0];$window.Height=$size[1];$window.Measure((New-Object Windows.Size($size[0],$size[1])));$window.Arrange((New-Object Windows.Rect(0,0,$size[0],$size[1])));$window.UpdateLayout()
   $image=New-Object Windows.Media.Imaging.RenderTargetBitmap($size[0],$size[1],96,96,[Windows.Media.PixelFormats]::Pbgra32);$image.Render($window)
   $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($image))
   $file=[IO.File]::Create((Join-Path $OutputDirectory ('setup-'+$scenario+'-'+$size[0]+'.png')));try{$encoder.Save($file)}finally{$file.Dispose()}
  }
 }
 Write-Output 'PASS: vier UI-Zustände; acht Renderings. Nur Fakes, keine WFP-/Firewall-/Audit-Änderungen.'
}finally{$accessTimer.Stop();$window.Close()}

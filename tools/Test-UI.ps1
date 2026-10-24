param([string]$OutputDirectory=(Join-Path $env:TEMP ('Netzblick-UI-'+[guid]::NewGuid().ToString('N'))))
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$sources=@('NetworkReader.cs','GeoDatabase.cs','ProbeSession.cs','InspectionCore.cs','WindowsInspection.cs','NetworkPolicyCore.cs','EndpointInfo.cs','AccessCore.cs','WindowsAccess.cs','AccessWatch.cs') | ForEach-Object { Join-Path $root ('src\'+$_) }
Add-Type -ReferencedAssemblies System.dll,System.Core.dll,System.Xml.dll -Path $sources
$script:ui=@{}
function Load-Xaml([string]$file) {
 [xml]$xml=Get-Content -LiteralPath $file -Raw -Encoding UTF8
 $node=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xml))
 foreach($element in $xml.GetElementsByTagName('*')){
  $name=$element.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml')
  if($name){$ui[$name]=$node.FindName($name)}
 }
 return ,$node
}
$window=Load-Xaml (Join-Path $root 'src\MainWindow.xaml')
foreach($name in @('World','Terminal','Inspection','Overview','Access')){$ui[$name+'Panel'].Content=Load-Xaml (Join-Path $root ('src\'+$name+'Panel.xaml'))}
foreach($file in Get-ChildItem $root -Filter *.ps1 -Recurse){
 $tokens=$null;$errors=$null
 [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
 if($errors.Count){throw ($errors -join '; ')}
}
. (Join-Path $root 'src\InspectionMode.ps1')
. (Join-Path $root 'src\EndpointNames.ps1')
function Is-Protected([string]$path){return $false}
$script:ownRules=@()
$script:inspectionActivity=New-Object 'System.Collections.Generic.List[object]'
$script:inspectionProcessStates=@{}
$script:inspectionRows=New-Object 'System.Collections.Generic.List[object]'
$script:inspectionNodes=@()
$script:inspectionGuardWarning=''
$script:inspectionActive=$true
$script:mockNodes=@()
$script:inspection=[pscustomobject]@{StartedUtc=[datetime]::UtcNow.AddSeconds(-19);StoppedUtc=$null;Healthy=$true;Warning='';Outgoing=0;Incoming=0}
$inspection | Add-Member ScriptMethod Processes {return $script:mockNodes}
Update-InspectionProgress
if($ui.InspectionPhase.Text -notlike 'Wartet*'){throw 'Waiting phase'}
$script:mockNodes=@([Netzblick.ProcessNode]@{Pid=1234;ParentPid=1;Name='Beispielprogramm.exe';Path='C:\Beispiel\Beispielprogramm.exe';Root=$true;StartUtc=[datetime]::UtcNow;WindowVisible=$false})
Update-InspectionProcesses
if($ui.InspectionPhase.Text -notlike 'Programm läuft · kein*'){throw 'Background process phase'}
$script:mockNodes[0].WindowVisible=$true;$script:mockNodes[0].WindowTitle='Beispielprogramm'
Update-InspectionProcesses
if($ui.InspectionPhase.Text -notlike 'Programm läuft · sichtbares*'){throw 'Visible window phase'}
$script:mockNodes[0].EndUtc=[datetime]::UtcNow
Update-InspectionProcesses
if($ui.InspectionPhase.Text -notlike 'Programm beendet*'){throw 'Exit phase'}
$script:mockNodes[0].EndUtc=$null
$inspection.Outgoing=12
Update-InspectionProcesses
$ui.InspectionPath.Text='C:\Beispiel\Beispielprogramm.exe'
$ui.InspectionMetadata.Text='VORSCHAU MIT BEISPIELDATEN · keine echte Prüfung und keine Regeländerung'
$ui.InspectionOutgoing.Text='12'
$ui.InspectionActivity.ItemsSource=$inspectionActivity.ToArray()
$ui.InspectionEvents.ItemsSource=@([pscustomobject]@{Time='10:42:15';Subject='Beispielprogramm';Direction='Ausgehend';Endpoint='203.0.113.10:443';PeerName='cdn.example.test (Beispiel)';ServiceHint='TCP/443 · HTTPS / TLS möglich';Country='Beispieldaten'})
$ui.OverviewPanel.Visibility='Collapsed';$ui.InspectionPanel.Visibility='Visible';$ui.AccessPanel.Visibility='Collapsed'
$ui.FirewallStatus.Text='UI-Vorschau · Beispieldaten';$ui.Download.Text='—';$ui.Upload.Text='—';$ui.Count.Text='—';$ui.BlockedCount.Text='—'
$ui.Status.Text='UI-Prüfung ohne Firewall- oder Audit-Änderungen. Keine echten Netzwerkereignisse.'
$ui.InspectionHeartbeat.Text+=' · BEISPIELDATEN'
function Render-Preview([int]$width,[int]$height,[string]$name) {
 $content=$window.Content
 $content.Measure([Windows.Size]::new($width,$height));$content.Arrange([Windows.Rect]::new(0,0,$width,$height));$content.UpdateLayout()
 $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new($width,$height,96,96,[Windows.Media.PixelFormats]::Pbgra32)
 $bitmap.Render($content)
 $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
 $stream=[IO.File]::Create((Join-Path $OutputDirectory $name))
 try{$encoder.Save($stream)}finally{$stream.Dispose()}
}
Render-Preview 1396 876 'Netzblick-0.5.0-Pruefmodus.png'
Render-Preview 1076 716 'Netzblick-0.5.0-Pruefmodus-klein.png'
$script:inspectionActive=$false
Update-InspectionProgress
if($ui.InspectionPhase.Text -notlike 'Prüfung beendet*' -or $ui.InspectionPulse.IsIndeterminate){throw 'Stop phase'}
$windows=[Netzblick.WindowsProcesses]::Snapshot()
'PASS: Syntax aller PowerShell-Dateien; .NET Framework/C#-Kompilierung; alle WPF-Panels; fünf Prüfphasen; zwei Layoutgrößen; Prozess-/Fenstersnapshot mit '+$windows.Count+' zugänglichen Prozessen. Keine Firewall- oder Audit-Änderung.'

# Exercise the actual program-detail functions with a socket fixture.
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Netzblick.ps1'),[ref]$tokens,[ref]$parseErrors)
foreach($function in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in @('Refresh-Detail','Draw-Map','Map-Label','Format-Rate')},$true)){Invoke-Expression $function.Extent.Text}
. (Join-Path $root 'src\UserModes.ps1')
function Get-NetworkMode {return 'Default'}
$script:trafficPeers=@();$script:trafficSamples=@{};$script:trafficProblem='';$script:ruleError=''
$script:endpointNames=New-Object Netzblick.EndpointNames
$socket=[Netzblick.SocketRow]@{Pid=1234;Program='Beispielprogramm';Path='C:\Beispiel\app.exe';Protocol='TCPv4';Local='192.168.1.2:49001';Remote='203.0.113.10:443';Address='203.0.113.10';Port=443;State='Verbunden'}
$program=[pscustomobject]@{Key='C:\BEISPIEL\APP.EXE';Name='Beispielprogramm';Path=$socket.Path;Rows=@($socket)}
$ui.Programs.ItemsSource=@($program);$ui.Programs.SelectedIndex=0
Refresh-Detail
if($ui.Connections.Items.Count -ne 1){throw 'Program connection fixture'}
$ui.Connections.SelectedIndex=0
Show-ConnectionDetails
if($ui.Connections.SelectedItem.PeerName -ne 'DNS ausgeschaltet' -or $ui.SocketDetails.Text -notlike '*HTTPS / TLS möglich*'){throw 'Connection explanation'}
$endpointNames.Dispose()
'PASS: Tatsächliche Programm-Detailansicht mit DNS aus, Port-Hinweis und Erklärung ohne Netzwerkabfrage.'

# New access-control panel tests use fakes only. Never open a WFP engine or change audit.
. (Join-Path $root 'src\AccessMode.ps1')
function Add-Event([string]$kind,[string]$program,[string]$detail){}
$script:accessQueue=New-Object Netzblick.AccessQueue
$script:accessBaseline=New-Object 'System.Collections.Generic.HashSet[string]'
$script:accessSocketFirstSeen=@{}
$script:accessProblem='';$script:accessVerified=$false;$script:accessActive=$false;$script:accessGate=$null
$script:accessLastVerified=[datetime]::UtcNow
Refresh-AccessState
if($ui.AccessGlobalStatus.Text -notlike '*aus'){throw 'Inactive state must not imply protection'}
$script:accessGate=[pscustomobject]@{AllowedCount=0;FailClose=$false}
$accessGate | Add-Member ScriptMethod Verify {}
$accessGate | Add-Member ScriptMethod OwnBlock {param($id) return $true}
$accessGate | Add-Member ScriptMethod Revoke {param($path) $this.AllowedCount=0}
$accessGate | Add-Member ScriptMethod Dispose {if($this.FailClose){throw 'SIMULATED cleanup failure'}}
$script:accessWatch=[pscustomobject]@{Healthy=$true;Warning=''}
$accessWatch | Add-Member ScriptMethod Dispose {}
$accessWatch | Add-Member ScriptMethod VerifyAudit {}
$accessWatch | Add-Member ScriptMethod Drain {return @()}
$script:accessActive=$true;$script:accessVerified=$true
$samplePath="$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$entry=[Netzblick.BlockEvent]@{Application=$samplePath;Pid=1234;TimeUtc=[datetime]::UtcNow;Direction='Ausgehend';Destination='203.0.113.10';DestinationPort='443';Protocol='TCP'}
$accessQueue.Observe($entry,$true)
$entry2=[Netzblick.BlockEvent]@{Application='C:\Beispiel\musik.exe';Pid=1235;TimeUtc=[datetime]::UtcNow;Direction='Ausgehend';Destination='203.0.113.20';DestinationPort='443';Protocol='UDP'}
$accessQueue.Observe($entry2,$true)
$script:endpointNames=New-Object Netzblick.EndpointNames
$accessQueue.Find([Netzblick.ProcessLineage]::Normalize($samplePath)).Name='Beispielprogramm.exe'
Refresh-AccessLists;Refresh-AccessState
if($ui.AccessPendingCount.Text -ne '2' -or $ui.AccessHeadline.Text -notlike 'Kontrollmodus aktiv*'){throw 'Pending access state'}
$ui.AccessRequests.SelectedIndex=1
Show-AccessRequest
if($ui.AccessProgramState.Text -notlike '*blockiert'){throw 'Pending should remain blocked'}
$script:accessProblem='BEISPIEL: Filterprüfung nicht bestätigt';$script:accessVerified=$false
Refresh-AccessState;Show-AccessRequest
if($ui.AllowAccess.IsEnabled -or $ui.AccessHeadline.Text -notlike '*nicht bestätigt'){throw 'Unverified filter must disable grants'}
$script:accessProblem='';$script:accessVerified=$true
Refresh-AccessState;Show-AccessRequest
$script:rows=@($socket)
$ui.AccessPanel.Visibility='Visible'
Refresh-AccessSockets
if($ui.AccessSockets.Items[0].Observation -notlike 'Neu beobachtet*'){throw 'New socket observation'}
[void]$accessBaseline.Add($socket.Key)
Refresh-AccessSockets
if($ui.AccessSockets.Items[0].Observation -notlike 'Schon vor*'){throw 'Pre-existing socket is not claimed disconnected'}
$script:paused=$true
Update-AccessMode
if($ui.AccessSocketNote.Text -notlike '*veraltet*' -or -not $accessVerified){throw 'Pause does not stop access checks'}
$script:paused=$false
$ui.InspectionPanel.Visibility='Collapsed';$ui.AccessPanel.Visibility='Visible'
$ui.AccessGlobalStatus.Text+=' · BEISPIELDATEN';$ui.AccessProof.Text+=' · UI-VORSCHAU, KEINE ECHTE SPERRE'
$ui.AccessProgramTitle.Text='Beispielprogramm.exe'
$ui.AccessProgramPath.Text='C:\Beispiel\Beispielprogramm.exe'
$ui.AccessProgramState.Text='Entscheidung offen · aktuell blockiert (Beispieldaten)'
$ui.FirewallStatus.Text='Vorschau mit Beispieldaten'
Render-Preview 1396 876 'Netzblick-0.6.0-Kontrollmodus.png'
Render-Preview 1076 716 'Netzblick-0.6.0-Kontrollmodus-klein.png'
$first=$accessQueue.Snapshot()[0]
$accessQueue.Decide($first.Key,'Allowed');$accessGate.AllowedCount=1
Refresh-AccessLists;Refresh-AccessState
if($ui.AccessAllowedCount.Text -ne '1'){throw 'Grant count'}
$ui.AccessRequests.SelectedItem=$first
Set-AccessDecision 'Blocked'
if($first.Decision -ne 'Blocked' -or $accessGate.AllowedCount -ne 0){throw 'Revoke workflow'}
$accessGate.FailClose=$true
if(Stop-AccessMode -Quiet){throw 'Failed cleanup reported as success'}
if(-not $accessActive -or $accessVerified){throw 'Failed cleanup must remain actionable'}
$accessGate.FailClose=$false
if(-not (Stop-AccessMode -Quiet)){throw 'Successful cleanup'}
if($accessActive -or $ui.AccessAllowedCount.Text -ne '0'){throw 'Session end clears active allowances'}
$endpointNames.Dispose()
'PASS: Kontrollmodus-UI mit Fakes: aus, Anfragen blockiert, Freigabe, Rücknahme, nicht bestätigter Filter, fehlgeschlagener und erfolgreicher Sitzungsabschluss. Kein WFP-/Audit-Eingriff.'

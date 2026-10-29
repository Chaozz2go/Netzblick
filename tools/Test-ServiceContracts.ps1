#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$sources=@('InspectionCore.cs','AccessCore.cs','SetupCore.cs','SetupTransport.cs') | ForEach-Object {Join-Path $root ('src\'+$_)}
Add-Type -ReferencedAssemblies @('System.dll','System.Core.dll','System.Xml.dll','System.Web.Extensions.dll','System.ServiceProcess.dll') -Path $sources
$rule=New-Object Netzblick.SetupRule
$rule.Id=[guid]::NewGuid().ToString();$rule.Name='LDAPS zum Domänencontroller';$rule.Path='C:\Test\app.exe';$rule.Direction='Ausgehend';$rule.Address='10.0.0.10';$rule.Protocol=6;$rule.Port=636;$rule.Action='Allow';$rule.ExpiresUtc=[datetime]::UtcNow.AddMinutes(5)
$config=New-Object Netzblick.SetupConfig;$config.Rules.Add($rule)
$json=[Netzblick.SetupWire]::Json().Serialize($config)
$roundTrip=New-Object Netzblick.SetupConfig
# PowerShell 5.1 has no direct generic method syntax.
$method=[Netzblick.SetupWire]::Json().GetType().GetMethods() | Where-Object {$_.Name -eq 'Deserialize' -and $_.IsGenericMethodDefinition} | Select-Object -First 1
$closed=$method.MakeGenericMethod([Netzblick.SetupConfig]);$roundTrip=$closed.Invoke([Netzblick.SetupWire]::Json(),@($json))
$roundTrip.Validate()
if($roundTrip.Rules[0].Name -ne $rule.Name -or $roundTrip.Rules[0].ExpiresUtc.Kind -ne 'Utc' -or [Math]::Abs(($roundTrip.Rules[0].ExpiresUtc-$rule.ExpiresUtc).TotalMilliseconds) -gt 2){throw 'JSON-Vertrag oder UTC-Ablaufzeit verändert.'}
$stream=New-Object IO.MemoryStream
try{[Netzblick.SetupWire]::Write($stream,$json);$stream.Position=0;if([Netzblick.SetupWire]::Read($stream) -ne $json){throw 'Nachrichtenrahmen verändert.'}}finally{$stream.Dispose()}
Write-Output 'PASS: realer JSON-/UTC-Vertrag und Nachrichtenrahmen. Keine Dienst-/Firewalländerungen.'


# The saved restoration plan must survive real Framework JSON and a restart after expiry.
$path='C:\Test\timed.exe';$config=New-Object Netzblick.SetupConfig
[Netzblick.SetupChanges]::BlockProgram($config,$path);$config.WatchedPaths.Add($path)
$before=[Netzblick.SetupChanges]::CaptureProgram($config,$path)
[Netzblick.SetupChanges]::TemporaryAllowProgram($config,$path,[datetime]::UtcNow.AddMinutes(10),[datetime]::UtcNow)
$json=[Netzblick.SetupWire]::Json().Serialize($config)
$reloaded=$closed.Invoke([Netzblick.SetupWire]::Json(),@($json));$reloaded.Validate()
$expected=[Netzblick.SetupChanges]::CaptureProgram($reloaded,$path)
if(-not [Netzblick.SetupChanges]::SameProgram([Netzblick.SetupChanges]::CaptureProgram($config,$path),$expected)){throw 'Zeitweise Freigabe verliert Genauigkeit über JSON.'}
[void]$reloaded.Expire([datetime]::UtcNow.AddMinutes(11))
if(-not [Netzblick.SetupChanges]::SameProgram($before,[Netzblick.SetupChanges]::CaptureProgram($reloaded,$path))){throw 'Neustart nach Frist stellt vorherige Regeln nicht wieder her.'}
$oldJson='{"Version":1,"Ask":false,"WatchedPaths":[],"Rules":[]}'
$old=$closed.Invoke([Netzblick.SetupWire]::Json(),@($oldJson));$old.Validate()
if($null -eq $old.ProgramLeases){throw 'Alte Regeldatei nicht kompatibel.'}
Write-Output 'PASS: zeitweise Programmfreigabe, JSON-Uhrzeit, Rückweg nach Neustart und alte Regeldateien.'

# Timed denials and manual pauses retain exact restoration plans over a restart.
foreach($minutes in @(30,0)){
 $blocked=New-Object Netzblick.SetupConfig;[Netzblick.SetupChanges]::AllowProgram($blocked,$path)
 $prior=[Netzblick.SetupChanges]::CaptureProgram($blocked,$path)
 [Netzblick.SetupChanges]::TemporaryBlockProgram($blocked,$path,$minutes,[datetime]::UtcNow)
 $reloaded=$closed.Invoke([Netzblick.SetupWire]::Json(),@([Netzblick.SetupWire]::Json().Serialize($blocked)));$reloaded.Validate()
 if($minutes){[void]$reloaded.Expire([datetime]::UtcNow.AddMinutes(31))}else{
  [void]$reloaded.Expire([datetime]::UtcNow.AddYears(1))
  if([Netzblick.ProgramPolicy]::Category($reloaded,$path) -ne 'Blocked'){throw 'Manuelle Sperre geht bei Neustart verloren.'}
  [Netzblick.SetupChanges]::EndProgramLease($reloaded,$path,[Netzblick.SetupChanges]::CaptureProgram($reloaded,$path),[datetime]::UtcNow)
 }
 if(-not [Netzblick.SetupChanges]::SameProgram($prior,[Netzblick.SetupChanges]::CaptureProgram($reloaded,$path))){throw 'Zeitweise Sperre verliert vorherige Regeln über JSON.'}
}
Write-Output 'PASS: zeitweise und manuelle Sperre über echten JSON-/Neustart-Vertrag mit exakter Wiederherstellung.'

$previewKey=[Netzblick.SetupChanges]::ConfigKey($config)
$command=[Netzblick.SetupCommand]@{Operation='BlockProgram';Path=$path;ExpectedConfigKey=$previewKey}
$roundCommand=$method.MakeGenericMethod([Netzblick.SetupCommand]).Invoke([Netzblick.SetupWire]::Json(),@([Netzblick.SetupWire]::Json().Serialize($command)))
if($roundCommand.ExpectedConfigKey -ne $previewKey){throw 'Vorschau-Konfigurationsschlüssel geht über JSON verloren.'}
if([Netzblick.SetupChanges]::ConfigKey($config) -ne [Netzblick.SetupChanges]::ConfigKey($closed.Invoke([Netzblick.SetupWire]::Json(),@([Netzblick.SetupWire]::Json().Serialize($config))))){throw 'Vorschau-Konfigurationsschlüssel ist über JSON nicht stabil.'}
Write-Output 'PASS: Vorschau-Konfigurationsschlüssel und UTC-Genauigkeit über echten JSON-Vertrag.'

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

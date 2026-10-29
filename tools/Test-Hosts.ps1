#requires -Version 5.1
$ErrorActionPreference='Stop'
Add-Type -Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src\NetworkReader.cs') -ReferencedAssemblies @('System.dll','System.Core.dll')
$job=[Netzblick.HostReader]::Start()
if(-not $job.Wait(30000)){throw 'Dienst-Erfassung hat das Zeitlimit überschritten.'}
$snapshot=$job.Result
if($snapshot.Errors.Count){throw ($snapshot.Errors -join '; ')}
if(-not $snapshot.Hosts.Count){throw 'Keine laufenden Dienstprozesse erfasst.'}
$rpc=$snapshot.Hosts | Where-Object {@($_.Services | Where-Object Name -eq 'RpcSs').Count -gt 0} | Select-Object -First 1
$native=Get-CimInstance Win32_Service -Filter "Name='RpcSs'"
if(-not $rpc -or $rpc.Pid -ne $native.ProcessId -or $rpc.StartUtc -ne (Get-Process -Id $rpc.Pid).StartTime.ToUniversalTime()){throw 'SCM-Dienste wurden falscher Prozessidentität zugeordnet.'}
foreach($h in $snapshot.Hosts){if($h.Pid -le 0 -or -not $h.Services.Count -or $h.StartUtc -eq [datetime]::MinValue){throw 'Unvollständige Hostidentität.'};foreach($service in $h.Services){if(-not $service.Name -or -not $service.DisplayName -or -not $service.Description){throw 'Dienstname/Beschreibung fehlt.'}}}
Write-Output ('PASS: native read-only SCM-Erfassung, '+$snapshot.Hosts.Count+' Hostprozesse; RpcSs-PID und Startzeit gegen Windows geprüft. Keine Dienst-/Firewalländerung.')

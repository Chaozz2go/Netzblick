#requires -Version 5.1
[CmdletBinding()]
param([switch]$LogBinary)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$compiler=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$sources=@('SetupCore.cs','SetupTransport.cs','ServiceHost.cs','WindowsAccess.cs','AccessWatch.cs','AccessCore.cs','InspectionCore.cs','WindowsInspection.cs') | ForEach-Object {Join-Path $root ('src\'+$_)}
$output=Join-Path $root 'lib\Netzblick.Service.exe'
& $compiler /nologo /target:exe /platform:x64 /optimize+ /r:System.dll /r:System.Core.dll /r:System.Xml.dll /r:System.Web.Extensions.dll /r:System.ServiceProcess.dll "/out:$output" @sources
if($LASTEXITCODE -ne 0){throw 'Dienst-Kompilierung fehlgeschlagen.'}
Write-Output $output

if($LogBinary){
    $encoded=[Convert]::ToBase64String([IO.File]::ReadAllBytes($output))
    Write-Output ('NETZBLICK_SERVICE_SHA256='+(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash)
    for($i=0;$i -lt $encoded.Length;$i+=2048){Write-Output ('NETZBLICK_SERVICE_'+$i.ToString('D7')+'='+$encoded.Substring($i,[Math]::Min(2048,$encoded.Length-$i)))}
}

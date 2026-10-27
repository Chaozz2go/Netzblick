#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$compiler=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$candidates=@(
 (Join-Path ${env:ProgramFiles(x86)} 'Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8\Facades\netstandard.dll'),
 (Join-Path ${env:ProgramFiles(x86)} 'Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8.1\Facades\netstandard.dll'),
 (Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\Facades\netstandard.dll')
)
$facade=$candidates | Where-Object {Test-Path -LiteralPath $_} | Select-Object -First 1
if(-not $facade){throw '.NET-Framework-4.8-Entwicklerpaket mit netstandard-Fassade für die Kompilierung fehlt.'}
& $compiler ("/r:"+$facade) /nologo /target:library /platform:x64 /optimize+ /r:System.dll /r:System.Core.dll ("/r:"+(Join-Path $root 'lib\Microsoft.Diagnostics.Tracing.TraceEvent.dll')) ("/r:"+(Join-Path $root 'lib\Microsoft.Diagnostics.FastSerialization.dll')) ("/out:"+(Join-Path $root 'lib\Netzblick.Capture.dll')) (Join-Path $root 'src\TrafficCore.cs') (Join-Path $root 'src\WindowsTraffic.cs')
if($LASTEXITCODE -ne 0){throw 'Netzwerkerfassung konnte nicht kompiliert werden.'}
Write-Output 'PASS: ETW-Erfassung mit TCP-Aufbau-/Annahmerichtung kompiliert.'

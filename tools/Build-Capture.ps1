#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$compiler=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $compiler /nologo /target:library /platform:x64 /optimize+ /r:System.dll /r:System.Core.dll ("/r:"+(Join-Path $root 'lib\Microsoft.Diagnostics.Tracing.TraceEvent.dll')) ("/r:"+(Join-Path $root 'lib\Microsoft.Diagnostics.FastSerialization.dll')) ("/out:"+(Join-Path $root 'lib\Netzblick.Capture.dll')) (Join-Path $root 'src\TrafficCore.cs') (Join-Path $root 'src\WindowsTraffic.cs')
if($LASTEXITCODE -ne 0){throw 'Netzwerkerfassung konnte nicht kompiliert werden.'}
Write-Output 'PASS: ETW-Erfassung mit TCP-Aufbau-/Annahmerichtung kompiliert.'

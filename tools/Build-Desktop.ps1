#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory=(Join-Path (Split-Path $PSScriptRoot -Parent) 'dist'))
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$work=Join-Path $root 'obj\desktop'
[void][IO.Directory]::CreateDirectory($work)
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$compiler=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
function Compile([string[]]$options){& $compiler /nologo /optimize+ /platform:x64 @options;if($LASTEXITCODE -ne 0){throw 'EXE-Kompilierung fehlgeschlagen.'}}
& (Join-Path $PSScriptRoot 'Build-Service.ps1')
$core=Join-Path $work 'Netzblick.Core.dll'
$sources=@('NetworkReader.cs','GeoDatabase.cs','ProbeSession.cs','InspectionCore.cs','WindowsInspection.cs','NetworkPolicyCore.cs','EndpointInfo.cs','AccessCore.cs','WindowsAccess.cs','AccessWatch.cs','SetupCore.cs','SetupTransport.cs','ServiceHost.cs','ReleaseUpdates.cs') | ForEach-Object {Join-Path $root ('src\'+$_)}
Compile (@('/target:library',"/out:$core",'/r:System.dll','/r:System.Core.dll','/r:System.Xml.dll','/r:System.Web.Extensions.dll','/r:System.ServiceProcess.dll','/r:System.Security.dll')+$sources)
$payload=Join-Path $work 'payload'
if(Test-Path -LiteralPath $payload){Remove-Item -LiteralPath $payload -Recurse -Force}
[void][IO.Directory]::CreateDirectory((Join-Path $payload 'src'))
foreach($name in @('Netzblick.ps1','Install-Netzblick.ps1')){Copy-Item -LiteralPath (Join-Path $root $name) -Destination $payload}
Get-ChildItem -LiteralPath (Join-Path $root 'src') -File | Where-Object {$_.Extension -in @('.ps1','.xaml')} | Copy-Item -Destination (Join-Path $payload 'src')
Copy-Item -LiteralPath (Join-Path $root 'data') -Destination $payload -Recurse
[void][IO.Directory]::CreateDirectory((Join-Path $payload 'lib\amd64'))
Copy-Item -LiteralPath (Join-Path $root 'lib\amd64\KernelTraceControl.dll') -Destination (Join-Path $payload 'lib\amd64')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=Join-Path $work 'payload.zip'
if(Test-Path -LiteralPath $zip){Remove-Item -LiteralPath $zip}
[IO.Compression.ZipFile]::CreateFromDirectory($payload,$zip)
$exe=Join-Path $OutputDirectory 'Netzblick.exe'
$references=@('/target:winexe',"/out:$exe",('/win32manifest:'+(Join-Path $root 'src\Netzblick.manifest')),('/r:'+([psobject].Assembly.Location)),"/r:$core",'/r:System.dll','/r:System.Core.dll','/r:System.Windows.Forms.dll','/r:System.ServiceProcess.dll','/r:System.IO.Compression.dll','/r:System.IO.Compression.FileSystem.dll',"/resource:$zip,Netzblick.Payload","/resource:$core,Netzblick.Library.Netzblick.Core.dll")
foreach($dll in Get-ChildItem -LiteralPath (Join-Path $root 'lib') -Filter '*.dll' -File){$references+=('/resource:'+$dll.FullName+',Netzblick.Library.'+$dll.Name)}
$stamp=Join-Path $work 'BuildStamp.cs'
$buildNumber=if($env:GITHUB_RUN_NUMBER -match '^\d+$'){$env:GITHUB_RUN_NUMBER}else{'0'}
[IO.File]::WriteAllText($stamp,('[assembly: System.Reflection.AssemblyInformationalVersion("0.11.2+build.'+$buildNumber+'") ]'))
Compile ($references+@(Join-Path $root 'src\ExeHost.cs')+@($stamp))
# No loadFromRemoteSources switch: libraries come from the EXE's own resources.
@'
<?xml version="1.0" encoding="utf-8"?>
<configuration><startup useLegacyV2RuntimeActivationPolicy="true"><supportedRuntime version="v4.0" sku=".NETFramework,Version=v4.8"/></startup></configuration>
'@ | Set-Content -LiteralPath ($exe+'.config') -Encoding UTF8
foreach($file in @('README.md','PRUEFSTAND.txt','THIRD-PARTY-NOTICES.txt')){Copy-Item -LiteralPath (Join-Path $root $file) -Destination $OutputDirectory}
Copy-Item -LiteralPath (Join-Path $root 'lib') -Destination (Join-Path $OutputDirectory 'licenses') -Recurse -Force
Get-ChildItem -LiteralPath (Join-Path $OutputDirectory 'licenses') -Recurse -File | Where-Object {$_.Extension -in @('.dll','.exe')} | Remove-Item -Force
[void][IO.Directory]::CreateDirectory((Join-Path $OutputDirectory 'lib'))
Copy-Item -LiteralPath (Join-Path $root 'lib\Netzblick.Service.exe') -Destination (Join-Path $OutputDirectory 'lib')
Write-Output ('PASS: Windows x64 EXE mit eingebetteten Komponenten: '+$exe)

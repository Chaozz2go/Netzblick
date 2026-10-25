#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Add-Type -ReferencedAssemblies @('System.dll','System.Core.dll','System.Web.Extensions.dll','System.Security.dll') -Path (Join-Path $root 'src\ReleaseUpdates.cs')
[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
# Deliberately no Authorization header: this is what ordinary users can see.
$json=(Invoke-WebRequest -UseBasicParsing -Uri 'https://api.github.com/repos/Chaozz2go/Netzblick/releases?per_page=100' -Headers @{'User-Agent'='Netzblick-PublicUpdate-Test'} -TimeoutSec 20).Content
$release=[Netzblick.ReleaseUpdates]::Select($json,'0.11.0',0,$false,$false)
if(-not $release -or $release.Version -ne '0.11.1' -or -not [Netzblick.ReleaseUpdates]::IsNewer($release,'0.11.0',999)){throw 'Neue öffentliche Version wird ohne Token nicht erkannt.'}
$task=[Netzblick.ReleaseUpdates]::Start($false,$false)
if(-not $task.Wait(20000)){throw 'Öffentliche App-Updateprüfung läuft in Timeout.'}
$result=$task.GetAwaiter().GetResult()
if(-not $result.Release -or $result.Release.Draft -or $result.Release.Prerelease){throw ('App findet die öffentliche Version nicht: '+$result.Message)}
Write-Output ('PASS: anonyme Release-Abfrage und echte App-Updateprüfung ohne Token: '+$release.Tag)

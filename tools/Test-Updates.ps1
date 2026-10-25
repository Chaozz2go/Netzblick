#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Add-Type -ReferencedAssemblies @('System.dll','System.Core.dll','System.Web.Extensions.dll','System.Security.dll') -Path (Join-Path $root 'src\ReleaseUpdates.cs')
function Release([string]$tag,[bool]$draft,[bool]$pre,[string]$url='https://github.com/Chaozz2go/Netzblick/releases/tag/test'){
 return @{tag_name=$tag;name=$tag;draft=$draft;prerelease=$pre;html_url=$url;body='Änderungen';assets=@(@{name='Netzblick-Setup-0.10.0-win-x64.exe'})}
}
$releases=@((Release 'v0.10.0-build-7' $false $false),(Release 'v0.10.0-build-9' $true $false),(Release 'v0.11.0' $false $true),(Release 'v9.0.0' $false $false 'https://evil.example/Netzblick/releases/tag/test')) | ConvertTo-Json -Depth 6
$r=[Netzblick.ReleaseUpdates]::Select($releases,'0.10.0',7,$false,$false)
if($r.Tag -ne 'v0.10.0-build-7' -or [Netzblick.ReleaseUpdates]::IsNewer($r,'0.10.0',7)){throw 'Gleiche installierte Build-Version wird als Update gemeldet.'}
$r=[Netzblick.ReleaseUpdates]::Select($releases,'0.10.0',7,$true,$false)
if($r.Tag -ne 'v0.10.0-build-9' -or -not [Netzblick.ReleaseUpdates]::IsNewer($r,'0.10.0',7)){throw 'Entwurf/Build-Vergleich falsch.'}
$r=[Netzblick.ReleaseUpdates]::Select($releases,'0.10.0',7,$false,$true)
if($r.Tag -ne 'v0.11.0'){throw 'Numerischer Versionsvergleich/Testversionsauswahl falsch.'}
foreach($url in @('http://github.com/Chaozz2go/Netzblick/releases/tag/x','https://github.com.evil.example/Chaozz2go/Netzblick/releases/tag/x','https://github.com/Other/Netzblick/releases/tag/x','https://github.com/Chaozz2go/Netzblick/releases/tag/x?token=secret')){if([Netzblick.ReleaseUpdates]::SafeReleaseUrl($url)){throw 'Unsichere Release-URL akzeptiert.'}}
$noPackage=@((Release 'v0.10.0' $false $false));$noPackage[0].assets=@()
if([Netzblick.ReleaseUpdates]::Select(('['+($noPackage[0] | ConvertTo-Json -Depth 5)+']'),'0.10.0',0,$false,$false)){throw 'Release ohne Windows-Paket akzeptiert.'}
Write-Output 'PASS: Release-/Build-Vergleich, Entwürfe, Testversionen, fehlende Pakete und sichere Repository-URLs. Keine Netzwerkabfragen oder echten Zugangsdaten.'

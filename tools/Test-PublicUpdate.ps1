#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Add-Type -ReferencedAssemblies @('System.dll','System.Core.dll','System.Web.Extensions.dll','System.Security.dll') -Path (Join-Path $root 'src\ReleaseUpdates.cs')
[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$current=[Netzblick.ReleaseUpdates]::CurrentVersion
# GitHub's anonymous list may briefly lag behind a just-published release.
# Retry the real anonymous API and app request; never accept an older result.
for($attempt=1;$attempt -le 12;$attempt++){
    $json=(Invoke-WebRequest -UseBasicParsing -Uri 'https://api.github.com/repos/Chaozz2go/Netzblick/releases?per_page=100' -Headers @{'User-Agent'='Netzblick-PublicUpdate-Test';'Cache-Control'='no-cache'} -TimeoutSec 20).Content
    $release=[Netzblick.ReleaseUpdates]::Select($json,'0.11.1',0,$false,$false)
    if($release -and $release.Version -eq $current -and [Netzblick.ReleaseUpdates]::IsNewer($release,'0.11.1',999)){
        $task=[Netzblick.ReleaseUpdates]::Start($false,$false)
        if(-not $task.Wait(20000)){throw 'Öffentliche App-Updateprüfung läuft in Timeout.'}
        $result=$task.GetAwaiter().GetResult()
        if($result.Release -and $result.Release.Version -eq $current -and -not $result.Release.Draft -and -not $result.Release.Prerelease){
            Write-Output ('PASS: anonyme Release-Abfrage und echte App-Updateprüfung ohne Token: '+$result.Release.Tag)
            return
        }
    }
    if($attempt -lt 12){Write-Output ('Öffentliche Versionsliste noch nicht bei '+$current+'; erneute Prüfung in 5 Sekunden.');Start-Sleep -Seconds 5}
}
throw ('Veröffentlichte Version '+$current+' wird auch nach wiederholter anonymer Prüfung nicht erkannt.')

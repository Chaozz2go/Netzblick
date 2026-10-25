#requires -Version 5.1
# Development test for an isolated disposable Windows runner, never a live server.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -ne 'true'){throw 'Dieser automatische Diensttest ist auf isolierte GitHub-Actions-Runner begrenzt. Gerätetest siehe PRUEFSTAND.txt.'}
$principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Write-Warning 'SKIP: Runner ist nicht erhöht; keine automatische UAC-Abfrage.';return}
$root=Split-Path $PSScriptRoot -Parent
if(Get-Service NetzblickControl -ErrorAction SilentlyContinue){throw 'Ein vorhandener Dienst wird vom Test nicht verändert.'}
$sources=@('InspectionCore.cs','WindowsInspection.cs','AccessCore.cs','SetupCore.cs','SetupTransport.cs','WindowsAccess.cs') | ForEach-Object {Join-Path $root ('src\'+$_)}
$sources+=Join-Path $PSScriptRoot 'WfpPeerFixture.cs'
Add-Type -ReferencedAssemblies @('System.dll','System.Core.dll','System.Xml.dll','System.Web.Extensions.dll','System.ServiceProcess.dll') -Path $sources
$directory=Join-Path $env:TEMP ('NetzblickCheck-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($directory)
$fixture=Join-Path $directory 'ConnectFixture.exe'
$source=Join-Path $directory 'ConnectFixture.cs'
[IO.File]::WriteAllText($source,'using System;using System.Net.Sockets;class Check{static int Main(){using(var c=new TcpClient()){try{var t=c.ConnectAsync("1.1.1.1",443);if(!t.Wait(4000)||!c.Connected)return 2;return 0;}catch{return 2;}}}}')
& "$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:exe "/out:$fixture" $source
if($LASTEXITCODE -ne 0){throw 'Netzwerk-Fixture kompiliert nicht.'}
function Connect-Fixture {
    $info=New-Object Diagnostics.ProcessStartInfo($fixture);$info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $process=[Diagnostics.Process]::Start($info)
    try{$null=$process.Handle;if(-not $process.WaitForExit(8000)){$process.Kill();return $false};$code=$process.ExitCode;Write-Host ('Fixture exit code: '+$code);return $code -eq 0}finally{$process.Dispose()}
}
function Send-Control($command){$r=[Netzblick.SetupClient]::Send($command);if(-not $r.Ok){throw $r.Error};return $r}
$fixture=[Netzblick.WfpGate]::CanonicalPath($fixture)
$auditBefore=[Netzblick.WindowsAudit]::Query()
$installed=$false;$peer=$null
try{
    $peer=[WfpPeerFixture]::Start()
    & (Join-Path $root 'Install-Netzblick.ps1') -NoTray
    $installed=$true
    if($LASTEXITCODE -ne 0){throw 'Dienstinstallation fehlgeschlagen.'}
    $status=$null;$lastFailure=''
    for($i=0;$i -lt 20;$i++){try{$status=Send-Control ([Netzblick.SetupCommand]@{Operation='Status'});break}catch{$lastFailure=$_.Exception.GetBaseException().Message;Start-Sleep -Milliseconds 500}}
    if(-not $status -or -not $status.Verified -or $status.Config.Ask){throw ('Dienst nicht bereit. Status: '+($status | ConvertTo-Json -Depth 4 -Compress)+'; letzter Verbindungsfehler: '+$lastFailure)}
    Write-Output 'PASS: Dienststart neben leerer WFP-Ebene mit gleicher angeforderter Priorität.'
    [void]$peer.AddPermit($fixture,$false)
    [void]$peer.AddPermit((Join-Path $env:SystemRoot 'System32\where.exe'),$true)
    if(-not (Connect-Fixture)){Write-Warning 'SKIP: Baseline-TCP zu 1.1.1.1:443 nicht verfügbar. Dienst-/Pipe-Start bestanden; echte Sperr-/Freigabeprüfung nicht durchgeführt.';return}
    [void](Send-Control ([Netzblick.SetupCommand]@{Operation='Watch';Path=$fixture}))
    if(Connect-Fixture){throw 'Vorab gesperrte Fixture kann weiterhin verbinden.'}
    $evidence=$null
    for($i=0;$i -lt 20;$i++){$status=Send-Control ([Netzblick.SetupCommand]@{Operation='Status'});$evidence=$status.Attempts | Where-Object {$_.Path -eq $fixture -and $_.OwnBlock -and $_.Address -eq '1.1.1.1'} | Select-Object -First 1;if($evidence){break};Start-Sleep -Milliseconds 500}
    if(-not $evidence){throw 'Keine passende echte WFP-Blockmeldung angekommen.'}
    $rule=New-Object Netzblick.SetupRule;$rule.Id=[guid]::NewGuid().ToString();$rule.Name='CI TCP-Fixture';$rule.Path=$fixture;$rule.Direction='Ausgehend';$rule.Address='1.1.1.1';$rule.Protocol=6;$rule.Port=443;$rule.Action='Allow';$rule.ExpiresUtc=[datetime]::UtcNow.AddMinutes(2)
    [void](Send-Control ([Netzblick.SetupCommand]@{Operation='Rule';Rule=$rule}))
    if(-not (Connect-Fixture)){throw 'Gezielte TCP-Freigabe stellt die Baseline-Verbindung nicht wieder her.'}
    [void](Send-Control ([Netzblick.SetupCommand]@{Operation='Remove';RuleId=$rule.Id}))
    if(Connect-Fixture){throw 'Rücknahme der Freigabe sperrt nicht erneut.'}
    [void](Send-Control ([Netzblick.SetupCommand]@{Operation='Unwatch';Path=$fixture}))
    [void](Send-Control ([Netzblick.SetupCommand]@{Operation='BlockProgram';Path=$fixture}))
    if(Connect-Fixture){throw 'Schnellsperre verhindert die neue Fixture-Verbindung nicht.'}
    $status=Send-Control ([Netzblick.SetupCommand]@{Operation='Status'})
    $blocks=@($status.Config.Rules | Where-Object {$_.Path -eq $fixture -and $_.Action -eq 'Block' -and $_.Protocol -eq 0 -and $_.Address -eq '*'})
    if($blocks.Count -ne 2 -or @($blocks.Direction | Select-Object -Unique).Count -ne 2){throw 'Schnellsperre hat nicht beide Richtungen gespeichert.'}
    foreach($block in $blocks){[void](Send-Control ([Netzblick.SetupCommand]@{Operation='Remove';RuleId=$block.Id}))}
    if(-not (Connect-Fixture)){throw 'Rücknahme der Schnellsperre stellt die Baseline nicht wieder her.'}
    [void](Send-Control ([Netzblick.SetupCommand]@{Operation='Watch';Path=$fixture}))
    [void](Send-Control ([Netzblick.SetupCommand]@{Operation='BlockProgram';Path=$fixture}))
    $fresh=Send-Control ([Netzblick.SetupCommand]@{Operation='Reset'})
    if($fresh.Config.Ask -or $fresh.Config.Rules.Count -or $fresh.Config.WatchedPaths.Count -or $fresh.Attempts.Count){throw 'Reset lässt alte Regeln oder Ereignisse stehen.'}
    if(-not (Connect-Fixture)){throw 'Reset gibt die Baseline-Verbindung nicht wieder frei.'}
    $fresh=Send-Control ([Netzblick.SetupCommand]@{Operation='Recheck'})
    if(-not $fresh.Verified){throw 'Erneute Filterprüfung nach Reset nicht bestätigt.'}
    # An overlapping hard permit must still be rejected, while unrelated
    # app permits and a peer soft permit must not disable Netzblick.
    $hard=$peer.AddPermit($fixture,$true)
    $rejected=[Netzblick.SetupClient]::Send([Netzblick.SetupCommand]@{Operation='Watch';Path=$fixture})
    if($rejected.Ok -or $rejected.Error -notlike '*nicht übersteuerbare Freigabe*' -or $rejected.Config.WatchedPaths.Count){throw 'Passende fremde Hard-Permit-Regel wurde nicht vor Installation zurückgewiesen.'}
    $peer.Remove($hard)
    [void](Send-Control ([Netzblick.SetupCommand]@{Operation='Recheck'}))
    [void](Send-Control ([Netzblick.SetupCommand]@{Operation='Watch';Path=$fixture}))
    if(Connect-Fixture){throw 'Sperre nach Entfernen des Konflikts wirkt nicht.'}
    [void](Send-Control ([Netzblick.SetupCommand]@{Operation='Reset'}))
    $peer.Verify()
    Write-Output 'PASS: gemeinsam angeforderte WFP-Priorität mit Soft Permit und fremdem App-Hard-Permit; echte Sperre/Freigabe; passende Hard-Permit-Regel zurückgewiesen; Peer-Filter unverändert.'
    Write-Output 'PASS: Dienst-Reset entfernt Regeln, Prüfungen und Ereignisse; Recheck und Baseline-Verbindung bestätigt.'
    Write-Output 'PASS: atomare Programm-Schnellsperre für beide Richtungen, echte IPv4/TCP-Sperrwirkung und Rücknahme.'
    Write-Output 'PASS: echter Dienststart, Pipe, pfadbezogene WFP-Sperre, Security-Blockereignis, gezielte IPv4/TCP-Freigabe und Rücknahme. Kein globaler Nachfragemodus aktiviert.'
}finally{
    $log=Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'Netzblick\service.log'
    if(Test-Path -LiteralPath $log){Get-Content -LiteralPath $log -Encoding UTF8 -Tail 30 | Write-Host}
    Get-Service NetzblickControl -ErrorAction SilentlyContinue | Format-List Name,Status | Out-String | Write-Host
    if($installed -or (Get-Service NetzblickControl -ErrorAction SilentlyContinue)){& (Join-Path $root 'Install-Netzblick.ps1') -Uninstall -NoTray}
    if([Netzblick.WindowsAudit]::Query() -ne $auditBefore){throw 'Audit-Ausgangszustand nach Dienstende nicht wiederhergestellt.'}
    if($peer){$peer.Dispose()}
    Remove-Item -LiteralPath $directory -Recurse -Force
}


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
    if(-not $evidence.FilterId -or $evidence.BlockReason -notlike '*Prüfsperre*' -or $evidence.BlockReason -notlike '*ConnectFixture.exe*' -or $evidence.BlockReason -notlike '*Ausgehend*'){throw 'Eigener Filtername wurde beim realen Blockereignis nicht aufgezeichnet.'}
    . (Join-Path $root 'src\ProgramCatalog.ps1')
    $blockedCatalog=@(Get-ProgramCatalog @() @() @() $status @())
    $blockedProgram=$blockedCatalog | Where-Object {$_.Path -eq $fixture} | Select-Object -First 1
    $blockedRows=@(Get-ProgramBlockRows $fixture $status)
    if(-not $blockedProgram -or $blockedProgram.Rows.Count -or $blockedProgram.BlockCount -lt 1 -or $blockedRows.Count -lt 1 -or $blockedRows[0].State -notlike '*Blockiert*'){throw 'Echte gesperrte Verbindung fehlt ohne Socket in der Programmansicht.'}
    Write-Output 'PASS: echter WFP-Blockversuch ohne Socket als sichtbares Programm mit Ziel, Zähler und Zeitpunkt.'

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
    $allowed=Send-Control ([Netzblick.SetupCommand]@{Operation='AllowProgram';Path=$fixture})
    if($allowed.Config.WatchedPaths.Count -or @($allowed.Config.Rules | Where-Object {$_.Path -eq $fixture -and $_.Action -eq 'Block'}).Count -or -not (Connect-Fixture)){throw 'Programm erlauben hebt Dienst-/Prüfsperren nicht vollständig auf.'}
    $standard=Send-Control ([Netzblick.SetupCommand]@{Operation='ProgramDefault';Path=$fixture})
    if(@($standard.Config.Rules | Where-Object {$_.Path -eq $fixture}).Count -or -not (Connect-Fixture)){throw 'Programmstandard entfernt eigene Freigaben nicht.'}
    [void](Send-Control ([Netzblick.SetupCommand]@{Operation='BlockProgram';Path=$fixture}))
    if(Connect-Fixture){throw 'Erneutes Sperren nach Programmfreigabe wirkungslos.'}
    $prior=[Netzblick.SetupChanges]::CaptureProgram((Send-Control ([Netzblick.SetupCommand]@{Operation='Status'})).Config,$fixture)
    $temporary=Send-Control ([Netzblick.SetupCommand]@{Operation='TemporaryAllowProgram';Path=$fixture})
    if($temporary.Config.ProgramLeases.Count -ne 1 -or -not (Connect-Fixture)){throw 'Zeitweise Programmfreigabe lässt neue TCP-Verbindung nicht zu.'}
    $expected=[Netzblick.SetupChanges]::CaptureProgram($temporary.Config,$fixture)
    [void](Send-Control ([Netzblick.SetupCommand]@{Operation='RestoreProgram';BeforeProgram=$prior;ExpectedProgram=$expected}))
    if(Connect-Fixture){throw 'Programm-Rückgängig stellt echte TCP-Sperre nicht wieder her.'}
    [void](Send-Control ([Netzblick.SetupCommand]@{Operation='AllowProgram';Path=$fixture}))
    $stale=[Netzblick.SetupClient]::Send([Netzblick.SetupCommand]@{Operation='RestoreProgram';BeforeProgram=$prior;ExpectedProgram=$expected})
    if($stale.Ok -or -not (Connect-Fixture)){throw 'Veraltetes Rückgängig überschreibt neuere Entscheidung.'}
    Write-Output 'PASS: echte TCP-Freigabe für 10 Minuten, scoped Rückgängig und Ablehnung veralteter Zustände.'
    Write-Output 'PASS: Programm erlauben entfernt Sperren und Prüfsperre atomar; Standard entfernt eigene Freigaben; erneute echte TCP-Sperre bestätigt.'
    $beforePause=Send-Control ([Netzblick.SetupCommand]@{Operation='AllowProgram';Path=$fixture})
    $online=[Netzblick.SetupChanges]::CaptureProgram($beforePause.Config,$fixture)
    foreach($minutes in @(10,0)){
     $pause=Send-Control ([Netzblick.SetupCommand]@{Operation='TemporaryBlockProgram';Path=$fixture;DurationMinutes=$minutes})
     if(Connect-Fixture){throw 'Zeitweise Sperre verhindert echte neue TCP-Verbindung nicht.'}
     $resumed=Send-Control ([Netzblick.SetupCommand]@{Operation='EndProgramLease';Path=$fixture;ExpectedProgram=[Netzblick.SetupChanges]::CaptureProgram($pause.Config,$fixture)})
     if(-not (Connect-Fixture) -or -not [Netzblick.SetupChanges]::SameProgram($online,[Netzblick.SetupChanges]::CaptureProgram($resumed.Config,$fixture))){throw 'Beenden der zeitweisen Sperre stellt Verbindung oder Regeln nicht wieder her.'}
    }
    Write-Output 'PASS: echte TCP-Sperre für Dauer/manuell und anschließende Wiederherstellung vorheriger Freigaben.'
    $fresh=Send-Control ([Netzblick.SetupCommand]@{Operation='Reset'})
    if($fresh.Config.Ask -or $fresh.Config.Rules.Count -or $fresh.Config.WatchedPaths.Count -or $fresh.Attempts.Count){throw 'Reset lässt alte Regeln oder Ereignisse stehen.'}
    if(-not (Connect-Fixture)){throw 'Reset gibt die Baseline-Verbindung nicht wieder frei.'}
    $fresh=Send-Control ([Netzblick.SetupCommand]@{Operation='Recheck'})
    if(-not $fresh.Verified){throw 'Erneute Filterprüfung nach Reset nicht bestätigt.'}
    [void](Send-Control ([Netzblick.SetupCommand]@{Operation='ObserveBlocks';Enabled=$true}))
    $observed=Send-Control ([Netzblick.SetupCommand]@{Operation='Status'})
    if($observed.Config.Ask -or $observed.Config.Rules.Count -or $observed.Config.WatchedPaths.Count -or $observed.Warning -like '*Ereignisanzeige nicht verfügbar*'){throw 'Blockbeobachtung verändert Filter oder startet nicht.'}
    $foreignId=$peer.AddBlock($fixture)
    if(Connect-Fixture){throw 'Fremder Fixture-Block hat keine Sperrwirkung.'}
    $foreign=$null
    for($i=0;$i -lt 20;$i++){$observed=Send-Control ([Netzblick.SetupCommand]@{Operation='Status'});$foreign=$observed.Attempts | Where-Object {$_.FilterId -eq $foreignId} | Select-Object -First 1;if($foreign){break};Start-Sleep -Milliseconds 500}
    if(-not $foreign -or $foreign.OwnBlock -or $foreign.BlockReason -notlike '*CI peer block*'){throw 'Echter Fremdfilter wird nicht mit Name und eigener Filter-ID erkannt.'}
    $peer.Remove($foreignId)
    if(-not (Connect-Fixture)){throw 'Rücknahme der Fremd-Fixturesperre gibt nicht frei.'}
    Write-Output 'PASS: echte eigene Prüfsperre und fremder WFP-Block mit Filtername/ID getrennt aufgezeichnet.'
    [void](Send-Control ([Netzblick.SetupCommand]@{Operation='ObserveBlocks';Enabled=$false}))
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


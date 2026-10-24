#requires -Version 5.1
$ErrorActionPreference='Stop'
$principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Write-Warning 'SKIP: vollständiger Startcheck benötigt einen erhöhten Testprozess.';return}
$root=Split-Path $PSScriptRoot -Parent
$out=Join-Path $env:TEMP ('netzblick-out-'+[guid]::NewGuid().ToString('N')+'.txt')
$err=$out+'.err'
try{
 $process=Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList ('-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "'+(Join-Path $root 'Netzblick.ps1')+'" -SmokeTest') -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
 if(-not $process.WaitForExit(30000)){$process.Kill();throw 'Vollständiger Start-/Tray-Check hat nicht rechtzeitig beendet.'}
 $process.Refresh()
 $text=Get-Content -LiteralPath $out -Raw;$errorText=Get-Content -LiteralPath $err -Raw
 Write-Host $text
 if($process.ExitCode -ne 0 -or $text -notmatch 'PASS: full WPF/tray') {throw ('Startcheck fehlgeschlagen: '+$errorText)}
 Write-Output 'PASS: echte App einschließlich Tray/Erfassung initialisiert und geschlossen. Keine Sperre aktiviert.'
}finally{Remove-Item -LiteralPath $out,$err -Force -ErrorAction SilentlyContinue}

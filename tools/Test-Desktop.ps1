#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$exe=Join-Path $root 'dist\Netzblick.exe'
function Run-Exe([string]$arguments){
 $report=Join-Path $env:TEMP ('netzblick-exe-'+[guid]::NewGuid().ToString('N')+'.txt')
 try{
  $info=New-Object Diagnostics.ProcessStartInfo
  $info.FileName=$exe;$info.Arguments=$arguments+' --report "'+$report+'"';$info.UseShellExecute=$false
  $p=[Diagnostics.Process]::Start($info)
  $null=$p.Handle
  if(-not $p.WaitForExit(45000)){$p.Kill();throw ('EXE-Start hängt: '+$arguments)}
  $text=if(Test-Path -LiteralPath $report){Get-Content -LiteralPath $report -Raw}else{'Kein Prüfbericht'}
  if($p.ExitCode -ne 0 -or $text -notmatch 'PASS: EXE host'){throw ($arguments+': '+$text)}
  Write-Host $text
 }finally{Remove-Item -LiteralPath $report -Force -ErrorAction SilentlyContinue}
}
$before=Get-Service NetzblickControl -ErrorAction SilentlyContinue
if($before){throw 'Desktop-Prüfung nur auf einem isolierten Runner ohne Netzblick-Dienst ausführen.'}
# Reproduce the user's exact download condition without unblocking anything.
Set-Content -LiteralPath $exe -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3" -Encoding ASCII
Run-Exe '--portable --check'
Run-Exe '--portable --smoke-test'
if(Get-Service NetzblickControl -ErrorAction SilentlyContinue){throw 'Portable Version hat einen Dienst hinterlassen.'}
if(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {$_.TaskName -like 'Netzblick Tray *'}){throw 'Portable Version hat einen Autostart hinterlassen.'}
Write-Output 'PASS: heruntergeladene EXE startet mit ETW, Tray und portabler Steuerung; kein Dienst/Autostart installiert.'

#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$setup=Join-Path $root 'dist-install\Netzblick-Setup-0.8.0-win-x64.exe'
$installed=Join-Path $env:ProgramFiles 'Netzblick'
function Run-Checked([string]$exe,[string]$arguments){
 $p=Start-Process -FilePath $exe -ArgumentList $arguments -PassThru
 $null=$p.Handle
 if(-not $p.WaitForExit(90000)){$p.Kill();throw ('Zeitüberschreitung: '+$exe)}
 if($p.ExitCode -ne 0){
  foreach($log in @('Netzblick-Setup.log','Netzblick-Uninstall.log')){$path=Join-Path $env:ProgramData $log;if(Test-Path -LiteralPath $path){Write-Host (Get-Content -LiteralPath $path -Raw)}}
  throw ('Fehlercode '+$p.ExitCode+': '+$exe)
 }
}
try{
 Run-Checked $setup '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART'
 if((Get-Service NetzblickControl).Status -ne 'Running'){throw 'Dienst läuft nach Installation nicht.'}
 $task=Get-ScheduledTask | Where-Object {$_.TaskName -like 'Netzblick Tray *'}
 if(-not $task -or $task.Actions.Execute -notcontains (Join-Path $installed 'Netzblick.exe')){throw 'EXE-Autostart fehlt.'}
 $config=Join-Path $env:ProgramData 'Netzblick\control.json'
 $marker=Join-Path $env:ProgramData 'Netzblick\update-preserves-data.txt'
 Set-Content -LiteralPath $marker -Value 'behalten'
 $report=Join-Path $env:TEMP 'netzblick-installed-report.txt'
 Run-Checked (Join-Path $installed 'Netzblick.exe') ('--installed --smoke-test --report "'+$report+'"')
 if((Get-Content -LiteralPath $report -Raw) -notmatch 'PASS: EXE host'){throw 'Installierte EXE nicht bestätigt.'}
 # Repeat installation exercises stopping and replacing an existing service.
 Run-Checked $setup '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART'
 if(-not(Test-Path -LiteralPath $marker)){throw 'Update hat Einstellungen entfernt.'}
 if((Get-Service NetzblickControl).Status -ne 'Running'){throw 'Dienst läuft nach Update nicht.'}
 Run-Checked (Join-Path $installed 'unins000.exe') '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART'
 if(Get-Service NetzblickControl -ErrorAction SilentlyContinue){throw 'Dienst nach Deinstallation noch vorhanden.'}
 if(Get-ScheduledTask | Where-Object {$_.TaskName -like 'Netzblick Tray *'}){throw 'Autostart nach Deinstallation noch vorhanden.'}
 if(-not(Test-Path -LiteralPath $marker)){throw 'Deinstallation hat gespeicherte Daten entfernt.'}
 Write-Output 'PASS: Setup, EXE-Start mit ETW, Update und Deinstallation; gespeicherte Daten erhalten.'
}finally{
 if(Get-Service NetzblickControl -ErrorAction SilentlyContinue){Stop-Service NetzblickControl -ErrorAction SilentlyContinue;& sc.exe delete NetzblickControl | Out-Null}
}

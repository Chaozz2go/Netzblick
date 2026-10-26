#requires -Version 5.1
param([string]$ExpectedCulture)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$setup=Join-Path $root 'dist-install\Netzblick-Setup-0.12.0-win-x64.exe'
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
 Run-Checked (Join-Path $installed 'Netzblick.exe') ('--smoke-test --report "'+$report+'"')
 if((Get-Content -LiteralPath $report -Raw) -notmatch 'PASS: EXE host; embedded assemblies; installed'){throw 'Installierte EXE nicht bestätigt.'}
 if($ExpectedCulture -and (Get-Content -LiteralPath $report -Raw) -notmatch ('Kultur='+[regex]::Escape($ExpectedCulture))){throw 'Erwartete Windows-Benutzerkultur wurde nicht im EXE-Prozess bestätigt.'}
 # Exercise the production complete-exit handler against the real service,
 # with a minimal window stub; then ensure a direct EXE launch restarts it.
 . (Join-Path $root 'src\SessionMode.ps1')
 $script:Portable=$false;$script:setupStatus=$null;$script:quitWindowClosed=$false
 $script:window=New-Object PSObject
 $window | Add-Member -MemberType ScriptMethod -Name Close -Value {$script:quitWindowClosed=$true}
 function Show-Error([string]$message){throw $message}
 Stop-NetzblickCompletely
 if(-not $quitWindowClosed -or (Get-Service NetzblickControl).Status -ne 'Stopped'){throw 'Vollständiges Beenden stoppt den Dienst nicht.'}
 Run-Checked (Join-Path $installed 'Netzblick.exe') ('--smoke-test --report "'+$report+'"')
 if((Get-Service NetzblickControl).Status -ne 'Running'){throw 'Erneuter EXE-Start startet den Dienst nicht.'}
 Write-Output 'PASS: vollständiges Beenden stoppt den Dienst; erneuter EXE-Start startet ihn wieder.'
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

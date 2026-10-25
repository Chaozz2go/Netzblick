#requires -Version 5.1
[CmdletBinding()]
param([switch]$Uninstall,[switch]$NoTray)
$ErrorActionPreference='Stop'
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=New-Object Security.Principal.WindowsPrincipal($identity)
if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
    $extra=if($Uninstall){' -Uninstall'}else{''};if($NoTray){$extra+=' -NoTray'}
    Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -Wait -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'"'+$extra)
    exit
}
if(-not [Environment]::Is64BitProcess){throw '64-Bit-Windows-PowerShell verwenden.'}
$target=Join-Path $env:ProgramFiles 'Netzblick'
$distribution=if($NetzblickDistributionRoot){$NetzblickDistributionRoot}else{$PSScriptRoot}
$exeDistribution=Test-Path -LiteralPath (Join-Path $distribution 'Netzblick.exe')
$data=Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'Netzblick'
$taskName='Netzblick Tray '+$identity.User.Value
function Invoke-Sc([string[]]$arguments){& "$env:SystemRoot\System32\sc.exe" @arguments | Write-Host;if($LASTEXITCODE -ne 0){throw ('Dienstverwaltung fehlgeschlagen: '+($arguments -join ' '))}}
function Protect-Directory([string]$path){
    $exists=Test-Path -LiteralPath $path
    if($exists){
        $owner=(Get-Acl -LiteralPath $path).GetOwner([Security.Principal.SecurityIdentifier]).Value
        if($owner -notin @('S-1-5-18','S-1-5-32-544')){throw 'Vorhandener Installations-/Datenordner gehört nicht SYSTEM oder Administratoren. Bitte vorab prüfen und umbenennen.'}
        foreach($item in Get-ChildItem -LiteralPath $path -Recurse -Force){if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Verknüpfung im vorhandenen Installations-/Datenordner gefunden.'}}
    }
    [void][IO.Directory]::CreateDirectory($path)
    if((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Installations-/Datenordner darf keine Verknüpfung sein.'}
    $acl=New-Object Security.AccessControl.DirectorySecurity;$acl.SetAccessRuleProtection($true,$false)
    foreach($sid in @('S-1-5-18','S-1-5-32-544')){$rule=New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)),'FullControl','ContainerInherit,ObjectInherit','None','Allow');$acl.AddAccessRule($rule)}
    $read=New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-545')),'ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow');if($path -ne $data){$acl.AddAccessRule($read)}
    Set-Acl -LiteralPath $path -AclObject $acl
}
try{
    $service=Get-Service -Name NetzblickControl -ErrorAction SilentlyContinue
    if($service){Stop-Service NetzblickControl;$service.WaitForStatus('Stopped',[timespan]::FromSeconds(20))}
    if($Uninstall){
        if($service){Invoke-Sc @('delete','NetzblickControl')}
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host 'Dienst und Tray-Autostart entfernt. Regeldatei und installierte Dateien bleiben als Sicherung erhalten. Frühere Windows-Firewallregeln werden nicht gelöscht.'
        Write-Output 'NETZBLICK_MAINTENANCE_OK'
        if($NetzblickDistributionRoot){return}else{exit 0}
    }
    Protect-Directory $target;Protect-Directory $data
    if([IO.Path]::GetFullPath($distribution) -ne [IO.Path]::GetFullPath($target)){
        $files=if($exeDistribution){@('Netzblick.exe','Netzblick.exe.config','README.md','PRUEFSTAND.txt','THIRD-PARTY-NOTICES.txt','lib','licenses')}else{@('Netzblick.ps1','Start-Netzblick.cmd','Install-Netzblick.ps1','Install-Netzblick.cmd','README.md','PRUEFSTAND.txt','THIRD-PARTY-NOTICES.txt','src','lib','data','docs')}
        foreach($name in $files){
            Copy-Item -LiteralPath (Join-Path $distribution $name) -Destination $target -Recurse -Force
        }
    }
    foreach($item in @(Get-ChildItem -LiteralPath $target -Recurse -Force)+@(Get-ChildItem -LiteralPath $data -Recurse -Force)){
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Verknüpfung im Installationsordner gefunden.'}
        $acl=if($item.PSIsContainer){New-Object Security.AccessControl.DirectorySecurity}else{New-Object Security.AccessControl.FileSecurity}
        $acl.SetAccessRuleProtection($false,$false);Set-Acl -LiteralPath $item.FullName -AclObject $acl
    }
    if(-not $service){Invoke-Sc @('create','NetzblickControl','binPath=',('"'+(Join-Path $target 'lib\Netzblick.Service.exe')+'"'),'start=','auto','depend=','BFE','DisplayName=','Netzblick Netzwerksteuerung')}
    Invoke-Sc @('failure','NetzblickControl','reset=','86400','actions=','restart/2000/restart/5000/restart/10000')
    Start-Service NetzblickControl
    $action=if($exeDistribution){New-ScheduledTaskAction -Execute (Join-Path $target 'Netzblick.exe') -Argument '--installed --tray'}else{New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument ('-NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $target 'Netzblick.ps1')+'" -Tray')}
    $trigger=New-ScheduledTaskTrigger -AtLogOn -User $identity.Name
    $taskPrincipal=New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Highest
    $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([timespan]::Zero) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $taskPrincipal -Settings $settings -Force | Out-Null
    if(-not $NoTray){
        if($exeDistribution){Start-Process -FilePath (Join-Path $target 'Netzblick.exe') -ArgumentList '--installed'}
        else{Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList ('-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $target 'Netzblick.ps1')+'"')}
    }
    Write-Host 'Netzblick installiert. Der Kontrollmodus wird erst nach deiner Entscheidung aktiviert.'
    Write-Output 'NETZBLICK_MAINTENANCE_OK'
}catch{throw}


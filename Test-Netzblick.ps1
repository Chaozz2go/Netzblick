#requires -Version 5.1
$ErrorActionPreference='Stop'
$files=@('Netzblick.ps1','src\VisualModes.ps1','src\InspectionMode.ps1','src\UserModes.ps1','src\FirewallNames.ps1','src\EndpointNames.ps1','src\AccessMode.ps1','src\PermissionMode.ps1','src\ProgramCatalog.ps1','src\ThemeMode.ps1','src\DesignMode.ps1','src\DirectionMode.ps1','src\ExperienceState.ps1','src\GuideMode.ps1','src\ChangePreview.ps1','src\HostsMode.ps1','src\DashboardMode.ps1','src\DashboardNavigation.ps1','src\WorkspaceMode.ps1','src\ActivityReview.ps1','src\TrayMode.ps1','src\ReviewMode.ps1','src\UpdatesMode.ps1','src\SessionMode.ps1','src\WorldNavigation.ps1','Install-Netzblick.ps1','tools\Build-Service.ps1','tools\Test-UI.ps1','tools\Test-ExperienceFixtures.ps1','Test-Netzblick.ps1')
foreach($file in $files){
    $tokens=$null;$errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $file),[ref]$tokens,[ref]$errors)
    if($errors.Count){$errors | ForEach-Object {Write-Host $_.ToString()};exit 1}
}
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Netzblick.ps1') -Check
exit $LASTEXITCODE



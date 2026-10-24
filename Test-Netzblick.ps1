#requires -Version 5.1
$ErrorActionPreference='Stop'
$files=@('Netzblick.ps1','src\VisualModes.ps1','src\InspectionMode.ps1','src\UserModes.ps1','Test-Netzblick.ps1')
foreach($file in $files){
    $tokens=$null;$errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $file),[ref]$tokens,[ref]$errors)
    if($errors.Count){$errors | ForEach-Object {Write-Host $_.ToString()};exit 1}
}
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Netzblick.ps1') -Check
exit $LASTEXITCODE

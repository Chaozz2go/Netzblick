function Get-OwnedRuleMarker([string]$path,[int]$direction){
    return 'Netzblick verwaltet; ID='+(Rule-Base $path)+$(if($direction -eq 1){'.In'}else{'.Out'})+';'
}
function Get-ReadableRuleName([string]$path,[int]$direction,[string]$mode){
    $program=[IO.Path]::GetFileName($path);$program=($program -replace '[\x00-\x1f|]',' ').Trim()
    if($program.Length -gt 80){$program=$program.Substring(0,80)}
    $action=if($mode -eq 'Private'){'Nur private Netze'}else{'Gesperrt'}
    $way=if($direction -eq 1){'Eingehend'}else{'Ausgehend'}
    $id=(Rule-Base $path).Substring('Netzblick.v1.'.Length,12)
    return 'Netzblick · '+$program+' · '+$action+' · '+$way+' [NB-'+$id+']'
}
function Test-OwnedNetworkRule($rule,[string]$path=''){
    if($rule.Grouping -ne $script:group -or -not $rule.ApplicationName -or $rule.Direction -notin @(1,2)){return $false}
    if($path -and [Netzblick.ProcessLineage]::Normalize($rule.ApplicationName) -ne [Netzblick.ProcessLineage]::Normalize($path)){return $false}
    $base=Rule-Base $rule.ApplicationName
    if($rule.Name -in @(($base+'.In'),($base+'.Out'))){return $true}
    foreach($direction in @(1,2)){
        $marker=Get-OwnedRuleMarker $rule.ApplicationName $direction
        if(([string]$rule.Description).StartsWith($marker,[StringComparison]::Ordinal) -and $rule.Name -in @((Get-ReadableRuleName $rule.ApplicationName $direction 'Blocked'),(Get-ReadableRuleName $rule.ApplicationName $direction 'Private'))){return $true}
    }
    return $false
}
function Assert-ReadableRuleNameAvailable([string]$path,[int]$direction,[string]$mode){
    $name=Get-ReadableRuleName $path $direction $mode
    foreach($rule in $policy.Rules){if($rule.Name -eq $name -and (-not (Test-OwnedNetworkRule $rule $path) -or $rule.Direction -ne $direction)){throw 'Der lesbare Regelname ist fremd belegt. Es wird keine fremde Regel verändert.'}}
}
function Rename-OwnedNetworkRules {
    $changed=$false;$historyChanged=$false
    $paths=@($policy.Rules | Where-Object {Test-OwnedNetworkRule $_} | ForEach-Object {$_.ApplicationName} | Select-Object -Unique)
    foreach($path in $paths){
        try{
            $before=@(Read-NetworkRules $path);$mode=Get-NetworkMode $path $before
            if($mode -notin @('Blocked','Private')){continue}
            foreach($direction in @(1,2)){Assert-ReadableRuleNameAvailable $path $direction $mode}
            $fingerprint=Get-NetworkFingerprint $before
            $rules=@($policy.Rules | Where-Object {Test-OwnedNetworkRule $_ $path})
            foreach($rule in $rules){
                $name=Get-ReadableRuleName $path $rule.Direction $mode;$marker=Get-OwnedRuleMarker $path $rule.Direction
                if($rule.Name -eq $name -and ([string]$rule.Description).StartsWith($marker,[StringComparison]::Ordinal)){continue}
                $rule.Description=$marker+' Programm: '+$path;$rule.Name=$name;$changed=$true
            }
            $after=Get-NetworkFingerprint @(Read-NetworkRules $path)
            foreach($change in $script:changes){if($change.Version -eq 1 -and [Netzblick.ProcessLineage]::Normalize($change.Path) -eq [Netzblick.ProcessLineage]::Normalize($path) -and $change.Fingerprint -eq $fingerprint){$change.Fingerprint=$after;$historyChanged=$true}}
        }catch{$ui.UserNotice.Text='Regelnamen konnten für '+[IO.Path]::GetFileName($path)+' nicht umgestellt werden: '+$_.Exception.Message}
    }
    if($historyChanged){Save-UserState}
    if($changed){Refresh-Rules}
}

#requires -Version 5.1
$ErrorActionPreference='Stop'
trap {$failure=$_;Write-Output $failure.ToString();Write-Output $failure.ScriptStackTrace;Write-Output $failure.InvocationInfo.PositionMessage;throw $failure}
if($env:GITHUB_ACTIONS -ne 'true'){throw 'Nur auf isolierten Windows-Runnern ausführen.'}
$root=Split-Path $PSScriptRoot -Parent
Add-Type -ReferencedAssemblies @('System.dll','System.Core.dll','System.Xml.dll','System.Numerics.dll') -Path @((Join-Path $root 'src\InspectionCore.cs'),(Join-Path $root 'src\AccessCore.cs'),(Join-Path $root 'src\NetworkPolicyCore.cs'))
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Netzblick.ps1'),[ref]$tokens,[ref]$errors)
$definition=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Rule-Base'},$true)
Invoke-Expression $definition.Extent.Text
. (Join-Path $root 'src\FirewallNames.ps1')
. (Join-Path $root 'src\UserModes.ps1')
$script:policy=New-Object -ComObject HNetCfg.FwPolicy2
$script:group='Netzblick.CI.Names.'+[guid]::NewGuid().ToString('N');$foreignGroup=$group+'.foreign'
$script:changes=New-Object 'System.Collections.Generic.List[object]';$script:ui=@{UserNotice=[pscustomobject]@{Text=''}};$script:saved=$false
function Refresh-Rules {}
function Save-UserState {$script:saved=$true}
$directory=Join-Path $env:RUNNER_TEMP ('NetzblickNames-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($directory)
$fixture=Join-Path $directory 'Steam-Fixture.exe';Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\where.exe') -Destination $fixture
function New-FixtureRule([string]$name,[string]$groupName,[int]$direction){
 $r=New-Object -ComObject HNetCfg.FWRule;$r.Name=$name;$r.Description='Fixture original';$r.ApplicationName=$fixture;$r.Protocol=256;$r.Direction=$direction;$r.Action=0;$r.Profiles=2147483647;$r.Grouping=$groupName;$r.RemoteAddresses='*';$r.LocalAddresses='*';$r.InterfaceTypes='All';$r.Enabled=$true;Write-Output ('Adding fixture rule: '+$r.Name+'; group='+$r.Grouping+'; direction='+$r.Direction+'; protocol='+$r.Protocol+'; path='+$r.ApplicationName);$policy.Rules.Add($r)
}
try{
 $base=Rule-Base $fixture
 New-FixtureRule ($base+'.In') $group 1;New-FixtureRule ($base+'.Out') $group 2
 New-FixtureRule 'Andere Software – unverändert' $foreignGroup 2
 $snapshot=@(Read-NetworkRules $fixture);if($snapshot.Count -ne 2 -or (Get-NetworkMode $fixture) -ne 'Blocked'){throw 'Alte Regelidentität nicht erkannt.'}
 $changes.Add([pscustomobject]@{Version=1;Path=$fixture;Fingerprint=(Get-NetworkFingerprint $snapshot)})
 # A foreign collision must prevent renaming, without changing either rule.
 $collisionName=Get-ReadableRuleName $fixture 2 'Blocked';New-FixtureRule $collisionName $foreignGroup 2
 Rename-OwnedNetworkRules
 if(@(Read-NetworkRules $fixture | Where-Object {$_.Name -like 'Netzblick.v1.*'}).Count -ne 2){throw 'Fremde Namenskollision verändert eigene Regeln.'}
 $policy.Rules.Remove($collisionName);Rename-OwnedNetworkRules
 $current=@(Read-NetworkRules $fixture)
 if($current.Count -ne 2 -or (Get-NetworkMode $fixture) -ne 'Blocked' -or @($current | Where-Object {$_.Name -notlike 'Netzblick · Steam-Fixture.exe · Gesperrt · *'}).Count){throw 'Migration verliert Programmname, Aktion, Richtung oder Sperrwirkung.'}
 if($changes[0].Fingerprint -ne (Get-NetworkFingerprint $current)){throw 'Migration erhält gültiges Rückgängig nicht.'}
 Rename-OwnedNetworkRules
 if(@(Read-NetworkRules $fixture).Count -ne 2){throw 'Wiederholter Start dupliziert Regeln.'}
 Write-NetworkMode $fixture 'Private'
 if((Get-NetworkMode $fixture) -ne 'Private' -or @(Read-NetworkRules $fixture | Where-Object {$_.Name -notlike '*Nur private Netze*'}).Count){throw 'Private-Netze-Modus nach Umbenennung fehlerhaft.'}
 Write-NetworkMode $fixture 'Default'
 if(@(Read-NetworkRules $fixture).Count){throw 'Lesbar benannte Regeln nicht entfernbar.'}
 Write-NetworkMode $fixture 'Blocked'
 if(@(Read-NetworkRules $fixture).Count -ne 2){throw 'Neue lesbare Regeln nicht erkennbar.'}
 $first=@($policy.Rules | Where-Object {Test-OwnedNetworkRule $_ $fixture})[0];$first.Protocol=6
 $modified=Get-NetworkFingerprint @(Read-NetworkRules $fixture);Rename-OwnedNetworkRules
 if((Get-NetworkMode $fixture) -ne 'Modified' -or $modified -ne (Get-NetworkFingerprint @(Read-NetworkRules $fixture))){throw 'Extern geänderte Regeln wurden verdeckt oder überschrieben.'}
 $foreign=$policy.Rules.Item('Andere Software – unverändert')
 if($foreign.Grouping -ne $foreignGroup -or $foreign.Description -ne 'Fixture original' -or $foreign.Protocol -ne 256 -or -not $foreign.Enabled){throw 'Fremde Regel verändert.'}
 Write-Output 'PASS: echte Windows-Firewallnamen mit Programm/Aktion/Richtung, Migration, Namenskollision, Rückgängig, Privatmodus, Entfernen, wiederholter Start und unveränderte Fremdregeln.'
}finally{
 foreach($r in @($policy.Rules | Where-Object {$_.ApplicationName -eq $fixture -and $_.Grouping -in @($group,$foreignGroup)})){$policy.Rules.Remove($r.Name)}
 Remove-Item -LiteralPath $directory -Recurse -Force
}

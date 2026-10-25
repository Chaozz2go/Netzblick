# Socket snapshots omit connections denied before they can be established.
# Keep configured paths and actual block evidence as separate catalog sources.
function Get-ProgramCatalog($socketRows,$samples,$pending,$status,$legacyRules){
    $catalog=@{}
    foreach($row in @($socketRows)){
        if(-not $row){continue}
        $key=if($row.Path){[Netzblick.ProcessLineage]::Normalize($row.Path)}else{'PID:'+$row.Pid}
        if(-not $catalog.ContainsKey($key)){$catalog[$key]=[pscustomobject]@{Key=$key;Name=$row.Program;Path=$row.Path;Summary='';Rows=@();Observed=$true;Saved=$false;BlockCount=[long]0;BlockSummary='';LastBlockUtc=$null;BlockedTargets=''}}
        $catalog[$key].Rows+=@($row)
    }
    $sources=@($samples)+@($pending)
    foreach($item in $sources){
        if(-not $item -or -not [Netzblick.AccessQueue]::CanAllow($item.Path)){continue}
        $key=[Netzblick.ProcessLineage]::Normalize($item.Path)
        if(-not $catalog.ContainsKey($key)){$catalog[$key]=[pscustomobject]@{Key=$key;Name=$item.Name;Path=$item.Path;Summary='';Rows=@();Observed=$true;Saved=$false;BlockCount=[long]0;BlockSummary='';LastBlockUtc=$null;BlockedTargets=''}}
    }
    $paths=@($legacyRules | ForEach-Object {$_.Path})
    if($status -and $status.Config){$paths+=@($status.Config.WatchedPaths)+@($status.Config.Rules | ForEach-Object {$_.Path})}
    foreach($path in $paths){
        if(-not [Netzblick.AccessQueue]::CanAllow($path)){continue}
        $key=[Netzblick.ProcessLineage]::Normalize($path)
        if(-not $catalog.ContainsKey($key)){$catalog[$key]=[pscustomobject]@{Key=$key;Name=[IO.Path]::GetFileName($path);Path=$path;Summary='';Rows=@();Observed=$false;Saved=$true;BlockCount=[long]0;BlockSummary='';LastBlockUtc=$null;BlockedTargets=''}}
        $catalog[$key].Saved=$true
    }
    if($status){foreach($attempt in @($status.Attempts)){
        if(-not $attempt -or -not [Netzblick.AccessQueue]::CanAllow($attempt.Path)){continue}
        $key=[Netzblick.ProcessLineage]::Normalize($attempt.Path)
        if(-not $catalog.ContainsKey($key)){$catalog[$key]=[pscustomobject]@{Key=$key;Name=$attempt.Program;Path=$attempt.Path;Summary='';Rows=@();Observed=$true;Saved=$false;BlockCount=[long]0;BlockSummary='';LastBlockUtc=$null;BlockedTargets=''}}
        $p=$catalog[$key];$p.Observed=$true;$p.BlockCount+=[long]$attempt.Count
        if(-not $p.LastBlockUtc -or $attempt.LastUtc -gt $p.LastBlockUtc){$p.LastBlockUtc=$attempt.LastUtc}
        $p.BlockedTargets+=' '+$attempt.Target
    }}
    foreach($p in $catalog.Values){
        $base=if($p.Rows.Count){$p.Rows.Count.ToString()+' sichtbare Sockets'}elseif($p.Saved){'Gespeicherte Regel · kein Socket sichtbar'}else{'In dieser Sitzung erfasst · kein Socket sichtbar'}
        if($p.BlockCount){$p.BlockSummary=$p.BlockCount.ToString()+' blockierte Versuche · zuletzt '+$p.LastBlockUtc.ToLocalTime().ToString('HH:mm:ss');$p.Summary=$p.BlockSummary+[Environment]::NewLine+$base}else{$p.Summary=$base}
        $p
    }
}
function Get-ProgramBlockRows([string]$path,$status){
    if(-not $status){return}
    $key=[Netzblick.ProcessLineage]::Normalize($path)
    foreach($a in @($status.Attempts | Where-Object {[Netzblick.ProcessLineage]::Normalize($_.Path) -eq $key})){
        [pscustomobject]@{Key=('BLOCK|'+$a.Key);Pid='Blockereignis';Protocol=[Netzblick.SetupRule]::ProtocolName($a.Protocol);Local=$a.Direction;Remote=$a.Target;Address=$a.Address;Port=$a.Port;State=('Blockiert · '+$a.Count+' Versuche · zuletzt '+$a.LastUtc.ToLocalTime().ToString('HH:mm:ss')+' · '+$a.Evidence)}
    }
}

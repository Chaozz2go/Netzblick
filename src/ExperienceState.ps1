# Local bounded presentation history and pinned paths, independent of firewall policy.
function Read-ExperienceState {
    $script:favoritePrograms=@{};$script:programTimeline=New-Object 'System.Collections.Generic.List[object]'
    if(-not [IO.File]::Exists($experienceFile)){return}
    $file=Get-Item -LiteralPath $experienceFile
    if($file.Length -gt 2000000){throw 'Favoriten-/Zeitstrahldatei ist zu groß; vorhandene Datei bleibt erhalten.'}
    $saved=Get-Content -LiteralPath $experienceFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if($saved.Version -ne 1){throw 'Unbekanntes Favoriten-/Zeitstrahlformat; vorhandene Datei bleibt erhalten.'}
    foreach($p in @($saved.Favorites | Select-Object -First 50)){
        if($p -is [string] -and $p.Length -le 1024 -and [Netzblick.AccessQueue]::CanAllow($p)){$favoritePrograms[[Netzblick.ProcessLineage]::Normalize($p)]=$p}
    }
    foreach($e in @($saved.Timeline | Select-Object -Last 400)){
        $utc=[datetime]::MinValue
        if($e.Path -is [string] -and $e.Path.Length -le 1024 -and ($e.Path -eq '*' -or [Netzblick.AccessQueue]::CanAllow($e.Path)) -and $e.Kind -is [string] -and $e.Kind.Length -le 100 -and $e.Detail -is [string] -and $e.Detail.Length -le 800 -and [datetime]::TryParse([string]$e.TimeUtc,[ref]$utc)){
            $programTimeline.Add([pscustomobject]@{Id=[guid]::NewGuid().ToString('N');Path=$e.Path;Kind=$e.Kind;Detail=$e.Detail;TimeUtc=$utc.ToUniversalTime()})
        }
    }
}
function Save-ExperienceState {
    param([switch]$ThrowOnError)
    if(-not $script:experienceReady -or $script:experienceReadOnly){if($ThrowOnError){throw 'Gespeicherte Favoriten konnten nicht gelesen werden; Datei wird nicht überschrieben.'};return}
    try{
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($experienceFile))
        $text=@{Version=1;Favorites=@($favoritePrograms.Values | Sort-Object);Timeline=@($programTimeline.ToArray())} | ConvertTo-Json -Depth 6
        $temp=$experienceFile+'.tmp';[IO.File]::WriteAllText($temp,$text,[Text.UTF8Encoding]::new($false))
        if([IO.File]::Exists($experienceFile)){[IO.File]::Replace($temp,$experienceFile,$experienceFile+'.bak')}else{[IO.File]::Move($temp,$experienceFile)}
        $script:experienceDirty=$false;$script:experienceSavedUtc=[datetime]::UtcNow
    }catch{if($ThrowOnError){throw};$ui.UserNotice.Text='Favoriten/Zeitstrahl konnten nicht gespeichert werden: '+$_.Exception.Message}
}
function Add-ProgramTimeline([string]$path,[string]$kind,[string]$detail,[datetime]$timeUtc=[datetime]::UtcNow){
    if(-not $script:experienceReady -or -not $path -or $path.Length -gt 1024 -or ($path -ne '*' -and -not [Netzblick.AccessQueue]::CanAllow($path))){return}
    if($kind.Length -gt 100){$kind=$kind.Substring(0,100)}
    if($detail.Length -gt 800){$detail=$detail.Substring(0,780)+' … (gekürzt)'}
    $programTimeline.Add([pscustomobject]@{Id=[guid]::NewGuid().ToString('N');Path=$path;Kind=$kind;Detail=$detail;TimeUtc=$timeUtc.ToUniversalTime()})
    while($programTimeline.Count -gt 400){$programTimeline.RemoveAt(0)}
    $script:experienceDirty=$true
}
function Get-FavoriteCatalogEntries {
    if(-not $script:experienceReady){return}
    foreach($path in $favoritePrograms.Values){[pscustomobject]@{Path=$path;Name=[IO.Path]::GetFileName($path);Historical=$true}}
}
function Set-ProgramFavorite([string]$path,[bool]$favorite){
    if(-not [Netzblick.AccessQueue]::CanAllow($path) -or $path.Length -gt 1024){throw 'Ein vollständiger lokaler Programmpfad wird benötigt (maximal 1024 Zeichen).'}
    $key=[Netzblick.ProcessLineage]::Normalize($path);$old=$favoritePrograms[$key]
    if($favorite -and -not $old -and $favoritePrograms.Count -ge 50){throw 'Maximal 50 Favoriten. Zuerst einen entfernen.'}
    if($favorite){$favoritePrograms[$key]=$path}else{$favoritePrograms.Remove($key)}
    try{Save-ExperienceState -ThrowOnError}catch{if($old){$favoritePrograms[$key]=$old}else{$favoritePrograms.Remove($key)};throw}
    Refresh-Favorites;Update-FavoriteButtons
}
function Update-FavoriteButtons {
    if(-not $script:experienceReady){return}
    foreach($prefix in @('Program','Overview')){
        $p=if($prefix -eq 'Program'){$ui.Programs.SelectedItem}else{$ui.OverviewPrograms.SelectedItem}
        $valid=$p -and $p.Path -and $p.Path.Length -le 1024 -and [Netzblick.AccessQueue]::CanAllow($p.Path)
        $ui[$prefix+'Favorite'].IsEnabled=[bool]($valid -and -not $script:experienceReadOnly)
        $marked=$valid -and $favoritePrograms.ContainsKey([Netzblick.ProcessLineage]::Normalize($p.Path))
        $ui[$prefix+'Favorite'].Content=if($prefix -eq 'Overview'){$(if($marked){'★ Gemerkt'}else{'☆ Merken'})}else{$(if($marked){'★ Favorit entfernen'}else{'☆ Als Favorit merken'})}
    }
}
function Get-ProgramLeaseText([string]$path){
    if(-not $script:setupStatus -or -not $setupStatus.Verified){return 'Sperrwirkung unbestätigt'}
    $key=[Netzblick.ProcessLineage]::Normalize($path)
    $lease=$setupStatus.Config.ProgramLeases | Where-Object {[Netzblick.ProcessLineage]::Normalize($_.Path) -eq $key} | Select-Object -First 1
    if(-not $lease){return 'Keine zeitweise Entscheidung'}
    $action=if($lease.EffectiveAction -eq 'Block'){'Gesperrt'}else{'Erlaubt'}
    if($lease.UntilResumed){return $action+' · bis aufgehoben'}
    $seconds=[Math]::Max(0,[int][Math]::Ceiling(($lease.ExpiresUtc-[datetime]::UtcNow).TotalSeconds))
    if($seconds -eq 0){return 'Frist abgelaufen · Dienstbestätigung abwarten'}
    return $action+' · noch '+[Math]::Floor($seconds/60).ToString('0')+':'+($seconds%60).ToString('00')
}
function Refresh-Favorites {
    if(-not $script:experienceReady){return}
    $selected=if($ui.FavoritesList.SelectedItem){$ui.FavoritesList.SelectedItem.Key}else{''}
    $entries=@(foreach($path in $favoritePrograms.Values){
        $key=[Netzblick.ProcessLineage]::Normalize($path);$s=Get-PermissionStatus $path
        $catalog=$script:allProgramItems | Where-Object Key -eq $key | Select-Object -First 1
        [pscustomobject]@{Key=$key;Path=$path;Name=[IO.Path]::GetFileNameWithoutExtension($path);Icon=(Get-ApplicationIcon $path -Always);SignalColor=$s.SignalColor;Status=$s.Status;LeaseText=(Get-ProgramLeaseText $path);Activity=$(if($catalog){Get-ProgramDirectionSummary $catalog}else{'Kein Socket in der aktuellen Stichprobe'})}
    })
    $script:favoritesRefreshing=$true
    try{$ui.FavoritesList.ItemsSource=@($entries | Sort-Object Name);$ui.FavoritesList.SelectedItem=$ui.FavoritesList.Items | Where-Object Key -eq $selected | Select-Object -First 1;if(-not $selected -and $entries.Count){$ui.FavoritesList.SelectedIndex=0}}finally{$script:favoritesRefreshing=$false}
    $ui.FavoritesEmpty.Visibility=if($entries.Count){'Collapsed'}else{'Visible'}
    Show-FavoriteSelection
}
function Show-FavoriteSelection {
    $p=$ui.FavoritesList.SelectedItem;$valid=$p -and [Netzblick.AccessQueue]::CanAllow($p.Path)
    $ready=$valid -and $script:setupStatus -and $setupStatus.Verified
    $lease=if($ready){$setupStatus.Config.ProgramLeases | Where-Object {[Netzblick.ProcessLineage]::Normalize($_.Path) -eq $p.Key} | Select-Object -First 1}else{$null}
    $ui.FavoriteBlock.IsEnabled=[bool]($ready -and [IO.File]::Exists($p.Path) -and -not(Is-Protected $p.Path) -and -not $lease)
    $ui.FavoriteResume.IsEnabled=[bool]($ready -and $lease -and -not(Is-Protected $p.Path))
    $ui.FavoriteRemove.IsEnabled=[bool]($valid -and -not $script:experienceReadOnly)
    $ui.FavoriteDetails.IsEnabled=[bool]$valid
    $ui.FavoritePath.Text=if($valid){$p.Path}else{'Einen Favoriten auswählen. Auch Programme ohne aktuellen Netzwerkzugriff bleiben hier sichtbar.'}
}
function Update-ProgramTimeline {
    if(-not $script:experienceReady){return}
    $p=$ui.Programs.SelectedItem
    if(-not $p){$ui.ProgramTimeline.ItemsSource=@();$ui.TimelineDetail.Text='Programm auswählen.';return}
    $key=[Netzblick.ProcessLineage]::Normalize($p.Path);$selected=if($ui.ProgramTimeline.SelectedItem){$ui.ProgramTimeline.SelectedItem.Id}else{''}
    $entries=@($programTimeline | Where-Object {$_.Path -eq '*' -or [Netzblick.ProcessLineage]::Normalize($_.Path) -eq $key} | Sort-Object TimeUtc -Descending | ForEach-Object {[pscustomobject]@{Id=$_.Id;Time=([datetime]$_.TimeUtc).ToLocalTime().ToString('dd.MM. HH:mm:ss');Kind=$_.Kind;Detail=$_.Detail}})
    $ui.ProgramTimeline.ItemsSource=$entries;$ui.ProgramTimeline.SelectedItem=$entries | Where-Object Id -eq $selected | Select-Object -First 1
    if(-not $ui.ProgramTimeline.SelectedItem -and $entries.Count){$ui.ProgramTimeline.SelectedIndex=0}
    if(-not $entries.Count){$ui.TimelineDetail.Text='Noch keine passenden Ereignisse aufgezeichnet. Das beweist keinen fehlenden Netzwerkzugriff.'}
}
function Update-ExperienceObservations([datetime]$sampleUtc){
    if(-not $script:experienceReady){return}
    $current=@{}
    foreach($row in $script:rows){
        if(-not $row.Path){continue};$start=if($row.ProcessStartUtc){([datetime]$row.ProcessStartUtc).Ticks}else{0};$key=$start.ToString()+'|'+$row.Key;$current[$key]=$true
        if(-not $script:timelineSockets.ContainsKey($key)){$d=Get-ConnectionDirection $row $row.Path;Add-ProgramTimeline $row.Path 'Socket beobachtet' ('PID '+$row.Pid+' · '+$row.Protocol+' · '+$d.Label+' · lokal '+$row.Local+' · Gegenstelle '+$row.Remote+' · '+$row.State+'. Stichprobe, kein Nachweis des tatsächlichen Startzeitpunkts.') $sampleUtc}
    }
    $script:timelineSockets=$current
    Update-ExperienceBlocks
    Update-ProgramTimeline
}
function Update-ExperienceBlocks {
    if(-not $script:experienceReady){return}
    $health=if($script:setupStatus){[string]$setupStatus.Verified+'|'+$setupStatus.Warning}else{'unreachable'}
    if($health -ne $script:timelineHealth){$script:timelineHealth=$health;Add-ProgramTimeline '*' 'Erfassungsstatus' $(if($script:setupStatus -and $setupStatus.Verified){'Filterstatus bestätigt. '+$setupStatus.Warning}else{'Filterdienst nicht bestätigt/erreichbar. Blockanzeige und Sperrwirkung können unvollständig sein.'})}
    if($script:setupStatus){
        $fresh=@{}
        foreach($a in $setupStatus.Attempts){
            $key=$setupStatus.StartedUtc.ToString('o')+'|'+$a.Key;$prior=$script:timelineBlockCounts[$key];$fresh[$key]=[long]$a.Count
            $delta=if($null -eq $prior){[long]$a.Count}else{[Math]::Max(0,[long]$a.Count-[long]$prior)}
            if($delta -gt 0){Add-ProgramTimeline $a.Path 'Blockversuche erfasst' ($delta.ToString()+' Versuche · '+$a.Direction+' · '+$a.Target+' · '+$a.Evidence+'. Gesammelt seit '+$a.FirstUtc.ToLocalTime().ToString('dd.MM. HH:mm:ss')+'; letzte Beobachtung. Keine sichere Zuordnung zu einem Dienst.') $a.LastUtc}
        }
        $script:timelineBlockCounts=$fresh
    }
    if($script:experienceDirty -and ([datetime]::UtcNow-$script:experienceSavedUtc).TotalSeconds -ge 5){Save-ExperienceState}
}
function Reset-ExperienceHistory {
    if(-not $script:experienceReady){return}
    $programTimeline.Clear();$script:timelineSockets=@{};$script:timelineBlockCounts=@{};$script:timelineHealth='';$script:guideQueue=@();$script:guideSnapshot=$null;$script:guideEpoch=[guid]::NewGuid().ToString('N')
    Add-ProgramTimeline '*' 'Neu begonnen' 'Prüfungen und Zeitstrahl zurückgesetzt. Favoriten bleiben erhalten.'
    Save-ExperienceState;Update-ProgramTimeline;Refresh-Guide
}
function Initialize-ExperienceState {
    $script:experienceFile=Join-Path $userStateDirectory 'experience-state.json';$script:experienceReadOnly=$false
    $script:experienceSavedUtc=[datetime]::UtcNow;$script:experienceDirty=$false;$script:timelineSockets=@{};$script:timelineBlockCounts=@{};$script:timelineHealth=''
    try{Read-ExperienceState}catch{$script:experienceReadOnly=$true;$ui.UserNotice.Text='Favoriten/Zeitstrahl nicht geladen: '+$_.Exception.Message}
    $script:experienceReady=$true
    Add-ProgramTimeline '*' 'Erfassung begonnen' 'Netzblick gestartet. Zwischen Starts, bei Pausen oder Erfassungsfehlern besteht keine lückenlose Aufzeichnung. Maximal 400 Ereignisse für alle Programme zusammen.'
    foreach($prefix in @('Program','Overview')){$ui[$prefix+'Favorite'].Tag=$prefix;$ui[$prefix+'Favorite'].Add_Click({param($sender,$e) $p=if($sender.Tag -eq 'Program'){$ui.Programs.SelectedItem}else{$ui.OverviewPrograms.SelectedItem};if($p){try{Set-ProgramFavorite $p.Path (-not $favoritePrograms.ContainsKey([Netzblick.ProcessLineage]::Normalize($p.Path)))}catch{Show-Error $_.Exception.Message}}})}
    $ui.FavoritesList.Add_SelectionChanged({if(-not $script:favoritesRefreshing){Show-FavoriteSelection}})
    $ui.FavoriteBlock.Add_Click({if($ui.FavoritesList.SelectedItem){Confirm-PermissionChange 'TemporaryBlockProgram' $ui.FavoritesList.SelectedItem.Path}})
    $ui.FavoriteResume.Add_Click({if($ui.FavoritesList.SelectedItem){Confirm-PermissionChange 'EndProgramLease' $ui.FavoritesList.SelectedItem.Path}})
    $ui.FavoriteRemove.Add_Click({if($ui.FavoritesList.SelectedItem){try{Set-ProgramFavorite $ui.FavoritesList.SelectedItem.Path $false}catch{Show-Error $_.Exception.Message}}})
    $ui.FavoriteDetails.Add_Click({if($ui.FavoritesList.SelectedItem){Show-ReviewProgram $ui.FavoritesList.SelectedItem.Path}})
    $ui.ProgramTimeline.Add_SelectionChanged({$ui.TimelineDetail.Text=if($ui.ProgramTimeline.SelectedItem){$ui.ProgramTimeline.SelectedItem.Detail}else{'Ereignis auswählen.'}})
    $window.Add_Closed({Add-ProgramTimeline '*' 'Erfassung beendet' 'Netzblick vollständig beendet. Bis zum nächsten Start keine Aufzeichnung durch die Oberfläche.';Save-ExperienceState})
    Refresh-Favorites;Update-FavoriteButtons
}

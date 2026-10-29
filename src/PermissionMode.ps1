function Get-PermissionStatus([string]$path){
    $key=[Netzblick.ProcessLineage]::Normalize($path)
    $category=if($script:setupStatus -and $setupStatus.Config){[Netzblick.ProgramPolicy]::Category($setupStatus.Config,$path)}else{'Unknown'}
    $legacy=@($script:ownRules | Where-Object {[Netzblick.ProcessLineage]::Normalize($_.Path) -eq $key})
    if($legacy.Count){$mode=try{Get-NetworkMode $path $legacy}catch{'Modified'};if($mode -eq 'Blocked'){$category='Blocked'}elseif($category -ne 'Blocked'){$category='Limited'}}
    if(-not $script:setupStatus -or -not $setupStatus.Verified){$category='Unknown'}
    if(-not [Netzblick.AccessQueue]::CanAllow($path)){$category='Unknown'}
    $label=switch($category){'Blocked'{'Gesperrt'} 'Limited'{'Teilweise eingeschränkt'} 'Allowed'{'Erlaubt (Netzblick)'} 'Default'{'Windows-Standard'} default{'Status unbestätigt'}}
    $color=switch($category){'Blocked'{(Get-ThemeColor '#B32D40')} 'Limited'{(Get-ThemeColor '#996000')} 'Allowed'{(Get-ThemeColor '#08704E')} default{(Get-ThemeColor '#57677B')}}
    $signal=if($category -eq 'Default'){(Get-ThemeColor '#08704E')}else{$color}
    $hint=$label+' · neue externe Verbindungen. '+$(if($category -eq 'Default'){'Netzblick lässt im Beobachten-Modus durch; Windows kann zusätzlich sperren.'}else{'Windows und andere Sicherheitsprogramme können zusätzlich sperren.'})
    [pscustomobject]@{Category=$category;Status=$label;Color=$color;SignalColor=$signal;SignalHint=$hint;Legacy=($legacy.Count -gt 0)}
}
function Open-Permissions([string]$path=''){
    Show-Panel 'AccessPanel';$ui.AccessViews.SelectedIndex=1;$ui.PermissionFilter.SelectedIndex=0;$ui.PermissionSearch.Text='';Refresh-Permissions
    if($path){$key=[Netzblick.ProcessLineage]::Normalize($path);$ui.PermissionPrograms.SelectedItem=$ui.PermissionPrograms.Items | Where-Object {$_.Key -eq $key} | Select-Object -First 1;Show-PermissionSelection}
}
function Initialize-PermissionMode {
    $script:permissionRefreshing=$false
    $ui.ProgramAccessRules.Add_Click({if($ui.Programs.SelectedItem){Open-Permissions $ui.Programs.SelectedItem.Path}})
    $ui.OverviewPermissions.Add_Click({Open-Permissions $(if($ui.OverviewPrograms.SelectedItem){$ui.OverviewPrograms.SelectedItem.Path}else{''})})
    $ui.PermissionFilter.Add_SelectionChanged({if(-not $script:permissionRefreshing){Refresh-Permissions}})
    $ui.PermissionSearch.Add_TextChanged({if(-not $script:permissionRefreshing){Refresh-Permissions}})
    $ui.PermissionPrograms.Add_SelectionChanged({if(-not $script:permissionRefreshing){Show-PermissionSelection}})
    $ui.PermissionAllow.Add_Click({Confirm-PermissionChange 'AllowProgram'})
    $ui.PermissionBlock.Add_Click({Confirm-PermissionChange 'BlockProgram'})
    $ui.PermissionDefault.Add_Click({Confirm-PermissionChange 'ProgramDefault'})
    $ui.PermissionShow.Add_Click({if($ui.PermissionPrograms.SelectedItem){Show-ReviewProgram $ui.PermissionPrograms.SelectedItem.Path}})
    $ui.PermissionLegacy.Add_Click({Show-Panel 'RulesPanel'})
    $ui.SetupRules.Add_SelectionChanged({$ui.RemoveSetupRule.IsEnabled=[bool]($ui.SetupRules.SelectedItem -and $script:setupStatus -and $setupStatus.Verified)})
}
function Refresh-Permissions {
    if(-not $ui.ContainsKey('PermissionPrograms') -or $script:permissionRefreshing){return}
    $script:permissionRefreshing=$true
    try{
        $selected=$ui.PermissionPrograms.SelectedItem;$key=if($selected){$selected.Key}else{''}
        $programs=@{}
        foreach($p in @($script:allProgramItems)+@($script:newPrograms.Values)+@($script:ownRules)){
            if($p -and [Netzblick.AccessQueue]::CanAllow($p.Path)){$k=[Netzblick.ProcessLineage]::Normalize($p.Path);$programs[$k]=[pscustomobject]@{Key=$k;Path=$p.Path;Name=[IO.Path]::GetFileName($p.Path)}}
        }
        $entries=New-Object 'System.Collections.Generic.List[object]'
        if($script:setupStatus -and $setupStatus.Config){
            foreach($path in @($setupStatus.Config.WatchedPaths)+@($setupStatus.Config.Rules | ForEach-Object {$_.Path})+@($setupStatus.Attempts | ForEach-Object {$_.Path})){
                if([Netzblick.AccessQueue]::CanAllow($path)){$k=[Netzblick.ProcessLineage]::Normalize($path);$programs[$k]=[pscustomobject]@{Key=$k;Path=$path;Name=[IO.Path]::GetFileName($path)}}
            }
            foreach($rule in $setupStatus.Config.Rules){$entries.Add([pscustomobject]@{Id=$rule.Id;Name=$rule.Name;ActionLabel=$(if($rule.Action -eq 'Block'){'Sperren'}else{'Erlauben'});Scope=$rule.Scope;Lifetime=$rule.Lifetime;Kind='Rule';Path=$rule.Path})}
            foreach($path in $setupStatus.Config.WatchedPaths){$entries.Add([pscustomobject]@{Id=('watch:'+([Netzblick.ProcessLineage]::Normalize($path)));Name=('Prüfsperre: '+[IO.Path]::GetFileName($path));ActionLabel='Sperren';Scope=($path+' · beide Richtungen · Ausnahmen durch Freigaben');Lifetime='Bis aufgehoben';Kind='Watch';Path=$path})}
            if($setupStatus.Config.Ask){$entries.Add([pscustomobject]@{Id='ask';Name='Unbekannte Verbindungen';ActionLabel='Sperren';Scope='Alle Programme · beide Richtungen · ohne passende Freigabe';Lifetime='Bis ausgeschaltet';Kind='Ask';Path='*'})}
        }
        $items=@(foreach($p in $programs.Values){$s=Get-PermissionStatus $p.Path;$pending=$script:newPrograms -and $newPrograms.ContainsKey($p.Key);[pscustomobject]@{Key=$p.Key;Name=$p.Name;Path=$p.Path;Status=$s.Status;Category=$s.Category;Color=$s.Color;Legacy=$s.Legacy;Pending=[bool]$pending;Review=$(if($pending){'Noch ungeprüft'}else{'Beobachtet'})}})
        $ui.PermissionSummary.Text=(@($items | Where-Object Category -eq 'Blocked').Count.ToString()+' gesperrt · '+@($items | Where-Object Category -eq 'Limited').Count+' teilweise · '+@($items | Where-Object Category -eq 'Allowed').Count+' erlaubt · '+@($items | Where-Object Category -eq 'Default').Count+' Windows-Standard · '+@($items | Where-Object Category -eq 'Unknown').Count+' unbestätigt')
        $category=switch($ui.PermissionFilter.SelectedIndex){1{'Blocked'} 2{'Limited'} 3{'Allowed'} 4{'Default'} default{''}}
        $search=$ui.PermissionSearch.Text.Trim()
        $visible=@($items | Where-Object {(-not $category -or $_.Category -eq $category) -and ($ui.PermissionFilter.SelectedIndex -ne 5 -or $_.Pending) -and (-not $search -or $_.Path.IndexOf($search,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or $_.Name.IndexOf($search,[StringComparison]::OrdinalIgnoreCase) -ge 0)} | Sort-Object Name,Path)
        $ui.PermissionPrograms.ItemsSource=$visible
        $match=$visible | Where-Object {$_.Key -eq $key} | Select-Object -First 1
        if($match){$ui.PermissionPrograms.SelectedItem=$match}elseif($visible.Count){$ui.PermissionPrograms.SelectedIndex=0}
        $ruleId=if($ui.SetupRules.SelectedItem){$ui.SetupRules.SelectedItem.Id}else{''}
        $ui.SetupRules.ItemsSource=@($entries.ToArray())
        $ui.SetupRules.SelectedItem=$ui.SetupRules.Items | Where-Object {$_.Id -eq $ruleId} | Select-Object -First 1
        $ui.PermissionLegacy.Visibility=if(@($script:ownRules).Count){'Visible'}else{'Collapsed'}
    }finally{$script:permissionRefreshing=$false}
    Show-PermissionSelection
}
function Show-PermissionSelection {
    $p=$ui.PermissionPrograms.SelectedItem
    if(-not $p -or -not $script:setupStatus -or -not $setupStatus.Verified -or $script:permissionNoticeKey -ne $p.Key){$ui.PermissionNotice.Text=''}
    $ready=$p -and $script:setupStatus -and $setupStatus.Verified
    $exists=$p -and [IO.File]::Exists($p.Path)
    $protected=$p -and (Is-Protected $p.Path)
    $ui.PermissionAllow.IsEnabled=[bool]($ready -and $exists -and -not $protected -and -not $p.Legacy)
    $ui.PermissionBlock.IsEnabled=[bool]($ready -and $exists -and -not $protected)
    $ui.PermissionDefault.IsEnabled=[bool]($ready -and -not $p.Legacy)
    $ui.PermissionShow.IsEnabled=[bool]$p
    $ui.RemoveSetupRule.IsEnabled=[bool]($ui.SetupRules.SelectedItem -and $script:setupStatus -and $setupStatus.Verified)
    if(-not $p){$ui.PermissionDetail.Text='Keine Programme in dieser Auswahl. Auch beendete Programme mit gespeicherten Regeln werden hier angezeigt.';return}
    $reason=if(-not $ready){'Aktuelle Sperrwirkung nicht bestätigt; Änderungen gesperrt.'}elseif($p.Legacy){'Zusätzliche alte Netzblick-Regeln in der Windows-Firewall. Zum Aufheben „Alte Windows-Regeln ansehen“ öffnen.'}elseif($protected){'Windows-Sammelprozess: Einzelne Verbindungen unten gezielt verwalten.'}elseif(-not $exists){'Datei nicht mehr vorhanden. Gespeicherte Regeln können auf Standard zurückgesetzt werden.'}elseif($p.Category -eq 'Default'){'Keine eigene Dienstregel. Im Beobachten-Modus lässt Netzblick neue Verbindungen durch; Windows entscheidet zusätzlich.'}else{'„Erlauben“ ersetzt alle eigenen Programmregeln durch Freigaben. „Standard“ entfernt sie; bei aktivem Nachfragen ist dann wieder eine Freigabe nötig.'}
    $ui.PermissionDetail.Text=$p.Path+[Environment]::NewLine+$reason
}
function Confirm-PermissionChange([string]$operation,[string]$path=''){
    $p=if($path){[pscustomobject]@{Path=$path}}else{$ui.PermissionPrograms.SelectedItem};if(-not $p){return}
    try{
        $preview=Show-ChangePreview (Get-ChangePreview $p.Path $operation)
        if($preview){Set-PermissionProgram $p.Path $operation $preview.Minutes $preview.ExpectedConfigKey}
    }catch{Show-Error $_.Exception.GetBaseException().Message}
}
function Set-PermissionProgram([string]$path,[string]$operation,[int]$durationMinutes=10,[string]$expectedConfigKey=''){
    if($operation -notin @('AllowProgram','BlockProgram','ProgramDefault','TemporaryAllowProgram','TemporaryBlockProgram','EndProgramLease')){throw 'Unbekannte Programmaktion.'}
    if(-not $script:setupStatus -or -not $setupStatus.Verified){throw 'Filterstatus nicht bestätigt.'}
    $s=Get-PermissionStatus $path
    if($s.Legacy -and $operation -notin @('BlockProgram','TemporaryBlockProgram','EndProgramLease')){throw 'Zuerst die alten Windows-Regeln dieses Programms prüfen.'}
    if($operation -ne 'ProgramDefault' -and (Is-Protected $path)){throw 'System-Sammelprozess über einzelne Verbindungen verwalten.'}
    $before=[Netzblick.SetupChanges]::CaptureProgram($setupStatus.Config,$path)
    $reply=Send-SetupCommand ([Netzblick.SetupCommand]@{Operation=$operation;Path=$path;DurationMinutes=$durationMinutes;ExpectedProgram=$before;ExpectedConfigKey=$expectedConfigKey})
    $after=[Netzblick.SetupChanges]::CaptureProgram($reply.Config,$path)
    Save-ProgramChange $path $before $after $(if($operation -eq 'TemporaryAllowProgram'){'10 Minuten erlaubt'}elseif($operation -eq 'TemporaryBlockProgram'){'Zeitweise gesperrt · '+$(if($durationMinutes){$durationMinutes.ToString()+' Minuten'}else{'bis aufgehoben'})}elseif($operation -eq 'EndProgramLease'){'Zeitweise Entscheidung beendet'}else{(Get-PermissionStatus $path).Status})
    Update-AccessMode;Refresh-Overview;Refresh-Detail
    $script:permissionNoticeKey=[Netzblick.ProcessLineage]::Normalize($path)
    $ui.PermissionNotice.Text=([IO.Path]::GetFileName($path)+': '+(Get-PermissionStatus $path).Status+' · Änderung bestätigt.')
}
function Remove-PermissionEntry($entry){
    $command=switch($entry.Kind){
        'Watch' {[Netzblick.SetupCommand]@{Operation='Unwatch';Path=$entry.Path}}
        'Ask' {[Netzblick.SetupCommand]@{Operation='Ask';Enabled=$false}}
        default {[Netzblick.SetupCommand]@{Operation='Remove';RuleId=$entry.Id}}
    }
    [void](Send-SetupCommand $command)
}

function Set-ProgramSignal($program){
    if(-not $program){return}
    $state=Get-PermissionStatus $program.Path
    $program | Add-Member NoteProperty SignalColor $state.SignalColor -Force
    $program | Add-Member NoteProperty SignalHint $state.SignalHint -Force
}
function Refresh-ProgramSignals {
    foreach($p in @($script:allProgramItems)){Set-ProgramSignal $p}
    foreach($p in @($ui.OverviewPrograms.Items)){
        $state=Get-PermissionStatus $p.Path
        $p | Add-Member NoteProperty SignalColor $state.SignalColor -Force
        $p | Add-Member NoteProperty SignalHint $state.SignalHint -Force
        $p.Status=$state.Status
    }
    $ui.Programs.Items.Refresh();$ui.OverviewPrograms.Items.Refresh()
    $selected=$ui.Programs.SelectedItem
    if($selected){$state=Get-PermissionStatus $selected.Path;$ui.ProgramSignal.Fill=$state.SignalColor;$ui.ProgramSignal.ToolTip=$state.SignalHint}else{$ui.ProgramSignal.Fill=(Get-ThemeColor '#57677B');$ui.ProgramSignal.ToolTip='Kein Programm ausgewählt.'}
    $ui.ProgramAccessRules.IsEnabled=[bool]($selected -and [Netzblick.AccessQueue]::CanAllow($selected.Path))
}

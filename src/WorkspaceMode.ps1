function Get-ProgramActivity($program,$sample){
    $last=$null
    if($sample -and $sample.LastUtc){$last=[datetime]$sample.LastUtc}
    if($program.LastBlockUtc -and (-not $last -or $program.LastBlockUtc -gt $last)){$last=[datetime]$program.LastBlockUtc}
    $recent=$last -and ([datetime]::UtcNow-$last).TotalSeconds -le 30
    $sockets=@($program.Rows | Where-Object {$_.State -in @('Verbunden','SYN gesendet','SYN empfangen')}).Count -gt 0
    $label=if($last){$last.ToLocalTime().ToString('dd.MM. HH:mm:ss')}elseif($sockets){'Socket sichtbar'}else{'Nicht beobachtet'}
    [pscustomobject]@{Label=$label;Active=[bool]($recent -or $sockets)}
}
function Open-OverviewSelection {
    $item=$ui.OverviewPrograms.SelectedItem
    if(-not $item -and $ui.OverviewPrograms.Items.Count){$item=$ui.OverviewPrograms.Items[0]}
    if($item){$ui.Search.Text='';$ui.ProgramDetailTabs.SelectedIndex=0;Show-Panel 'LivePanel';$match=$ui.Programs.Items | Where-Object {$_.Key -eq $item.Key} | Select-Object -First 1;if($match){$ui.Programs.SelectedItem=$match;Refresh-Detail}}else{$ui.UserNotice.Text='Keine Programme in dieser Auswahl.'}
}
function Update-ProgramPresentation($program){
    if(-not $program){return}
    $state=Get-PermissionStatus $program.Path
    $name=$program.Name
    $sentence=switch($state.Category){
        'Blocked' {"Für $name sind neue externe Verbindungen gesperrt."}
        'Limited' {"Der Netzwerkzugriff von $name ist teilweise eingeschränkt."}
        'Allowed' {"$name ist in Netzblick erlaubt."}
        'Default' {"Netzblick lässt $name im Standardmodus durch."}
        default {"Der aktuelle Zugriff von $name ist nicht bestätigt."}
    }
    $attempts=@(if($script:setupStatus){$setupStatus.Attempts | Where-Object {[Netzblick.ProcessLineage]::Normalize($_.Path) -eq $program.Key}})
    $count=[long]0;foreach($a in $attempts){$count+=$a.Count}
    $last=$attempts | Sort-Object LastUtc -Descending | Select-Object -First 1
    $ui.ProgramExplanation.Text=$sentence
    $ui.ProgramShortState.Text=$state.Status+' · '+$(if($newPrograms -and $newPrograms.ContainsKey($program.Key)){'noch zu prüfen'}else{'beobachtet'})
    if($last){
        $ui.ProgramEvidenceSummary.Text=$count.ToString()+' erfasste Blockversuche seit Dienststart, zuletzt '+$last.LastUtc.ToLocalTime().ToString('dd.MM. HH:mm:ss')+'.'+[Environment]::NewLine+'Letzter aufgezeichneter Grund: '+$last.Evidence+[Environment]::NewLine+'Der aktuelle Zugriff und vergangene Sperrereignisse sind getrennt. Windows und andere Sicherheitsprogramme können zusätzlich sperren.'
    }else{$ui.ProgramEvidenceSummary.Text='Keine Blockversuche in der laufenden Erfassung aufgezeichnet. Das beweist keinen fehlenden Netzwerkzugriff. Windows und andere Sicherheitsprogramme können zusätzlich sperren.'}
    $selected=if($ui.ProgramRules.SelectedItem){$ui.ProgramRules.SelectedItem.Id}else{''}
    $rules=@($ui.SetupRules.Items | Where-Object {$_.Path -eq '*' -or [Netzblick.ProcessLineage]::Normalize($_.Path) -eq $program.Key})
    $ui.ProgramRules.ItemsSource=$rules
    $ui.ProgramRules.SelectedItem=$rules | Where-Object {$_.Id -eq $selected} | Select-Object -First 1
    $legacy=@($script:ownRules | Where-Object {[Netzblick.ProcessLineage]::Normalize($_.Path) -eq $program.Key})
    $ui.ProgramRulesHint.Text=if($legacy.Count){'Zusätzlich '+$legacy.Count+' ältere Netzblick-Windows-Regeln. Unter Übersicht → Ältere Windows-Regeln verwalten ansehen.'}elseif(-not $rules.Count){'Keine eigenen Einzelregeln oder Prüfsperren für dieses Programm. Es gilt der allgemeine Modus.'}else{'Einträge mit „Alle Programme“ wirken über dieses Programm hinaus. Eine Einzel-Freigabe hebt andere Sperren nicht automatisch auf.'}
    $ui.ProgramRuleRemove.IsEnabled=[bool]($ui.ProgramRules.SelectedItem -and $script:setupStatus -and $setupStatus.Verified)
}
function Initialize-WorkspaceMode {
    $ui.BackToPrograms.Add_Click({Show-Panel 'OverviewPanel'})
    $ui.OverviewFilter.Add_SelectionChanged({Refresh-Overview})
    $ui.OverviewSearch.Add_TextChanged({Refresh-Overview})
    $ui.ProgramRulesManage.Add_Click({if($ui.Programs.SelectedItem){Open-Permissions $ui.Programs.SelectedItem.Path}})
    $ui.ProgramRules.Add_SelectionChanged({$ui.ProgramRuleRemove.IsEnabled=[bool]($ui.ProgramRules.SelectedItem -and $script:setupStatus -and $setupStatus.Verified)})
    $ui.ProgramRuleRemove.Add_Click({
        $entry=$ui.ProgramRules.SelectedItem;if(-not $entry){return}
        $scope=if($entry.Path -eq '*'){'Dieser Eintrag gilt für alle Programme.'}else{'Andere Regeln bleiben wirksam.'}
        if([Windows.MessageBox]::Show($window,('„'+$entry.Name+'“ zurücknehmen? '+$scope+[Environment]::NewLine+$entry.Scope),'Regel zurücknehmen','YesNo','Question') -ne 'Yes'){return}
        try{Remove-PermissionEntry $entry;Update-AccessMode}catch{Show-Error $_.Exception.GetBaseException().Message}
    })
}

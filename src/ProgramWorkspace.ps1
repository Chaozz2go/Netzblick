function Get-LocalJson {New-Object System.Web.Script.Serialization.JavaScriptSerializer -Property @{MaxJsonLength=8388608;RecursionLimit=24}}
function ConvertFrom-LocalJson([string]$json,[type]$type){
    $serializer=Get-LocalJson;$method=$serializer.GetType().GetMethods() | Where-Object {$_.Name -eq 'Deserialize' -and $_.IsGenericMethodDefinition} | Select-Object -First 1
    $method.MakeGenericMethod($type).Invoke($serializer,@($json))
}
function Write-LocalAtomic([string]$path,[string]$text){
    if([Text.Encoding]::UTF8.GetByteCount($text) -gt 8388608){throw 'Lokale Datei überschreitet 8 MB.'}
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path));$temp=$path+'.tmp'
    [IO.File]::WriteAllText($temp,$text,[Text.UTF8Encoding]::new($false))
    if([IO.File]::Exists($path)){[IO.File]::Replace($temp,$path,$path+'.bak')}else{[IO.File]::Move($temp,$path)}
}
function Save-WorkspaceSettings {
    if($script:workspaceReadOnly){throw 'Arbeitsbereich konnte nicht gelesen werden; vorhandene Datei wird nicht überschrieben.'}
    $workspaceSettings.Validate();Write-LocalAtomic $workspaceFile ((Get-LocalJson).Serialize($workspaceSettings))
}
function Copy-WorkspaceSettings {ConvertFrom-LocalJson ((Get-LocalJson).Serialize($workspaceSettings)) ([Netzblick.WorkspaceSettings])}
function Get-GroupCatalogEntries {
    if(-not $script:programWorkspaceReady){return}
    foreach($g in $workspaceSettings.Groups){foreach($p in $g.Paths){[pscustomobject]@{Path=$p;Name=[IO.Path]::GetFileName($p);Historical=$true}}}
}
function Save-ProgramGroup($group){
    $group.Validate();$before=Copy-WorkspaceSettings
    $existing=$workspaceSettings.Groups | Where-Object Id -eq $group.Id | Select-Object -First 1
    if($existing){[void]$workspaceSettings.Groups.Remove($existing)}
    $workspaceSettings.Groups.Add($group)
    try{Save-WorkspaceSettings}catch{$script:workspaceSettings=$before;throw}
    Refresh-Groups
}
function Remove-ProgramGroup([string]$id){
    $before=Copy-WorkspaceSettings;$g=$workspaceSettings.Groups | Where-Object Id -eq $id | Select-Object -First 1
    if($g){[void]$workspaceSettings.Groups.Remove($g);try{Save-WorkspaceSettings}catch{$script:workspaceSettings=$before;throw}}
    Refresh-Groups
}
function New-GroupEditor($group,[string]$initialPath=''){
    [xml]$markup=Get-Content -LiteralPath (Join-Path $appRoot 'src\GroupEditor.xaml') -Raw -Encoding UTF8
    $dialog=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($markup));$dialog.Resources=$window.Resources;if($window.IsLoaded){$dialog.Owner=$window}
    $selected=@{};if($group){foreach($p in $group.Paths){$selected[[Netzblick.ProcessLineage]::Normalize($p)]=$p}}elseif($initialPath){$selected[[Netzblick.ProcessLineage]::Normalize($initialPath)]=$initialPath}
    $paths=@{};foreach($p in @($script:allProgramItems | ForEach-Object Path)+@($selected.Values)){if([Netzblick.AccessQueue]::CanAllow($p) -and $p.Length -le 1024){$paths[[Netzblick.ProcessLineage]::Normalize($p)]=$p}}
    $entries=New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    foreach($p in @($paths.Values | Sort-Object)){[void]$entries.Add([pscustomobject]@{Include=$selected.ContainsKey([Netzblick.ProcessLineage]::Normalize($p));Name=[IO.Path]::GetFileName($p);Path=$p})}
    $dialog.Tag=[pscustomobject]@{Id=$(if($group){$group.Id}else{[guid]::NewGuid().ToString()});Entries=$entries;Result=$null}
    $dialog.FindName('GroupName').Text=if($group){$group.Name}elseif($initialPath){[IO.Path]::GetFileNameWithoutExtension($initialPath)}else{'Neue Programmgruppe'}
    $dialog.FindName('GroupCandidates').ItemsSource=$entries
    $dialog.FindName('GroupBrowse').Add_Click({param($sender,$e)
        $owner=[Windows.Window]::GetWindow($sender);$picker=New-Object Microsoft.Win32.OpenFileDialog;$picker.Filter='Windows-Programme (*.exe)|*.exe';$picker.Multiselect=$true
        if($picker.ShowDialog($owner)){foreach($p in $picker.FileNames){if(-not @($owner.Tag.Entries | Where-Object {[Netzblick.ProcessLineage]::Normalize($_.Path) -eq [Netzblick.ProcessLineage]::Normalize($p)}).Count){$owner.Tag.Entries.Add([pscustomobject]@{Include=$false;Name=[IO.Path]::GetFileName($p);Path=$p})}}}
    })
    $dialog.FindName('GroupSave').Add_Click({param($sender,$e)
        $owner=[Windows.Window]::GetWindow($sender);$grid=$owner.FindName('GroupCandidates');[void]$grid.CommitEdit();[void]$grid.CommitEdit([Windows.Controls.DataGridEditingUnit]::Row,$true)
        try{$g=New-Object Netzblick.ProgramGroup;$g.Id=$owner.Tag.Id;$g.Name=$owner.FindName('GroupName').Text.Trim();foreach($p in $owner.Tag.Entries | Where-Object Include){$g.Paths.Add($p.Path)};$g.Validate();$owner.Tag.Result=$g;$owner.DialogResult=$true}catch{$owner.FindName('GroupEditorNotice').Text=$_.Exception.GetBaseException().Message}
    })
    $dialog
}
function Show-GroupEditor($group=$null,[string]$initialPath=''){
    $dialog=New-GroupEditor $group $initialPath
    if($dialog.ShowDialog()){Save-ProgramGroup $dialog.Tag.Result;Navigate-Workspace 'Groups';$ui.GroupsList.SelectedItem=$ui.GroupsList.Items | Where-Object Id -eq $dialog.Tag.Result.Id | Select-Object -First 1;Show-GroupSelection}
}
function Refresh-Groups {
    if(-not $script:programWorkspaceReady){return}
    $key=if($ui.GroupsList.SelectedItem){$ui.GroupsList.SelectedItem.Id}else{''}
    $script:groupsRefreshing=$true
    try{$ui.GroupsList.ItemsSource=@($workspaceSettings.Groups | Sort-Object Name);$ui.GroupsList.SelectedItem=$ui.GroupsList.Items | Where-Object Id -eq $key | Select-Object -First 1;if(-not $key -and $ui.GroupsList.Items.Count){$ui.GroupsList.SelectedIndex=0}}finally{$script:groupsRefreshing=$false}
    Show-GroupSelection
}
function Show-GroupSelection {
    $g=$ui.GroupsList.SelectedItem;$ui.GroupEdit.IsEnabled=[bool]($g -and -not $workspaceReadOnly);$ui.GroupRemove.IsEnabled=$ui.GroupEdit.IsEnabled
    $ui.GroupTitle.Text=if($g){$g.Name}else{'Bestätigte Programmgruppen'}
    $ui.GroupScope.Text=if($g){$g.Paths.Count.ToString()+' selbst bestätigte EXE-Pfade. Neue Hilfsprogramme werden nicht automatisch aufgenommen. Regeln gelten für alle Instanzen der jeweils aufgeführten EXE.'}else{'Eine Gruppe anlegen und die zugehörigen EXE-Pfade selbst auswählen. Die Gruppe startet oder beendet keine Programme.'}
    $members=@(if($g){foreach($path in $g.Paths){$s=Get-PermissionStatus $path;$key=[Netzblick.ProcessLineage]::Normalize($path);$p=$script:allProgramItems | Where-Object Key -eq $key | Select-Object -First 1;[pscustomobject]@{Path=$path;Name=[IO.Path]::GetFileName($path);Status=$s.Status;Color=$s.SignalColor;Activity=$(if($p){Get-ProgramDirectionSummary $p}else{'Kein Socket erfasst'});Lease=(Get-ProgramLeaseText $path)}}})
    $selected=if($ui.GroupMembers.SelectedItem){$ui.GroupMembers.SelectedItem.Path}else{''};$ui.GroupMembers.ItemsSource=$members;$ui.GroupMembers.SelectedItem=$members | Where-Object Path -eq $selected | Select-Object -First 1
    $ready=$g -and $script:setupStatus -and $setupStatus.Verified
    $blocked=$g -and @($g.Paths | Where-Object {[Netzblick.SetupChanges]::IsProtectedProgram($_) -or -not [IO.File]::Exists($_)}).Count -gt 0
    $leases=@(if($g -and $script:setupStatus){$setupStatus.Config.ProgramLeases | Where-Object {$p=$_.Path;@($g.Paths | Where-Object {[Netzblick.ProcessLineage]::Normalize($_) -eq [Netzblick.ProcessLineage]::Normalize($p)}).Count}})
    $ui.GroupPause.IsEnabled=[bool]($ready -and -not $blocked -and -not $leases.Count)
    $ui.GroupResume.IsEnabled=[bool]($ready -and $leases.Count -and -not @($g.Paths | Where-Object {[Netzblick.SetupChanges]::IsProtectedProgram($_)}).Count)
    $ui.GroupNotice.Text=if($blocked){'Gruppensperre nicht verfügbar: Eine Datei fehlt oder ein geschützter Windows-Sammelprozess ist enthalten. Einzelne Mitglieder lassen sich weiterhin ansehen.'}elseif($leases.Count){$leases.Count.ToString()+' Mitglieder mit zeitweiser Entscheidung. Vor einer neuen Gruppensperre diese zuerst beenden.'}else{'Eine Gruppenaktion wird im Dienst vollständig übernommen oder vollständig abgelehnt. Fremde Firewallregeln bleiben unabhängig wirksam.'}
    Show-GroupMemberSelection
}
function Show-GroupMemberSelection {
    $p=$ui.GroupMembers.SelectedItem;$ui.GroupMemberDetails.IsEnabled=[bool]$p
    $ui.GroupMemberBlock.IsEnabled=[bool]($p -and $script:setupStatus -and $setupStatus.Verified -and [IO.File]::Exists($p.Path) -and -not(Is-Protected $p.Path))
    $ui.GroupMemberPath.Text=if($p){$p.Path}else{'Ein Mitglied auswählen, um nur diese EXE zu bearbeiten.'}
}
function Get-GroupChangePreview($group,[string]$operation,[int]$minutes=10){
    if(-not $script:setupStatus -or -not $setupStatus.Verified){throw 'Filterstatus unbestätigt.'}
    $paths=@($group.Paths)
    if($operation -eq 'GroupEndLeases'){$paths=@($paths | Where-Object {$p=$_;@($setupStatus.Config.ProgramLeases | Where-Object {[Netzblick.ProcessLineage]::Normalize($_.Path) -eq [Netzblick.ProcessLineage]::Normalize($p)}).Count})}
    $before=[Netzblick.SetupChanges]::CopyConfig($setupStatus.Config);$problem='';$after=$null
    try{if($operation -eq 'GroupTemporaryBlock' -and @($paths | Where-Object {-not [IO.File]::Exists($_)}).Count){throw 'Eine bestätigte Gruppendatei fehlt.'};$after=[Netzblick.SetupChanges]::GroupChange($before,[string[]]$paths,$operation,$minutes,[datetime]::UtcNow)}catch{$problem=$_.Exception.GetBaseException().Message}
    $observations=Get-PreviewObservations;$matches=@()
    foreach($o in $observations.Known){$a=$o.Attempt;if(-not @($paths | Where-Object {[Netzblick.ProcessLineage]::Normalize($_) -eq [Netzblick.ProcessLineage]::Normalize($a.Path)}).Count){continue};$matches+=[pscustomobject]@{Program=[IO.Path]::GetFileName($a.Path);Direction=$a.Direction;Target=$a.Target;Source=$o.Source;Before=(Get-PreviewDecision $before $a ([bool]$o.Loopback));After=$(if($after){Get-PreviewDecision $after $a ([bool]$o.Loopback)}else{'Änderung nicht anwendbar'})}}
    [pscustomobject]@{Path='';Paths=[string[]]$paths;Operation=$operation;Rule=$null;Minutes=$minutes;ExpectedConfigKey=[Netzblick.SetupChanges]::ConfigKey($before);Matches=$matches;Unknown=$observations.Unknown;Scope=('Gruppe „'+$group.Name+'“ · '+$paths.Count+' bestätigte EXE-Pfade'+[Environment]::NewLine+($paths -join [Environment]::NewLine));Footprint=$(if($operation -eq 'GroupTemporaryBlock'){'Neue externe Verbindungen aller genannten EXEs werden ein- und ausgehend zeitweise gesperrt. Vorherige Regeln werden pro EXE gesichert.'}else{'Die zeitweisen Entscheidungen der genannten EXEs werden beendet; ihre jeweils vorherigen Regeln werden wiederhergestellt.'});Warning='Gilt für alle Instanzen dieser Pfade. Bestehende Verbindungen werden nicht garantiert beendet. Nicht aufgeführte Hilfsprogramme und fremde Filter werden nicht erfasst.';Problem=$problem;TimeUtc=[datetime]::UtcNow;CanApply=(-not [bool]$problem)}
}
function Apply-GroupChange($preview){
    if(-not $preview.CanApply){throw $preview.Problem}
    [void](Send-SetupCommand ([Netzblick.SetupCommand]@{Operation=$preview.Operation;Paths=[System.Collections.Generic.List[string]]$preview.Paths;DurationMinutes=$preview.Minutes;ExpectedConfigKey=$preview.ExpectedConfigKey}))
    foreach($path in $preview.Paths){Add-ProgramTimeline $path 'Bestätigte Gruppenaktion' ($(if($preview.Operation -eq 'GroupTemporaryBlock'){'Zeitweise Gruppensperre'}else{'Zeitweise Gruppenentscheidungen beendet'})+' · '+$preview.Paths.Count+' ausdrücklich ausgewählte EXEs. Änderung vom Dienst bestätigt.')}
    Update-AccessMode;Refresh-Groups
}
function Confirm-GroupChange([string]$operation){
    $g=$ui.GroupsList.SelectedItem;if(-not $g){return}
    try{$preview=Show-ChangePreview (Get-GroupChangePreview $g $operation);if($preview){Apply-GroupChange $preview}}catch{Show-Error $_.Exception.GetBaseException().Message}
}
function Initialize-ProgramWorkspace {
    $script:workspaceFile=Join-Path $userStateDirectory 'workspace-state.json';$script:workspaceReadOnly=$false;$script:workspaceSettings=New-Object Netzblick.WorkspaceSettings
    try{if([IO.File]::Exists($workspaceFile)){if((Get-Item -LiteralPath $workspaceFile).Length -gt 8388608){throw 'Arbeitsbereichsdatei zu groß.'};$loaded=ConvertFrom-LocalJson ([IO.File]::ReadAllText($workspaceFile)) ([Netzblick.WorkspaceSettings]);$loaded.Validate();$script:workspaceSettings=$loaded}}catch{$script:workspaceReadOnly=$true;$ui.UserNotice.Text='Arbeitsbereich konnte nicht gelesen werden; Datei bleibt erhalten: '+$_.Exception.GetBaseException().Message}
    $script:programWorkspaceReady=$true;$script:fileObservations=@{};$script:fileAnnouncedHashes=@{};$script:fileNextChecks=@{};$script:fileScanJob=$null;$script:fileScanRequest=$null;$script:fileAckPending=$null;$script:fileScanEpoch=[guid]::NewGuid().ToString('N')
    $ui.GroupNew.IsEnabled=-not $workspaceReadOnly
    $ui.GroupNew.Add_Click({try{Show-GroupEditor}catch{Show-Error $_.Exception.Message}})
    $ui.GroupEdit.Add_Click({if($ui.GroupsList.SelectedItem){try{Show-GroupEditor $ui.GroupsList.SelectedItem}catch{Show-Error $_.Exception.Message}}})
    $ui.GroupRemove.Add_Click({$g=$ui.GroupsList.SelectedItem;if($g -and [Windows.MessageBox]::Show($window,('Gruppe „'+$g.Name+'“ entfernen? Die Regeln ihrer EXEs bleiben bestehen.'),'Gruppe entfernen','YesNo','Question') -eq 'Yes'){try{Remove-ProgramGroup $g.Id}catch{Show-Error $_.Exception.Message}}})
    $ui.GroupsList.Add_SelectionChanged({if(-not $script:groupsRefreshing){Show-GroupSelection}})
    $ui.GroupMembers.Add_SelectionChanged({Show-GroupMemberSelection})
    $ui.GroupPause.Add_Click({Confirm-GroupChange 'GroupTemporaryBlock'});$ui.GroupResume.Add_Click({Confirm-GroupChange 'GroupEndLeases'})
    $ui.GroupMemberDetails.Add_Click({if($ui.GroupMembers.SelectedItem){Show-ReviewProgram $ui.GroupMembers.SelectedItem.Path}})
    $ui.GroupMemberBlock.Add_Click({if($ui.GroupMembers.SelectedItem){Confirm-PermissionChange 'TemporaryBlockProgram' $ui.GroupMembers.SelectedItem.Path}})
    foreach($prefix in @('Overview','Program')){$ui[$prefix+'Group'].Tag=$prefix;$ui[$prefix+'Group'].Add_Click({param($sender,$e) $p=if($sender.Tag -eq 'Program'){$ui.Programs.SelectedItem}else{$ui.OverviewPrograms.SelectedItem};if($p){try{Show-GroupEditor $null $p.Path}catch{Show-Error $_.Exception.Message}}})}
    $ui.FileCheckNow.Add_Click({if($ui.Programs.SelectedItem){Request-FileScan $ui.Programs.SelectedItem.Path}})
    $ui.FileCompare.Add_Click({if($ui.Programs.SelectedItem){Show-FileComparison $ui.Programs.SelectedItem.Path}})
    Refresh-Groups;Update-ProgramFileCard
}

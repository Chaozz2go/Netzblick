# A bounded, local presentation of observed activity. No firewall mutations here.
function Reset-DashboardHistory {
    $script:dashboardHistory=New-Object 'System.Collections.Generic.List[object]'
    $script:dashboardFrame=$null;$script:dashboardFrozen=$false;$script:dashboardSelectedKey='';$script:dashboardSelectionSnapshot=$null
    if($script:dashboardReady){$ui.DashboardNodes.Children.Clear();Initialize-DashboardCamera}
    if($ui.ContainsKey('DashboardFreeze')){$ui.DashboardFreeze.Content='Ⅱ Einfrieren'}
}
function Add-DashboardSample([datetime]$time,$received,$sent,[bool]$ready){
    if($null -eq $script:dashboardHistory){Reset-DashboardHistory}
    $dashboardHistory.Add([pscustomobject]@{Time=$time;Rx=$(if($ready){[double]$received}else{$null});Tx=$(if($ready){[double]$sent}else{$null})})
    while($dashboardHistory.Count -gt 301 -or ($dashboardHistory.Count -gt 1 -and ($time-$dashboardHistory[0].Time).TotalSeconds -gt 305)){$dashboardHistory.RemoveAt(0)}
}
function Get-DashboardProgram($program){
    $edges=New-Object 'System.Collections.Generic.List[object]';$present=@{};$outgoing=0;$incoming=0;$unknown=0;$listening=0
    foreach($row in @($program.Rows)){
        $direction=Get-ConnectionDirection $row $program.Path
        if($direction.Label -eq 'Lauschend'){$listening++;continue}
        if($row.State -notin @('Verbunden','SYN gesendet','SYN empfangen') -or -not $row.Address){continue}
        switch($direction.Label){'Ausgehend'{$outgoing++} 'Eingehend'{$incoming++} default{$unknown++}}
        $present[$row.Protocol+'|'+$row.Address+'|'+$row.Port]=$true
        $edges.Add([pscustomobject]@{Address=$row.Address;Port=$row.Port;Protocol=$row.Protocol;Direction=$direction.Label;Blocked=$false})
    }
    foreach($peer in @($script:trafficPeers | Where-Object {[Netzblick.ProcessLineage]::Normalize($_.Path) -eq $program.Key -and $_.LastUtc -and ([datetime]::UtcNow-[datetime]$_.LastUtc).TotalSeconds -le 30})){
        if($present.ContainsKey($peer.Protocol+'|'+$peer.Address+'|'+$peer.Port)){continue}
        $unknown++;$edges.Add([pscustomobject]@{Address=$peer.Address;Port=$peer.Port;Protocol=$peer.Protocol;Direction='Unbekannt';Blocked=$false})
    }
    if($script:setupStatus){foreach($attempt in @($setupStatus.Attempts | Where-Object {[Netzblick.ProcessLineage]::Normalize($_.Path) -eq $program.Key -and ([datetime]::UtcNow-$_.LastUtc).TotalSeconds -le 30})){
        $edges.Add([pscustomobject]@{Address=$attempt.Address;Port=$attempt.Port;Protocol=([Netzblick.SetupRule]::ProtocolName($attempt.Protocol));Direction=$attempt.Direction;Blocked=$true})
    }}
    $sample=$script:trafficSamples[$program.Key];$state=Get-PermissionStatus $program.Path
    [pscustomobject]@{Key=$program.Key;Path=$program.Path;Name=$program.Name;Icon=(Get-ApplicationIcon $program.Path -Always);State=$state.Status;Review=(Get-ProgramReviewState $program.Path).Reason;Outgoing=$outgoing;Incoming=$incoming;Unknown=$unknown;Listening=$listening;Edges=@($edges.ToArray());RateReady=[bool]($sample -and $sample.RateReady -and -not $script:trafficProblem);Rx=$(if($sample){$sample.ReceivedRate}else{0});Tx=$(if($sample){$sample.SentRate}else{0})}
}
function Update-Dashboard {
    if(-not $script:dashboardReady -or $script:dashboardFrozen -or ($script:activePanel -and $script:activePanel -ne 'DashboardPanel')){return}
    $active=@($script:allProgramItems | Where-Object {(Get-ProgramActivity $_ $script:trafficSamples[$_.Key]).Active})
    $programs=@($active | Sort-Object Name,Key | ForEach-Object {Get-DashboardProgram $_})
    $blocks=[long]0;if($script:setupStatus){foreach($attempt in @($setupStatus.Attempts)){$blocks+=[long]$attempt.Count}}
    $review=@($script:allProgramItems | Where-Object {(Get-ProgramReviewState $_.Path).NeedsReview}).Count
    $script:dashboardFrame=[pscustomobject]@{Time=[datetime]::UtcNow;Programs=$programs;ActiveCount=$active.Count;BlockCount=$blocks;ReviewCount=$review;History=@($script:dashboardHistory.ToArray());Problem=$script:trafficProblem}
    if(-not $script:dashboardSelectedKey -and $programs.Count){$script:dashboardSelectedKey=$programs[0].Key}
    $selected=$programs | Where-Object Key -eq $script:dashboardSelectedKey | Select-Object -First 1
    if($selected){$script:dashboardSelectionSnapshot=$selected}
    Draw-Dashboard
}
function Add-DashboardLabel($canvas,[string]$text,[double]$x,[double]$y,[double]$width,[string]$role='Text',[double]$size=14){
    $t=[Windows.Controls.TextBlock]::new();$t.Text=$text;$t.Foreground=$window.Resources[$role];$t.FontSize=$size;$t.Width=$width;$t.TextAlignment='Center';$t.TextTrimming='CharacterEllipsis';$t.ToolTip=$text
    [Windows.Controls.Canvas]::SetLeft($t,$x);[Windows.Controls.Canvas]::SetTop($t,$y);[void]$canvas.Children.Add($t)
}
function Add-DashboardEdge($canvas,[double]$x1,[double]$y1,[double]$x2,[double]$y2,[string]$direction,[bool]$blocked,[double]$offset,[double]$thickness=2.2){
    $dx=$x2-$x1;$dy=$y2-$y1;$length=[Math]::Sqrt($dx*$dx+$dy*$dy);if($length -lt 1){return}
    $ux=$dx/$length;$uy=$dy/$length
    $trimX=if([Math]::Abs($ux) -gt 0.001){68/[Math]::Abs($ux)}else{100000};$trimY=if([Math]::Abs($uy) -gt 0.001){29/[Math]::Abs($uy)}else{100000};$targetTrim=[Math]::Min($trimX,$trimY)+8
    $appTrim=33*(Get-DashboardNodeGain)+5
    $a=[Windows.Point]::new(($x1+$ux*$appTrim-$uy*$offset),($y1+$uy*$appTrim+$ux*$offset));$b=[Windows.Point]::new(($x2-$ux*$targetTrim-$uy*$offset),($y2-$uy*$targetTrim+$ux*$offset))
    $role=if($blocked){'Danger'}elseif($direction -eq 'Ausgehend'){'Accent'}elseif($direction -eq 'Eingehend'){'Inbound'}else{'Muted'}
    $line=[Windows.Shapes.Line]::new();$line.X1=$a.X;$line.Y1=$a.Y;$line.X2=$b.X;$line.Y2=$b.Y;$line.Stroke=$window.Resources[$role];$line.StrokeThickness=$thickness
    if($blocked){$line.StrokeDashArray=[Windows.Media.DoubleCollection]::new([double[]]@(5,4))};[void]$canvas.Children.Add($line)
    if($direction -notin @('Ausgehend','Eingehend')){return}
    $tip=if($direction -eq 'Eingehend'){$a}else{$b};$sign=if($direction -eq 'Eingehend'){-1}else{1}
    $triangle=[Windows.Shapes.Polygon]::new();$triangle.Fill=$window.Resources[$role]
    $triangle.Points=[Windows.Media.PointCollection]::new([Windows.Point[]]@($tip,[Windows.Point]::new(($tip.X-$sign*$ux*12+$uy*5),($tip.Y-$sign*$uy*12-$ux*5)),[Windows.Point]::new(($tip.X-$sign*$ux*12-$uy*5),($tip.Y-$sign*$uy*12+$ux*5))))
    [void]$canvas.Children.Add($triangle)
}
function Draw-DashboardNetwork {
    $canvas=$ui.DashboardLinks;$canvas.Children.Clear();$frame=$script:dashboardFrame
    $bounds=Get-DashboardBounds
    for($x=[Math]::Floor($bounds.Left/120)*120;$x -le $bounds.Right;$x+=120){$l=[Windows.Shapes.Line]::new();$l.X1=$x;$l.X2=$x;$l.Y1=$bounds.Top;$l.Y2=$bounds.Bottom;$l.Stroke=$window.Resources['Border'];$l.Opacity=0.18;[void]$canvas.Children.Add($l)}
    for($y=[Math]::Floor($bounds.Top/120)*120;$y -le $bounds.Bottom;$y+=120){$l=[Windows.Shapes.Line]::new();$l.Y1=$y;$l.Y2=$y;$l.X1=$bounds.Left;$l.X2=$bounds.Right;$l.Stroke=$window.Resources['Border'];$l.Opacity=0.18;[void]$canvas.Children.Add($l)}
    $present=@{};if($frame){foreach($p in $frame.Programs){$present[$p.Key]=$true}}
    foreach($key in @($script:dashboardNodeVisuals.Keys)){if(-not $present.ContainsKey($key)){$ui.DashboardNodes.Children.Remove($dashboardNodeVisuals[$key].Container);$dashboardNodeVisuals.Remove($key)}}
    $pc=[Windows.Controls.Border]::new();$pc.Width=78;$pc.Height=78;$pc.CornerRadius=[Windows.CornerRadius]::new(39);$pc.Background=$window.Resources['Raised'];$pc.BorderBrush=$window.Resources['Accent'];$pc.BorderThickness='2';$label=[Windows.Controls.TextBlock]::new();$label.Text="▣`nDein PC";$label.TextAlignment='Center';$label.FontSize=20;$label.VerticalAlignment='Center';$label.Foreground=$window.Resources['Text'];$pc.Child=$label
    [Windows.Controls.Canvas]::SetLeft($pc,-39);[Windows.Controls.Canvas]::SetTop($pc,-39);[void]$canvas.Children.Add($pc)
    if(-not $frame -or -not $frame.Programs.Count){Add-DashboardLabel $canvas 'Noch keine aktive Netzwerkkommunikation erfasst' -280 70 560 'Muted' 18;return}
    foreach($p in $frame.Programs){
        $pos=Get-DashboardPosition $p.Key;$x=$pos.X;$y=$pos.Y;$tx=$pos.TargetX;$ty=$pos.TargetY
        $spoke=[Windows.Shapes.Line]::new();$spoke.X1=0;$spoke.Y1=0;$spoke.X2=$x;$spoke.Y2=$y;$spoke.Stroke=$window.Resources['Border'];[void]$canvas.Children.Insert(0,$spoke)
        $groups=@($p.Edges | Group-Object Direction,Blocked);$offset=-($groups.Count-1)*4
        $edgeWidth=if($p.RateReady){[Math]::Min(4.5,1.5+[Math]::Log10(1+($p.Rx+$p.Tx)/1024))}else{1.5}
        foreach($g in $groups){Add-DashboardEdge $canvas $x $y $tx $ty $g.Group[0].Direction $g.Group[0].Blocked $offset $edgeWidth;$offset+=8}
        if($p.Edges.Count){
            $targets=@($p.Edges | ForEach-Object {$_.Address} | Select-Object -Unique);$scopes=@($targets | ForEach-Object {[Netzblick.EndpointInfo]::Scope($_)})
            $kind=if(@($scopes | Where-Object {$_ -eq 'Öffentliche / sonstige Adresse'}).Count -eq $scopes.Count){'Internet'}elseif(@($scopes | Where-Object {$_ -eq 'Öffentliche / sonstige Adresse'}).Count){'LAN / Internet'}else{'Lokal / LAN'}
            $endpoint=[Windows.Controls.Border]::new();$endpoint.Width=136;$endpoint.Height=58;$endpoint.Background=$window.Resources['Raised'];$endpoint.BorderBrush=$window.Resources['Border'];$endpoint.BorderThickness='1';$endpoint.CornerRadius=[Windows.CornerRadius]::new(5);$endpoint.ToolTip=($p.Edges | ForEach-Object {$_.Direction+' · '+$_.Address+':'+$_.Port+$(if($_.Blocked){' · blockiert'})} | Select-Object -First 12)-join "`n"
            $t=[Windows.Controls.TextBlock]::new();$t.Text=$kind+"`n"+$targets.Count+$(if($targets.Count -eq 1){' Gegenstelle'}else{' Gegenstellen'});$t.FontSize=15;$t.TextAlignment='Center';$t.VerticalAlignment='Center';$t.Foreground=$window.Resources['Text'];$endpoint.Child=$t
            [Windows.Controls.Canvas]::SetLeft($endpoint,($tx-68));[Windows.Controls.Canvas]::SetTop($endpoint,($ty-29));[void]$canvas.Children.Add($endpoint)
        }
        if(-not $dashboardNodeVisuals.ContainsKey($p.Key)){
            $container=[Windows.Controls.Canvas]::new();$container.Width=180;$container.Height=104
            $button=[Windows.Controls.Button]::new();$button.Width=66;$button.Height=66;$button.Padding='6';$button.Margin='0';$button.Tag=$p.Key
            $button.Template=[Windows.Markup.XamlReader]::Parse('<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button"><Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="2" CornerRadius="33"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border></ControlTemplate>')
            $button.Add_Click({param($sender,$e) $script:dashboardSelectedKey=[string]$sender.Tag;$script:dashboardSelectionSnapshot=$dashboardFrame.Programs | Where-Object Key -eq $script:dashboardSelectedKey | Select-Object -First 1;Draw-Dashboard})
            [Windows.Controls.Canvas]::SetLeft($button,57);[void]$container.Children.Add($button)
            $name=[Windows.Controls.TextBlock]::new();$name.Width=110;[Windows.Controls.Canvas]::SetLeft($name,35);$name.TextAlignment='Center';$name.FontSize=18;$name.TextTrimming='CharacterEllipsis';[Windows.Controls.Canvas]::SetTop($name,70);[void]$container.Children.Add($name)
            [void]$ui.DashboardNodes.Children.Add($container);$dashboardNodeVisuals[$p.Key]=[pscustomobject]@{Container=$container;Button=$button;Label=$name}
        }
        $visual=$dashboardNodeVisuals[$p.Key];$button=$visual.Button
        $button.Background=$window.Resources['Raised'];$button.BorderBrush=$window.Resources[$(if($p.Key -eq $script:dashboardSelectedKey){'Accent'}else{'Border'})];$button.ToolTip=$p.Name+' · '+$p.State
        $button.Effect=$null
        if($p.Key -eq $script:dashboardSelectedKey){$glow=[Windows.Media.Effects.DropShadowEffect]::new();$glow.Color=$window.Resources['Accent'].Color;$glow.BlurRadius=16;$glow.ShadowDepth=0;$glow.Opacity=0.45;$button.Effect=$glow}
        if($p.Icon){$im=[Windows.Controls.Image]::new();$im.Source=$p.Icon;$im.Width=36;$im.Height=36;$button.Content=$im}else{$button.Content=$p.Name.Substring(0,1).ToUpperInvariant();$button.FontSize=25}
        [Windows.Automation.AutomationProperties]::SetName($button,$p.Name+' auswählen')
        $gain=Get-DashboardNodeGain;$visual.Container.RenderTransform=[Windows.Media.ScaleTransform]::new($gain,$gain,90,33)
        $visual.Label.Text=$p.Name;$visual.Label.ToolTip=$p.Name;$visual.Label.Foreground=$window.Resources['Text']
        [Windows.Controls.Canvas]::SetLeft($visual.Container,($x-90));[Windows.Controls.Canvas]::SetTop($visual.Container,($y-33))

    }
}
function Draw-DashboardChart($canvas,[string]$property,[string]$role){
    $canvas.Children.Clear();$frame=$script:dashboardFrame;if(-not $frame){return}
    $period=[int]$ui.DashboardPeriod.SelectedItem.Tag;$samples=@($frame.History | Where-Object {($frame.Time-$_.Time).TotalSeconds -ge 0 -and ($frame.Time-$_.Time).TotalSeconds -le $period})
    $w=[Math]::Max(100,$canvas.ActualWidth);$h=[Math]::Max(55,$canvas.ActualHeight)-15;$max=1.0
    foreach($s in $samples){if($null -ne $s.$property){$max=[Math]::Max($max,[double]$s.$property)}}
    for($i=1;$i -le 3;$i++){$line=[Windows.Shapes.Line]::new();$line.X2=$w;$line.Y1=$h*$i/3;$line.Y2=$line.Y1;$line.Stroke=$window.Resources['Border'];$line.Opacity=0.5;[void]$canvas.Children.Add($line)}
    $segment=$null;$last=$null
    foreach($s in $samples){
        if($null -eq $s.$property){$segment=$null;$last=$null;continue}
        if(-not $segment -or ($last -and ($s.Time-$last.Time).TotalSeconds -gt 6)){$segment=[Windows.Shapes.Polyline]::new();$segment.Stroke=$window.Resources[$role];$segment.StrokeThickness=2;[void]$canvas.Children.Add($segment)}
        $x=$w*(1-($frame.Time-$s.Time).TotalSeconds/$period);$y=$h*(1-[double]$s.$property/$max);$segment.Points.Add([Windows.Point]::new($x,$y));$last=$s
    }
    Add-DashboardLabel $canvas ('−'+$period+' s') 0 $h 50 'Muted' 10;Add-DashboardLabel $canvas 'jetzt' ($w-40) $h 40 'Muted' 10
    $peak=Format-Rate $max
    if($property -eq 'Rx'){$ui.DashboardRxHint.Text='Adapter gesamt · Skala 0–'+$peak}else{$ui.DashboardTxHint.Text='Adapter gesamt · Skala 0–'+$peak+' · VPN kann doppelt zählen'}
}
function Draw-Dashboard {
    if(-not $script:dashboardReady){return}
    $frame=$script:dashboardFrame
    $ui.DashboardActiveCount.Text=if($frame){[string]$frame.ActiveCount}else{'0'};$ui.DashboardBlockedCount.Text=if($frame){[string]$frame.BlockCount}else{'0'};$ui.DashboardReviewCount.Text=if($frame){[string]$frame.ReviewCount}else{'0'}
    $ui.DashboardGraphHint.Text=$(if($script:dashboardFrozen){'Eingefroren · '+$frame.Time.ToLocalTime().ToString('HH:mm:ss')+' · '}else{''})+'Alle aktiven Programme · Mausrad: Zoom · Fläche ziehen · Ziele zusammengefasst'
    $p=if($frame){$frame.Programs | Where-Object Key -eq $script:dashboardSelectedKey | Select-Object -First 1}else{$null}
    $inactiveSelection=-not $p -and $script:dashboardSelectionSnapshot
    if($inactiveSelection){$p=$script:dashboardSelectionSnapshot}
    $ui.DashboardProgramName.Text=if($p){$p.Name}else{'Programm auswählen'};$ui.DashboardProgramIcon.Source=if($p){$p.Icon}else{$null};$ui.DashboardProgramStatus.Text=if($inactiveSelection){'Letzte Auswahl · derzeit nicht aktiv'}elseif($p){$p.State}else{'Aktive Programme erscheinen automatisch.'}
    $ui.DashboardDirections.Text=if($inactiveSelection){'Keine aktuelle Aktivität erfasst.'}elseif($p){$p.Outgoing.ToString()+' ausgehend · '+$p.Incoming+' eingehend'+"`n"+$p.Unknown+' unbekannt · '+$p.Listening+' lauschend'}else{'Noch keine Verbindungen erfasst.'}
    $ui.DashboardTargets.Text=if($inactiveSelection){'Die Auswahl bleibt erhalten. Wähle ein aktives Programm im Netzwerkbild.'}elseif($p -and $p.Edges.Count){($p.Edges | Select-Object -First 4 | ForEach-Object {$_.Direction+' · '+$_.Address+':'+$_.Port+$(if($_.Blocked){' · blockiert'})}) -join "`n"}else{'Aufbau nicht erfasst oder keine aktuelle Gegenstelle.'}
    $ui.DashboardProgramRx.Text='↓ Empfang '+$(if($p -and -not $inactiveSelection -and $p.RateReady){Format-Rate $p.Rx}else{'nicht gemessen'});$ui.DashboardProgramTx.Text='↑ Versand '+$(if($p -and -not $inactiveSelection -and $p.RateReady){Format-Rate $p.Tx}else{'nicht gemessen'});$ui.DashboardProgramReview.Text=if($inactiveSelection){''}elseif($p){$p.Review}else{''}
    $ui.DashboardDetails.IsEnabled=[bool]($p -and -not $inactiveSelection);$ui.DashboardTemporaryBlock.IsEnabled=[bool]($p -and -not $inactiveSelection -and -not $script:dashboardFrozen -and $script:setupStatus -and $setupStatus.Verified -and [IO.File]::Exists($p.Path) -and -not(Is-Protected $p.Path))
    $last=if($frame){$frame.History | Select-Object -Last 1}else{$null}
    $ui.DashboardRx.Text=if($last -and $null -ne $last.Rx){Format-Rate $last.Rx}else{'Messung …'};$ui.DashboardTx.Text=if($last -and $null -ne $last.Tx){Format-Rate $last.Tx}else{'Messung …'}
    Draw-DashboardNetwork
    if(-not $script:dashboardCameraReady -or (-not $script:dashboardFittedPrograms -and $frame -and $frame.Programs.Count)){Fit-Dashboard}
    $ui.DashboardCenter.IsEnabled=[bool]($p -and -not $inactiveSelection)
    Draw-DashboardChart $ui.DashboardRxGraph 'Rx' 'Accent';Draw-DashboardChart $ui.DashboardTxGraph 'Tx' 'Blue'
    if($frame -and $frame.Problem){$ui.DashboardProgramRx.Text='↓ Empfang: Erfassung eingeschränkt';$ui.DashboardProgramTx.Text='↑ Versand: Erfassung eingeschränkt';$ui.DashboardProgramRx.ToolTip=$frame.Problem;$ui.DashboardProgramTx.ToolTip=$frame.Problem}
}
function Initialize-DashboardMode {
    Reset-DashboardHistory;Initialize-DashboardNavigation;$script:dashboardReady=$true
    $ui.DashboardTab.Add_Click({Show-Panel 'DashboardPanel'})
    $ui.DashboardFreeze.Add_Click({$script:dashboardFrozen=-not $script:dashboardFrozen;$ui.DashboardFreeze.Content=if($dashboardFrozen){'▶ Fortsetzen'}else{'Ⅱ Einfrieren'};if($dashboardFrozen){Draw-Dashboard}else{Update-Dashboard}})
    $ui.DashboardPeriod.Add_SelectionChanged({Draw-Dashboard})
    foreach($canvas in @($ui.DashboardRxGraph,$ui.DashboardTxGraph)){$canvas.Add_SizeChanged({if($script:activePanel -eq 'DashboardPanel'){Draw-Dashboard}})}
    $ui.DashboardActive.Add_Click({Set-OverviewFilter 3});$ui.DashboardReview.Add_Click({Set-OverviewFilter 2})
    $ui.DashboardBlocked.Add_Click({if($script:setupStatus){$last=$setupStatus.Attempts | Sort-Object LastUtc -Descending | Select-Object -First 1;if($last){Open-ProgramBlocks $last.Path}}})
    $ui.DashboardDetails.Add_Click({$p=$script:dashboardFrame.Programs | Where-Object Key -eq $script:dashboardSelectedKey | Select-Object -First 1;if($p){Show-ReviewProgram $p.Path}})
    $ui.DashboardTemporaryBlock.Add_Click({$p=$script:dashboardFrame.Programs | Where-Object Key -eq $script:dashboardSelectedKey | Select-Object -First 1;if($p -and -not $script:dashboardFrozen){Confirm-PermissionChange 'TemporaryBlockProgram' $p.Path}})
    Update-Dashboard
}

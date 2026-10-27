# Session-stable positions and a camera independent of live traffic ranking.
function Initialize-DashboardCamera {
    $script:dashboardNodeSlots=@{};$script:dashboardNextSlot=0;$script:dashboardNodeVisuals=@{}
    $script:dashboardScale=1.0;$script:dashboardOffsetX=0.0;$script:dashboardOffsetY=0.0
    $script:dashboardCameraReady=$false;$script:dashboardFittedPrograms=$false;$script:dashboardDragging=$false
    $script:dashboardViewportWidth=0.0;$script:dashboardViewportHeight=0.0
}
function Get-DashboardPosition([string]$key){
    if(-not $script:dashboardNodeSlots.ContainsKey($key)){$script:dashboardNodeSlots[$key]=$script:dashboardNextSlot;$script:dashboardNextSlot++}
    $slot=[int]$script:dashboardNodeSlots[$key];$ring=0
    while($slot -ge 12*($ring+1)){$slot-=12*($ring+1);$ring++}
    $angle=-[Math]::PI/2+$slot*2*[Math]::PI/(12*($ring+1));$r=420+480*$ring
    [pscustomobject]@{X=$r*[Math]::Cos($angle);Y=$r*[Math]::Sin($angle);TargetX=($r+200)*[Math]::Cos($angle);TargetY=($r+200)*[Math]::Sin($angle)}
}
function Get-DashboardBounds {
    $left=-70.0;$top=-70.0;$right=70.0;$bottom=70.0
    if($script:dashboardFrame){foreach($p in $dashboardFrame.Programs){
        $pos=Get-DashboardPosition $p.Key
        $left=[Math]::Min($left,$pos.X-100);$right=[Math]::Max($right,$pos.X+100);$top=[Math]::Min($top,$pos.Y-40);$bottom=[Math]::Max($bottom,$pos.Y+65)
        if($p.Edges.Count){$left=[Math]::Min($left,$pos.TargetX-80);$right=[Math]::Max($right,$pos.TargetX+80);$top=[Math]::Min($top,$pos.TargetY-40);$bottom=[Math]::Max($bottom,$pos.TargetY+40)}
    }}
    [pscustomobject]@{Left=$left;Top=$top;Right=$right;Bottom=$bottom}
}
function Set-DashboardTransform([double]$scale,[double]$x,[double]$y){
    $script:dashboardScale=[Math]::Max(0.002,[Math]::Min(8.0,$scale));$script:dashboardOffsetX=$x;$script:dashboardOffsetY=$y
    $ui.DashboardNetwork.RenderTransform=[Windows.Media.MatrixTransform]::new([Windows.Media.Matrix]::new($dashboardScale,0,0,$dashboardScale,$x,$y))
    $ui.DashboardZoomText.Text=('{0:0.#} %' -f ($dashboardScale*100))
}
function Fit-Dashboard {
    $w=$ui.DashboardViewport.ActualWidth;$h=$ui.DashboardViewport.ActualHeight;if($w -le 1 -or $h -le 1){return}
    $b=Get-DashboardBounds;$scale=[Math]::Min(($w-32)/[Math]::Max(1,$b.Right-$b.Left),($h-32)/[Math]::Max(1,$b.Bottom-$b.Top));$scale=[Math]::Max(0.002,[Math]::Min(1.0,$scale))
    Set-DashboardTransform $scale ($w/2-($b.Left+$b.Right)/2*$scale) ($h/2-($b.Top+$b.Bottom)/2*$scale)
    $script:dashboardCameraReady=$true
    if($script:dashboardFrame -and $dashboardFrame.Programs.Count){$script:dashboardFittedPrograms=$true}
}
function Zoom-Dashboard([double]$delta,[double]$x,[double]$y){
    $next=[Math]::Max(0.002,[Math]::Min(8.0,$dashboardScale*[Math]::Pow(1.2,$delta/120)));$factor=$next/$dashboardScale
    Set-DashboardTransform $next ($x-($x-$dashboardOffsetX)*$factor) ($y-($y-$dashboardOffsetY)*$factor)
    $script:dashboardCameraReady=$true;$script:dashboardFittedPrograms=$true
}
function Center-DashboardSelection {
    $p=if($script:dashboardFrame){$dashboardFrame.Programs | Where-Object Key -eq $script:dashboardSelectedKey | Select-Object -First 1}else{$null}
    if(-not $p){return};$pos=Get-DashboardPosition $p.Key
    $x=$pos.X;$y=$pos.Y;if($p.Edges.Count){$x=($x+$pos.TargetX)/2;$y=($y+$pos.TargetY)/2}
    $scale=[Math]::Max(1.0,$dashboardScale)
    Set-DashboardTransform $scale ($ui.DashboardViewport.ActualWidth/2-$x*$scale) ($ui.DashboardViewport.ActualHeight/2-$y*$scale)
    $script:dashboardCameraReady=$true;$script:dashboardFittedPrograms=$true
}
function Stop-DashboardDrag {
    $script:dashboardDragging=$false
    if($ui.DashboardViewport.IsMouseCaptured){$ui.DashboardViewport.ReleaseMouseCapture()}
    $ui.DashboardViewport.Cursor='Arrow'
}
function Initialize-DashboardNavigation {
    Initialize-DashboardCamera
    $ui.DashboardViewport.Add_PreviewMouseWheel({param($sender,$e) $p=$e.GetPosition($sender);Zoom-Dashboard $e.Delta $p.X $p.Y;$e.Handled=$true})
    $ui.DashboardZoomIn.Add_Click({Zoom-Dashboard 120 ($ui.DashboardViewport.ActualWidth/2) ($ui.DashboardViewport.ActualHeight/2)})
    $ui.DashboardZoomOut.Add_Click({Zoom-Dashboard -120 ($ui.DashboardViewport.ActualWidth/2) ($ui.DashboardViewport.ActualHeight/2)})
    $ui.DashboardFit.Add_Click({Fit-Dashboard});$ui.DashboardCenter.Add_Click({Center-DashboardSelection})
    $ui.DashboardViewport.Add_MouseLeftButtonDown({param($sender,$e)
        $script:dashboardDragStart=$e.GetPosition($sender);$script:dashboardDragX=$dashboardOffsetX;$script:dashboardDragY=$dashboardOffsetY;$script:dashboardDragging=$true
        [void]$sender.CaptureMouse();$sender.Cursor='SizeAll';$e.Handled=$true
    })
    $ui.DashboardViewport.Add_MouseMove({param($sender,$e) if($script:dashboardDragging){if($e.LeftButton -ne 'Pressed'){Stop-DashboardDrag;return};$p=$e.GetPosition($sender);Set-DashboardTransform $dashboardScale ($dashboardDragX+$p.X-$dashboardDragStart.X) ($dashboardDragY+$p.Y-$dashboardDragStart.Y)}})
    $ui.DashboardViewport.Add_MouseLeftButtonUp({if($script:dashboardDragging){Stop-DashboardDrag}})
    $ui.DashboardViewport.Add_LostMouseCapture({$script:dashboardDragging=$false;$ui.DashboardViewport.Cursor='Arrow'})
    $ui.DashboardViewport.Add_SizeChanged({param($sender,$e)
        $w=$sender.ActualWidth;$h=$sender.ActualHeight
        if(-not $script:dashboardCameraReady -or -not $script:dashboardFittedPrograms){Fit-Dashboard}else{Set-DashboardTransform $dashboardScale ($dashboardOffsetX+($w-$dashboardViewportWidth)/2) ($dashboardOffsetY+($h-$dashboardViewportHeight)/2)}
        $script:dashboardViewportWidth=$w;$script:dashboardViewportHeight=$h
    })
}

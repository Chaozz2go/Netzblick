function Set-WorldTransform([double]$scale,[double]$x,[double]$y){
    $script:worldScale=[Math]::Max(1.0,[Math]::Min(8.0,$scale))
    $script:worldOffsetX=[Math]::Min(0.0,[Math]::Max(1000*(1-$worldScale),$x))
    $script:worldOffsetY=[Math]::Min(0.0,[Math]::Max(500*(1-$worldScale),$y))
    $ui.WorldMap.RenderTransform=New-Object Windows.Media.MatrixTransform([Windows.Media.Matrix]::new($worldScale,0,0,$worldScale,$worldOffsetX,$worldOffsetY))
    $ui.WorldZoomText.Text=('{0:0} % · Mausrad: Zoom · Ziehen: Verschieben' -f ($worldScale*100))
}
function Zoom-World([double]$delta,[double]$x,[double]$y){
    $next=[Math]::Max(1.0,[Math]::Min(8.0,$worldScale*[Math]::Pow(1.2,$delta/120)))
    $factor=$next/$worldScale
    Set-WorldTransform $next ($x-($x-$worldOffsetX)*$factor) ($y-($y-$worldOffsetY)*$factor)
}
function Initialize-WorldNavigation {
    $script:worldDragging=$false;Set-WorldTransform 1 0 0
    $ui.WorldViewport.Add_PreviewMouseWheel({param($sender,$e) try{$p=$e.GetPosition($ui.WorldViewport);Zoom-World $e.Delta $p.X $p.Y;$e.Handled=$true}catch{$ui.WorldSummary.Text='Zoom konnte nicht aktualisiert werden: '+$_.Exception.GetBaseException().Message}})
    $ui.ResetWorldZoom.Add_Click({Set-WorldTransform 1 0 0})
    $ui.WorldViewport.Add_MouseLeftButtonDown({param($sender,$e)
        if($worldScale -le 1){return};$script:worldDragStart=$e.GetPosition($ui.WorldViewport);$script:worldDragX=$worldOffsetX;$script:worldDragY=$worldOffsetY;$script:worldDragging=$true;[void]$ui.WorldViewport.CaptureMouse();$ui.WorldViewport.Cursor='SizeAll'
    })
    $ui.WorldViewport.Add_MouseMove({param($sender,$e) if($script:worldDragging -and $e.LeftButton -eq 'Pressed'){$p=$e.GetPosition($ui.WorldViewport);Set-WorldTransform $worldScale ($worldDragX+$p.X-$worldDragStart.X) ($worldDragY+$p.Y-$worldDragStart.Y)}})
    $ui.WorldViewport.Add_MouseLeftButtonUp({$script:worldDragging=$false;$ui.WorldViewport.ReleaseMouseCapture();$ui.WorldViewport.Cursor='Arrow'})
    $ui.WorldViewport.Add_LostMouseCapture({$script:worldDragging=$false;$ui.WorldViewport.Cursor='Arrow'})
}

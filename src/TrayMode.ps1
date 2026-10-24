function Show-NetzblickWindow {
    $window.Show();$window.WindowState='Normal';[void]$window.Activate()
}
function Initialize-TrayMode {
    Add-Type -AssemblyName @('System.Windows.Forms','System.Drawing')
    $script:exitNetzblick=$false
    $script:tray=New-Object System.Windows.Forms.NotifyIcon
    $tray.Icon=[Drawing.SystemIcons]::Shield;$tray.Text='Netzblick';$tray.Visible=$true
    $menu=New-Object System.Windows.Forms.ContextMenuStrip
    $open=$menu.Items.Add('Netzblick öffnen');$open.Add_Click({Show-NetzblickWindow})
    $requests=$menu.Items.Add('Blockierte Versuche');$requests.Add_Click({Show-NetzblickWindow;Show-Panel 'AccessPanel';$ui.AccessViews.SelectedIndex=0})
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $quit=$menu.Items.Add('Oberfläche beenden · Dienst läuft weiter')
    $quit.Add_Click({$script:exitNetzblick=$true;$window.Close()})
    $tray.ContextMenuStrip=$menu
    $tray.Add_DoubleClick({Show-NetzblickWindow})
    $tray.Add_BalloonTipClicked({Show-NetzblickWindow;Show-Panel 'AccessPanel';$ui.AccessViews.SelectedIndex=0;if($script:setupNoticeTarget -and $setupStatus){$ui.AccessRequests.SelectedItem=$setupStatus.Attempts | Where-Object {$_.Key -eq $setupNoticeTarget.Key} | Select-Object -First 1}})
    $window.Add_Closing({if(-not $script:exitNetzblick){$_.Cancel=$true;$window.Hide()}})
    $window.Add_StateChanged({if($window.WindowState -eq 'Minimized'){$window.Hide()}})
    $window.Add_Closed({$tray.Visible=$false;$tray.Dispose()})
    if($script:startInTray){$window.Add_ContentRendered({$window.Hide()})}
}

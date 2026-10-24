function Initialize-EndpointNames {
    $script:endpointNames=New-Object Netzblick.EndpointNames
    $ui.ResolveNames.Add_Checked({$endpointNames.SetEnabled($true);Refresh-Detail;Update-InspectionNames})
    $ui.ResolveNames.Add_Unchecked({$endpointNames.SetEnabled($false);Refresh-Detail;Update-InspectionNames})
    $window.Add_Closed({$endpointNames.Dispose()})
}
function Get-EndpointName([string]$address) {
    if($null -eq $script:endpointNames){return 'DNS ausgeschaltet'}
    return $endpointNames.Get($address)
}
function Show-ConnectionDetails {
    $row=$ui.Connections.SelectedItem
    if($null -eq $row){$ui.SocketDetails.Text='Eine Gegenstelle auswählen: IP, DNS-Name und Diensthinweis erscheinen hier.';return}
    $scope=[Netzblick.EndpointInfo]::Scope($row.Address)
    $ui.SocketDetails.Text="Gegenstelle: $($row.Remote)`nName: $($row.PeerName)`nBereich: $scope`nHinweis: $($row.ServiceHint)`n`nBeobachtung: $($row.State)`nProtokoll: $($row.Protocol) · PID: $($row.Pid)`nLokal: $($row.Local)`n`nWarum? Port und DNS-Name liefern Anhaltspunkte. Ob es um Updates, Anmeldung, Inhalte oder Telemetrie geht, ist ohne Anwendungsdaten nicht feststellbar. Ein DNS-Name belegt weder Betreiber noch Sicherheit; mehrere Dienste können dieselbe IP nutzen."
}
function Update-InspectionNames {
    if($null -eq $script:inspectionRows){return}
    $changed=$false
    $index=0
    foreach($row in @($inspectionRows.ToArray())) {
        $index++
        if($ui.ResolveNames.IsChecked -and $index -gt 100){$name='DNS: nur die neuesten 100 Einträge'}else{$name=Get-EndpointName $row.PeerAddress}
        if($row.PeerName -ne $name){$row.PeerName=$name;$changed=$true}
    }
    if($changed){$ui.InspectionEvents.Items.Refresh()}
}

# Connection initiation and transferred bytes are independent measurements.
function Get-ConnectionDirection($row,[string]$path){
    if($row.IsBlock -and $row.Direction -in @('Ausgehend','Eingehend')){return [pscustomobject]@{Label=$row.Direction;Source='Windows-Blockereignis'}}
    if($row.State -eq 'Lauscht'){return [pscustomobject]@{Label='Lauschend';Source='TCP wartet auf Verbindungen; keine Gegenstelle verbunden'}}
    if($row.State -eq 'SYN gesendet'){return [pscustomobject]@{Label='Ausgehend';Source='TCP-Aufbau: SYN gesendet'}}
    if($row.State -eq 'SYN empfangen'){return [pscustomobject]@{Label='Eingehend';Source='TCP-Aufbau: SYN empfangen'}}
    if($row.Protocol -like 'TCP*' -and $row.Local -and $row.ProcessStartUtc){
        try{
            $match=[regex]::Match([string]$row.Local,'^(?:\[(.+)\]|(.+)):(\d+)$')
            if($match.Success){
                $address=if($match.Groups[1].Success){$match.Groups[1].Value}else{$match.Groups[2].Value}
                $key=[Netzblick.Capture.FlowStore]::KeyFor($path,[int]$row.Pid,[datetime]$row.ProcessStartUtc,$row.Protocol,$address,[int]$match.Groups[3].Value,$row.Address,[int]$row.Port)
                if($key -and $script:connectionDirectionIndex -and $connectionDirectionIndex.ContainsKey($key)){return [pscustomobject]@{Label=$connectionDirectionIndex[$key];Source='Beobachteter TCP-Connect/Accept-Aufbau (ETW)'}}
            }
        }catch{}
    }
    return [pscustomobject]@{Label='Unbekannt';Source=$(if($row.Protocol -like 'UDP*'){'UDP: Datenrichtung ist kein Verbindungsaufbau'}else{'Aufbau nicht sicher erfasst; keine Ableitung aus Ports oder Empfang/Versand'})}
}
function Select-ConnectionDirection($rows,[int]$filter){
    @($rows | Where-Object {switch($filter){1{$_.ConnectionDirection -eq 'Ausgehend'} 2{$_.ConnectionDirection -eq 'Eingehend'} 3{$_.ConnectionDirection -eq 'Lauschend'} 4{$_.ConnectionDirection -eq 'Unbekannt'} default{$true}}})
}
function Initialize-DirectionMode {
    $ui.ConnectionDirectionFilter.Add_SelectionChanged({Refresh-Detail})
}

function Get-ProgramDirectionSummary($program){
    $counts=@{Ausgehend=0;Eingehend=0;Lauschend=0;Unbekannt=0}
    foreach($row in @($program.Rows)){$counts[(Get-ConnectionDirection $row $program.Path).Label]++}
    if(-not @($program.Rows).Count){return 'Aufbau nicht erfasst'}
    return '→ '+$counts.Ausgehend+' ausgehend · ← '+$counts.Eingehend+' eingehend · '+$counts.Lauschend+' lauschend · '+$counts.Unbekannt+' unbekannt'
}

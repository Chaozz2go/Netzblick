#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Add-Type -Path (Join-Path $root 'src\NetworkReader.cs')
[void][Reflection.Assembly]::LoadFrom((Join-Path $root 'lib\Microsoft.Diagnostics.FastSerialization.dll'))
[void][Reflection.Assembly]::LoadFrom((Join-Path $root 'lib\Microsoft.Diagnostics.Tracing.TraceEvent.dll'))
[void][Reflection.Assembly]::LoadFrom((Join-Path $root 'lib\Netzblick.Capture.dll'))
$capture=[Netzblick.Capture.NetworkCapture]::Start()
$clientScript=Join-Path $env:RUNNER_TEMP ('netzblick-flow-'+[guid]::NewGuid().ToString('N')+'.ps1')
@'
param([int]$Port,[string]$Address)
$c=New-Object Net.Sockets.TcpClient ([Net.IPAddress]::Parse($Address).AddressFamily)
try{$c.Connect($Address,$Port);$c.GetStream().WriteByte(1);[void]$c.GetStream().ReadByte()}finally{$c.Close()}
'@ | Set-Content -LiteralPath $clientScript -Encoding UTF8
try{
 foreach($address in @('127.0.0.1','::1')){
  $listener=$null;$accepted=$null;$child=$null
  try{
   $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Parse($address),0);$listener.Start();$port=$listener.LocalEndpoint.Port
   $child=Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$clientScript+'" -Port '+$port+' -Address '+$address) -PassThru
   $accept=$listener.AcceptTcpClientAsync();if(-not $accept.Wait(10000)){throw 'Lokale Testverbindung fehlt.'};$accepted=$accept.Result
   $deadline=[datetime]::UtcNow.AddSeconds(8);$matched=$false
   do{
    Start-Sleep -Milliseconds 150
    $flows=@($capture.Directions());$sockets=@([Netzblick.Reader]::Collect().Rows | Where-Object {$_.State -eq 'Verbunden' -and $_.Pid -in @($PID,$child.Id)})
    $directions=@{}
    foreach($s in $sockets){
     $m=[regex]::Match($s.Local,'^(?:\[(.+)\]|(.+)):(\d+)$');if(-not $m.Success){continue}
     $local=if($m.Groups[1].Success){$m.Groups[1].Value}else{$m.Groups[2].Value}
     $key=[Netzblick.Capture.FlowStore]::KeyFor($s.Path,$s.Pid,$s.ProcessStartUtc,$s.Protocol,$local,[int]$m.Groups[3].Value,$s.Address,$s.Port)
     $flow=$flows | Where-Object Key -eq $key | Select-Object -First 1
     if($flow -and ($s.Port -eq $port -or [int]$m.Groups[3].Value -eq $port)){$directions[$s.Pid]=$flow.Direction}
    }
    $matched=$directions[$PID] -eq 'Eingehend' -and $directions[$child.Id] -eq 'Ausgehend'
   }while(-not $matched -and [datetime]::UtcNow -lt $deadline)
   if(-not $matched){throw ('TCP-Richtungen nicht sicher erfasst: '+$address+'; '+($directions | ConvertTo-Json -Compress)+'; '+$capture.Error)}
   Write-Output ('PASS: echtes TCP '+$address+' – Connect ausgehend, Accept eingehend, Zuordnung zu PID/Prozessstart und Socket-Tupel.')
  }finally{if($accepted){$accepted.Close()};if($listener){$listener.Stop()};if($child){if(-not $child.WaitForExit(3000)){$child.Kill()};$child.Dispose()}}
 }
}finally{$capture.Dispose();Remove-Item -LiteralPath $clientScript -Force -ErrorAction SilentlyContinue}

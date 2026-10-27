using System;
using System.Collections.Generic;
using Netzblick;
using Netzblick.Capture;

public static class UserModeChecks {
 public static int Run(){
  int count=0;Action<bool,string> check=(ok,name)=>{if(!ok)throw new Exception("User mode check failed: "+name);count++;};
  var blocked=NetworkPolicy.PublicRanges();
  foreach(string ip in new string[]{"10.0.0.1","10.255.255.255","100.64.0.1","100.127.255.254","127.0.0.1","169.254.1.1","172.16.0.1","172.31.255.255","192.168.1.1","224.0.0.251","239.255.255.250","255.255.255.255","::1","fc00::1","fdff:ffff::1","fe80::1","ff01::1","ff02::fb","febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff"}){
   check(!blocked.Exists(r=>r.Contains(ip)),"private/local address not denied: "+ip);
  }
  foreach(string ip in new string[]{"0.0.0.0","8.8.8.8","1.1.1.1","9.255.255.255","11.0.0.0","100.63.255.255","100.128.0.0","126.255.255.255","128.0.0.0","169.253.255.255","169.255.0.0","172.15.255.255","172.32.0.0","192.167.255.255","192.169.0.0","224.0.1.1","238.255.255.255","240.0.0.1","::","::2","2001:4860:4860::8888","2606:4700:4700::1111","fec0::1","ff00::1","ff03::1","ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff"}){
   check(blocked.Exists(r=>r.Contains(ip)),"non-private address denied: "+ip);
  }
  check(NetworkPolicy.ClassifyScope("*")=="Blocked","block all scope");
  check(NetworkPolicy.ClassifyScope(NetworkPolicy.PrivateOnlyBlockScope())=="Private","private-only scope roundtrip");
  check(NetworkPolicy.ClassifyScope("8.8.8.8")=="Modified","arbitrary scope does not masquerade as managed mode");
  check(NetworkPolicy.CanonicalScope("192.168.0.0/16")==NetworkPolicy.CanonicalScope("192.168.0.0-192.168.255.255"),"CIDR/range equivalence");
  check(NetworkPolicy.CanonicalScope("10.0.0.0/9,10.128.0.0/9")==NetworkPolicy.CanonicalScope("10.0.0.0/8"),"adjacent ranges merge");
  check(NetworkPolicy.CanonicalScope("10.0.0.0/8,10.2.0.0/16")==NetworkPolicy.CanonicalScope("10.0.0.0/8"),"nested ranges merge");
  check(NetworkPolicy.CanonicalScope("fc00:0000::/7")==NetworkPolicy.CanonicalScope("fc00::-fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff"),"IPv6 canonical representation");
  foreach(var range in blocked){check(AddressRange.Compare(range.First,range.Last)<=0,"valid complement range");}
  var random=new Random(43);
  for(int i=0;i<2000;i++){
   var bytes=new byte[i%2==0?4:16];random.NextBytes(bytes);string ip=new System.Net.IPAddress(bytes).ToString();
   bool allowed=false;foreach(string subnet in NetworkPolicy.PrivateScopes)if(AddressRange.Parse(subnet).Contains(ip)){allowed=true;break;}
   check(blocked.Exists(r=>r.Contains(ip))!=allowed,"private scope/complement partition");
  }
  var traffic=new TrafficStore();var time=new DateTime(2026,10,24,12,0,0,DateTimeKind.Utc);
  var app=new ProcessIdentity{Pid=100,Path="C:\\App\\client.exe",Name="client",StartUtc=time};
  traffic.Add(app,time.AddSeconds(1),true,1200,"8.8.8.8",443,"TCPv4");
  traffic.Add(app,time.AddSeconds(2),false,2400,"8.8.8.8",443,"TCPv4");
  var second=new ProcessIdentity{Pid=101,Path=app.Path,Name="client",StartUtc=time};
  traffic.Add(second,time.AddSeconds(3),true,300,"2606:4700::1",443,"UDPv6");
  var values=traffic.Snapshot();check(values.Count==1,"instances grouped by path");check(values[0].Sent==1500 && values[0].Received==2400,"send/receive byte counts");
  check(traffic.Peers().Count==2,"TCP and UDP peers retained");
  traffic.Add(app,time.AddSeconds(4),true,-1,"1.1.1.1",443,"TCPv4");check(traffic.Invalid==1,"negative byte count rejected");
  var reused=new ProcessIdentity{Pid=100,Path="C:\\Other\\app.exe",Name="other",StartUtc=time.AddSeconds(20)};
  traffic.Add(reused,time.AddSeconds(10),true,400,"1.1.1.1",443,"TCPv4");
  check(traffic.Snapshot().Find(r=>r.Path==reused.Path)==null,"late event not assigned to replacement PID");
  check(traffic.Snapshot().Find(r=>r.Key=="PID:100").Sent==400,"unattributed bytes shown separately");
  check(TrafficStore.Rate(100,300,2)==100,"rate from measured delta");check(TrafficStore.Rate(100,50,2)==0,"counter reset bounded");check(TrafficStore.Rate(0,50,0)==0,"zero interval bounded");
  var flows=new FlowStore();
  string fk=FlowStore.KeyFor(app.Path,app.Pid,app.StartUtc,"TCPv4","127.0.0.1",50000,"127.0.0.1",443);
  flows.Observe(app,time.AddSeconds(1),"TCPv4","127.0.0.1",50000,"127.0.0.1",443,false,false);
  check(flows.Snapshot().Count==1 && flows.Snapshot()[0].Direction=="Ausgehend","connect defines initiation, not received bytes");
  check(fk==FlowStore.KeyFor(app.Path,app.Pid,app.StartUtc,"TCPv4","127.0.0.1",443,"127.0.0.1",50000),"accept/connect endpoint orientation does not affect tuple identity");
  check(fk!=FlowStore.KeyFor(app.Path,app.Pid,app.StartUtc.AddSeconds(10),"TCPv4","127.0.0.1",443,"127.0.0.1",50000),"PID reuse/start time cannot inherit direction");
  check(fk!=FlowStore.KeyFor(app.Path,app.Pid,app.StartUtc,"TCPv4","127.0.0.1",443,"127.0.0.1",50001),"different local ephemeral port is a separate flow");
  flows.Observe(app,time.AddSeconds(2),"TCPv4","127.0.0.1",443,"127.0.0.1",50000,true,false);
  check(flows.Snapshot()[0].Direction=="Unbekannt","same-process ambiguous loopback roles stay unknown");
  flows.Observe(app,time.AddSeconds(3),"TCPv4","127.0.0.1",443,"127.0.0.1",50000,false,true);
  check(flows.Snapshot().Count==0,"disconnect removes stale tuple role");
  flows.Observe(reused,time.AddSeconds(1),"TCPv4","1.1.1.1",50001,"8.8.8.8",443,false,false);
  check(flows.Snapshot().Count==0,"late flow event rejected for a replacement process");
  check(FlowStore.KeyFor(app.Path,app.Pid,app.StartUtc,"TCPv6","::ffff:127.0.0.1",50000,"::ffff:127.0.0.1",443)==FlowStore.KeyFor(app.Path,app.Pid,app.StartUtc,"TCPv6","127.0.0.1",50000,"127.0.0.1",443),"mapped IPv6 endpoints normalized");
  Console.WriteLine("PASS: "+count+" policy/traffic checks.");return count;
 }
}


using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Text;
using System.Threading;
using Netzblick;

// Development checks: no firewall changes. Optional --loopback probes localhost only.
public static class CoreChecks {
 static int checks;
 static void Assert(bool value,string name){if(!value)throw new Exception("FAILED: "+name);checks++;}
 static void Range(BinaryWriter w,string start,string end,string country){w.Write(IPAddress.Parse(start).GetAddressBytes());w.Write(IPAddress.Parse(end).GetAddressBytes());w.Write(Encoding.ASCII.GetBytes(country));}
 static bool Reject(string command){try{ProbeCommand.Parse(command);return false;}catch(ArgumentException){return true;}}
 public static int Main(string[] args){
  string temp=Path.Combine(Path.GetTempPath(),"netzblick-check-"+Guid.NewGuid().ToString("N"));
  Directory.CreateDirectory(temp);
  try {
   File.WriteAllText(Path.Combine(temp,"geo-version.txt"),"TEST FIXTURE");
   File.WriteAllText(Path.Combine(temp,"countries.tsv"),"AU\t-25\t134\tAustralia\nUS\t39\t-98\tUnited States\n");
   using(var w=new BinaryWriter(File.Create(Path.Combine(temp,"geo-country.bin")))){
    w.Write(Encoding.ASCII.GetBytes("NBG1"));w.Write(2);w.Write(2);
    Range(w,"1.0.0.0","1.0.0.255","AU");Range(w,"8.8.8.8","8.8.8.8","US");
    Range(w,"2001:4860::","2001:4860:ffff:ffff:ffff:ffff:ffff:ffff","US");
    Range(w,"2606:4700::","2606:4700:ffff:ffff:ffff:ffff:ffff:ffff","AU");
   }
   var geo=new GeoDatabase(temp);
   Assert(geo.Lookup("1.0.0.0").Code=="AU","IPv4 lower inclusive bound");
   Assert(geo.Lookup("1.0.0.255").Code=="AU","IPv4 upper inclusive bound");
   Assert(geo.Lookup("1.0.1.0").Code=="","IPv4 gap");
   Assert(geo.Lookup("8.8.8.8").Code=="US","single address range");
   Assert(geo.Lookup("8.8.8.9").Code=="","after last IPv4 range");
   Assert(geo.Lookup("::ffff:8.8.8.8").Code=="US","IPv4 mapped IPv6");
   Assert(geo.Lookup("2001:4860::").Code=="US","IPv6 lower inclusive bound");
   Assert(geo.Lookup("2001:4860:ffff:ffff:ffff:ffff:ffff:ffff").Code=="US","IPv6 upper inclusive bound");
   Assert(geo.Lookup("2001:4861::").Code=="","IPv6 gap");
   Assert(geo.Lookup("2606:4700::1").Code=="AU","IPv6 second range");
   Assert(!geo.Lookup("2606:4701::").CanPlot,"after last IPv6 range");
   foreach(string ip in new string[]{"10.0.0.1","172.16.0.1","172.31.255.255","192.168.1.1","127.0.0.1","169.254.1.1","100.64.0.1","100.127.255.254","192.0.2.1","198.51.100.1","203.0.113.1","198.18.0.1","224.0.0.1","255.255.255.255","0.0.0.0","::1","::","fc00::1","fd00::1","fe80::1%12","ff02::1","2001:db8::1","64:ff9b::1"}){
    Assert(GeoDatabase.Special(IPAddress.Parse(ip))!=null,"special address: "+ip);
    Assert(!geo.Lookup(ip).CanPlot,"no fabricated location: "+ip);
   }
   foreach(string ip in new string[]{"1.1.1.1","8.8.8.8","100.63.255.255","100.128.0.0","172.15.255.255","172.32.0.0","2001:4860::1","2606:4700::1"})Assert(GeoDatabase.Special(IPAddress.Parse(ip))==null,"public address classification: "+ip);
   Assert(!geo.Lookup("bad input").CanPlot,"invalid lookup input");
   Assert(ProbeCommand.Parse("ping example.org").Mode=="ping","ping command");
   Assert(ProbeCommand.Parse("traceroute -6 example.org").Mode=="tracert","traceroute alias");
   Assert(ProbeCommand.Parse("tracert -4 127.0.0.1").Family==4,"IPv4 switch");
   Assert(ProbeCommand.Parse("ping -6 ::1").Target=="::1","IPv6 literal");
   Assert(ProbeCommand.Parse("PING bücher.de").Target=="xn--bcher-kva.de","IDN conversion");
   foreach(string command in new string[]{"", "cmd /c whoami","ping example.org & whoami","ping example.org;whoami","ping $(whoami)","ping `whoami`","ping https://example.org","ping example.org:443","ping -n 100 example.org","ping -4 ::1","ping -6 127.0.0.1","ping 255.255.255.255","ping ff02::1","ping 0.0.0.0","ping example.org | calc","tracert example.org > file"})Assert(Reject(command),"reject unsupported/injected input: "+command);
   string path=Path.Combine(temp,"geo-country.bin");File.WriteAllBytes(path,new byte[]{1,2,3});
   bool invalid=false;try{new GeoDatabase(temp);}catch(InvalidDataException){invalid=true;}
   Assert(invalid,"reject truncated database");
   if(args.Length>0){
    var actual=new GeoDatabase(args[0]);
    Assert(actual.Countries.Count>=170,"actual country coordinates");
    Assert(actual.Lookup("8.8.8.8").Code.Length==2,"actual database public IPv4 lookup");
    Assert(actual.Lookup("2001:4860:4860::8888").Code.Length==2,"actual database public IPv6 lookup");
    if(args.Length>1 && File.Exists(args[1])){
     foreach(string line in File.ReadLines(args[1])){
      var p=line.Split('\t');var a=IPAddress.Parse(p[0]);
      if(GeoDatabase.Special(a)==null)Assert(actual.Lookup(p[0]).Code==(p[1]=="ZZ"?"":p[1]),"CSV/binary vector: "+p[0]);
     }
    }
   }
   if(Array.IndexOf(args,"--loopback")>=0){
    using(var session=ProbeSession.Start("tracert -4 127.0.0.1")){
     var clock=Stopwatch.StartNew();while(!session.IsCompleted && clock.ElapsedMilliseconds<5000)Thread.Sleep(20);
     Assert(session.IsCompleted,"loopback traceroute completes");
     var events=session.Drain();foreach(var e in events)Console.WriteLine(e.Type+": "+e.Text);Assert(events.Exists(e=>e.Type=="probe" && e.Status=="Success" && e.Number==1),"loopback reached at hop 1");
     Assert(events.Exists(e=>e.Type=="summary"),"loopback traceroute summary");
    }
    using(var session=ProbeSession.Start("ping -4 127.0.0.1")){
     Thread.Sleep(100);var clock=Stopwatch.StartNew();session.Cancel();
     while(!session.IsCompleted && clock.ElapsedMilliseconds<2500)Thread.Sleep(20);
     Assert(session.IsCompleted,"ping cancellation bounded");
     Assert(session.Drain().Exists(e=>e.Type=="summary" && e.Text=="Abgebrochen."),"cancellation reported");
    }
   }
   checks+=InspectionChecks.Run();
   checks+=EndpointChecks.Run();
   checks+=AccessChecks.Run();
   checks+=UserModeChecks.Run();
   Console.WriteLine("PASS: "+checks+" core checks. No firewall modifications.");return 0;
  }finally{Directory.Delete(temp,true);}
 }
}

using System;
using System.Threading;
using Netzblick;
public static class EndpointChecks {
 public static int Run(){
  int count=0;Action<bool,string> check=(ok,name)=>{if(!ok)throw new Exception("Endpoint check: "+name);count++;};
  check(EndpointInfo.Scope("::ffff:127.0.0.1")=="Dieser Computer","mapped loopback");
  check(EndpointInfo.Scope("192.168.0.1")=="Privates Netz","private IPv4");
  check(EndpointInfo.Scope("fc00::1")=="Privates Netz","private IPv6");
  check(!EndpointInfo.CanResolve("224.0.0.251"),"no multicast DNS query");
  check(!EndpointInfo.CanResolve("::"),"no wildcard DNS query");
  check(!EndpointInfo.CanResolve("not-an-ip"),"no hostname injection");
  check(EndpointInfo.Service("UDPv6",443).Contains("QUIC") && EndpointInfo.Service("UDP",443).Contains("möglich"),"QUIC is a hint");
  check(EndpointInfo.Service("TCP",50001).Contains("nicht ermittelt"),"unknown purpose");
  int calls=0;var release=new ManualResetEventSlim(false);
  using(var names=new EndpointNames(ip=>{Interlocked.Increment(ref calls);release.Wait();return "cdn.example.test";})){
   check(names.Get("8.8.8.8")=="DNS ausgeschaltet" && calls==0,"opt-in required");
   names.SetEnabled(true);
   for(int i=1;i<=4;i++)names.Get("8.8.8."+i);
   check(SpinWait.SpinUntil(()=>calls==4,3000),"four lookups start");
   check(names.Get("8.8.8.5").Contains("wartet"),"concurrency bounded");
   names.Get("8.8.8.1");check(calls==4,"in-flight query deduplicated");
   release.Set();
   check(SpinWait.SpinUntil(()=>names.Get("8.8.8.1").Contains("(Reverse-DNS)"),3000),"resolver completion visible");
   check(names.Get("8.8.8.1")=="cdn.example.test (Reverse-DNS)","name provenance");
   names.SetEnabled(false);check(names.Get("8.8.8.1")=="DNS ausgeschaltet","opt-out hides cached name");
  }
  using(var names=new EndpointNames(ip=>"unsafe\nname")){
   names.SetEnabled(true);names.Get("1.1.1.1");
   check(SpinWait.SpinUntil(()=>names.Get("1.1.1.1")=="DNS-Name nicht darstellbar",3000),"control characters rejected");
  }
  using(var names=new EndpointNames(ip=>"1.1.1.1")){
   names.SetEnabled(true);names.Get("1.1.1.1");
   check(SpinWait.SpinUntil(()=>names.Get("1.1.1.1")=="Kein DNS-Name gefunden",3000),"numeric answer not presented as DNS");
  }
  return count;
 }
}

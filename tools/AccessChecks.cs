using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Netzblick;
public static class AccessChecks {
 public static int Run(){
  int n=0;Action<bool,string> check=(ok,name)=>{if(!ok)throw new Exception("Access check: "+name);n++;};
  DateTime now=DateTime.UtcNow;
  Func<string,DateTime,BlockEvent> make=(path,time)=>new BlockEvent{Application=path,Direction="Ausgehend",Destination="203.0.113.10",DestinationPort="443",Protocol="TCP",TimeUtc=time};
  var queue=new AccessQueue();queue.Observe(make(@"C:\Apps\one.exe",now),true);queue.Observe(make(@"c:\apps\ONE.exe",now.AddSeconds(1)),true);
  check(queue.Snapshot().Count==1,"same program grouped regardless of case");
  var request=queue.Snapshot()[0];check(request.Count==2 && request.Decision=="Pending","default decision remains blocked pending");
  check(request.Targets.Count==1,"duplicate target deduplicated");
  check(request.Evidence.Contains("Sitzungsfilter"),"own filter provenance");
  queue.Decide(request.Key,"Blocked");queue.Observe(make(request.Path,now.AddSeconds(2)),false);
  check(queue.Find(request.Key).Decision=="Blocked","repeated attempt does not reprompt denied program");
  queue.Decide(request.Key,"Allowed");check(queue.Find(request.Key).AllowedUtc.HasValue,"grant timestamp");
  var old=make(request.Path,now.AddMinutes(-1));queue.Observe(old,true);
  check(!queue.Find(request.Key).BlockedAfterAllow,"old queued event not interpreted as failed grant");
  queue.Observe(make(request.Path,DateTime.UtcNow.AddSeconds(1)),false);
  check(queue.Find(request.Key).BlockedAfterAllow,"later Windows block after grant is visible");
  queue.Decide(request.Key,"Blocked");check(!queue.Find(request.Key).AllowedUtc.HasValue,"revoke clears grant");
  var inbound=make(@"C:\Apps\two.exe",now);inbound.Direction="Eingehend";queue.Observe(inbound,true);
  check(queue.Incoming==1 && queue.Snapshot().Count==1,"inbound event not an outbound request");
  var unknown=make("",now);queue.Observe(unknown,true);check(queue.Unknown==1,"missing program is surfaced");
  for(int i=0;i<600;i++)queue.Observe(make(@"C:\Apps\p"+i+".exe",now),true);
  check(queue.Snapshot().Count==512 && queue.Overflow>0,"bounded queue reports truncation");
  for(int i=0;i<25;i++){var e=make(request.Path,now);e.Destination="203.0.113."+i;queue.Observe(e,true);}
  check(queue.Find(request.Key).Targets.Count==20,"target list bounded");
  check(AccessQueue.CanAllow(@"C:\Apps\app.exe"),"canonical local executable");
  foreach(string path in new string[]{@"\\server\app.exe",@"\Device\HarddiskVolume3\app.exe",@"C:\Apps\..\app.exe",@"C:\Apps\app.exe:stream.exe",@"C:\Apps\*.exe","System","https://host/app.exe"}){
   check(!AccessQueue.CanAllow(path),"reject broad or unresolved app identity");
  }
  bool rejected=false;try{queue.Decide(request.Key,"PermitAll");}catch(ArgumentException){rejected=true;}check(rejected,"invalid decision rejected");
  if(IntPtr.Size==8){WfpGate.ValidateLayout();check(Marshal.SizeOf(typeof(WfpGate.Filter))==200,"Windows x64 native layout");}
  return n;
 }
}
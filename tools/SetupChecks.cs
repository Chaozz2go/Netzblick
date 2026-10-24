using System;
using Netzblick;
public static class SetupChecks {
 public static int Run(){
  int count=0;Action<bool,string> check=(ok,label)=>{if(!ok)throw new Exception("Setup: "+label);count++;};
  Func<SetupRule> rule=()=>new SetupRule{Id=Guid.NewGuid().ToString(),Name="LDAPS zum DC",Path=@"C:\Apps\server.exe",Direction="Ausgehend",Address="10.0.0.10",Protocol=6,Port=636,Action="Allow"};
  Action<SetupRule,string> reject=(r,label)=>{try{r.Validate();throw new Exception("Accepted invalid "+label);}catch(ArgumentException){count++;}};
  var r=rule();r.Validate();check(r.Scope.Contains("636"),"port visible");
  var queue=new SetupQueue();DateTime now=DateTime.UtcNow;
  var e=new BlockEvent{Application=r.Path,Direction="Ausgehend",Destination="10.0.0.10",DestinationPort="636",Source="10.0.0.5",SourcePort="55001",Protocol="TCP",TimeUtc=now};
  queue.Observe(e,true);queue.Observe(e,true);var a=queue.Snapshot()[0];check(a.Count==2&&a.Port==636,"outbound grouped on destination service port");check(r.Matches(a),"scoped match");
  e.Destination="10.0.0.11";queue.Observe(e,true);check(queue.Snapshot().Count==2,"different destination separate");check(!r.Matches(queue.Snapshot().Find(x=>x.Address=="10.0.0.11")),"exact destination");
  e.Direction="Eingehend";e.Source="10.0.0.10";e.SourcePort="50000";e.Destination="10.0.0.5";e.DestinationPort="389";queue.Observe(e,false);
  var incoming=queue.Snapshot().Find(x=>x.Direction=="Eingehend");check(incoming.Address=="10.0.0.10"&&incoming.Port==389,"incoming uses remote IP and local service port");check(!incoming.OwnBlock,"foreign block provenance preserved");
  e.SourcePort="50001";queue.Observe(e,false);check(queue.Snapshot().Find(x=>x.Direction=="Eingehend").Count==2,"ephemeral peer port does not create prompt flood");
  e.Direction="Ausgehend";e.Protocol="ICMP";e.DestinationPort="0";e.SourcePort="8";queue.Observe(e,true);var ping=queue.Snapshot().Find(x=>x.Protocol==1);check(ping.Port==0&&!ping.Target.Contains(":8"),"no fake ICMP ports");
  r=rule();r.Protocol=1;r.Port=0;r.Path="*";r.Validate();check(r.Scope.Contains("Gesamter Rechner"),"host ICMP scope explicit");
  r.Address="*";reject(r,"broad host ICMP");r=rule();r.Path="*";reject(r,"host TCP");
  r=rule();r.Address="example.org";reject(r,"hostname cannot masquerade as exact IP");r=rule();r.Protocol=1;reject(r,"ICMP with port");
  r=rule();r.Address="fe80::1%4";reject(r,"ambiguous IPv6 scope");r=rule();r.Address="2001:db8::1";r.Protocol=1;r.Port=0;reject(r,"ICMP family mismatch");
  r=rule();r.Address="::ffff:10.0.0.10";r.Validate();check(r.Address=="10.0.0.10","mapped IPv4 canonicalized");
  r=rule();r.Path=@"\\server\share\app.exe";reject(r,"UNC executable");r=rule();r.Name="a\nb";reject(r,"control in name");r=rule();r.Direction="Unknown";reject(r,"unknown direction");r=rule();r.Protocol=47;reject(r,"unsupported protocol");
  var config=new SetupConfig();r=rule();r.ExpiresUtc=now.AddMinutes(-1);config.Rules.Add(r);config.Rules.Add(rule());check(config.Expire(now)==1&&config.Rules.Count==1,"expired grants removed before use");
  r=rule();r.ExpiresUtc=DateTime.SpecifyKind(now,DateTimeKind.Local);reject(r,"local expiry");
  config.Rules.Add(config.Rules[0]);try{config.Validate();throw new Exception("duplicate accepted");}catch(ArgumentException){count++;}
  var bounded=new SetupQueue();for(int i=0;i<600;i++){e.Application=@"C:\Apps\p"+i+".exe";bounded.Observe(e,true);}check(bounded.Snapshot().Count==512&&bounded.Dropped==88,"capacity reports dropped requests");
  var before=new SetupConfig();var after=new SetupConfig{Ask=true};bool applied=false;int applications=0;
  SetupChanges.Commit(before,after,c=>{applied=c.Ask;applications++;},c=>{});check(applied&&applications==1,"successful change applied once");
  applications=0;try{SetupChanges.Commit(before,after,c=>{applied=c.Ask;applications++;},c=>{throw new Exception("disk full");});throw new Exception("save failure swallowed");}catch(SetupChangeFailure failure){check(failure.Restored&&!applied&&applications==2,"save failure restores prior filters");}
  try{SetupChanges.Commit(before,after,c=>{throw new Exception("filter unavailable");},c=>{});throw new Exception("restore failure swallowed");}catch(SetupChangeFailure failure){check(!failure.Restored,"failed rollback never reports verified protection");}
  check(WfpGate.ValidReturnedFlags(0,false),"unchanged soft permit flags");
  check(WfpGate.ValidReturnedFlags(64,false),"indexing does not change permit semantics");
  check(WfpGate.ValidReturnedFlags(72,true),"indexed hard block stays restrictive");
  check(!WfpGate.ValidReturnedFlags(8,false),"hard permit rejected");
  check(!WfpGate.ValidReturnedFlags(32,true),"disabled block rejected");
  check(!WfpGate.ValidReturnedFlags(1,true),"unexpected persistent flag rejected");
  check(!WfpGate.ValidReturnedFlags(128,true),"unknown returned flag rejected");
  return count;
 }
}

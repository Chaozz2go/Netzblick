using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;

namespace Netzblick {
 public sealed class SetupChangeFailure : Exception {
  public bool Restored {get;private set;}
  public SetupChangeFailure(string text,bool restored,Exception inner):base(text,inner){Restored=restored;}
 }
 public static class SetupChanges {
  public static bool IsProtectedProgram(string path){
   if(String.IsNullOrWhiteSpace(path))return true;
   string p=path.Replace('/','\\');string name=p.Substring(p.LastIndexOf('\\')+1).ToLowerInvariant();
   return new[]{"svchost.exe","lsass.exe","services.exe","wininit.exe","winlogon.exe","smss.exe","system","msmpeng.exe","mpssvc.exe"}.Contains(name);
  }
  public static SetupConfig GroupChange(SetupConfig current,IEnumerable<string> paths,string operation,int minutes,DateTime now){
   var members=paths==null?new List<string>():paths.ToList();
   if(members.Count<1||members.Count>16||members.Select(ProcessLineage.Normalize).Distinct(StringComparer.Ordinal).Count()!=members.Count)throw new ArgumentException("Gruppe: 1 bis 16 unterschiedliche Programmpfade auswählen.");
   foreach(string p in members)if(!AccessQueue.CanAllow(p)||p.Length>1024||IsProtectedProgram(p))throw new ArgumentException("Gruppe enthält einen ungültigen Pfad oder geschützten Windows-Sammelprozess.");
   var next=CopyConfig(current);
   foreach(string p in members){
    if(operation=="GroupTemporaryBlock")TemporaryBlockProgram(next,p,minutes,now);
    else if(operation=="GroupEndLeases")EndProgramLease(next,p,CaptureProgram(next,p),now);
    else throw new ArgumentException("Unbekannte Gruppenaktion.");
   }
   next.Validate();return next;
  }
  public static SetupConfig RestoreOwnedConfig(SetupConfig current,SetupConfig saved,DateTime now){
   if(saved==null)throw new ArgumentException("Sicherung enthält keine Dienstregeln.");
   var next=CopyConfig(saved);next.Validate();next.Expire(now);next.Ask=current.Ask;next.Validate();return next;
  }
  public static SetupConfig CopyConfig(SetupConfig c){
   return new SetupConfig{Version=c.Version,Ask=c.Ask,WatchedPaths=new List<string>(c.WatchedPaths),Rules=c.Rules.Select(CopyRule).ToList(),ProgramLeases=c.ProgramLeases.Select(CopyLease).ToList()};
  }
  static void WriteRules(System.IO.BinaryWriter w,IEnumerable<SetupRule> rules){
   var sorted=rules.OrderBy(r=>r.Id,StringComparer.Ordinal).ToList();w.Write(sorted.Count);
   foreach(var r in sorted){w.Write(r.Id??"");w.Write(r.Name??"");w.Write(ProcessLineage.Normalize(r.Path));w.Write(r.Direction??"");w.Write(r.Address??"");w.Write(r.Action??"");w.Write(r.Protocol);w.Write(r.Port);w.Write(r.ExpiresUtc.HasValue);if(r.ExpiresUtc.HasValue)w.Write(r.ExpiresUtc.Value.ToUniversalTime().Ticks/TimeSpan.TicksPerMillisecond);}
  }
  public static string ConfigKey(SetupConfig c){
   using(var stream=new System.IO.MemoryStream()){
    using(var w=new System.IO.BinaryWriter(stream,System.Text.Encoding.UTF8,true)){
     w.Write(c.Version);w.Write(c.Ask);var paths=c.WatchedPaths.Select(ProcessLineage.Normalize).OrderBy(p=>p,StringComparer.Ordinal).ToList();w.Write(paths.Count);foreach(string p in paths)w.Write(p);WriteRules(w,c.Rules);
     var leases=c.ProgramLeases.OrderBy(l=>ProcessLineage.Normalize(l.Path),StringComparer.Ordinal).ToList();w.Write(leases.Count);
     foreach(var l in leases){w.Write(ProcessLineage.Normalize(l.Path));w.Write(l.EffectiveAction);w.Write(l.UntilResumed);w.Write(l.WasWatched);w.Write(l.ExpiresUtc.ToUniversalTime().Ticks/TimeSpan.TicksPerMillisecond);WriteRules(w,l.PreviousRules);}
    }
    using(var hash=System.Security.Cryptography.SHA256.Create())return Convert.ToBase64String(hash.ComputeHash(stream.ToArray()));
   }
  }
  public static void AssertPreview(SetupConfig config,string expectedKey){
   if(!String.IsNullOrEmpty(expectedKey)&&!String.Equals(ConfigKey(config),expectedKey,StringComparison.Ordinal))throw new InvalidOperationException("Regeln wurden seit der Vorschau verändert. Bitte Auswirkung erneut ansehen.");
  }
  public static void BlockProgram(SetupConfig config,string path){
   if(!AccessQueue.CanAllow(path))throw new ArgumentException("Ein vollständiger lokaler EXE-Pfad wird benötigt.");
   config.ProgramLeases.RemoveAll(l=>ProcessLineage.Normalize(l.Path)==ProcessLineage.Normalize(path));
   string name=System.IO.Path.GetFileName(path);
   foreach(string direction in new[]{"Ausgehend","Eingehend"})Upsert(config,new SetupRule{Id=Guid.NewGuid().ToString(),Name="Gesperrt: "+name.Substring(0,Math.Min(70,name.Length)),Path=path,Direction=direction,Address="*",Protocol=0,Port=0,Action="Block"});
   config.Validate();
  }
  public static void ProgramDefault(SetupConfig config,string path){
   if(!AccessQueue.CanAllow(path))throw new ArgumentException("Ein vollständiger lokaler EXE-Pfad wird benötigt.");
   string key=ProcessLineage.Normalize(path);
   config.ProgramLeases.RemoveAll(l=>ProcessLineage.Normalize(l.Path)==key);
   config.WatchedPaths.RemoveAll(p=>ProcessLineage.Normalize(p)==key);
   config.Rules.RemoveAll(r=>ProcessLineage.Normalize(r.Path)==key);
  }
  public static void AllowProgram(SetupConfig config,string path){
   ProgramDefault(config,path);
   string name=System.IO.Path.GetFileName(path);
   foreach(string direction in new[]{"Ausgehend","Eingehend"})Upsert(config,new SetupRule{Id=Guid.NewGuid().ToString(),Name="Erlaubt: "+name.Substring(0,Math.Min(70,name.Length)),Path=path,Direction=direction,Address="*",Protocol=0,Port=0,Action="Allow"});
   config.Validate();
  }
  public static SetupRule CopyRule(SetupRule r){return new SetupRule{Id=r.Id,Name=r.Name,Path=r.Path,Direction=r.Direction,Address=r.Address,Action=r.Action,Protocol=r.Protocol,Port=r.Port,ExpiresUtc=r.ExpiresUtc};}
  static SetupProgramLease CopyLease(SetupProgramLease l){return l==null?null:new SetupProgramLease{Path=l.Path,Action=l.Action,UntilResumed=l.UntilResumed,WasWatched=l.WasWatched,PreviousRules=l.PreviousRules.Select(CopyRule).ToList(),ExpiresUtc=l.ExpiresUtc};}
  public static SetupProgramState CaptureProgram(SetupConfig config,string path){
   if(!AccessQueue.CanAllow(path))throw new ArgumentException("Vollständiger Programmpfad fehlt.");
   string key=ProcessLineage.Normalize(path);
   return new SetupProgramState{Path=path,Watched=config.WatchedPaths.Any(p=>ProcessLineage.Normalize(p)==key),Rules=config.Rules.Where(r=>ProcessLineage.Normalize(r.Path)==key).Select(CopyRule).ToList(),Lease=CopyLease(config.ProgramLeases.Find(l=>ProcessLineage.Normalize(l.Path)==key))};
  }
  static string RulesKey(IEnumerable<SetupRule> rules){return String.Join("\n",rules.OrderBy(r=>r.Id,StringComparer.Ordinal).Select(r=>String.Join("|",new[]{r.Id,r.Name,ProcessLineage.Normalize(r.Path),r.Direction,r.Address,r.Action,r.Protocol.ToString(),r.Port.ToString(),r.ExpiresUtc.HasValue?(r.ExpiresUtc.Value.Ticks/TimeSpan.TicksPerMillisecond).ToString():""})));}
  public static bool SameProgram(SetupProgramState a,SetupProgramState b){
   if(a==null||b==null||ProcessLineage.Normalize(a.Path)!=ProcessLineage.Normalize(b.Path)||a.Watched!=b.Watched||RulesKey(a.Rules)!=RulesKey(b.Rules))return false;
   if(a.Lease==null||b.Lease==null)return a.Lease==b.Lease;
   return a.Lease.EffectiveAction==b.Lease.EffectiveAction&&a.Lease.UntilResumed==b.Lease.UntilResumed&&a.Lease.ExpiresUtc.Ticks/TimeSpan.TicksPerMillisecond==b.Lease.ExpiresUtc.Ticks/TimeSpan.TicksPerMillisecond&&a.Lease.WasWatched==b.Lease.WasWatched&&RulesKey(a.Lease.PreviousRules)==RulesKey(b.Lease.PreviousRules);
  }
  public static void RestoreProgram(SetupConfig config,SetupProgramState before,SetupProgramState expected,DateTime now){
   before.Validate();expected.Validate();
   if(!SameProgram(CaptureProgram(config,expected.Path),expected)||ProcessLineage.Normalize(before.Path)!=ProcessLineage.Normalize(expected.Path))throw new InvalidOperationException("Programmregeln wurden inzwischen geändert. Rückgängig wurde abgebrochen.");
   ProgramDefault(config,before.Path);
   if(before.Watched)config.WatchedPaths.Add(before.Path);
   config.Rules.AddRange(before.Rules.Select(CopyRule));if(before.Lease!=null)config.ProgramLeases.Add(CopyLease(before.Lease));
   config.Expire(now);config.Validate();
  }
  public static void TemporaryAllowProgram(SetupConfig config,string path,DateTime expires,DateTime now){
   if(expires.Kind!=DateTimeKind.Utc||expires<=now||expires>now.AddHours(24))throw new ArgumentException("Freigabe muss innerhalb von 24 Stunden ablaufen.");
   var before=CaptureProgram(config,path);if(before.Lease!=null)throw new InvalidOperationException("Eine zeitweise Freigabe läuft bereits. Erst beenden oder dauerhaft entscheiden.");
   AllowProgram(config,path);
   foreach(var r in config.Rules.Where(r=>ProcessLineage.Normalize(r.Path)==ProcessLineage.Normalize(path))){r.ExpiresUtc=expires;r.Name="Zeitweise: "+r.Name;}
   config.ProgramLeases.Add(new SetupProgramLease{Path=path,WasWatched=before.Watched,PreviousRules=before.Rules,ExpiresUtc=expires});config.Validate();
  }
  public static void TemporaryBlockProgram(SetupConfig config,string path,int minutes,DateTime now){
   if(minutes!=0&&minutes!=10&&minutes!=30&&minutes!=60)throw new ArgumentException("Sperrdauer: 10, 30, 60 Minuten oder bis aufgehoben.");
   var before=CaptureProgram(config,path);if(before.Lease!=null)throw new InvalidOperationException("Eine zeitweise Entscheidung läuft bereits. Zuerst beenden.");
   ProgramDefault(config,path);BlockProgram(config,path);
   DateTime expires=minutes==0?DateTime.SpecifyKind(DateTime.MaxValue,DateTimeKind.Utc):now.AddMinutes(minutes);
   foreach(var r in config.Rules.Where(r=>ProcessLineage.Normalize(r.Path)==ProcessLineage.Normalize(path))){r.ExpiresUtc=minutes==0?(DateTime?)null:expires;r.Name="Zeitweise: "+r.Name;}
   config.ProgramLeases.Add(new SetupProgramLease{Path=path,Action="Block",UntilResumed=minutes==0,WasWatched=before.Watched,PreviousRules=before.Rules,ExpiresUtc=expires});config.Validate();
  }
  public static void EndProgramLease(SetupConfig config,string path,SetupProgramState expected,DateTime now){
   var current=CaptureProgram(config,path);if(current.Lease==null)throw new InvalidOperationException("Keine zeitweise Entscheidung aktiv.");
   var before=new SetupProgramState{Path=path,Watched=current.Lease.WasWatched,Rules=current.Lease.PreviousRules.Select(CopyRule).ToList()};
   RestoreProgram(config,before,expected,now);
  }
  public static void AssertNoProgramLease(SetupConfig config,string path){
   if(config.ProgramLeases.Any(l=>ProcessLineage.Normalize(l.Path)==ProcessLineage.Normalize(path)))throw new InvalidOperationException("Zeitweise Entscheidung aktiv. Zuerst beenden, dauerhaft erlauben oder sperren.");
  }
  public static void Upsert(SetupConfig config,SetupRule rule){
   rule.Validate();var keep=config.Rules.Where(r=>!(r.Covers(rule)&&rule.Covers(r))).ToList();
   var conflict=keep.FirstOrDefault(r=>r.Action=="Block"&&r.Covers(rule));
   if(rule.Action=="Allow"&&conflict!=null)throw new InvalidOperationException("Zuerst die übergeordnete Sperrregel zurücknehmen: "+conflict.Name);
   keep.Add(rule);config.Rules=keep;
  }
  public static void Commit(SetupConfig before,SetupConfig next,Action<SetupConfig> apply,Action<SetupConfig> save){
   next.Validate();
   try{apply(next);save(next);}
   catch(Exception original){
    try{apply(before);}catch(Exception restore){throw new SetupChangeFailure(original.Message+" Regelzustand unbestätigt: "+restore.Message,false,original);}
    throw new SetupChangeFailure(original.Message+" Vorherige Filter wiederhergestellt.",true,original);
   }
  }
 }
 // Describes only Netzblick's configured external traffic policy, never a promise
 // about Windows/third-party filters or already established connections.
 public static class ProgramPolicy {
  public static string Category(SetupConfig config,string path){
   string key=ProcessLineage.Normalize(path);
   var rules=config.Rules.Where(r=>(!r.ExpiresUtc.HasValue||r.ExpiresUtc.Value>DateTime.UtcNow)&&(r.Path=="*"||ProcessLineage.Normalize(r.Path)==key)).ToList();
   Func<string,string,bool> full=(action,direction)=>rules.Any(r=>r.Action==action&&r.Direction==direction&&r.Address=="*"&&r.Protocol==0&&r.Port==0);
   bool deny=rules.Any(r=>r.Action=="Block"),allow=rules.Any(r=>r.Action=="Allow");
   if(full("Block","Ausgehend")&&full("Block","Eingehend"))return "Blocked";
   bool gated=config.Ask||config.WatchedPaths.Any(p=>ProcessLineage.Normalize(p)==key);
   if(gated&&!allow)return "Blocked";
   if(deny)return "Limited";
   if(full("Allow","Ausgehend")&&full("Allow","Eingehend"))return "Allowed";
   if(gated||allow)return "Limited";
   return "Default";
  }
 }
 public sealed class SetupRule {
  public string Id {get;set;} public string Name {get;set;} public string Path {get;set;}
  public string Direction {get;set;} public string Address {get;set;} public string Action {get;set;}
  public int Protocol {get;set;} public int Port {get;set;} public DateTime? ExpiresUtc {get;set;}
  public string Scope {get{return (Path=="*"?"Gesamter Rechner":Path)+" · "+Direction+" · "+Address+" · "+ProtocolName(Protocol)+(Port>0?" "+Port:"");}}
  public string Lifetime {get{return ExpiresUtc.HasValue?"Bis "+ExpiresUtc.Value.ToLocalTime().ToString("HH:mm:ss"):"Gespeichert";}}
  public static string ProtocolName(int p){return p==6?"TCP":p==17?"UDP":p==1?"ICMP (alle Typen)":p==58?"ICMPv6 (alle Typen)":p==0?"Alle Protokolle":"Protokoll "+p;}
  public static int Number(string p){int n;return p=="TCP"?6:p=="UDP"?17:p=="ICMP"?1:p=="ICMPv6"?58:Int32.TryParse(p,out n)?n:-1;}
  public void Validate(){
   Guid id;if(!Guid.TryParse(Id,out id))throw new ArgumentException("Ungültige Regel-ID.");
   if(String.IsNullOrWhiteSpace(Name)||Name.Length>100||Name.Any(Char.IsControl))throw new ArgumentException("Regelname: 1 bis 100 sichtbare Zeichen.");
   if(Action!="Allow"&&Action!="Block")throw new ArgumentException("Ungültige Regelaktion.");
   if(Direction!="Ausgehend"&&Direction!="Eingehend")throw new ArgumentException("Richtung nicht eindeutig.");
   if(Protocol!=0&&Protocol!=6&&Protocol!=17&&Protocol!=1&&Protocol!=58)throw new ArgumentException("Dieses Protokoll wird noch nicht unterstützt.");
   if(Address!="*"){
    IPAddress ip;if(String.IsNullOrEmpty(Address)||Address.Contains("%")||!IPAddress.TryParse(Address,out ip))throw new ArgumentException("Eine genaue IP-Adresse wird benötigt.");
    if(ip.IsIPv4MappedToIPv6)ip=ip.MapToIPv4();Address=ip.ToString();
    if((Protocol==1&&ip.AddressFamily!=System.Net.Sockets.AddressFamily.InterNetwork)||(Protocol==58&&ip.AddressFamily!=System.Net.Sockets.AddressFamily.InterNetworkV6))throw new ArgumentException("ICMP-Version und Zieladresse passen nicht zusammen.");
   }
   if(Port<0||Port>65535||(Protocol!=6&&Protocol!=17&&Port!=0))throw new ArgumentException("Ungültiger Port; ICMP hat keine TCP-/UDP-Ports.");
   if(Path=="*"){
    if(Address=="*"||(Protocol!=1&&Protocol!=58))throw new ArgumentException("Rechnerweite Regeln sind nur für ICMP zu einer genauen IP erlaubt.");
   }else if(!AccessQueue.CanAllow(Path))throw new ArgumentException("Ein vollständiger lokaler EXE-Pfad wird benötigt.");
   if(ExpiresUtc.HasValue&&ExpiresUtc.Value.Kind!=DateTimeKind.Utc)throw new ArgumentException("Ablaufzeit muss UTC sein.");
  }
  public bool Covers(SetupRule other){return (Path=="*"||ProcessLineage.Normalize(Path)==ProcessLineage.Normalize(other.Path))&&Direction==other.Direction&&(Address=="*"||Address==other.Address)&&(Protocol==0||Protocol==other.Protocol)&&(Port==0||Port==other.Port);}
  public bool Matches(SetupAttempt a){return (Path=="*"||ProcessLineage.Normalize(Path)==ProcessLineage.Normalize(a.Path))&&Direction==a.Direction&&(Address=="*"||Address==a.Address)&&(Protocol==0||Protocol==a.Protocol)&&(Port==0||Port==a.Port);}
 }
 public sealed class SetupProgramLease {
  public string Path {get;set;} public string Action {get;set;} public bool UntilResumed {get;set;}
  public string EffectiveAction {get{return String.IsNullOrEmpty(Action)?"Allow":Action;}}
  public bool WasWatched {get;set;} public List<SetupRule> PreviousRules {get;set;} public DateTime ExpiresUtc {get;set;}
  public SetupProgramLease(){PreviousRules=new List<SetupRule>();}
  public void Validate(){
   if((EffectiveAction!="Allow"&&EffectiveAction!="Block")||(UntilResumed&&EffectiveAction!="Block")||!AccessQueue.CanAllow(Path)||ExpiresUtc.Kind!=DateTimeKind.Utc||PreviousRules==null||PreviousRules.Count>1000)throw new ArgumentException("Ungültiger Rückweg der zeitweisen Freigabe.");
   foreach(var r in PreviousRules){if(r==null||ProcessLineage.Normalize(r.Path)!=ProcessLineage.Normalize(Path))throw new ArgumentException("Rückweg betrifft ein anderes Programm.");r.Validate();}
  }
 }
 public sealed class SetupProgramState {
  public string Path {get;set;} public bool Watched {get;set;} public List<SetupRule> Rules {get;set;} public SetupProgramLease Lease {get;set;}
  public SetupProgramState(){Rules=new List<SetupRule>();}
  public void Validate(){
   if(!AccessQueue.CanAllow(Path)||Rules==null||Rules.Count>1000)throw new ArgumentException("Ungültiger Programmzustand.");
   foreach(var r in Rules){if(r==null||ProcessLineage.Normalize(r.Path)!=ProcessLineage.Normalize(Path))throw new ArgumentException("Programmzustand enthält fremde Regeln.");r.Validate();}
   if(Lease!=null){Lease.Validate();if(ProcessLineage.Normalize(Lease.Path)!=ProcessLineage.Normalize(Path))throw new ArgumentException("Rückweg gehört zu anderem Programm.");}
  }
 }
 public sealed class SetupConfig {
  public int Version {get;set;} public bool Ask {get;set;} public List<string> WatchedPaths {get;set;}
  public List<SetupRule> Rules {get;set;} public List<SetupProgramLease> ProgramLeases {get;set;}
  public SetupConfig(){Version=1;WatchedPaths=new List<string>();Rules=new List<SetupRule>();ProgramLeases=new List<SetupProgramLease>();}
  public void Validate(){
   if(Version!=1||WatchedPaths==null||Rules==null||WatchedPaths.Count>256||Rules.Count>1000||ProgramLeases==null||ProgramLeases.Count>256)throw new ArgumentException("Regeldatei ungültig oder Kapazität überschritten.");
   foreach(string p in WatchedPaths)if(!AccessQueue.CanAllow(p))throw new ArgumentException("Ungültiger Prüfpfad.");
   var leasePaths=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
   foreach(var l in ProgramLeases){if(l==null)throw new ArgumentException("Leerer Freigabe-Rückweg.");l.Validate();if(!leasePaths.Add(ProcessLineage.Normalize(l.Path)))throw new ArgumentException("Doppelter Freigabe-Rückweg.");
    var current=Rules.Where(r=>ProcessLineage.Normalize(r.Path)==ProcessLineage.Normalize(l.Path)).ToList();
    if(current.Count!=2||!new[]{"Ausgehend","Eingehend"}.All(d=>current.Any(r=>r.Direction==d&&r.Action==l.EffectiveAction&&r.Address=="*"&&r.Protocol==0&&r.Port==0&&r.ExpiresUtc==(l.UntilResumed?(DateTime?)null:l.ExpiresUtc))))throw new ArgumentException("Zeitweise Freigabe und Rückweg passen nicht zusammen.");
   }
   if(Rules.Count+ProgramLeases.Sum(l=>Math.Max(0,l.PreviousRules.Count-2))>1000||WatchedPaths.Count+ProgramLeases.Count(l=>l.WasWatched)>256)throw new ArgumentException("Kapazität für den gespeicherten Freigabe-Rückweg überschritten.");
   var ids=new HashSet<string>(StringComparer.OrdinalIgnoreCase);foreach(var r in Rules){if(r==null)throw new ArgumentException("Leere Regel.");r.Validate();if(!ids.Add(r.Id))throw new ArgumentException("Doppelte Regel-ID.");}
  }
  public int Expire(DateTime utc){
   int changed=0;
   foreach(var l in ProgramLeases.Where(l=>!l.UntilResumed&&l.ExpiresUtc<=utc).ToList()){
    string key=ProcessLineage.Normalize(l.Path);Rules.RemoveAll(r=>ProcessLineage.Normalize(r.Path)==key);WatchedPaths.RemoveAll(p=>ProcessLineage.Normalize(p)==key);
    if(l.WasWatched)WatchedPaths.Add(l.Path);Rules.AddRange(l.PreviousRules.Select(SetupChanges.CopyRule));ProgramLeases.Remove(l);changed++;
   }
   return changed+Rules.RemoveAll(r=>r.ExpiresUtc.HasValue&&r.ExpiresUtc.Value<=utc);
  }
 }
 public sealed class SetupAttempt {
  public string Key {get;set;} public string Path {get;set;} public string Program {get;set;} public string Address {get;set;}
  public string Direction {get;set;} public int Protocol {get;set;} public int Port {get;set;}
  public long Count {get;set;} public DateTime FirstUtc {get;set;} public DateTime LastUtc {get;set;} public bool OwnBlock {get;set;} public ulong FilterId {get;set;} public string BlockReason {get;set;}
  public string Target {get{return Address+" · "+SetupRule.ProtocolName(Protocol)+(Port>0?" "+Port:"");}}
  public string Evidence {get{return !String.IsNullOrEmpty(BlockReason)?BlockReason:OwnBlock?"Netzblick-Filter bestätigt; Regelname nicht aufgezeichnet":"Windows-Blockereignis; Filtername nicht aufgezeichnet";}}
 }
 public sealed class SetupQueue {
  readonly Dictionary<string,SetupAttempt> items=new Dictionary<string,SetupAttempt>(StringComparer.OrdinalIgnoreCase);
  public long Dropped {get;private set;} public long Unknown {get;private set;}
  public void Clear(){items.Clear();Dropped=0;Unknown=0;}
  public void Observe(BlockEvent e,bool own){Observe(e,own,null);}
  public void Observe(BlockEvent e,bool own,string reason){
   if(e.Direction!="Ausgehend"&&e.Direction!="Eingehend"){Unknown++;return;}
   IPAddress ip;string raw=e.Target;
   if(!IPAddress.TryParse(raw,out ip)){Unknown++;return;}if(ip.IsIPv4MappedToIPv6)ip=ip.MapToIPv4();
   int protocol=SetupRule.Number(e.Protocol),port=0;
   if(protocol==6||protocol==17){if(!Int32.TryParse(e.DestinationPort,out port)||port<1||port>65535){Unknown++;return;}}
   string path=e.Application??"",address=ip.ToString();
   string key=ProcessLineage.Normalize(path)+"|"+e.Direction+"|"+address+"|"+protocol+"|"+port+"|"+e.FilterId+"|"+own;
   SetupAttempt a;if(!items.TryGetValue(key,out a)){
    if(items.Count>=512){Dropped++;return;}
    a=new SetupAttempt{Key=key,Path=path,Program=e.Program,Address=address,Protocol=protocol,Port=port,Direction=e.Direction,FirstUtc=e.TimeUtc,LastUtc=e.TimeUtc,FilterId=e.FilterId,BlockReason=reason};items.Add(key,a);
   }
   a.Count++;if(e.TimeUtc>=a.LastUtc){a.LastUtc=e.TimeUtc;a.OwnBlock=own;a.BlockReason=reason;}
  }
  public List<SetupAttempt> Snapshot(){return items.Values.OrderByDescending(a=>a.LastUtc).ToList();}
 }
 public sealed class SetupStatus {
  public bool Ok {get;set;} public bool Verified {get;set;} public string Error {get;set;} public string Warning {get;set;}
  public SetupConfig Config {get;set;} public List<SetupAttempt> Attempts {get;set;} public List<string> History {get;set;}
  public DateTime CheckedUtc {get;set;} public DateTime StartedUtc {get;set;} public DateTime? RecoveryUtc {get;set;}
 }
 public sealed class SetupCommand {
  public string Operation {get;set;} public bool Enabled {get;set;} public string Path {get;set;}
  public List<string> Paths {get;set;} public SetupConfig RestoreConfig {get;set;} public string ExpectedConfigKey {get;set;} public string RuleId {get;set;} public SetupRule Rule {get;set;} public int RecoveryMinutes {get;set;}
  public int DurationMinutes {get;set;} public SetupProgramState BeforeProgram {get;set;} public SetupProgramState ExpectedProgram {get;set;}
 }
}


namespace Netzblick {
 public sealed class BackupPending {public string Path {get;set;} public DateTime FirstUtc {get;set;}}
 public sealed class BackupTarget {
  public string Path {get;set;} public string Address {get;set;} public int Protocol {get;set;} public int Port {get;set;} public bool Reviewed {get;set;} public DateTime FirstUtc {get;set;}
 }
 public sealed class BackupBundle {
  public string Format {get;set;} public int Version {get;set;} public DateTime CreatedUtc {get;set;} public SetupConfig Control {get;set;}
  public List<string> Favorites {get;set;} public List<ProgramGroup> Groups {get;set;} public List<string> Seen {get;set;} public List<BackupPending> Pending {get;set;} public List<BackupTarget> Targets {get;set;}
  public BackupBundle(){Format="Netzblick.Backup";Version=1;CreatedUtc=DateTime.UtcNow;Favorites=new List<string>();Groups=new List<ProgramGroup>();Seen=new List<string>();Pending=new List<BackupPending>();Targets=new List<BackupTarget>();}
  static void Paths(IEnumerable<string> paths,int max){var seen=new HashSet<string>(StringComparer.Ordinal);foreach(string p in paths)if(!AccessQueue.CanAllow(p)||p.Length>max||!seen.Add(ProcessLineage.Normalize(p)))throw new ArgumentException("Sicherung enthält ungültige oder doppelte Programmpfade.");}
  public void Validate(){
   if(Format!="Netzblick.Backup"||Version!=1||CreatedUtc.Kind!=DateTimeKind.Utc||Favorites==null||Groups==null||Seen==null||Pending==null||Targets==null||Favorites.Count>50||Groups.Count>32||Seen.Count>10000||Pending.Count>1000||Targets.Count>5000)throw new ArgumentException("Unbekannte oder zu große Netzblick-Sicherung.");
   if(Control!=null)Control.Validate();Paths(Favorites,1024);Paths(Seen,32767);Paths(Pending.Select(p=>p==null?null:p.Path),32767);
   foreach(var p in Pending)if(p.FirstUtc.Kind!=DateTimeKind.Utc)throw new ArgumentException("Prüfzeitpunkt muss UTC sein.");
   var groups=new WorkspaceSettings{Groups=Groups};groups.Validate();
   var targets=new HashSet<string>(StringComparer.Ordinal);
   foreach(var t in Targets){IPAddress ip;if(t==null||!AccessQueue.CanAllow(t.Path)||!IPAddress.TryParse(t.Address,out ip)||!(t.Protocol==6||t.Protocol==17||t.Protocol==1||t.Protocol==58)||t.Port<0||t.Port>65535||t.FirstUtc.Kind!=DateTimeKind.Utc)throw new ArgumentException("Ungültige Ziel-Prüfentscheidung in Sicherung.");if(ip.IsIPv4MappedToIPv6)ip=ip.MapToIPv4();string key=ProcessLineage.Normalize(t.Path)+"|"+ip+"|"+t.Protocol+"|"+t.Port;if(!targets.Add(key))throw new ArgumentException("Doppelte Ziel-Prüfentscheidung.");}
  }
 }
}

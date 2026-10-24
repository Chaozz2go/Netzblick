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
  public static void Commit(SetupConfig before,SetupConfig next,Action<SetupConfig> apply,Action<SetupConfig> save){
   next.Validate();
   try{apply(next);save(next);}
   catch(Exception original){
    try{apply(before);}catch(Exception restore){throw new SetupChangeFailure(original.Message+" Regelzustand unbestätigt: "+restore.Message,false,original);}
    throw new SetupChangeFailure(original.Message+" Vorherige Filter wiederhergestellt.",true,original);
   }
  }
 }
 public sealed class SetupRule {
  public string Id {get;set;} public string Name {get;set;} public string Path {get;set;}
  public string Direction {get;set;} public string Address {get;set;} public string Action {get;set;}
  public int Protocol {get;set;} public int Port {get;set;} public DateTime? ExpiresUtc {get;set;}
  public string Scope {get{return (Path=="*"?"Gesamter Rechner":Path)+" · "+Direction+" · "+Address+" · "+ProtocolName(Protocol)+(Port>0?" "+Port:"");}}
  public string Lifetime {get{return ExpiresUtc.HasValue?"Bis "+ExpiresUtc.Value.ToLocalTime().ToString("HH:mm:ss"):"Gespeichert";}}
  public static string ProtocolName(int p){return p==6?"TCP":p==17?"UDP":p==1?"ICMP (alle Typen)":p==58?"ICMPv6 (alle Typen)":"Alle Protokolle";}
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
  public bool Matches(SetupAttempt a){return (Path=="*"||ProcessLineage.Normalize(Path)==ProcessLineage.Normalize(a.Path))&&Direction==a.Direction&&(Address=="*"||Address==a.Address)&&(Protocol==0||Protocol==a.Protocol)&&(Port==0||Port==a.Port);}
 }
 public sealed class SetupConfig {
  public int Version {get;set;} public bool Ask {get;set;} public List<string> WatchedPaths {get;set;}
  public List<SetupRule> Rules {get;set;}
  public SetupConfig(){Version=1;WatchedPaths=new List<string>();Rules=new List<SetupRule>();}
  public void Validate(){
   if(Version!=1||WatchedPaths==null||Rules==null||WatchedPaths.Count>256||Rules.Count>1000)throw new ArgumentException("Regeldatei ungültig oder Kapazität überschritten.");
   foreach(string p in WatchedPaths)if(!AccessQueue.CanAllow(p))throw new ArgumentException("Ungültiger Prüfpfad.");
   var ids=new HashSet<string>(StringComparer.OrdinalIgnoreCase);foreach(var r in Rules){if(r==null)throw new ArgumentException("Leere Regel.");r.Validate();if(!ids.Add(r.Id))throw new ArgumentException("Doppelte Regel-ID.");}
  }
  public int Expire(DateTime utc){return Rules.RemoveAll(r=>r.ExpiresUtc.HasValue&&r.ExpiresUtc.Value<=utc);}
 }
 public sealed class SetupAttempt {
  public string Key {get;set;} public string Path {get;set;} public string Program {get;set;} public string Address {get;set;}
  public string Direction {get;set;} public int Protocol {get;set;} public int Port {get;set;}
  public long Count {get;set;} public DateTime FirstUtc {get;set;} public DateTime LastUtc {get;set;} public bool OwnBlock {get;set;}
  public string Target {get{return Address+" · "+SetupRule.ProtocolName(Protocol)+(Port>0?" "+Port:"");}}
  public string Evidence {get{return OwnBlock?"Netzblick-Filter bestätigt":"Windows-Blockereignis; andere Sperre möglich";}}
 }
 public sealed class SetupQueue {
  readonly Dictionary<string,SetupAttempt> items=new Dictionary<string,SetupAttempt>(StringComparer.OrdinalIgnoreCase);
  public long Dropped {get;private set;} public long Unknown {get;private set;}
  public void Observe(BlockEvent e,bool own){
   if(e.Direction!="Ausgehend"&&e.Direction!="Eingehend"){Unknown++;return;}
   IPAddress ip;string raw=e.Target;
   if(!IPAddress.TryParse(raw,out ip)){Unknown++;return;}if(ip.IsIPv4MappedToIPv6)ip=ip.MapToIPv4();
   int protocol=SetupRule.Number(e.Protocol),port=0;
   if(protocol==6||protocol==17){if(!Int32.TryParse(e.DestinationPort,out port)||port<1||port>65535){Unknown++;return;}}
   string path=e.Application??"",address=ip.ToString();
   string key=ProcessLineage.Normalize(path)+"|"+e.Direction+"|"+address+"|"+protocol+"|"+port;
   SetupAttempt a;if(!items.TryGetValue(key,out a)){
    if(items.Count>=512){Dropped++;return;}
    a=new SetupAttempt{Key=key,Path=path,Program=e.Program,Address=address,Protocol=protocol,Port=port,Direction=e.Direction,FirstUtc=e.TimeUtc,LastUtc=e.TimeUtc};items.Add(key,a);
   }
   a.Count++;if(e.TimeUtc>=a.LastUtc){a.LastUtc=e.TimeUtc;a.OwnBlock=own;}
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
  public string RuleId {get;set;} public SetupRule Rule {get;set;} public int RecoveryMinutes {get;set;}
 }
}

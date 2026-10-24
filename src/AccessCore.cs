using System;
using System.Collections.Generic;
using System.IO;
using System.Net;

namespace Netzblick {
 public sealed class AccessRequest {
  public string Key {get;set;} public string Path {get;set;} public string Name {get;set;}
  public string Decision {get;set;} public DateTime FirstUtc {get;set;} public DateTime LastUtc {get;set;}
  public DateTime? AllowedUtc {get;set;} public long Count {get;set;} public bool BlockedAfterAllow {get;set;}
  public string LatestAddress {get;set;} public int LatestPort {get;set;} public string Protocol {get;set;}
  public string Evidence {get;set;}
  public List<string> Targets=new List<string>();
  public string Summary {get{return Count+" blockierte Versuche · zuletzt "+LastUtc.ToLocalTime().ToString("HH:mm:ss");}}
  public string DecisionText {get{return Decision=="Allowed"?(BlockedAfterAllow?"Freigabe vorhanden · weitere Sperre beobachtet":"Sitzungsentscheidung: freigegeben"):Decision=="Blocked"?"Entscheidung: weiter blockieren":"Noch keine Freigabe entschieden";}}
 }
 public sealed class AccessQueue {
  readonly Dictionary<string,AccessRequest> items=new Dictionary<string,AccessRequest>(StringComparer.OrdinalIgnoreCase);
  public long Incoming {get;private set;} public long Unknown {get;private set;} public long Overflow {get;private set;}
  public static bool CanAllow(string path) {
   return !String.IsNullOrWhiteSpace(path) && path.Length<32768 && path.Length>3 &&
    Char.IsLetter(path[0]) && path[1]==':' && path[2]=='\\' && path.EndsWith(".exe",StringComparison.OrdinalIgnoreCase) &&
    path.IndexOfAny(new char[]{'\r','\n','\0','"','*','?'})<0 && path.IndexOf(':',2)<0 &&
    Array.IndexOf(path.Split('\\'),"..")<0;
  }
  public void Observe(BlockEvent e,bool ownBlock) {
   if(e.Direction=="Eingehend"){Incoming++;return;}
   if(e.Direction!="Ausgehend"){Unknown++;return;}
   string key=ProcessLineage.Normalize(e.Application);
   if(key.Length==0){Unknown++;return;}
   AccessRequest request;
   if(!items.TryGetValue(key,out request)){
    if(items.Count>=512){Overflow++;return;}
    request=new AccessRequest{Key=key,Path=e.Application,Name=e.Program,Decision="Pending",FirstUtc=e.TimeUtc,LastUtc=e.TimeUtc};
    items.Add(key,request);
   }
   request.Count++;if(e.TimeUtc>=request.LastUtc){request.LastUtc=e.TimeUtc;request.LatestAddress=e.Destination;int port;Int32.TryParse(e.DestinationPort,out port);request.LatestPort=port;request.Protocol=e.Protocol;request.Evidence=ownBlock?"Durch Netzblick-Sitzungsfilter blockiert":"Windows-Blockereignis; auslösender Netzblick-Filter nicht bestätigt";}
   if(request.AllowedUtc.HasValue && e.TimeUtc>request.AllowedUtc.Value)request.BlockedAfterAllow=true;
   string endpoint=(e.Destination.Contains(":")?"["+e.Destination+"]":e.Destination)+":"+e.DestinationPort+" · "+e.Protocol;
   if(!request.Targets.Contains(endpoint) && request.Targets.Count<20)request.Targets.Add(endpoint);
  }
  public AccessRequest Find(string key){AccessRequest value;return items.TryGetValue(key,out value)?value:null;}
  public void Decide(string key,string decision) {
   AccessRequest r=Find(key);if(r==null)throw new ArgumentException("Anfrage nicht mehr vorhanden.");
   if(decision!="Allowed" && decision!="Blocked")throw new ArgumentException("Unbekannte Entscheidung.");
   r.Decision=decision;r.AllowedUtc=decision=="Allowed"?(DateTime?)DateTime.UtcNow:null;r.BlockedAfterAllow=false;
  }
  public List<AccessRequest> Snapshot(){var list=new List<AccessRequest>(items.Values);list.Sort((a,b)=>b.LastUtc.CompareTo(a.LastUtc));return list;}
 }
}
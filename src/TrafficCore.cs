using System;
using System.Collections.Generic;

namespace Netzblick.Capture {
 public sealed class ProcessIdentity {public int Pid;public string Path;public string Name;public DateTime StartUtc;}
 public sealed class TrafficRow {
  public string Key {get;set;}public string Path {get;set;}public string Name {get;set;}public int Pid {get;set;}
  public long Sent {get;set;}public long Received {get;set;}public DateTime LastUtc {get;set;}
 }
 public sealed class PeerRow {public string Path {get;set;}public string Name {get;set;}public string Address {get;set;}public int Port {get;set;}public string Protocol {get;set;}public DateTime LastUtc {get;set;}}
 public sealed class TrafficStore {
  readonly object gate=new object();readonly Dictionary<string,TrafficRow> rows=new Dictionary<string,TrafficRow>();
  readonly Dictionary<string,PeerRow> peers=new Dictionary<string,PeerRow>();long invalid;
  public long Invalid {get{lock(gate)return invalid;}}
  public void Add(ProcessIdentity process,DateTime time,bool send,long size,string address,int port,string protocol){
   lock(gate){
    if(size<0 || process==null){invalid++;return;}
    bool known=!String.IsNullOrWhiteSpace(process.Path) && time>=process.StartUtc;
    string path=known?process.Path:"",key=known?path.ToUpperInvariant():"PID:"+process.Pid;
    TrafficRow row;if(!rows.TryGetValue(key,out row)){if(rows.Count>=10000){invalid++;return;}row=new TrafficRow{Key=key,Path=path,Name=known?process.Name:"Nicht zugeordnet · PID "+process.Pid,Pid=process.Pid};rows[key]=row;}
    if(send)row.Sent+=size;else row.Received+=size;if(time>row.LastUtc)row.LastUtc=time;
    if(!known || String.IsNullOrWhiteSpace(address))return;
    string peerKey=key+"|"+protocol+"|"+address+"|"+port;PeerRow peer;
    if(!peers.TryGetValue(peerKey,out peer)){if(peers.Count>=20000){invalid++;return;}peer=new PeerRow{Path=path,Name=process.Name,Address=address,Port=port,Protocol=protocol};peers[peerKey]=peer;}
    if(time>peer.LastUtc)peer.LastUtc=time;
   }
  }
  public List<TrafficRow> Snapshot(){lock(gate){var result=new List<TrafficRow>();foreach(var r in rows.Values)result.Add(new TrafficRow{Key=r.Key,Path=r.Path,Name=r.Name,Pid=r.Pid,Sent=r.Sent,Received=r.Received,LastUtc=r.LastUtc});return result;}}
  public List<PeerRow> Peers(){lock(gate){var result=new List<PeerRow>();foreach(var r in peers.Values)result.Add(new PeerRow{Path=r.Path,Name=r.Name,Address=r.Address,Port=r.Port,Protocol=r.Protocol,LastUtc=r.LastUtc});return result;}}
  public static double Rate(long previous,long current,double seconds){return seconds<=0 || current<previous?0:(current-previous)/seconds;}
 }
}


namespace Netzblick.Capture {
 // Connection role comes only from a connect/accept event, never from byte direction.
 public sealed class FlowRow {
  public string Key {get;set;} public string Path {get;set;} public int Pid {get;set;}
  public string Direction {get;set;} public System.DateTime LastUtc {get;set;}
 }
 public sealed class FlowStore {
  readonly object gate=new object();readonly System.Collections.Generic.Dictionary<string,FlowRow> flows=new System.Collections.Generic.Dictionary<string,FlowRow>();
  static string Endpoint(string address,int port){System.Net.IPAddress ip;if(!System.Net.IPAddress.TryParse(address,out ip))return null;if(ip.IsIPv4MappedToIPv6)ip=ip.MapToIPv4();return "["+ip.ToString().ToUpperInvariant()+"]:"+port;}
  public static string KeyFor(string path,int pid,System.DateTime started,string protocol,string a,int ap,string b,int bp){
   if(System.String.IsNullOrWhiteSpace(path) || started==System.DateTime.MinValue || ap<1 || bp<1)return "";
   string first=Endpoint(a,ap),second=Endpoint(b,bp);if(first==null || second==null)return "";
   if(System.String.CompareOrdinal(first,second)>0){string tmp=first;first=second;second=tmp;}
   return path.ToUpperInvariant()+"|"+pid+"|"+started.ToUniversalTime().Ticks+"|"+(protocol??"").ToUpperInvariant()+"|"+first+"|"+second;
  }
  public void Observe(ProcessIdentity process,System.DateTime time,string protocol,string a,int ap,string b,int bp,bool incoming,bool close){
   if(process==null || time<process.StartUtc)return;
   string key=KeyFor(process.Path,process.Pid,process.StartUtc,protocol,a,ap,b,bp);if(key.Length==0)return;
   lock(gate){
    FlowRow old;if(flows.TryGetValue(key,out old) && time<old.LastUtc)return;
    if(close){flows.Remove(key);return;}
    if(!flows.ContainsKey(key) && flows.Count>=20000){string oldest=null;System.DateTime earliest=System.DateTime.MaxValue;foreach(var row in flows)if(row.Value.LastUtc<earliest){earliest=row.Value.LastUtc;oldest=row.Key;}if(oldest!=null)flows.Remove(oldest);}
    string direction=incoming?"Eingehend":"Ausgehend";
    // Same-process loopback can expose both roles for one undirected tuple.
    if(old!=null && old.Direction!=direction)direction="Unbekannt";
    flows[key]=new FlowRow{Key=key,Path=process.Path,Pid=process.Pid,Direction=direction,LastUtc=time};
   }
  }
  public System.Collections.Generic.List<FlowRow> Snapshot(){lock(gate){var list=new System.Collections.Generic.List<FlowRow>();foreach(var r in flows.Values)list.Add(new FlowRow{Key=r.Key,Path=r.Path,Pid=r.Pid,Direction=r.Direction,LastUtc=r.LastUtc});return list;}}
 }
}

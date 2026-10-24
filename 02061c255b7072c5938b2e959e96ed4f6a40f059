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

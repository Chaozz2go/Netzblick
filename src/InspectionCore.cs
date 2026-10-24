using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using System.Xml;

namespace Netzblick {
 public sealed class BlockEvent {
  public ulong FilterId {get;set;} public long RecordId {get;set;} public DateTime TimeUtc {get;set;} public int Pid {get;set;}
  public string Application {get;set;} public string Direction {get;set;} public string Protocol {get;set;}
  public string Source {get;set;} public string SourcePort {get;set;} public string Destination {get;set;} public string DestinationPort {get;set;}
  public string Kind {get;set;} public string Note {get;set;}
  public string Time {get{return TimeUtc.ToLocalTime().ToString("HH:mm:ss.fff");}}
  public string Program {get{int slash=(Application??"").LastIndexOf('\\');return slash<0?Application:Application.Substring(slash+1);}}
  public string Target {get{return Direction=="Ausgehend"?Destination:Source;}}
  public string Endpoint {get{return Source+":"+SourcePort+" → "+Destination+":"+DestinationPort;}}
 }
 public static class BlockEventParser {
  public static BlockEvent Parse(string xml) {
   var settings=new XmlReaderSettings{DtdProcessing=DtdProcessing.Prohibit,XmlResolver=null,MaxCharactersInDocument=1048576};
   var doc=new XmlDocument{XmlResolver=null};using(var sr=new StringReader(xml))using(var reader=XmlReader.Create(sr,settings))doc.Load(reader);
   var ns=new XmlNamespaceManager(doc.NameTable);ns.AddNamespace("e","http://schemas.microsoft.com/win/2004/08/events/event");
   var id=doc.SelectSingleNode("/e:Event/e:System/e:EventID",ns);
   if(id==null || id.InnerText!="5157")throw new FormatException("Kein Ereignis 5157.");
   var provider=doc.SelectSingleNode("/e:Event/e:System/e:Provider",ns) as XmlElement;
   if(provider==null || provider.GetAttribute("Name")!="Microsoft-Windows-Security-Auditing")throw new FormatException("Unerwarteter Ereignisanbieter.");
   var time=doc.SelectSingleNode("/e:Event/e:System/e:TimeCreated",ns) as XmlElement;
   DateTime timestamp;
   if(time==null || !DateTime.TryParse(time.GetAttribute("SystemTime"),CultureInfo.InvariantCulture,DateTimeStyles.RoundtripKind,out timestamp))throw new FormatException("Ereigniszeit fehlt.");
   var values=new Dictionary<string,string>(StringComparer.Ordinal);
   foreach(XmlElement node in doc.SelectNodes("/e:Event/e:EventData/e:Data",ns))values[node.GetAttribute("Name")]=node.InnerText;
   foreach(string required in new string[]{"ProcessID","Application","Direction","SourceAddress","SourcePort","DestAddress","DestPort","Protocol"})if(!values.ContainsKey(required))throw new FormatException("Ereignisfeld fehlt: "+required);
   long pid;string raw=values["ProcessID"];
   bool valid=raw.StartsWith("0x",StringComparison.OrdinalIgnoreCase)?Int64.TryParse(raw.Substring(2),NumberStyles.HexNumber,CultureInfo.InvariantCulture,out pid):Int64.TryParse(raw,out pid);
   if(!valid || pid<0 || pid>Int32.MaxValue)throw new FormatException("Ungültige Prozess-ID.");
   string protocol=values["Protocol"];
   protocol=protocol=="6"?"TCP":protocol=="17"?"UDP":protocol=="1"?"ICMP":protocol=="58"?"ICMPv6":protocol;
   string direction=values["Direction"]=="%%14593"?"Ausgehend":values["Direction"]=="%%14592"?"Eingehend":"Unbekannt";
   long recordId=0;var record=doc.SelectSingleNode("/e:Event/e:System/e:EventRecordID",ns);if(record!=null)Int64.TryParse(record.InnerText,out recordId);
   ulong filterId=0;string rawFilter;if(values.TryGetValue("FilterRTID",out rawFilter))UInt64.TryParse(rawFilter,out filterId);
   return new BlockEvent{FilterId=filterId,RecordId=recordId,TimeUtc=timestamp.ToUniversalTime(),Pid=(int)pid,Application=values["Application"],Direction=direction,Protocol=protocol,Source=values["SourceAddress"],SourcePort=values["SourcePort"],Destination=values["DestAddress"],DestinationPort=values["DestPort"],Kind="Blockierter Versuch",Note="WFP 5157 · keine Messung übertragener Bytes"};
  }
 }
 public sealed class ProcessNode {
  public int Pid {get;set;} public int ParentPid {get;set;} public string Name {get;set;} public string Path {get;set;}
  public DateTime StartUtc {get;set;} public DateTime SeenUtc {get;set;} public DateTime? EndUtc {get;set;}
  public int Depth {get;set;} public bool Root {get;set;}
  public bool? WindowVisible {get;set;} public string WindowTitle {get;set;}
  public string WindowState {get{return EndUtc.HasValue?"Fenster nicht mehr beobachtet":!WindowVisible.HasValue?"Fensterstatus nicht verfügbar":WindowVisible.Value?"Sichtbares Fenster erkannt"+(String.IsNullOrEmpty(WindowTitle)?"":": "+WindowTitle):"Kein sichtbares Fenster erkannt (Hintergrundbetrieb möglich)";}}
  public string Key {get{return Pid+"|"+StartUtc.Ticks;}}
  public string Caption {get{return new string(' ',Math.Min(Depth,8)*2)+(Root?"● ":"↳ ")+Name+" · PID "+Pid;}}
  public string State {get{return EndUtc.HasValue?"Beendet / nicht mehr beobachtet":"Prozess läuft";}}
 }
 public sealed class ProcessLineage {
  readonly Dictionary<string,ProcessNode> history=new Dictionary<string,ProcessNode>();
  readonly object gate=new object();readonly string rootPath;readonly DateTime since;
  public ProcessLineage(string path,DateTime sinceUtc){rootPath=Normalize(path);since=sinceUtc;}
  public static string Normalize(string path){
   if(String.IsNullOrWhiteSpace(path))return "";
   string p=path.Trim().Replace('/','\\');
   if(p.StartsWith("\\??\\",StringComparison.Ordinal))p=p.Substring(4);
   if(p.StartsWith("\\\\?\\UNC\\",StringComparison.OrdinalIgnoreCase))p="\\\\"+p.Substring(8);
   else if(p.StartsWith("\\\\?\\",StringComparison.Ordinal))p=p.Substring(4);
   return p.TrimEnd('\\').ToUpperInvariant();
  }
  public void Observe(List<ProcessNode> snapshot,DateTime time){
   lock(gate){
    var present=new HashSet<string>();var current=new Dictionary<int,ProcessNode>();
    foreach(var node in snapshot){present.Add(node.Key);current[node.Pid]=node;}
    foreach(var old in history.Values)if(!old.EndUtc.HasValue && !present.Contains(old.Key)){ProcessNode replacement;old.EndUtc=current.TryGetValue(old.Pid,out replacement) && replacement.StartUtc<time?replacement.StartUtc:time;}
    foreach(var node in snapshot)if(Normalize(node.Path)==rootPath){node.Root=true;node.Depth=0;Track(node,time);}
    // Resolve children only against the actual parent instance still in this snapshot.
    for(int pass=0;pass<16;pass++){
     bool changed=false;
     foreach(var node in snapshot){
      if(history.ContainsKey(node.Key) || node.StartUtc<since || String.IsNullOrWhiteSpace(node.Path))continue;
      ProcessNode parent;
      if(!current.TryGetValue(node.ParentPid,out parent) || parent.StartUtc>node.StartUtc)continue;
      ProcessNode known;
      if(!history.TryGetValue(parent.Key,out known) || known.EndUtc.HasValue)continue;
      node.Root=false;node.Depth=known.Depth+1;Track(node,time);changed=true;
     }
     if(!changed)break;
    }
    foreach(var node in snapshot){ProcessNode old;if(history.TryGetValue(node.Key,out old)){old.SeenUtc=time;old.EndUtc=null;old.WindowVisible=node.WindowVisible;old.WindowTitle=node.WindowTitle;}}
   }
  }
  void Track(ProcessNode node,DateTime time){if(history.ContainsKey(node.Key) || history.Count>=1024)return;node.SeenUtc=time;history[node.Key]=node;}
  public bool Matches(BlockEvent e){
   if(e.TimeUtc<since)return false;
   string path=Normalize(e.Application);if(path.Length==0)return false;
   if(path==rootPath)return true;
   lock(gate){foreach(var node in history.Values)if(node.Pid==e.Pid && Normalize(node.Path)==path && e.TimeUtc>=node.StartUtc && (!node.EndUtc.HasValue || e.TimeUtc<node.EndUtc.Value))return true;}
   return false;
  }
  public List<ProcessNode> Snapshot(){lock(gate){var result=new List<ProcessNode>();foreach(var n in history.Values)result.Add(new ProcessNode{Pid=n.Pid,ParentPid=n.ParentPid,Name=n.Name,Path=n.Path,StartUtc=n.StartUtc,SeenUtc=n.SeenUtc,EndUtc=n.EndUtc,Depth=n.Depth,Root=n.Root,WindowVisible=n.WindowVisible,WindowTitle=n.WindowTitle});result.Sort((a,b)=>a.StartUtc.CompareTo(b.StartUtc));return result;}}
 }
 public static class InspectionAuditFlags {
  public static uint Canonical(uint flags){uint bits=flags&3;return bits==0?4:bits;}
  public static uint WithFailure(uint flags){return (flags&3)|2;}
  public static bool CanRestore(uint original,uint applied,uint current){return Canonical(current)==Canonical(applied) || Canonical(current)==Canonical(original);}
 }
}

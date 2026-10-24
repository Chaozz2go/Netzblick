using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics.Eventing.Reader;
using System.Threading;

namespace Netzblick {
 public sealed class AccessWatch : IDisposable {
  readonly ConcurrentQueue<BlockEvent> queue=new ConcurrentQueue<BlockEvent>();
  readonly object gate=new object();EventLogWatcher watcher;InspectionAuditLease audit;Dictionary<string,string> devices;
  bool healthy=true;volatile bool stopped;string warning="";long dropped;
  public DateTime StartedUtc {get;private set;}
  public bool Healthy {get{lock(gate)return healthy;}} public string Warning {get{lock(gate)return warning;}}
  public long Dropped {get{return Interlocked.Read(ref dropped);}}
  void Warn(string text){lock(gate){healthy=false;warning=text;}}
  public static AccessWatch Start(){
   var watch=new AccessWatch{StartedUtc=DateTime.UtcNow,devices=WindowsProcesses.DeviceMap()};
   try{
    watch.audit=InspectionAuditLease.Acquire();
    var query=new EventLogQuery("Security",PathType.LogName,"*[System[Provider[@Name='Microsoft-Windows-Security-Auditing'] and (EventID=5157)]]");
    watch.watcher=new EventLogWatcher(query,null,false);watch.watcher.EventRecordWritten+=watch.Receive;watch.watcher.Enabled=true;return watch;
   }catch(Exception initial){try{watch.Dispose();}catch(Exception restore){throw new InvalidOperationException(initial.Message+" Audit-Wiederherstellung: "+restore.Message,initial);}throw;}
  }
  void Receive(object sender,EventRecordWrittenEventArgs args){
   if(args.EventException!=null){Warn("Blockereignisse nicht vollständig verfügbar: "+args.EventException.Message);return;}
   using(var record=args.EventRecord){
    if(record==null || stopped)return;
    try{
     var e=BlockEventParser.Parse(record.ToXml());if(e.TimeUtc<StartedUtc)return;
     e.Application=WindowsProcesses.ConvertPath(e.Application,devices);
     if(queue.Count>=4096){Interlocked.Increment(ref dropped);Warn("Ereignispuffer voll. Anfragen können fehlen; Sperrfilter werden separat überprüft.");return;}
     queue.Enqueue(e);
    }catch(Exception e){Warn("Ein Blockereignis konnte nicht ausgewertet werden: "+e.Message);}
   }
  }
  public List<BlockEvent> Drain(){var list=new List<BlockEvent>();BlockEvent e;while(queue.TryDequeue(out e))list.Add(e);return list;}
  public void VerifyAudit(){if((WindowsAudit.Query()&2)==0)Warn("Windows-Audit deaktiviert. Neue blockierte Zugriffe können in der Anzeige fehlen.");}
  public void Dispose(){
   if(stopped)return;stopped=true;
   try{if(watcher!=null){watcher.EventRecordWritten-=Receive;try{watcher.Enabled=false;}finally{watcher.Dispose();}}}
   finally{if(audit!=null){audit.Dispose();audit=null;}}
  }
 }
}
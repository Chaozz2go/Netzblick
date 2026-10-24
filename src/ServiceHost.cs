using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Pipes;
using System.Linq;
using System.Security.AccessControl;
using System.Security.Principal;
using System.ServiceProcess;
using System.Threading;

namespace Netzblick {
 public sealed class ControlService : ServiceBase {
  Thread worker;readonly ManualResetEvent stop=new ManualResetEvent(false);
  public ControlService(){ServiceName="NetzblickControl";CanStop=true;CanShutdown=true;AutoLog=false;}
  protected override void OnStart(string[] args){worker=new Thread(Run){IsBackground=true,Name="Netzblick Control"};worker.Start();}
  protected override void OnStop(){stop.Set();if(worker!=null&&!worker.Join(12000))throw new System.TimeoutException("Netzblick-Regeln konnten nicht geordnet beendet werden.");}
  protected override void OnShutdown(){OnStop();}
  static string ConfigPath {get{return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),"Netzblick","control.json");}}
  SetupConfig config=new SetupConfig();readonly SetupQueue queue=new SetupQueue();readonly List<string> history=new List<string>();
  WfpGate gate;AccessWatch watch;string problem="",warning="";bool verified;DateTime started=DateTime.UtcNow,checkedUtc;DateTime? recovery;
  public sealed class Recovery {public SetupConfig Before {get;set;} public DateTime UntilUtc {get;set;}}
  static string RecoveryPath {get{return ConfigPath+".recovery";}}
  SetupConfig rollback;
  void SaveRecovery(){string temp=RecoveryPath+".tmp";File.WriteAllText(temp,SetupWire.Json().Serialize(new Recovery{Before=rollback,UntilUtc=recovery.Value}));if(File.Exists(RecoveryPath))File.Replace(temp,RecoveryPath,null);else File.Move(temp,RecoveryPath);}
  void ClearRecovery(){if(File.Exists(RecoveryPath))File.Delete(RecoveryPath);recovery=null;rollback=null;}
  void Log(string text){history.Insert(0,DateTime.Now.ToString("HH:mm:ss")+" · "+text);if(history.Count>100)history.RemoveAt(history.Count-1);}
  static SetupConfig Clone(SetupConfig value){return SetupWire.Json().Deserialize<SetupConfig>(SetupWire.Json().Serialize(value));}
  void Save(SetupConfig value){string path=ConfigPath;Directory.CreateDirectory(Path.GetDirectoryName(path));string temp=path+".tmp";string json=SetupWire.Json().Serialize(value);if(System.Text.Encoding.UTF8.GetByteCount(json)>1048576)throw new InvalidDataException("Regeldatei wäre zu groß.");File.WriteAllText(temp,json,new System.Text.UTF8Encoding(false));if(File.Exists(path))File.Replace(temp,path,null);else File.Move(temp,path);}
  void Apply(SetupConfig next){
   next.Validate();if(gate==null)throw new InvalidOperationException("Filterdienst nicht bereit: "+problem);
   try{SetupChanges.Commit(config,next,gate.Replace,Save);config=next;verified=true;problem="";}
   catch(SetupChangeFailure e){verified=e.Restored;if(!verified)problem=e.Message;throw;}
  }
  bool NeedsWatch(SetupConfig value){return value.Ask||value.WatchedPaths.Count>0||value.Rules.Any(r=>r.Action=="Block");}
  void EnsureWatch(){if(watch==null)watch=AccessWatch.Start();if(!watch.Healthy)throw new InvalidOperationException(watch.Warning);}
  void Tick(){
   if(watch!=null){foreach(var e in watch.Drain())queue.Observe(e,gate!=null&&gate.OwnBlock(e.FilterId));}
   try{
    if(gate==null)throw new InvalidOperationException(problem);
    var next=Clone(config);if(next.Expire(DateTime.UtcNow)>0){Apply(next);Log("Zeitlich begrenzte Freigabe abgelaufen");}
    if(recovery.HasValue&&DateTime.UtcNow>=recovery.Value){var previous=Clone(rollback);previous.Expire(DateTime.UtcNow);Apply(previous);ClearRecovery();Log("Sicherheitsrückweg: vorherige Regeln wiederhergestellt");}
    if((DateTime.UtcNow-checkedUtc).TotalSeconds>=2){gate.Verify();verified=true;checkedUtc=DateTime.UtcNow;}
   }catch(Exception e){verified=false;problem=e.Message;}
   if(!NeedsWatch(config)&&watch!=null){try{watch.Dispose();watch=null;}catch(Exception e){warning="Audit-Wiederherstellung: "+e.Message;}}
   warning=watch==null&&NeedsWatch(config)?"Ereignisanzeige nicht verfügbar; Dienst neu starten und Audit prüfen.":"";
   if(watch!=null){watch.VerifyAudit();if(!watch.Healthy)warning=watch.Warning;}
   if(queue.Unknown>0||queue.Dropped>0)warning+=" Nicht zugeordnete Ereignisse: "+queue.Unknown+"; nicht gelistete Versuche: "+queue.Dropped+".";
  }
  SetupStatus Status(bool ok,string error){return new SetupStatus{Ok=ok,Error=error,Verified=verified,Warning=warning,Config=config,Attempts=queue.Snapshot(),History=new List<string>(history),CheckedUtc=checkedUtc,StartedUtc=started,RecoveryUtc=recovery};}
  SetupStatus Execute(SetupCommand command){
   if(command==null)throw new ArgumentException("Leerer Befehl.");
   if(command.Operation=="Status")return Status(true,problem);
   if(command.Operation=="ConfirmRecovery"){if(!verified)throw new InvalidOperationException("Einrichtung nicht bestätigt: Filterstatus unbekannt.");ClearRecovery();Log("Einrichtung bestätigt; Sicherheitsrückweg aufgehoben");return Status(true,problem);}
   if(!verified)throw new InvalidOperationException("Keine neue Änderung bei unbestätigtem Filterstatus: "+problem);
   var next=Clone(config);
   switch(command.Operation){
    case "Ask":
     if(command.Enabled&&!config.Ask){
      if(command.RecoveryMinutes<1||command.RecoveryMinutes>30)throw new ArgumentException("Rückweg benötigt 1 bis 30 Minuten.");
      if(recovery.HasValue)throw new InvalidOperationException("Bitte zuerst die laufende Einrichtung bestätigen.");
      EnsureWatch();
      rollback=Clone(config);recovery=DateTime.UtcNow.AddMinutes(command.RecoveryMinutes);Directory.CreateDirectory(Path.GetDirectoryName(ConfigPath));SaveRecovery();
     }
     next.Ask=command.Enabled;break;
    case "Watch":
     EnsureWatch();
     if(!AccessQueue.CanAllow(command.Path)||!File.Exists(command.Path))throw new ArgumentException("Vorhandene lokale EXE auswählen.");
     if(next.Rules.Any(r=>r.Action=="Allow"&&(r.Path=="*"||ProcessLineage.Normalize(r.Path)==ProcessLineage.Normalize(command.Path))))throw new InvalidOperationException("Zuerst bestehende Freigaben dieses Programms unter Regeln zurücknehmen.");
     if(!next.WatchedPaths.Any(p=>ProcessLineage.Normalize(p)==ProcessLineage.Normalize(command.Path)))next.WatchedPaths.Add(command.Path);break;
    case "Unwatch":next.WatchedPaths.RemoveAll(p=>ProcessLineage.Normalize(p)==ProcessLineage.Normalize(command.Path));break;
    case "Rule":
     if(command.Rule==null)throw new ArgumentException("Regel fehlt.");command.Rule.Validate();
     if(command.Rule.Path!="*"&&!File.Exists(command.Rule.Path))throw new ArgumentException("Programm existiert nicht mehr.");
     if(command.Rule.ExpiresUtc.HasValue&&(command.Rule.ExpiresUtc<=DateTime.UtcNow||command.Rule.ExpiresUtc>DateTime.UtcNow.AddHours(24)))throw new ArgumentException("Temporäre Regel muss innerhalb der nächsten 24 Stunden ablaufen.");
     if(next.Rules.Any(r=>r.Id==command.Rule.Id))throw new InvalidOperationException("Regel-ID ist bereits vorhanden.");
     if(command.Rule.Action=="Block")EnsureWatch();next.Rules.Add(command.Rule);break;
    case "Remove":if(next.Rules.RemoveAll(r=>r.Id==command.RuleId)==0)throw new ArgumentException("Regel nicht gefunden.");break;
    default:throw new ArgumentException("Unbekannter Befehl.");
   }
   try{Apply(next);}catch{if(command.Operation=="Ask"&&verified)ClearRecovery();throw;}
   if(command.Operation=="Ask"&&!command.Enabled)ClearRecovery();
   Log(command.Operation=="Rule"?"Regel gespeichert: "+command.Rule.Name:command.Operation=="Watch"?"Programm vorab gesperrt: "+command.Path:command.Operation=="Remove"?"Regel zurückgenommen":command.Operation=="Ask"?(command.Enabled?"Nachfragen aktiviert; Rückweg läuft":"Nachfragen deaktiviert; eigene Einzelregeln bleiben aktiv"):"Prüfsperre entfernt");
   return Status(true,problem);
  }
  static PipeSecurity Security(){var security=new PipeSecurity();security.SetAccessRuleProtection(true,false);security.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(WellKnownSidType.NetworkSid,null),PipeAccessRights.FullControl,AccessControlType.Deny));foreach(var sid in new[]{WellKnownSidType.LocalSystemSid,WellKnownSidType.BuiltinAdministratorsSid})security.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(sid,null),PipeAccessRights.FullControl,AccessControlType.Allow));return security;}
  void Run(){
   try{
    try{if(File.Exists(RecoveryPath)){
      var saved=SetupWire.Json().Deserialize<Recovery>(File.ReadAllText(RecoveryPath));if(saved==null||saved.Before==null)throw new InvalidDataException("Ungültiger Sicherheitsrückweg.");saved.Before.Validate();saved.Before.Expire(DateTime.UtcNow);Save(saved.Before);ClearRecovery();
     }
     if(File.Exists(ConfigPath)){var info=new FileInfo(ConfigPath);if(info.Length>1048576)throw new InvalidDataException("Regeldatei zu groß.");config=SetupWire.Json().Deserialize<SetupConfig>(File.ReadAllText(ConfigPath));config.Validate();config.Expire(DateTime.UtcNow);}
     gate=WfpGate.StartConfig(config);verified=true;checkedUtc=DateTime.UtcNow;
    }catch(Exception e){problem="Dienstfilter nicht bereit: "+e.Message;verified=false;}
    if(NeedsWatch(config))try{EnsureWatch();}catch(Exception e){warning="Ereignisanzeige nicht verfügbar: "+e.Message;}
    while(!stop.WaitOne(0)){
     try{
      using(var pipe=new NamedPipeServerStream(SetupWire.PipeName,PipeDirection.InOut,1,PipeTransmissionMode.Byte,PipeOptions.Asynchronous,8192,8192,Security())){
       var ar=pipe.BeginWaitForConnection(null,null);
       using(ar.AsyncWaitHandle){while(!ar.AsyncWaitHandle.WaitOne(400)){if(stop.WaitOne(0))break;Tick();}}
       if(stop.WaitOne(0))break;pipe.EndWaitForConnection(ar);Tick();
       SetupStatus reply;try{reply=Execute(SetupWire.Json().Deserialize<SetupCommand>(SetupWire.Read(pipe)));}catch(Exception e){reply=Status(false,e.Message);}
       SetupWire.Write(pipe,SetupWire.Json().Serialize(reply));
      }
     }catch(Exception e){Log("Dienstkommunikation: "+e.Message);stop.WaitOne(500);}
    }
   }finally{
    try{if(recovery.HasValue&&rollback!=null){Save(rollback);config=rollback;ClearRecovery();}}
    finally{try{if(gate!=null)gate.Dispose();}finally{if(watch!=null)watch.Dispose();}}
   }
  }
  public static void Main(){if(Environment.UserInteractive)throw new InvalidOperationException("Mit Install-Netzblick.cmd als Windows-Dienst installieren.");ServiceBase.Run(new ControlService());}
 }
}

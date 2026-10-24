using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Diagnostics.Eventing.Reader;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32;

namespace Netzblick {
 public sealed class InspectionFile {
  public string Path {get;set;} public string Company {get;set;} public string Version {get;set;}
  public string Hash {get;set;} public string Signer {get;set;} public string Error {get;set;}
  public static Task<InspectionFile> Start(string path){return Task.Run(()=>Read(path));}
  static InspectionFile Read(string path){
   var result=new InspectionFile{Path=System.IO.Path.GetFullPath(path),Company="Unbekannt",Version="Unbekannt",Signer="Keine eingebettete Signatur erkannt (Katalogsignaturen nicht geprüft)"};
   try{
    using(var file=File.Open(result.Path,FileMode.Open,FileAccess.Read,FileShare.Read))using(var sha=SHA256.Create())result.Hash=BitConverter.ToString(sha.ComputeHash(file)).Replace("-","");
    var info=FileVersionInfo.GetVersionInfo(result.Path);result.Company=info.CompanyName??"Unbekannt";result.Version=info.FileVersion??"Unbekannt";
    try{using(var cert=new X509Certificate2(X509Certificate.CreateFromSignedFile(result.Path)))result.Signer="Eingebetteter Unterzeichner: "+cert.Subject+" · Vertrauen/Gültigkeit nicht geprüft";}catch(CryptographicException){}
   }catch(Exception e){result.Error=e.Message;}
   return result;
  }
 }
 public static class WindowsAudit {
  public static readonly Guid FilteringConnection=new Guid("0CCE9226-69AE-11D9-BED3-505054503030");
  [StructLayout(LayoutKind.Sequential)] struct AuditPolicy {public Guid SubCategory;public uint Flags;public Guid Category;}
  [StructLayout(LayoutKind.Sequential)] struct Luid {public uint Low;public int High;}
  [StructLayout(LayoutKind.Sequential)] struct TokenPrivileges {public uint Count;public Luid Luid;public uint Attributes;}
  [DllImport("advapi32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.U1)] static extern bool AuditQuerySystemPolicy([In] Guid[] guids,uint count,out IntPtr result);
  [DllImport("advapi32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.U1)] static extern bool AuditSetSystemPolicy([In] AuditPolicy[] policies,uint count);
  [DllImport("advapi32.dll")] static extern void AuditFree(IntPtr pointer);
  [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
  [DllImport("kernel32.dll")] [return:MarshalAs(UnmanagedType.Bool)] static extern bool CloseHandle(IntPtr handle);
  [DllImport("advapi32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] static extern bool OpenProcessToken(IntPtr process,uint access,out IntPtr token);
  [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] static extern bool LookupPrivilegeValue(string system,string name,out Luid luid);
  [DllImport("advapi32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] static extern bool AdjustTokenPrivileges(IntPtr token,bool disable,ref TokenPrivileges state,uint size,IntPtr previous,IntPtr needed);
  public static void EnablePrivilege(){
   IntPtr token;if(!OpenProcessToken(GetCurrentProcess(),0x28,out token))throw new Win32Exception(Marshal.GetLastWin32Error());
   try{Luid luid;if(!LookupPrivilegeValue(null,"SeSecurityPrivilege",out luid))throw new Win32Exception(Marshal.GetLastWin32Error());
    var p=new TokenPrivileges{Count=1,Luid=luid,Attributes=2};
    if(!AdjustTokenPrivileges(token,false,ref p,0,IntPtr.Zero,IntPtr.Zero))throw new Win32Exception(Marshal.GetLastWin32Error());
    int error=Marshal.GetLastWin32Error();if(error!=0)throw new Win32Exception(error,"Berechtigung zum Lesen/Ändern der Audit-Richtlinie fehlt.");
   }finally{CloseHandle(token);}
  }
  public static uint Query(){
   IntPtr pointer;if(!AuditQuerySystemPolicy(new Guid[]{FilteringConnection},1,out pointer))throw new Win32Exception(Marshal.GetLastWin32Error());
   try{return ((AuditPolicy)Marshal.PtrToStructure(pointer,typeof(AuditPolicy))).Flags;}finally{AuditFree(pointer);}
  }
  public static void Set(uint flags){var p=new AuditPolicy{SubCategory=FilteringConnection,Flags=InspectionAuditFlags.Canonical(flags)};if(!AuditSetSystemPolicy(new AuditPolicy[]{p},1))throw new Win32Exception(Marshal.GetLastWin32Error());}
 }
 public sealed class InspectionAuditLease : IDisposable {
  const string KeyPath="SOFTWARE\\Netzblick\\InspectionAuditRecovery";
  Mutex mutex;bool owns;bool disposed;
  static RegistryKey Machine(){return RegistryKey.OpenBaseKey(RegistryHive.LocalMachine,RegistryView.Registry64);}
  void Lock(){
   mutex=new Mutex(false,"Global\\Netzblick.InspectionAudit.v1");
   try{owns=mutex.WaitOne(0);}catch(AbandonedMutexException){owns=true;}
   if(!owns){mutex.Dispose();mutex=null;throw new InvalidOperationException("In einer anderen Netzblick-Instanz läuft bereits eine Prüfung.");}
  }
  static string Recover(){
   using(var machine=Machine())using(var key=machine.OpenSubKey(KeyPath,false)){
    if(key==null)return "";
    byte[] state=key.GetValue("State",null) as byte[];
    if(state==null || state.Length!=12 || Encoding.ASCII.GetString(state,0,4)!="NBI1")throw new InvalidOperationException("Audit-Wiederherstellungsdaten unvollständig. Keine Richtlinie verändert.");
    uint original=InspectionAuditFlags.Canonical(BitConverter.ToUInt32(state,4)),applied=InspectionAuditFlags.Canonical(BitConverter.ToUInt32(state,8));
    WindowsAudit.EnablePrivilege();uint current=WindowsAudit.Query();
    if(!InspectionAuditFlags.CanRestore(original,applied,current))throw new InvalidOperationException("Audit-Einstellung wurde zwischenzeitlich geändert. Keine fremde Änderung überschrieben. Gesichert="+original+", von Netzblick gesetzt="+applied+", aktuell="+current+". Details: README, Audit-Wiederherstellung.");
    if(InspectionAuditFlags.Canonical(current)!=original){WindowsAudit.Set(original);if(InspectionAuditFlags.Canonical(WindowsAudit.Query())!=original)throw new InvalidOperationException("Audit-Wiederherstellung konnte nicht bestätigt werden.");}
   }
   using(var machine=Machine())machine.DeleteSubKey(KeyPath,false);
   return "Vorherige Audit-Einstellung wiederhergestellt.";
  }
  public static string RecoverPending(){var lease=new InspectionAuditLease();try{lease.Lock();return Recover();}finally{lease.Release();}}
  public static InspectionAuditLease Acquire(){
   var lease=new InspectionAuditLease();
   try{
    lease.Lock();Recover();WindowsAudit.EnablePrivilege();
    uint original=InspectionAuditFlags.Canonical(WindowsAudit.Query()),applied=InspectionAuditFlags.WithFailure(original);
    if(original!=applied){
     using(var machine=Machine())using(var key=machine.CreateSubKey(KeyPath)){
      byte[] state=new byte[12];Encoding.ASCII.GetBytes("NBI1").CopyTo(state,0);BitConverter.GetBytes(original).CopyTo(state,4);BitConverter.GetBytes(applied).CopyTo(state,8);
      key.SetValue("State",state,RegistryValueKind.Binary);
      key.SetValue("RecordedUtc",DateTime.UtcNow.ToString("o"),RegistryValueKind.String);key.Flush();
     }
     WindowsAudit.Set(applied);
    }
    if((WindowsAudit.Query()&2)==0)throw new InvalidOperationException("Fehlerüberwachung wurde nicht wirksam. Möglicherweise verhindert eine Gruppenrichtlinie die Änderung.");
    return lease;
   }catch(Exception initial){
    string recovery="";if(lease.owns)try{Recover();}catch(Exception e){recovery=" Wiederherstellung: "+e.Message;}
    lease.Release();throw new InvalidOperationException(initial.Message+recovery,initial);
   }
  }
  void Release(){if(owns){mutex.ReleaseMutex();owns=false;}if(mutex!=null){mutex.Dispose();mutex=null;}}
  public void Dispose(){if(disposed)return;disposed=true;try{Recover();}finally{Release();}}
 }
 public static class WindowsProcesses {
  [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct Entry {
   public uint Size,Usage,Pid;public UIntPtr Heap;public uint Module,Threads,Parent;public int Priority;public uint Flags;
   [MarshalAs(UnmanagedType.ByValTStr,SizeConst=260)] public string Name;
  }
  [StructLayout(LayoutKind.Sequential)] struct FileTime {public uint Low,High;public long Value {get{return ((long)High<<32)|Low;}}}
  [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr CreateToolhelp32Snapshot(uint flags,uint pid);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] static extern bool Process32FirstW(IntPtr handle,ref Entry entry);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] static extern bool Process32NextW(IntPtr handle,ref Entry entry);
  [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(uint access,bool inherit,uint pid);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] static extern bool QueryFullProcessImageNameW(IntPtr process,uint flags,StringBuilder name,ref int length);
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] static extern bool GetProcessTimes(IntPtr process,out FileTime creation,out FileTime exit,out FileTime kernel,out FileTime user);
  [DllImport("kernel32.dll")] [return:MarshalAs(UnmanagedType.Bool)] static extern bool CloseHandle(IntPtr handle);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern uint QueryDosDeviceW(string name,StringBuilder target,int size);
  public static List<ProcessNode> Snapshot(){
   var result=new List<ProcessNode>();IntPtr snapshot=CreateToolhelp32Snapshot(2,0);
   if(snapshot==new IntPtr(-1))throw new Win32Exception(Marshal.GetLastWin32Error());
   try{
    var entry=new Entry{Size=(uint)Marshal.SizeOf(typeof(Entry))};
    bool more=Process32FirstW(snapshot,ref entry);
    if(!more && Marshal.GetLastWin32Error()!=18)throw new Win32Exception(Marshal.GetLastWin32Error());
    while(more){
     IntPtr process=OpenProcess(0x1000,false,entry.Pid);
     if(process!=IntPtr.Zero)try{
      int length=32768;var path=new StringBuilder(length);FileTime creation,exit,kernel,user;
      if(QueryFullProcessImageNameW(process,0,path,ref length) && GetProcessTimes(process,out creation,out exit,out kernel,out user))result.Add(new ProcessNode{Pid=(int)entry.Pid,ParentPid=(int)entry.Parent,Name=entry.Name,Path=path.ToString(),StartUtc=DateTime.FromFileTimeUtc(creation.Value)});
     }finally{CloseHandle(process);}
     more=Process32NextW(snapshot,ref entry);
    }
    int error=Marshal.GetLastWin32Error();if(error!=18)throw new Win32Exception(error);
   }finally{CloseHandle(snapshot);}
   return result;
  }
  public static Dictionary<string,string> DeviceMap(){
   var result=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
   for(char c='A';c<='Z';c++){
    var target=new StringBuilder(32768);string drive=c+":";
    if(QueryDosDeviceW(drive,target,target.Capacity)>0){string device=target.ToString().Split('\0')[0];if(device.Length>0)result[device]=drive;}
   }
   return result;
  }
  public static string ConvertPath(string path,Dictionary<string,string> devices){
   if(String.IsNullOrEmpty(path))return "";
   foreach(var pair in devices)if(path.StartsWith(pair.Key+"\\",StringComparison.OrdinalIgnoreCase))return pair.Value+path.Substring(pair.Key.Length);
   return path;
  }
 }
 public sealed class InspectionSession : IDisposable {
  sealed class Pending {public BlockEvent Event;public DateTime Received;}
  readonly ConcurrentQueue<BlockEvent> events=new ConcurrentQueue<BlockEvent>();
  readonly ConcurrentQueue<Pending> pending=new ConcurrentQueue<Pending>();
  readonly CancellationTokenSource cancel=new CancellationTokenSource();
  readonly object statusGate=new object();
  ProcessLineage lineage;Dictionary<string,string> devices;InspectionAuditLease lease;EventLogWatcher watcher;Task sampler;
  long outgoing,incoming,unknown,dropped,stoppedTicks;string warning="";bool healthy=true;volatile bool stopped;
  public string Path {get;private set;} public DateTime StartedUtc {get;private set;}
  public DateTime? StoppedUtc {get{long ticks=Interlocked.Read(ref stoppedTicks);return ticks==0?(DateTime?)null:new DateTime(ticks,DateTimeKind.Utc);}}
  public long Outgoing {get{return Interlocked.Read(ref outgoing);}} public long Incoming {get{return Interlocked.Read(ref incoming);}}
  public long UnknownDirection {get{return Interlocked.Read(ref unknown);}} public long Dropped {get{return Interlocked.Read(ref dropped);}}
  public bool Healthy {get{lock(statusGate)return healthy;}} public string Warning {get{lock(statusGate)return warning;}}
  void Warn(string text){lock(statusGate){healthy=false;if(warning.IndexOf(text,StringComparison.Ordinal)<0)warning=warning.Length==0?text:warning+" | "+text;}}
  public static InspectionSession Start(string path){
   string full=System.IO.Path.GetFullPath(path);
   if(!File.Exists(full) || !full.EndsWith(".exe",StringComparison.OrdinalIgnoreCase) || full.StartsWith("\\\\",StringComparison.Ordinal))throw new ArgumentException("Eine vorhandene lokale EXE auswählen.");
   var initial=WindowsProcesses.Snapshot();foreach(var n in initial)if(ProcessLineage.Normalize(n.Path)==ProcessLineage.Normalize(full))throw new InvalidOperationException("Das ausgewählte Programm läuft bereits. Bitte zuerst selbst schließen; danach die Prüfung erneut starten.");
   var s=new InspectionSession{Path=full,StartedUtc=DateTime.UtcNow};s.lineage=new ProcessLineage(full,s.StartedUtc);s.devices=WindowsProcesses.DeviceMap();
   try{
    s.lease=InspectionAuditLease.Acquire();
    var query=new EventLogQuery("Security",PathType.LogName,"*[System[Provider[@Name='Microsoft-Windows-Security-Auditing'] and (EventID=5157)]]");
    s.watcher=new EventLogWatcher(query,null,false);s.watcher.EventRecordWritten+=s.Receive;s.watcher.Enabled=true;
    s.sampler=Task.Run(()=>s.Sample());return s;
   }catch(Exception initialError){
    string recovery="";try{s.Dispose();}catch(Exception e){recovery=" Wiederherstellung: "+e.Message;}
    throw new InvalidOperationException(initialError.Message+recovery,initialError);
   }
  }
  void Receive(object sender,EventRecordWrittenEventArgs args){
   if(args.EventException!=null){Warn("Ereigniserfassung unterbrochen: "+args.EventException.Message);return;}
   using(var record=args.EventRecord){if(record==null || stopped)return;
    try{
     var e=BlockEventParser.Parse(record.ToXml());e.Application=WindowsProcesses.ConvertPath(e.Application,devices);
     if(e.TimeUtc<StartedUtc)return;
     if(ProcessLineage.Normalize(e.Application)==ProcessLineage.Normalize(Path)){Accept(e);return;}
     if(pending.Count>=4096){Interlocked.Increment(ref dropped);Warn("Puffer für noch nicht zugeordnete Ereignisse voll; Erfassung unvollständig.");return;}
     pending.Enqueue(new Pending{Event=e,Received=DateTime.UtcNow});
    }catch(Exception e){Warn("Ein Ereignis konnte nicht ausgewertet werden: "+e.Message);}
   }
  }
  void Accept(BlockEvent e){
   if(StoppedUtc.HasValue && e.TimeUtc>StoppedUtc.Value)return;
   if(e.Direction=="Ausgehend")Interlocked.Increment(ref outgoing);else if(e.Direction=="Eingehend")Interlocked.Increment(ref incoming);else Interlocked.Increment(ref unknown);
   if(events.Count>=4096){Interlocked.Increment(ref dropped);Warn("Anzeigepuffer voll; einzelne Ereignisse fehlen.");return;}events.Enqueue(e);
  }
  void FlushPending(){
   int count=pending.Count;
   for(int i=0;i<count;i++){
    Pending p;if(!pending.TryDequeue(out p))break;
    if((DateTime.UtcNow-p.Received).TotalMilliseconds<600){pending.Enqueue(p);continue;}
    if(lineage.Matches(p.Event))Accept(p.Event);
    else if((DateTime.UtcNow-p.Received).TotalSeconds<2)pending.Enqueue(p);
   }
  }
  void Sample(){
   DateTime lastAudit=DateTime.MinValue;
   while(!cancel.IsCancellationRequested){
    try{
     lineage.Observe(WindowsProcesses.Snapshot(),DateTime.UtcNow);FlushPending();
     if(lineage.Snapshot().Count>=1024)Warn("Prozesslimit 1024 erreicht; Prozessübersicht unvollständig.");
     if((DateTime.UtcNow-lastAudit).TotalSeconds>=3){if((WindowsAudit.Query()&2)==0)Warn("Windows-Audit wurde deaktiviert; blockierte Versuche können fehlen.");lastAudit=DateTime.UtcNow;}
    }catch(Exception e){Warn("Prozess-/Audit-Erfassung: "+e.Message);}
    cancel.Token.WaitHandle.WaitOne(500);
   }
  }
  public List<BlockEvent> Drain(){var result=new List<BlockEvent>();BlockEvent e;while(events.TryDequeue(out e))result.Add(e);return result;}
  public List<ProcessNode> Processes(){return lineage.Snapshot();}
  public void Dispose(){
   if(stopped)return;Interlocked.Exchange(ref stoppedTicks,DateTime.UtcNow.Ticks);stopped=true;cancel.Cancel();
   try{if(watcher!=null){watcher.EventRecordWritten-=Receive;try{watcher.Enabled=false;}finally{watcher.Dispose();}}}
   finally{
    try{if(sampler!=null && !sampler.Wait(1500))Warn("Prozesssammler beendet noch seine laufende Abfrage.");FlushPending();}
    finally{if(lease!=null){lease.Dispose();lease=null;}}
   }
  }
 }
}

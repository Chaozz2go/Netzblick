using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace Netzblick {
 public sealed class WfpStartFailure : Exception {
  public WfpGate RecoveryGate {get;private set;}
  public WfpStartFailure(string message,WfpGate gate,Exception inner):base(message,inner){RecoveryGate=gate;}
 }

 // Native Windows WFP structures. x64 only; no kernel driver, persistent filter
 // or modification of existing Windows Firewall rules.
 public sealed class WfpGate : IDisposable {
  [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] public struct Display {
   [MarshalAs(UnmanagedType.LPWStr)] public string Name;
   [MarshalAs(UnmanagedType.LPWStr)] public string Description;
  }
  [StructLayout(LayoutKind.Sequential)] public struct Blob {public uint Size;public IntPtr Data;}
  [StructLayout(LayoutKind.Explicit,Size=8)] public struct ValueUnion {
   [FieldOffset(0)] public byte Byte;[FieldOffset(0)] public uint UInt;[FieldOffset(0)] public IntPtr Pointer;
  }
  [StructLayout(LayoutKind.Sequential)] public struct Value {public uint Type;public ValueUnion Data;}
  [StructLayout(LayoutKind.Sequential)] public struct Action {public uint Type;public Guid Key;}
  [StructLayout(LayoutKind.Explicit,Size=16)] public struct Context {
   [FieldOffset(0)] public ulong Raw;[FieldOffset(0)] public Guid Key;
  }
  [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] public struct Session {
   public Guid Key;public Display Display;public uint Flags,Timeout,ProcessId;public IntPtr Sid;
   [MarshalAs(UnmanagedType.LPWStr)] public string User;public int KernelMode;
  }
  [StructLayout(LayoutKind.Sequential)] public struct SubLayer {
   public Guid Key;public Display Display;public uint Flags;public IntPtr Provider;public Blob Data;public ushort Weight;
  }
  [StructLayout(LayoutKind.Sequential)] public struct Condition {public Guid Field;public uint Match;public Value Value;}
  [StructLayout(LayoutKind.Sequential)] public struct Filter {
   public Guid Key;public Display Display;public uint Flags;public IntPtr Provider;public Blob Data;
   public Guid Layer,SubLayer;public Value Weight;public uint Count;public IntPtr Conditions;
   public Action Action;public Context Context;public IntPtr Reserved;public ulong Id;public Value EffectiveWeight;
  }
  sealed class Engine : SafeHandleZeroOrMinusOneIsInvalid {
   public Engine(IntPtr value):base(true){SetHandle(value);}
   protected override bool ReleaseHandle(){return FwpmEngineClose0(handle)==0;}
   public void CloseChecked(){uint error=FwpmEngineClose0(handle);Check(error,"WFP-Sitzung beenden");SetHandleAsInvalid();}
  }
  sealed class Expected {
   public ulong Id,Weight;public Guid Layer;public uint Action;public int Kind;public byte[] App;
  }
  [DllImport("fwpuclnt.dll",CharSet=CharSet.Unicode)] static extern uint FwpmEngineOpen0(string server,uint authentication,IntPtr identity,ref Session session,out IntPtr engine);
  [DllImport("fwpuclnt.dll")] static extern uint FwpmEngineClose0(IntPtr engine);
  [DllImport("fwpuclnt.dll")] static extern uint FwpmTransactionBegin0(Engine engine,uint flags);
  [DllImport("fwpuclnt.dll")] static extern uint FwpmTransactionCommit0(Engine engine);
  [DllImport("fwpuclnt.dll")] static extern uint FwpmTransactionAbort0(Engine engine);
  [DllImport("fwpuclnt.dll")] static extern uint FwpmSubLayerAdd0(Engine engine,ref SubLayer layer,IntPtr security);
  [DllImport("fwpuclnt.dll")] static extern uint FwpmSubLayerGetByKey0(Engine engine,ref Guid key,out IntPtr layer);
  [DllImport("fwpuclnt.dll")] static extern uint FwpmSubLayerCreateEnumHandle0(Engine engine,IntPtr template,out IntPtr handle);
  [DllImport("fwpuclnt.dll")] static extern uint FwpmSubLayerEnum0(Engine engine,IntPtr handle,uint requested,out IntPtr entries,out uint returned);
  [DllImport("fwpuclnt.dll")] static extern uint FwpmSubLayerDestroyEnumHandle0(Engine engine,IntPtr handle);
  [DllImport("fwpuclnt.dll")] static extern uint FwpmFilterAdd0(Engine engine,ref Filter filter,IntPtr security,out ulong id);
  [DllImport("fwpuclnt.dll")] static extern uint FwpmFilterDeleteById0(Engine engine,ulong id);
  [DllImport("fwpuclnt.dll")] static extern uint FwpmFilterGetById0(Engine engine,ulong id,out IntPtr filter);
  [DllImport("fwpuclnt.dll",CharSet=CharSet.Unicode)] static extern uint FwpmGetAppIdFromFileName0(string name,out IntPtr blob);
  [DllImport("fwpuclnt.dll")] static extern void FwpmFreeMemory0(ref IntPtr memory);
  static readonly Guid Connect4=new Guid("c38d57d1-05a7-4c33-904f-7fbceee60e82"),Connect6=new Guid("4a72393b-319f-44bc-84c3-ba54dcb3b6b4");
  static readonly Guid Receive4=new Guid("e1cd9fe7-f4b5-4273-96c0-592e487b8650"),Receive6=new Guid("a3b42c97-9f04-4672-b87e-cee9c483257f");
  static readonly Guid FlagsField=new Guid("632ce23b-5167-435c-86d7-e903684aa80c"),AppField=new Guid("d78e1e87-8644-4ea5-9437-d809ecefc971");
  const uint Block=0x1001,Permit=0x1002;
  Engine engine;readonly Guid subLayer=Guid.NewGuid();
  readonly List<Expected> expected=new List<Expected>();
  readonly Dictionary<string,List<Expected>> allowed=new Dictionary<string,List<Expected>>(StringComparer.OrdinalIgnoreCase);
  bool closed;
  static void Check(uint code,string operation){if(code!=0)throw new Win32Exception(unchecked((int)code),operation+" fehlgeschlagen (0x"+code.ToString("X8")+").");}
  public static void ValidateLayout(){
   if(IntPtr.Size!=8)throw new PlatformNotSupportedException("Der Kontrollmodus benötigt 64-Bit-Windows-PowerShell.");
   if(Marshal.SizeOf(typeof(Filter))!=200 || Marshal.SizeOf(typeof(Condition))!=40 ||
      Marshal.SizeOf(typeof(Session))!=72 || Marshal.SizeOf(typeof(SubLayer))!=72 ||
      Marshal.OffsetOf(typeof(Filter),"Context").ToInt32()!=152)
    throw new PlatformNotSupportedException("WFP-Strukturlayout konnte nicht bestätigt werden.");
  }
  public static WfpGate Start() {
   ValidateLayout();var gate=new WfpGate();
   try {
    var session=new Session{Key=Guid.NewGuid(),Display=new Display{Name="Netzblick Kontrollmodus",Description="Nur solange Netzblick läuft"},Flags=1,Timeout=5000};
    IntPtr handle;Check(FwpmEngineOpen0(null,10,IntPtr.Zero,ref session,out handle),"WFP öffnen");gate.engine=new Engine(handle);
    gate.CheckPriority();
    Check(FwpmTransactionBegin0(gate.engine,0),"Sperrtransaktion starten");
    try{
     var layer=new SubLayer{Key=gate.subLayer,Display=new Display{Name="Netzblick Sitzung"},Weight=65535};
     Check(FwpmSubLayerAdd0(gate.engine,ref layer,IntPtr.Zero),"Sitzungsebene anlegen");
     foreach(Guid target in new Guid[]{Connect4,Connect6,Receive4,Receive6}){
      gate.expected.Add(gate.Add(target,Block,1,0,IntPtr.Zero,null));
      gate.expected.Add(gate.Add(target,Permit,200,1,IntPtr.Zero,null));
     }
     Check(FwpmTransactionCommit0(gate.engine),"Sperrtransaktion bestätigen");
    }catch{FwpmTransactionAbort0(gate.engine);throw;}
    gate.Verify();return gate;
   }catch(Exception initial){if(gate.engine!=null)try{gate.Dispose();}catch(Exception cleanup){throw new WfpStartFailure(initial.Message+" Sitzungsende nicht bestätigt: "+cleanup.Message,gate,initial);}throw;}
  }
  void CheckPriority(){
   IntPtr handle;Check(FwpmSubLayerCreateEnumHandle0(engine,IntPtr.Zero,out handle),"WFP-Prioritäten lesen");
   try{int total=0;while(true){
    IntPtr entries;uint count;Check(FwpmSubLayerEnum0(engine,handle,128,out entries,out count),"WFP-Prioritäten lesen");
    try{for(int i=0;i<count;i++){var layer=(SubLayer)Marshal.PtrToStructure(Marshal.ReadIntPtr(entries,i*IntPtr.Size),typeof(SubLayer));if(layer.Key!=subLayer && layer.Weight==65535)throw new InvalidOperationException("Eine andere WFP-Ebene besitzt dieselbe höchste Priorität. Kontrollmodus nicht bestätigt; keine neuen Sperren aktiviert.");}}
    finally{if(entries!=IntPtr.Zero)FwpmFreeMemory0(ref entries);}
    total+=(int)count;if(total>16384)throw new InvalidOperationException("Zu viele WFP-Ebenen für eine vollständige Prüfung.");
    if(count==0)break;
   }}finally{FwpmSubLayerDestroyEnumHandle0(engine,handle);}
  }
  Expected Add(Guid layer,uint action,ulong weight,int kind,IntPtr appBlob,byte[] app) {
   IntPtr weightMemory=Marshal.AllocHGlobal(8),conditionMemory=IntPtr.Zero;
   try{
    Marshal.WriteInt64(weightMemory,unchecked((long)weight));
    var filter=new Filter{Key=Guid.NewGuid(),Display=new Display{Name=action==Block?"Netzblick: ohne Freigabe blockieren":kind==1?"Netzblick: Kommunikation auf diesem PC":"Netzblick: ausgehende Sitzungsfreigabe"},Layer=layer,SubLayer=subLayer,Weight=new Value{Type=4,Data=new ValueUnion{Pointer=weightMemory}},Action=new Action{Type=action}};
    if(kind!=0){
     var condition=kind==1?new Condition{Field=FlagsField,Match=6,Value=new Value{Type=3,Data=new ValueUnion{UInt=1}}}:new Condition{Field=AppField,Match=0,Value=new Value{Type=12,Data=new ValueUnion{Pointer=appBlob}}};
     conditionMemory=Marshal.AllocHGlobal(Marshal.SizeOf(typeof(Condition)));Marshal.StructureToPtr(condition,conditionMemory,false);
     filter.Count=1;filter.Conditions=conditionMemory;
    }
    ulong id;Check(FwpmFilterAdd0(engine,ref filter,IntPtr.Zero,out id),"WFP-Filter hinzufügen");
    return new Expected{Id=id,Layer=layer,Action=action,Weight=weight,Kind=kind,App=app};
   }finally{if(conditionMemory!=IntPtr.Zero)Marshal.FreeHGlobal(conditionMemory);Marshal.FreeHGlobal(weightMemory);}
  }
  static byte[] ReadBlob(IntPtr pointer){var blob=(Blob)Marshal.PtrToStructure(pointer,typeof(Blob));if(blob.Size>131072 || blob.Data==IntPtr.Zero)throw new InvalidOperationException("Ungültige WFP-App-ID.");var bytes=new byte[blob.Size];Marshal.Copy(blob.Data,bytes,0,bytes.Length);return bytes;}
  static bool Same(byte[] a,byte[] b){if(a==null || b==null || a.Length!=b.Length)return false;for(int i=0;i<a.Length;i++)if(a[i]!=b[i])return false;return true;}
  public void Allow(string path){
   if(closed)throw new ObjectDisposedException("WfpGate");
   if(!AccessQueue.CanAllow(path) || !File.Exists(path))throw new ArgumentException("Nur eine noch vorhandene lokale EXE kann freigegeben werden.");
   string key=ProcessLineage.Normalize(path);if(allowed.ContainsKey(key))return;
   Verify();IntPtr blob=IntPtr.Zero;var filters=new List<Expected>();
   try{
    Check(FwpmGetAppIdFromFileName0(Path.GetFullPath(path),out blob),"WFP-App-ID lesen");byte[] bytes=ReadBlob(blob);
    Check(FwpmTransactionBegin0(engine,0),"Freigabe starten");
    try{foreach(Guid layer in new Guid[]{Connect4,Connect6})filters.Add(Add(layer,Permit,100,2,blob,bytes));Check(FwpmTransactionCommit0(engine),"Freigabe bestätigen");}
    catch{FwpmTransactionAbort0(engine);throw;}
    allowed.Add(key,filters);expected.AddRange(filters);Verify();
   }finally{if(blob!=IntPtr.Zero)FwpmFreeMemory0(ref blob);}
  }
  public void Revoke(string path){
   if(closed)throw new ObjectDisposedException("WfpGate");
   string key=ProcessLineage.Normalize(path);List<Expected> filters;if(!allowed.TryGetValue(key,out filters))return;
   Check(FwpmTransactionBegin0(engine,0),"Freigabe zurücknehmen");
   try{foreach(var filter in filters)Check(FwpmFilterDeleteById0(engine,filter.Id),"Sitzungsfreigabe entfernen");Check(FwpmTransactionCommit0(engine),"Rücknahme bestätigen");}
   catch{FwpmTransactionAbort0(engine);throw;}
   foreach(var filter in filters)expected.Remove(filter);allowed.Remove(key);Verify();
  }
  public bool OwnBlock(ulong id){foreach(var filter in expected)if(filter.Id==id && filter.Action==Block)return true;return false;}
  public int AllowedCount {get{return allowed.Count;}}
  public void Verify(){
   if(closed || engine==null || engine.IsInvalid || engine.IsClosed)throw new InvalidOperationException("WFP-Sitzung ist nicht mehr aktiv.");
   IntPtr memory;Guid key=subLayer;Check(FwpmSubLayerGetByKey0(engine,ref key,out memory),"Sitzungsebene überprüfen");
   try{var layer=(SubLayer)Marshal.PtrToStructure(memory,typeof(SubLayer));if(layer.Key!=subLayer || layer.Weight!=65535)throw new InvalidOperationException("WFP-Ebene wurde verändert.");}
   finally{FwpmFreeMemory0(ref memory);}
   CheckPriority();
   foreach(var wanted in expected){
    Check(FwpmFilterGetById0(engine,wanted.Id,out memory),"Sperr-/Freigabefilter überprüfen");
    try{
     var actual=(Filter)Marshal.PtrToStructure(memory,typeof(Filter));
     if(actual.Layer!=wanted.Layer || actual.SubLayer!=subLayer || actual.Action.Type!=wanted.Action || actual.Flags!=0 || actual.Weight.Type!=4 || actual.Weight.Data.Pointer==IntPtr.Zero || unchecked((ulong)Marshal.ReadInt64(actual.Weight.Data.Pointer))!=wanted.Weight || actual.Count!=(wanted.Kind==0?0u:1u))throw new InvalidOperationException("WFP-Filter entspricht nicht mehr der Sitzungsentscheidung.");
     if(wanted.Kind!=0){
      var condition=(Condition)Marshal.PtrToStructure(actual.Conditions,typeof(Condition));
      if(wanted.Kind==1){if(condition.Field!=FlagsField || condition.Match!=6 || condition.Value.Type!=3 || condition.Value.Data.UInt!=1)throw new InvalidOperationException("Lokale Ausnahme wurde verändert.");}
      else if(condition.Field!=AppField || condition.Match!=0 || condition.Value.Type!=12 || !Same(ReadBlob(condition.Value.Data.Pointer),wanted.App))throw new InvalidOperationException("Programmfreigabe wurde verändert.");
     }
    }finally{FwpmFreeMemory0(ref memory);}
   }
  }
  public void Dispose(){if(closed)return;if(engine!=null){engine.CloseChecked();engine.Dispose();}closed=true;}
 }
}
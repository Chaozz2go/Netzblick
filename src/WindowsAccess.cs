using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Net;
using System.Linq;
using System.Text;
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
   [FieldOffset(0)] public ushort UShort;[FieldOffset(0)] public byte Byte;[FieldOffset(0)] public uint UInt;[FieldOffset(0)] public IntPtr Pointer;
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
  [StructLayout(LayoutKind.Sequential)] struct FilterEnumTemplate {
   public IntPtr Provider;public Guid Layer;public uint EnumType,Flags;public IntPtr ProviderContext;
   public uint Count;public IntPtr Conditions;public uint ActionMask;public IntPtr Callout;
  }
  sealed class Engine : SafeHandleZeroOrMinusOneIsInvalid {
   public Engine(IntPtr value):base(true){SetHandle(value);}
   protected override bool ReleaseHandle(){return FwpmEngineClose0(handle)==0;}
   public void CloseChecked(){uint error=FwpmEngineClose0(handle);Check(error,"WFP-Sitzung beenden");SetHandleAsInvalid();}
  }
  sealed class Expected {
   public ulong Id,Weight;public Guid Layer;public uint Action;public List<Spec> Specs;public string Name;
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
  [DllImport("fwpuclnt.dll")] static extern uint FwpmFilterCreateEnumHandle0(Engine engine,ref FilterEnumTemplate template,out IntPtr handle);
  [DllImport("fwpuclnt.dll")] static extern uint FwpmFilterEnum0(Engine engine,IntPtr handle,uint requested,out IntPtr entries,out uint returned);
  [DllImport("fwpuclnt.dll")] static extern uint FwpmFilterDestroyEnumHandle0(Engine engine,IntPtr handle);
  [DllImport("fwpuclnt.dll")] static extern uint FwpmFilterAdd0(Engine engine,ref Filter filter,IntPtr security,out ulong id);
  [DllImport("fwpuclnt.dll")] static extern uint FwpmFilterDeleteById0(Engine engine,ulong id);
  [DllImport("fwpuclnt.dll")] static extern uint FwpmFilterGetById0(Engine engine,ulong id,out IntPtr filter);
  [DllImport("fwpuclnt.dll",CharSet=CharSet.Unicode)] static extern uint FwpmGetAppIdFromFileName0(string name,out IntPtr blob);
  [DllImport("fwpuclnt.dll")] static extern void FwpmFreeMemory0(ref IntPtr memory);
  static readonly Guid Connect4=new Guid("c38d57d1-05a7-4c33-904f-7fbceee60e82"),Connect6=new Guid("4a72393b-319f-44bc-84c3-ba54dcb3b6b4");
  static readonly Guid Receive4=new Guid("e1cd9fe7-f4b5-4273-96c0-592e487b8650"),Receive6=new Guid("a3b42c97-9f04-4672-b87e-cee9c483257f");
  static readonly Guid FlagsField=new Guid("632ce23b-5167-435c-86d7-e903684aa80c"),AppField=new Guid("d78e1e87-8644-4ea5-9437-d809ecefc971");
  static readonly Guid RemoteAddressField=new Guid("b235ae9a-1d64-49b8-a44c-5ff3d9095045"),ProtocolField=new Guid("3971ef2b-623e-4f9a-8cb1-6e79b806b9a7");
  static readonly Guid RemotePortField=new Guid("c35a604d-d22b-4e1a-91b4-68f674ee674b"),LocalPortField=new Guid("0c1ba1af-5765-453f-af22-a8f791ac775b");
  sealed class Spec {public Guid Field;public uint Type,UInt;public byte[] Bytes;}
  sealed class Memory : IDisposable {
   readonly List<IntPtr> pointers=new List<IntPtr>();
   public IntPtr Alloc(int size){var p=Marshal.AllocHGlobal(size);pointers.Add(p);return p;}
   public IntPtr Bytes(byte[] data){var p=Alloc(data.Length);Marshal.Copy(data,0,p,data.Length);return p;}
   public void Dispose(){for(int i=pointers.Count-1;i>=0;i--)Marshal.FreeHGlobal(pointers[i]);}
  }
  const uint Block=0x1001,Permit=0x1002;
  Engine engine;readonly Guid subLayer=Guid.NewGuid();ushort layerWeight;
  readonly List<Expected> expected=new List<Expected>();
  readonly Dictionary<string,List<Expected>> allowed=new Dictionary<string,List<Expected>>(StringComparer.OrdinalIgnoreCase);
  bool closed;
  public string CompatibilityWarning {get;private set;}
  static void Check(uint code,string operation){if(code!=0)throw new Win32Exception(unchecked((int)code),operation+" fehlgeschlagen (0x"+code.ToString("X8")+").");}
  public static void ValidateLayout(){
   if(IntPtr.Size!=8)throw new PlatformNotSupportedException("Der Kontrollmodus benötigt 64-Bit-Windows-PowerShell.");
   if(Marshal.SizeOf(typeof(Filter))!=200 || Marshal.SizeOf(typeof(Condition))!=40 ||
      Marshal.SizeOf(typeof(Session))!=72 || Marshal.SizeOf(typeof(SubLayer))!=72 || Marshal.SizeOf(typeof(FilterEnumTemplate))!=72 ||
      Marshal.OffsetOf(typeof(Filter),"Context").ToInt32()!=152)
    throw new PlatformNotSupportedException("WFP-Strukturlayout konnte nicht bestätigt werden.");
  }
  public static WfpGate Start(){return StartConfig(new SetupConfig{Ask=true});}
  public static WfpGate StartConfig(SetupConfig config) {
   ValidateLayout();var gate=new WfpGate();
   try {
    var session=new Session{Key=Guid.NewGuid(),Display=new Display{Name="Netzblick Kontrollmodus",Description="Nur solange Netzblick läuft"},Flags=1,Timeout=5000};
    IntPtr handle;Check(FwpmEngineOpen0(null,10,IntPtr.Zero,ref session,out handle),"WFP öffnen");gate.engine=new Engine(handle);
    var plan=gate.Plan(config);
    // BFE chooses the closest free sublayer weight when the requested one
    // is occupied. Register an empty private layer, read that assignment,
    // then assess relevant higher/equal peers before installing any blocks.
    var layer=new SubLayer{Key=gate.subLayer,Display=new Display{Name="Netzblick Sitzung"},Weight=65535};
    Check(FwpmSubLayerAdd0(gate.engine,ref layer,IntPtr.Zero),"Sitzungsebene anlegen");
    IntPtr assigned;Guid own=gate.subLayer;Check(FwpmSubLayerGetByKey0(gate.engine,ref own,out assigned),"Zugewiesene WFP-Priorität lesen");
    try{var actual=(SubLayer)Marshal.PtrToStructure(assigned,typeof(SubLayer));if(actual.Key!=own)throw new InvalidOperationException("WFP-Ebene nicht bestätigt.");gate.layerWeight=actual.Weight;}finally{FwpmFreeMemory0(ref assigned);}
    gate.CheckCompatibility(plan);
    Check(FwpmTransactionBegin0(gate.engine,0),"Sperrtransaktion starten");
    try{gate.expected.AddRange(gate.InstallPlan(plan));Check(FwpmTransactionCommit0(gate.engine),"Sperrtransaktion bestätigen");}
    catch{FwpmTransactionAbort0(gate.engine);throw;}
    gate.Verify();return gate;
   }catch(Exception initial){if(gate.engine!=null)try{gate.Dispose();}catch(Exception cleanup){throw new WfpStartFailure(initial.Message+" Sitzungsende nicht bestätigt: "+cleanup.Message,gate,initial);}throw;}
  }
  Dictionary<Guid,string> PeerLayers(){
   var peers=new Dictionary<Guid,string>();
   IntPtr handle;Check(FwpmSubLayerCreateEnumHandle0(engine,IntPtr.Zero,out handle),"WFP-Prioritäten lesen");
   try{int total=0;while(true){
    IntPtr entries;uint count;Check(FwpmSubLayerEnum0(engine,handle,128,out entries,out count),"WFP-Prioritäten lesen");
    try{for(int i=0;i<count;i++){var layer=(SubLayer)Marshal.PtrToStructure(Marshal.ReadIntPtr(entries,i*IntPtr.Size),typeof(SubLayer));if(layer.Key!=subLayer && layer.Weight>=layerWeight)peers[layer.Key]=layer.Display.Name??layer.Key.ToString();}}
    finally{if(entries!=IntPtr.Zero)FwpmFreeMemory0(ref entries);}
    total+=(int)count;if(total>16384)throw new InvalidOperationException("Zu viele WFP-Ebenen für eine vollständige Prüfung.");
    if(count==0)break;
   }}finally{FwpmSubLayerDestroyEnumHandle0(engine,handle);}
   return peers;
  }
  // Equal sublayer weights alone do not prove interference. Inspect only
  // active filters on ALE layers used by our requested blocks. A static hard
  // permit that cannot be proven disjoint is rejected before installing them.
  // Driver callouts can make dynamic decisions; report this limit explicitly.
  bool MayOverlap(Expected block,Filter peer){
   if(block.Layer!=peer.Layer)return false;
   if(peer.Count>256||(peer.Count>0&&peer.Conditions==IntPtr.Zero))throw new InvalidOperationException("Fremde Filterbedingungen konnten nicht vollständig gelesen werden.");
   for(int i=0;i<peer.Count;i++){
    var c=(Condition)Marshal.PtrToStructure(IntPtr.Add(peer.Conditions,i*Marshal.SizeOf(typeof(Condition))),typeof(Condition));
    // Our higher-weight loopback exception intentionally permits local traffic.
    if(c.Field==FlagsField&&c.Value.Type==3&&((c.Match==6&&(c.Value.Data.UInt&1)!=0)||(c.Match==7&&c.Value.Data.UInt==1)||(c.Match==0&&(c.Value.Data.UInt&1)!=0)))return false;
    var own=block.Specs.FirstOrDefault(x=>x.Field==c.Field);if(own==null)continue;
    if(c.Field==AppField&&c.Value.Type==12&&(c.Match==0||c.Match==1)){
     bool same=Same(ReadBlob(c.Value.Data.Pointer),own.Bytes);if(c.Match==0&&!same||c.Match==1&&same)return false;
    }else if(c.Match==0&&c.Value.Type==own.Type){
     if(c.Value.Type==1&&c.Value.Data.Byte!=own.UInt)return false;
     if(c.Value.Type==2&&c.Value.Data.UShort!=own.UInt)return false;
     if(c.Value.Type==3&&c.Field!=FlagsField&&c.Value.Data.UInt!=own.UInt)return false;
     if(c.Value.Type==11){if(c.Value.Data.Pointer==IntPtr.Zero)throw new InvalidOperationException("Fremde IPv6-Bedingung fehlt.");var bytes=new byte[16];Marshal.Copy(c.Value.Data.Pointer,bytes,0,16);if(!Same(bytes,own.Bytes))return false;}
    }
   }
   return true;
  }
  void CheckCompatibility(List<Expected> plan){
   CompatibilityWarning="";var blocks=plan.Where(p=>p.Action==Block).ToList();if(blocks.Count==0)return;
   var peers=PeerLayers();if(peers.Count==0)return;var drivers=new HashSet<string>();
   foreach(var layer in blocks.Select(b=>b.Layer).Distinct()){
    var template=new FilterEnumTemplate{Layer=layer,ActionMask=UInt32.MaxValue};IntPtr handle;
    Check(FwpmFilterCreateEnumHandle0(engine,ref template,out handle),"Parallele Filter lesen");
    try{int total=0;while(true){
     IntPtr entries;uint count;Check(FwpmFilterEnum0(engine,handle,128,out entries,out count),"Parallele Filter aufzählen");
     try{for(int i=0;i<count;i++){
      var peer=(Filter)Marshal.PtrToStructure(Marshal.ReadIntPtr(entries,i*IntPtr.Size),typeof(Filter));
      if(!peers.ContainsKey(peer.SubLayer)||(peer.Flags&32)!=0)continue;
      bool hard=peer.Action.Type==Permit&&(peer.Flags&8)!=0,callout=(peer.Action.Type&0x4000)!=0;
      if((!hard&&!callout)||!blocks.Any(b=>MayOverlap(b,peer)))continue;
      if(hard)throw new InvalidOperationException("Diese Sperre kann nicht bestätigt werden: Eine nicht übersteuerbare Freigabe eines parallelen Netzwerkfilters könnte sie umgehen. Anbieter/Ebene: "+peers[peer.SubLayer]+"; Filter: "+(peer.Display.Name??peer.Key.ToString())+". Es werden keine fremden Regeln verändert.");
      drivers.Add(peers[peer.SubLayer]);
     }}finally{if(entries!=IntPtr.Zero)FwpmFreeMemory0(ref entries);}
     total+=(int)count;if(total>65536)throw new InvalidOperationException("Zu viele parallele Filter für eine vollständige Prüfung.");if(count==0)break;
    }}finally{FwpmFilterDestroyEnumHandle0(engine,handle);}
   }
   if(drivers.Count>0)CompatibilityWarning="Weitere Netzwerksoftware aktiv: "+String.Join(", ",drivers.Take(3))+". Die Netzblick-Regeln sind eingerichtet; zusätzliche Entscheidungen dieser Software lassen sich hier nicht vollständig prüfen.";
  }
  Expected Add(Guid layer,uint action,ulong weight,int kind,IntPtr appBlob,byte[] app) {
   var specs=new List<Spec>();
   if(kind==1)specs.Add(new Spec{Field=FlagsField,Type=3,UInt=1});
   if(kind==2)specs.Add(new Spec{Field=AppField,Type=12,Bytes=app});
   return AddSpecs(layer,action,weight,specs,kind==1?"Kommunikation auf diesem PC":"Sitzungsentscheidung");
  }
  Expected AddSpecs(Guid layer,uint action,ulong weight,List<Spec> specs,string name){
   using(var mem=new Memory()){
    IntPtr w=mem.Alloc(8);Marshal.WriteInt64(w,unchecked((long)weight));
    var filter=new Filter{Key=Guid.NewGuid(),Display=new Display{Name="Netzblick: "+name},Layer=layer,SubLayer=subLayer,Weight=new Value{Type=4,Data=new ValueUnion{Pointer=w}},Action=new Action{Type=action}};
    int stride=Marshal.SizeOf(typeof(Condition));
    if(specs.Count>0){filter.Count=(uint)specs.Count;filter.Conditions=mem.Alloc(stride*specs.Count);}
    for(int i=0;i<specs.Count;i++){
     var spec=specs[i];var val=new Value{Type=spec.Type};
     if(spec.Type==12){var blob=new Blob{Size=(uint)spec.Bytes.Length,Data=mem.Bytes(spec.Bytes)};val.Data.Pointer=mem.Alloc(Marshal.SizeOf(typeof(Blob)));Marshal.StructureToPtr(blob,val.Data.Pointer,false);}
     else if(spec.Type==11)val.Data.Pointer=mem.Bytes(spec.Bytes);
     else val.Data.UInt=spec.UInt;
     Marshal.StructureToPtr(new Condition{Field=spec.Field,Match=spec.Field==FlagsField?6u:0u,Value=val},IntPtr.Add(filter.Conditions,i*stride),false);
    }
    ulong id;Check(FwpmFilterAdd0(engine,ref filter,IntPtr.Zero,out id),"WFP-Filter hinzufügen");
    return new Expected{Id=id,Layer=layer,Action=action,Weight=weight,Specs=specs,Name=name};
   }
  }
  byte[] AppId(string path){if(File.Exists(path))path=CanonicalPath(path);IntPtr blob=IntPtr.Zero;try{Check(FwpmGetAppIdFromFileName0(path,out blob),"Programm-ID lesen");return ReadBlob(blob);}finally{if(blob!=IntPtr.Zero)FwpmFreeMemory0(ref blob);}}
  static Expected Planned(Guid layer,uint action,ulong weight,List<Spec> specs,string name){return new Expected{Layer=layer,Action=action,Weight=weight,Specs=specs,Name=name};}
  List<Expected> InstallPlan(List<Expected> plan){return plan.Select(p=>AddSpecs(p.Layer,p.Action,p.Weight,p.Specs,p.Name)).ToList();}
  List<Expected> Plan(SetupConfig config){
   config.Validate();var result=new List<Expected>();
   foreach(Guid target in new Guid[]{Connect4,Connect6,Receive4,Receive6}){
    if(config.Ask)result.Add(Planned(target,Block,1,new List<Spec>(),"ohne Freigabe blockieren"));
    result.Add(Planned(target,Permit,200,new List<Spec>{new Spec{Field=FlagsField,Type=3,UInt=1}},"Kommunikation auf diesem PC"));
   }
   foreach(string path in config.WatchedPaths){
    var specs=new List<Spec>{new Spec{Field=AppField,Type=12,Bytes=AppId(path)}};
    foreach(Guid target in new Guid[]{Connect4,Connect6,Receive4,Receive6})result.Add(Planned(target,Block,10,specs,"Programmprüfung"));
   }
   foreach(SetupRule r in config.Rules){
    if(r.ExpiresUtc.HasValue&&r.ExpiresUtc.Value<=DateTime.UtcNow)continue;
    var specs=new List<Spec>();
    if(r.Path!="*")specs.Add(new Spec{Field=AppField,Type=12,Bytes=AppId(r.Path)});
    IPAddress ip=null;if(r.Address!="*"){
     ip=IPAddress.Parse(r.Address);byte[] bytes=ip.GetAddressBytes();
     if(bytes.Length==4)specs.Add(new Spec{Field=RemoteAddressField,Type=3,UInt=((uint)bytes[0]<<24)|((uint)bytes[1]<<16)|((uint)bytes[2]<<8)|bytes[3]});
     else specs.Add(new Spec{Field=RemoteAddressField,Type=11,Bytes=bytes});
    }
    if(r.Protocol!=0)specs.Add(new Spec{Field=ProtocolField,Type=1,UInt=(uint)r.Protocol});
    if(r.Port>0)specs.Add(new Spec{Field=r.Direction=="Ausgehend"?RemotePortField:LocalPortField,Type=2,UInt=(uint)r.Port});
    bool outbound=r.Direction=="Ausgehend";
    foreach(bool v6 in new bool[]{false,true}){
     if(ip!=null&&(ip.GetAddressBytes().Length==16)!=v6)continue;
     if((r.Protocol==1&&v6)||(r.Protocol==58&&!v6))continue;
     Guid layer=outbound?(v6?Connect6:Connect4):(v6?Receive6:Receive4);
     result.Add(Planned(layer,r.Action=="Allow"?Permit:Block,r.Action=="Allow"?100ul:150ul,specs,r.Name));
    }
   }
   return result;
  }
  public void Replace(SetupConfig config){
   VerifyOwnFilters();var plan=Plan(config);CheckCompatibility(plan);Check(FwpmTransactionBegin0(engine,0),"Regeländerung starten");List<Expected> next;
   try{
    foreach(var item in expected)Check(FwpmFilterDeleteById0(engine,item.Id),"Alten Sitzungsfilter entfernen");
    next=InstallPlan(plan);Check(FwpmTransactionCommit0(engine),"Regeländerung bestätigen");
   }catch{FwpmTransactionAbort0(engine);throw;}
   expected.Clear();expected.AddRange(next);allowed.Clear();Verify();
  }
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern SafeFileHandle CreateFile(string path,uint access,uint share,IntPtr security,uint creation,uint flags,IntPtr template);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint GetFinalPathNameByHandle(SafeFileHandle file,StringBuilder name,uint size,uint flags);
  public static string CanonicalPath(string path){
   if(!AccessQueue.CanAllow(path))throw new ArgumentException("Lokaler EXE-Pfad erforderlich.");
   using(var file=CreateFile(Path.GetFullPath(path),0x80,7,IntPtr.Zero,3,0,IntPtr.Zero)){
    if(file.IsInvalid)throw new Win32Exception(Marshal.GetLastWin32Error(),"Programmpfad öffnen");
    var name=new StringBuilder(32768);uint n=GetFinalPathNameByHandle(file,name,(uint)name.Capacity,0);
    if(n==0||n>=name.Capacity)throw new Win32Exception(Marshal.GetLastWin32Error(),"Kanonischen Programmpfad lesen");
    string result=name.ToString();if(result.StartsWith(@"\\?\",StringComparison.Ordinal))result=result.Substring(4);
    if(!AccessQueue.CanAllow(result))throw new ArgumentException("Der endgültige Programmpfad ist keine lokale EXE.");return result;
   }
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
  // INDEXED only changes lookup performance. A returned CLEAR_ACTION_RIGHT
  // on a block remains restrictive; it is never accepted on our soft permits.
  public static bool ValidReturnedFlags(uint flags,bool block){return (flags & ~(64u|(block?8u:0u)))==0;}
  public void Verify(){VerifyOwnFilters();CheckCompatibility(expected);}
  void VerifyOwnFilters(){
   if(closed || engine==null || engine.IsInvalid || engine.IsClosed)throw new InvalidOperationException("WFP-Sitzung ist nicht mehr aktiv.");
   IntPtr memory;Guid key=subLayer;Check(FwpmSubLayerGetByKey0(engine,ref key,out memory),"Sitzungsebene überprüfen");
   try{var layer=(SubLayer)Marshal.PtrToStructure(memory,typeof(SubLayer));if(layer.Key!=subLayer || layer.Weight!=layerWeight)throw new InvalidOperationException("WFP-Ebene wurde verändert: Gewicht="+layer.Weight+"; erwartet="+layerWeight);}
   finally{FwpmFreeMemory0(ref memory);}
   foreach(var wanted in expected){
    Check(FwpmFilterGetById0(engine,wanted.Id,out memory),"Sperr-/Freigabefilter überprüfen");
    try{
     var actual=(Filter)Marshal.PtrToStructure(memory,typeof(Filter));
     if(actual.Layer!=wanted.Layer || actual.SubLayer!=subLayer || actual.Action.Type!=wanted.Action ||  !ValidReturnedFlags(actual.Flags,wanted.Action==Block) || actual.Weight.Type!=4 || actual.Weight.Data.Pointer==IntPtr.Zero || unchecked((ulong)Marshal.ReadInt64(actual.Weight.Data.Pointer))!=wanted.Weight || actual.Count!=wanted.Specs.Count)throw new InvalidOperationException("WFP-Filter entspricht nicht mehr der Entscheidung: Layer="+actual.Layer+"/"+wanted.Layer+", SubLayer="+actual.SubLayer+"/"+subLayer+", Action="+actual.Action.Type+"/"+wanted.Action+", Flags="+actual.Flags+", WeightType="+actual.Weight.Type+", Weight="+(actual.Weight.Type==4&&actual.Weight.Data.Pointer!=IntPtr.Zero?unchecked((ulong)Marshal.ReadInt64(actual.Weight.Data.Pointer)).ToString():"?")+"/"+wanted.Weight+", Conditions="+actual.Count+"/"+wanted.Specs.Count+".");
     for(int i=0;i<wanted.Specs.Count;i++){
      var spec=wanted.Specs[i];var condition=new Condition();int found=0;
      for(int j=0;j<actual.Count;j++){var candidate=(Condition)Marshal.PtrToStructure(IntPtr.Add(actual.Conditions,j*Marshal.SizeOf(typeof(Condition))),typeof(Condition));if(candidate.Field==spec.Field){condition=candidate;found++;}}
      if(found!=1)throw new InvalidOperationException("Filterbedingung fehlt oder ist doppelt.");
      if(condition.Field!=spec.Field||condition.Match!=(spec.Field==FlagsField?6u:0u)||condition.Value.Type!=spec.Type)throw new InvalidOperationException("Filterbedingung wurde verändert.");
      if(spec.Type==12){if(!Same(ReadBlob(condition.Value.Data.Pointer),spec.Bytes))throw new InvalidOperationException("Programm-ID wurde verändert.");}
      else if(spec.Type==11){if(condition.Value.Data.Pointer==IntPtr.Zero)throw new InvalidOperationException("IPv6-Adresse fehlt.");var bytes=new byte[16];Marshal.Copy(condition.Value.Data.Pointer,bytes,0,16);if(!Same(bytes,spec.Bytes))throw new InvalidOperationException("IPv6-Adresse wurde verändert.");}
      else if((spec.Type==1?condition.Value.Data.Byte:spec.Type==2?condition.Value.Data.UShort:condition.Value.Data.UInt)!=spec.UInt)throw new InvalidOperationException("Filterwert wurde verändert.");
     }
    }finally{FwpmFreeMemory0(ref memory);}
   }
  }
  public void Dispose(){if(closed)return;if(engine!=null){engine.CloseChecked();engine.Dispose();}closed=true;}
 }
}


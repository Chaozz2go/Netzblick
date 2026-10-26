using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Netzblick;

// Isolated Windows-runner fixture only. Not built into or shipped with Netzblick.
// Own dynamic session: closing it removes only this fixture's layer/filters.
public sealed class WfpPeerFixture : IDisposable {
 IntPtr engine;readonly Guid subLayer=Guid.NewGuid();ushort assignedWeight;
 readonly List<ulong> filters=new List<ulong>();
 static readonly Guid Connect4=new Guid("c38d57d1-05a7-4c33-904f-7fbceee60e82");
 static readonly Guid AppField=new Guid("d78e1e87-8644-4ea5-9437-d809ecefc971");
 [DllImport("fwpuclnt.dll",CharSet=CharSet.Unicode)] static extern uint FwpmEngineOpen0(string server,uint auth,IntPtr identity,ref WfpGate.Session session,out IntPtr engine);
 [DllImport("fwpuclnt.dll")] static extern uint FwpmEngineClose0(IntPtr engine);
 [DllImport("fwpuclnt.dll")] static extern uint FwpmSubLayerAdd0(IntPtr engine,ref WfpGate.SubLayer layer,IntPtr security);
 [DllImport("fwpuclnt.dll")] static extern uint FwpmFilterAdd0(IntPtr engine,ref WfpGate.Filter filter,IntPtr security,out ulong id);
 [DllImport("fwpuclnt.dll")] static extern uint FwpmFilterDeleteById0(IntPtr engine,ulong id);
 [DllImport("fwpuclnt.dll")] static extern uint FwpmSubLayerGetByKey0(IntPtr engine,ref Guid key,out IntPtr layer);
 [DllImport("fwpuclnt.dll")] static extern uint FwpmFilterGetById0(IntPtr engine,ulong id,out IntPtr filter);
 [DllImport("fwpuclnt.dll",CharSet=CharSet.Unicode)] static extern uint FwpmGetAppIdFromFileName0(string name,out IntPtr blob);
 [DllImport("fwpuclnt.dll")] static extern void FwpmFreeMemory0(ref IntPtr memory);
 static void Check(uint code){if(code!=0)throw new System.ComponentModel.Win32Exception((int)code,"Peer-Fixture WFP");}
 public static WfpPeerFixture Start(){
  if(Environment.GetEnvironmentVariable("GITHUB_ACTIONS")!="true")throw new InvalidOperationException("Nur auf isolierten GitHub-Runnern ausführen.");
  var peer=new WfpPeerFixture();
  try{
   var session=new WfpGate.Session{Key=Guid.NewGuid(),Display=new WfpGate.Display{Name="Netzblick CI parallel peer"},Flags=1,Timeout=5000};
   Check(FwpmEngineOpen0(null,10,IntPtr.Zero,ref session,out peer.engine));
   var layer=new WfpGate.SubLayer{Key=peer.subLayer,Display=new WfpGate.Display{Name="Netzblick CI parallel peer"},Weight=65535};
   Check(FwpmSubLayerAdd0(peer.engine,ref layer,IntPtr.Zero));
   IntPtr memory;Guid key=peer.subLayer;Check(FwpmSubLayerGetByKey0(peer.engine,ref key,out memory));
   try{peer.assignedWeight=((WfpGate.SubLayer)Marshal.PtrToStructure(memory,typeof(WfpGate.SubLayer))).Weight;}finally{FwpmFreeMemory0(ref memory);}
   return peer;
  }catch{peer.Dispose();throw;}
 }
 public ulong AddPermit(string path,bool hard){return AddRule(path,hard,false);}
 public ulong AddBlock(string path){return AddRule(path,false,true);}
 ulong AddRule(string path,bool hard,bool block){
  IntPtr app=IntPtr.Zero,condition=IntPtr.Zero,weight=IntPtr.Zero;
  try{
   Check(FwpmGetAppIdFromFileName0(path,out app));
   condition=Marshal.AllocHGlobal(Marshal.SizeOf(typeof(WfpGate.Condition)));
   Marshal.StructureToPtr(new WfpGate.Condition{Field=AppField,Value=new WfpGate.Value{Type=12,Data=new WfpGate.ValueUnion{Pointer=app}}},condition,false);
   weight=Marshal.AllocHGlobal(8);Marshal.WriteInt64(weight,block?150:100);
   var filter=new WfpGate.Filter{Key=Guid.NewGuid(),Display=new WfpGate.Display{Name=block?"CI peer block":hard?"CI peer hard permit":"CI peer soft permit"},Flags=block||hard?8u:0u,Layer=Connect4,SubLayer=subLayer,Weight=new WfpGate.Value{Type=4,Data=new WfpGate.ValueUnion{Pointer=weight}},Count=1,Conditions=condition,Action=new WfpGate.Action{Type=block?0x1001u:0x1002u}};
   ulong id;Check(FwpmFilterAdd0(engine,ref filter,IntPtr.Zero,out id));filters.Add(id);return id;
  }finally{if(app!=IntPtr.Zero)FwpmFreeMemory0(ref app);if(condition!=IntPtr.Zero)Marshal.FreeHGlobal(condition);if(weight!=IntPtr.Zero)Marshal.FreeHGlobal(weight);}
 }
 public void Remove(ulong id){Check(FwpmFilterDeleteById0(engine,id));filters.Remove(id);}
 public void Verify(){
  IntPtr memory;Guid key=subLayer;Check(FwpmSubLayerGetByKey0(engine,ref key,out memory));
  try{var layer=(WfpGate.SubLayer)Marshal.PtrToStructure(memory,typeof(WfpGate.SubLayer));if(layer.Weight!=assignedWeight)throw new Exception("Peer layer changed");}finally{FwpmFreeMemory0(ref memory);}
  foreach(ulong id in filters){Check(FwpmFilterGetById0(engine,id,out memory));try{var filter=(WfpGate.Filter)Marshal.PtrToStructure(memory,typeof(WfpGate.Filter));if(filter.SubLayer!=subLayer||filter.Action.Type!=0x1002)throw new Exception("Peer filter changed");}finally{FwpmFreeMemory0(ref memory);}}
 }
 public void Dispose(){if(engine==IntPtr.Zero)return;Check(FwpmEngineClose0(engine));engine=IntPtr.Zero;}
}

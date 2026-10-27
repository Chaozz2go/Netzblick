using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Net;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Threading.Tasks;

namespace Netzblick {
 public sealed class SocketRow {
  public DateTime ProcessStartUtc {get;set;}
  public int Pid {get;set;} public string Program {get;set;} public string Path {get;set;}
  public string Protocol {get;set;} public string Local {get;set;} public string Remote {get;set;}
  public string State {get;set;} public string Address {get;set;} public int Port {get;set;}
  public string Key { get { return Pid+"|"+Protocol+"|"+Local+"|"+Remote+"|"+State; } }
 }
 public sealed class AdapterRow {
  public string Id {get;set;} public string Name {get;set;} public long Received {get;set;} public long Sent {get;set;}
 }
 public sealed class Snapshot {
  public List<SocketRow> Rows = new List<SocketRow>();
  public List<AdapterRow> Adapters = new List<AdapterRow>();
  public List<string> Errors = new List<string>();
  public DateTime Time = DateTime.UtcNow;
 }
 public static class Reader {
  [DllImport("iphlpapi.dll")] static extern uint GetExtendedTcpTable(IntPtr p, ref int size, bool order, int af, int cls, uint reserved);
  [DllImport("iphlpapi.dll")] static extern uint GetExtendedUdpTable(IntPtr p, ref int size, bool order, int af, int cls, uint reserved);
  static int U32(IntPtr p,int o) { return Marshal.ReadInt32(p,o); }
  static int Port(IntPtr p,int o) { return Marshal.ReadByte(p,o)*256+Marshal.ReadByte(p,o+1); }
  static byte[] Bytes(IntPtr p,int o,int n) { var b=new byte[n]; Marshal.Copy(IntPtr.Add(p,o),b,0,n); return b; }
  static string Address(IntPtr p,int o,bool v6,int scope) { return v6 ? new IPAddress(Bytes(p,o,16),unchecked((uint)scope)).ToString() : new IPAddress(Bytes(p,o,4)).ToString(); }
  static string Endpoint(string a,int port) { return (a.Contains(":") ? "["+a+"]" : a)+":"+port; }
  static string State(int n) {
   string[] s={"Unbekannt","Geschlossen","Lauscht","SYN gesendet","SYN empfangen","Verbunden","FIN warten 1","FIN warten 2","Close wait","Closing","Last ACK","Time wait","Gelöscht"};
   return n>=0 && n<s.Length?s[n]:"Status "+n;
  }
  static void Table(Snapshot s,bool tcp,bool v6,Dictionary<int,string[]> processes) {
   int size=0, af=v6?23:2, cls=tcp?5:1;
   uint code=tcp?GetExtendedTcpTable(IntPtr.Zero,ref size,false,af,cls,0):GetExtendedUdpTable(IntPtr.Zero,ref size,false,af,cls,0);
   if(code!=0 && code!=122) throw new System.ComponentModel.Win32Exception((int)code);
   if(size<4) return;
   IntPtr data=IntPtr.Zero;
   try {
    for(int attempt=0;attempt<5;attempt++) {
     if(data!=IntPtr.Zero) { Marshal.FreeHGlobal(data); data=IntPtr.Zero; }
     data=Marshal.AllocHGlobal(size);
     code=tcp?GetExtendedTcpTable(data,ref size,false,af,cls,0):GetExtendedUdpTable(data,ref size,false,af,cls,0);
     if(code!=122) break;
    }
    if(code!=0) throw new System.ComponentModel.Win32Exception((int)code);
    int count=U32(data,0), stride=tcp?(v6?56:24):(v6?28:12);
    if(count<0 || (long)count*stride+4>size) throw new InvalidOperationException("Ungültige Socket-Tabelle");
    for(int i=0;i<count;i++) {
     IntPtr p=IntPtr.Add(data,4+i*stride);
     int pid=U32(p,tcp?(v6?52:20):(v6?24:8));
     string[] proc;
     if(!processes.TryGetValue(pid,out proc)) {
      proc=new string[]{pid==0?"System / beendet":"PID "+pid,"","0"};
      try { using(var pr=Process.GetProcessById(pid)) { proc[0]=pr.ProcessName; try{proc[2]=pr.StartTime.ToUniversalTime().Ticks.ToString();}catch{} try{proc[1]=pr.MainModule.FileName;}catch{} } } catch{}
      processes[pid]=proc;
     }
     int lo=tcp && !v6?4:0, lp=v6?20:(tcp?8:4);
     string local=Address(p,lo,v6,v6?U32(p,16):0), remote="";
     int port=0, state=tcp?U32(p,v6?48:0):0;
     if(tcp && state!=2) { remote=Address(p,v6?24:12,v6,v6?U32(p,40):0); port=Port(p,v6?44:16); }
     s.Rows.Add(new SocketRow{ProcessStartUtc=new DateTime(Int64.Parse(proc[2]),DateTimeKind.Utc),Pid=pid,Program=proc[0],Path=proc[1],Protocol=(tcp?"TCP":"UDP")+(v6?"v6":"v4"),Local=Endpoint(local,Port(p,lp)),Address=remote,Port=port,Remote=remote.Length>0?Endpoint(remote,port):(tcp?"—":"Gegenstelle nicht erfasst"),State=tcp?State(state):"UDP-Endpunkt"});
    }
   } finally { if(data!=IntPtr.Zero) Marshal.FreeHGlobal(data); }
  }
  public static Snapshot Collect() {
   var s=new Snapshot(); var procs=new Dictionary<int,string[]>();
   foreach(bool tcp in new bool[]{true,false}) foreach(bool v6 in new bool[]{false,true}) {
    try{Table(s,tcp,v6,procs);}catch(Exception e){s.Errors.Add((tcp?"TCP":"UDP")+(v6?"v6":"v4")+": "+e.Message);}
   }
   foreach(var n in NetworkInterface.GetAllNetworkInterfaces()) {
    if(n.OperationalStatus!=OperationalStatus.Up || n.NetworkInterfaceType==NetworkInterfaceType.Loopback) continue;
    try { var st=n.GetIPStatistics(); s.Adapters.Add(new AdapterRow{Id=n.Id,Name=n.Name,Received=st.BytesReceived,Sent=st.BytesSent}); }
    catch(Exception e){s.Errors.Add(n.Name+": "+e.Message);}
   }
   return s;
  }
  public static Task<Snapshot> Start() { return Task.Run<Snapshot>(()=>Collect()); }
 }
}


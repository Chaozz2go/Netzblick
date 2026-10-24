using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Threading.Tasks;
using Microsoft.Diagnostics.Tracing;
using Microsoft.Diagnostics.Tracing.Parsers;
using Microsoft.Diagnostics.Tracing.Session;

namespace Netzblick.Capture {
 public sealed class NetworkCapture : IDisposable {
  sealed class Cached {public ProcessIdentity Identity;public DateTime Checked;}
  readonly TrafficStore store=new TrafficStore();readonly Dictionary<int,Cached> identities=new Dictionary<int,Cached>();
  readonly object gate=new object();TraceEventSession session;Task reader;bool disposed;string error="";
  public string Error {get{lock(gate)return error;}}
  public bool Running {get{return !disposed && reader!=null && !reader.IsCompleted && Error.Length==0;}}
  public long Lost {get{try{return session==null?0:session.EventsLost;}catch{return -1;}}}
  public long Uncounted {get{return store.Invalid;}}
  public static NetworkCapture Start(){
   var c=new NetworkCapture();
   try{
    CleanupOrphans();
    long ticks;using(var p=Process.GetCurrentProcess())ticks=p.StartTime.ToUniversalTime().Ticks;
    string name="Netzblick.Network.v1."+Process.GetCurrentProcess().Id+"."+ticks;
    c.session=new TraceEventSession(name,TraceEventSessionOptions.Create|TraceEventSessionOptions.NoRestartOnCreate);
    c.session.StopOnDispose=true;c.session.BufferSizeMB=32;
    c.session.EnableKernelProvider(KernelTraceEventParser.Keywords.NetworkTCPIP|KernelTraceEventParser.Keywords.Process);
    var kernel=c.session.Source.Kernel;
    kernel.ProcessStart+=e=>c.Invalidate(e.ProcessID);kernel.ProcessStop+=e=>c.Invalidate(e.ProcessID);
    kernel.TcpIpSend+=e=>c.Add(e.ProcessID,e.TimeStamp,true,e.size,e.daddr.ToString(),e.dport,"TCPv4");
    kernel.TcpIpRecv+=e=>c.Add(e.ProcessID,e.TimeStamp,false,e.size,e.saddr.ToString(),e.sport,"TCPv4");
    kernel.TcpIpSendIPV6+=e=>c.Add(e.ProcessID,e.TimeStamp,true,e.size,e.daddr.ToString(),e.dport,"TCPv6");
    kernel.TcpIpRecvIPV6+=e=>c.Add(e.ProcessID,e.TimeStamp,false,e.size,e.saddr.ToString(),e.sport,"TCPv6");
    kernel.UdpIpSend+=e=>c.Add(e.ProcessID,e.TimeStamp,true,e.size,e.daddr.ToString(),e.dport,"UDPv4");
    kernel.UdpIpRecv+=e=>c.Add(e.ProcessID,e.TimeStamp,false,e.size,e.saddr.ToString(),e.sport,"UDPv4");
    kernel.UdpIpSendIPV6+=e=>c.Add(e.ProcessID,e.TimeStamp,true,e.size,e.daddr.ToString(),e.dport,"UDPv6");
    kernel.UdpIpRecvIPV6+=e=>c.Add(e.ProcessID,e.TimeStamp,false,e.size,e.saddr.ToString(),e.sport,"UDPv6");
    c.reader=Task.Run(()=>{try{c.session.Source.Process();}catch(Exception e){lock(c.gate)c.error=e.GetBaseException().Message;}});
    return c;
   }catch{c.Dispose();throw;}
  }
  static void CleanupOrphans(){
   foreach(string name in TraceEventSession.GetActiveSessionNames()){
    if(!name.StartsWith("Netzblick.Network.v1.",StringComparison.Ordinal))continue;
    string[] p=name.Split('.');int pid;long ticks;
    if(p.Length!=5 || !Int32.TryParse(p[3],out pid) || !Int64.TryParse(p[4],out ticks))continue;
    bool dead=false;
    try{using(var process=Process.GetProcessById(pid))dead=process.StartTime.ToUniversalTime().Ticks!=ticks;}
    catch(ArgumentException){dead=true;}catch{continue;}
    if(dead)using(var old=new TraceEventSession(name,TraceEventSessionOptions.Attach)){old.StopOnDispose=true;}
   }
  }
  void Invalidate(int pid){lock(identities)identities.Remove(pid);}
  ProcessIdentity Resolve(int pid,DateTime time){
   lock(identities){
    Cached cached;
    if(identities.TryGetValue(pid,out cached) && (DateTime.UtcNow-cached.Checked).TotalSeconds<1)return cached.Identity;
    var identity=new ProcessIdentity{Pid=pid,Path="",Name="PID "+pid,StartUtc=DateTime.MinValue};
    try{using(var p=Process.GetProcessById(pid)){identity.StartUtc=p.StartTime.ToUniversalTime();identity.Name=p.ProcessName;identity.Path=p.MainModule.FileName;}}
    catch{identity.Path="";}
    identities[pid]=new Cached{Identity=identity,Checked=DateTime.UtcNow};return identity;
   }
  }
  void Add(int pid,DateTime time,bool send,int size,string address,int port,string protocol){
   try{DateTime utc=time.ToUniversalTime();store.Add(Resolve(pid,utc),utc,send,size,address,port,protocol);}
   catch(Exception e){lock(gate)error="Ereignis konnte nicht gezählt werden: "+e.Message;}
  }
  public List<TrafficRow> Snapshot(){return store.Snapshot();}
  public List<PeerRow> Peers(){return store.Peers();}
  public void Dispose(){if(disposed)return;disposed=true;if(session!=null){try{session.Source.StopProcessing();}finally{session.Dispose();}}if(reader!=null)try{reader.Wait(1000);}catch{} }
 }
}

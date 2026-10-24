using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace Netzblick {
 public sealed class ProbeCommand {
  public string Mode {get;private set;} public string Target {get;private set;} public int Family {get;private set;}
  public static ProbeCommand Parse(string command) {
   if(String.IsNullOrWhiteSpace(command))throw new ArgumentException("Befehl eingeben: ping example.org oder tracert example.org");
   string[] parts=command.Trim().Split((char[])null,StringSplitOptions.RemoveEmptyEntries);
   string mode=parts[0].ToLowerInvariant();
   if(mode!="ping" && mode!="tracert" && mode!="traceroute")throw new ArgumentException("Unterstützt: ping und tracert / traceroute. Dies ist keine allgemeine Shell.");
   int index=1,family=0;
   if(parts.Length>index && (parts[index]=="-4" || parts[index]=="-6")){family=parts[index]=="-4"?4:6;index++;}
   if(parts.Length!=index+1)throw new ArgumentException("Format: ping [-4|-6] Ziel oder tracert [-4|-6] Ziel. Keine weiteren Optionen.");
   string target=parts[index];IPAddress ip;
   if(IPAddress.TryParse(target,out ip)) {
    if(ip.IsIPv4MappedToIPv6)ip=ip.MapToIPv4();
    target=ip.ToString();
    if(family==4 && ip.AddressFamily!=AddressFamily.InterNetwork || family==6 && ip.AddressFamily!=AddressFamily.InterNetworkV6)throw new ArgumentException("IP-Adresse passt nicht zu -4 / -6.");
    byte[] b=ip.GetAddressBytes();
    if(ip.Equals(IPAddress.Any) || ip.Equals(IPAddress.IPv6Any) || (b.Length==4 && b[0]>=224) || (b.Length==16 && b[0]==255))throw new ArgumentException("Bitte eine einzelne Unicast-Zieladresse verwenden.");
   } else {
    if(target.Length>253 || target.IndexOfAny(new char[]{'/','\\',':','&',';','|','<','>','\"','\'','`','$','(',')'})>=0)throw new ArgumentException("Als Ziel nur einen Hostnamen oder eine IP-Adresse eingeben, keine URL und keinen Shell-Befehl.");
    try{target=new IdnMapping().GetAscii(target);}catch(ArgumentException){throw new ArgumentException("Ungültiger Hostname.");}
    if(Uri.CheckHostName(target)!=UriHostNameType.Dns)throw new ArgumentException("Ungültiger Hostname.");
   }
   return new ProbeCommand{Mode=mode=="ping"?"ping":"tracert",Target=target,Family=family};
  }
 }
 public sealed class ProbeEvent {
  public string Type {get;set;} public string Text {get;set;} public int Number {get;set;} public int Attempt {get;set;}
  public string Address {get;set;} public string Status {get;set;} public double Milliseconds {get;set;} public bool HasLatency {get;set;}
  public string Latency {get {return HasLatency?Milliseconds.ToString("0.0",CultureInfo.CurrentCulture)+" ms":"—";} }
 }
 public sealed class ProbeSession : IDisposable {
  readonly ConcurrentQueue<ProbeEvent> queue=new ConcurrentQueue<ProbeEvent>();
  readonly CancellationTokenSource cancel=new CancellationTokenSource();
  Task worker;
  public ProbeCommand Command {get;private set;}
  public bool IsCompleted {get{return worker!=null && worker.IsCompleted;} }
  public static ProbeSession Start(string command) {
   var session=new ProbeSession{Command=ProbeCommand.Parse(command)};
   session.worker=Task.Run(()=>session.Run());return session;
  }
  public void Cancel(){cancel.Cancel();}
  public List<ProbeEvent> Drain(){var list=new List<ProbeEvent>();ProbeEvent e;while(queue.TryDequeue(out e))list.Add(e);return list;}
  void Message(string type,string text){queue.Enqueue(new ProbeEvent{Type=type,Text=text,Address="",Status="",Milliseconds=0});}
  IPAddress Resolve() {
   IPAddress literal;
   if(IPAddress.TryParse(Command.Target,out literal))return literal;
   Message("info","DNS-Auflösung: "+Command.Target);
   var task=Dns.GetHostAddressesAsync(Command.Target);
   // DNS itself may finish later; the visible operation can still be cancelled promptly.
   task.ContinueWith(t=>{var ignored=t.Exception;},TaskContinuationOptions.OnlyOnFaulted);
   var clock=Stopwatch.StartNew();
   while(!task.IsCompleted){cancel.Token.ThrowIfCancellationRequested();if(clock.ElapsedMilliseconds>=8000)throw new TimeoutException("DNS-Zeitlimit erreicht.");cancel.Token.WaitHandle.WaitOne(100);}
   var addresses=task.GetAwaiter().GetResult();
   if(Command.Family!=6)foreach(var a in addresses)if(a.AddressFamily==AddressFamily.InterNetwork)return a;
   if(Command.Family!=4)foreach(var a in addresses)if(a.AddressFamily==AddressFamily.InterNetworkV6)return a;
   throw new InvalidOperationException("Keine passende IPv4-/IPv6-Adresse gefunden.");
  }
  ProbeEvent Probe(IPAddress target,int ttl,int number,int attempt) {
   cancel.Token.ThrowIfCancellationRequested();
   using(var ping=new Ping()){
    var clock=Stopwatch.StartNew();
    var reply=ping.Send(target,1200,Encoding.ASCII.GetBytes("Netzblick network diagnostic"),new PingOptions(ttl,false));
    clock.Stop();
    bool timed=reply.Status==IPStatus.Success || reply.Status==IPStatus.TtlExpired || reply.Status==IPStatus.TimeExceeded;
    // PingReply.RoundtripTime is defined for successful echo replies only.
    double ms=reply.Status==IPStatus.Success?reply.RoundtripTime:clock.Elapsed.TotalMilliseconds;
    string address=reply.Address==null || reply.Address.Equals(IPAddress.Any) || reply.Address.Equals(IPAddress.IPv6Any)?"":reply.Address.ToString();
    var e=new ProbeEvent{Type="probe",Number=number,Attempt=attempt,Address=address,Status=reply.Status.ToString(),Milliseconds=ms,HasLatency=timed};
    e.Text=(Command.Mode=="ping"?"Ping ":"Hop ")+number+" / "+attempt+"   "+(address.Length>0?address:"*")+"   "+e.Latency+"   "+e.Status;
    queue.Enqueue(e);return e;
   }
  }
  void Run() {
   try {
    IPAddress target=Resolve();cancel.Token.ThrowIfCancellationRequested();
    queue.Enqueue(new ProbeEvent{Type="target",Address=target.ToString(),Text=Command.Mode+" "+Command.Target+" ["+target+"] · ICMP · 1200 ms Zeitlimit",Status="Resolved"});
    if(Command.Mode=="ping"){
     int received=0;double total=0,min=Double.MaxValue,max=0;
     for(int i=1;i<=10;i++){
      var e=Probe(target,64,i,1);
      if(e.Status=="Success"){received++;total+=e.Milliseconds;min=Math.Min(min,e.Milliseconds);max=Math.Max(max,e.Milliseconds);}
      if(i<10 && cancel.Token.WaitHandle.WaitOne(1000))cancel.Token.ThrowIfCancellationRequested();
     }
     Message("summary","Fertig · 10 gesendet · "+received+" Echo-Antworten · "+(10-received)+" ohne erfolgreiche Echo-Antwort"+(received>0?" · min/Ø/max "+min.ToString("0.0")+"/"+(total/received).ToString("0.0")+"/"+max.ToString("0.0")+" ms":""));
    }else{
     bool reached=false,terminal=false;
     for(int hop=1;hop<=30 && !reached && !terminal;hop++){
      for(int attempt=1;attempt<=3;attempt++){
       var e=Probe(target,hop,hop,attempt);
       if(e.Status=="Success" && e.Address==target.ToString()){reached=true;break;}
       if(e.Status!="Success" && e.Status!="TtlExpired" && e.Status!="TimeExceeded" && e.Status!="TimedOut"){terminal=true;break;}
      }
     }
     Message("summary",reached?"Ziel erreicht. Die Karte zeigt geschätzte Länder antwortender Stationen, keinen exakten Leitungsweg.":terminal?"Route mit ICMP-Fehlermeldung beendet. Details stehen in der Ausgabe.":"Nach 30 Hops beendet · Ziel nicht bestätigt. Fehlende ICMP-Antworten bedeuten nicht automatisch eine unterbrochene Verbindung.");
    }
   }catch(OperationCanceledException){Message("summary","Abgebrochen.");}
   catch(Exception e){Message("error","Fehler: "+e.GetBaseException().Message);}
  }
  public void Dispose(){if(!IsCompleted){Cancel();return;}cancel.Dispose();}
 }
}

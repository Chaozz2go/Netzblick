using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Sockets;
using System.Threading.Tasks;

namespace Netzblick {
 public static class EndpointInfo {
  public static string Scope(string value) {
   IPAddress ip;if(!IPAddress.TryParse(value,out ip))return "Keine Gegenstelle";
   if(ip.IsIPv4MappedToIPv6)ip=ip.MapToIPv4();
   byte[] b=ip.GetAddressBytes();
   if(IPAddress.IsLoopback(ip))return "Dieser Computer";
   if(ip.AddressFamily==AddressFamily.InterNetwork) {
    if(b[0]==0)return "Keine Gegenstelle";
    if(b[0]>=224)return "Multicast / Broadcast / reserviert";
    if(b[0]==10 || b[0]==172 && b[1]>=16 && b[1]<=31 || b[0]==192 && b[1]==168)return "Privates Netz";
    if(b[0]==169 && b[1]==254)return "Lokales Netz (Link-Local)";
    if(b[0]==100 && b[1]>=64 && b[1]<=127)return "Geteiltes Netz (Provider / VPN)";
   } else {
    if(ip.Equals(IPAddress.IPv6Any))return "Keine Gegenstelle";
    if(ip.IsIPv6Multicast)return "Multicast";
    if(ip.IsIPv6LinkLocal)return "Lokales Netz (Link-Local)";
    if((b[0]&254)==252)return "Privates Netz";
   }
   return "Öffentliche / sonstige Adresse";
  }
  public static bool CanResolve(string value) {
   string scope=Scope(value);
   return scope=="Öffentliche / sonstige Adresse" || scope=="Privates Netz" || scope=="Lokales Netz (Link-Local)" || scope=="Geteiltes Netz (Provider / VPN)";
  }
  public static string Service(string protocol,int port) {
   string p=(protocol??"").ToUpperInvariant();
   if(p.StartsWith("ICMP"))return "ICMP · Netzwerkdiagnose möglich";
   bool tcp=p.StartsWith("TCP"),udp=p.StartsWith("UDP");
   if(!tcp && !udp)return "Zweck nicht ermittelt";
   if(port==443)return udp?"UDP/443 · QUIC / HTTPS möglich":"TCP/443 · HTTPS / TLS möglich";
   if(port==80 && tcp)return "TCP/80 · HTTP möglich";
   if(port==53)return "Port 53 · DNS möglich";
   if(port==853 && tcp)return "TCP/853 · DNS über TLS möglich";
   if(port==123 && udp)return "UDP/123 · Zeitsynchronisierung möglich";
   if(port==5353 && udp)return "UDP/5353 · lokale Dienstsuche (mDNS) möglich";
   if(port==1900 && udp)return "UDP/1900 · Gerätesuche (SSDP) möglich";
   if(port==389 && tcp)return "TCP/389 · LDAP möglich";
   if(port==636 && tcp)return "TCP/636 · LDAPS möglich";
   if(port==445 && tcp)return "TCP/445 · Dateifreigabe (SMB) möglich";
   if(port<1 || port>65535)return "Zweck nicht ermittelt";
   return p+"/"+port+" · Zweck nicht ermittelt";
  }
 }
 // Background system resolver; no queries until opt-in. A slow OS call keeps
 // its concurrency slot even after the display reports a timeout.
 public sealed class EndpointNames : IDisposable {
  sealed class Entry {public DateTime Started,Expires;public string Text;public bool Pending;}
  readonly object gate=new object();readonly Dictionary<string,Entry> cache=new Dictionary<string,Entry>();
  readonly Func<string,string> lookup;bool enabled,disposed;int active,generation;
  public EndpointNames():this(address=>Dns.GetHostEntry(IPAddress.Parse(address)).HostName){}
  public EndpointNames(Func<string,string> resolver){if(resolver==null)throw new ArgumentNullException("resolver");lookup=resolver;}
  public void SetEnabled(bool value){lock(gate){if(disposed || enabled==value)return;enabled=value;generation++;cache.Clear();}}
  public string Get(string address) {
   if(!EndpointInfo.CanResolve(address))return EndpointInfo.Scope(address);
   string key=IPAddress.Parse(address).ToString();
   lock(gate) {
    if(!enabled || disposed)return "DNS ausgeschaltet";
    Entry entry;DateTime now=DateTime.UtcNow;
    if(cache.TryGetValue(key,out entry)) {
     if(entry.Pending)return (now-entry.Started).TotalSeconds>5?"DNS dauert länger · Name offen":"DNS wird abgefragt …";
     if(entry.Expires>now)return entry.Text;
     cache.Remove(key);
    }
    if(active>=4)return "DNS wartet auf freien Platz …";
    if(cache.Count>=256) {
     string oldest=null;DateTime time=DateTime.MaxValue;
     foreach(var item in cache)if(!item.Value.Pending && item.Value.Started<time){oldest=item.Key;time=item.Value.Started;}
     if(oldest!=null)cache.Remove(oldest);else return "DNS-Limit erreicht";
    }
    entry=new Entry{Started=now,Pending=true};cache[key]=entry;active++;int requestGeneration=generation;
    Task.Run(()=> {
     string text;
     try {
      string host=(lookup(key)??"").Trim().TrimEnd('.');IPAddress numeric;
      if(host.Length==0 || host.Length>253 || IPAddress.TryParse(host,out numeric))text="Kein DNS-Name gefunden";
      else {
       bool valid=true;foreach(char c in host)if(!(Char.IsLetterOrDigit(c) || c=='.' || c=='-' || c=='_')){valid=false;break;}
       text=valid?host+" (Reverse-DNS)":"DNS-Name nicht darstellbar";
      }
     } catch(SocketException){text="Kein DNS-Name / DNS nicht erreichbar";}
       catch(Exception){text="DNS-Abfrage fehlgeschlagen";}
     lock(gate){active--;if(requestGeneration!=generation || disposed)return;entry.Text=text;entry.Pending=false;entry.Expires=DateTime.UtcNow.AddMinutes(10);}
    });
    return "DNS wird abgefragt …";
   }
  }
  public void Dispose(){lock(gate){disposed=true;enabled=false;generation++;cache.Clear();}}
 }
}


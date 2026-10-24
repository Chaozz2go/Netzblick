using System;
using System.Collections.Generic;
using System.Net;

namespace Netzblick {
 public sealed class AddressRange {
  public byte[] First;public byte[] Last;
  public static int Compare(byte[] a,byte[] b){for(int i=0;i<a.Length;i++){int c=a[i]-b[i];if(c!=0)return c;}return 0;}
  public static byte[] Step(byte[] bytes,int delta){var r=(byte[])bytes.Clone();for(int i=r.Length-1;i>=0;i--){int n=r[i]+delta;if(n<0){r[i]=255;continue;}if(n>255){r[i]=0;continue;}r[i]=(byte)n;return r;}return null;}
  public static AddressRange Parse(string text){
   text=text.Trim();int dash=text.IndexOf('-'),slash=text.IndexOf('/');
   if(dash>=0){var a=IPAddress.Parse(text.Substring(0,dash)).GetAddressBytes();var b=IPAddress.Parse(text.Substring(dash+1)).GetAddressBytes();if(a.Length!=b.Length || Compare(a,b)>0)throw new FormatException("Ungültiger IP-Bereich");return new AddressRange{First=a,Last=b};}
   var bytes=IPAddress.Parse(slash>=0?text.Substring(0,slash):text).GetAddressBytes();int prefix=slash>=0?Int32.Parse(text.Substring(slash+1)):bytes.Length*8;
   if(prefix<0 || prefix>bytes.Length*8)throw new FormatException("Ungültiges Präfix");
   var first=(byte[])bytes.Clone();var last=(byte[])bytes.Clone();
   for(int i=0;i<bytes.Length;i++){int bits=Math.Max(0,Math.Min(8,prefix-i*8));int mask=bits==0?0:(255<<(8-bits))&255;first[i]=(byte)(bytes[i]&mask);last[i]=(byte)(first[i]|(255^mask));}
   return new AddressRange{First=first,Last=last};
  }
  public bool Contains(string text){var b=IPAddress.Parse(text).GetAddressBytes();return b.Length==First.Length && Compare(b,First)>=0 && Compare(b,Last)<=0;}
  public override string ToString(){return new IPAddress(First)+"-"+new IPAddress(Last);}
 }
 public static class NetworkPolicy {
  public static readonly string[] PrivateScopes={"10.0.0.0/8","100.64.0.0/10","127.0.0.0/8","169.254.0.0/16","172.16.0.0/12","192.168.0.0/16","224.0.0.0/24","239.0.0.0/8","255.255.255.255/32","::1/128","fc00::/7","fe80::/10","ff01::/16","ff02::/16"};
  public static List<AddressRange> Merge(List<AddressRange> ranges){
   ranges.Sort((a,b)=>a.First.Length!=b.First.Length?a.First.Length.CompareTo(b.First.Length):AddressRange.Compare(a.First,b.First));
   var result=new List<AddressRange>();foreach(var r in ranges){
    AddressRange previous=result.Count==0?null:result[result.Count-1];
    if(previous!=null && previous.First.Length==r.First.Length){var next=AddressRange.Step(previous.Last,1);if(AddressRange.Compare(r.First,previous.Last)<=0 || next!=null && AddressRange.Compare(r.First,next)<=0){if(AddressRange.Compare(r.Last,previous.Last)>0)previous.Last=r.Last;continue;}}
    result.Add(new AddressRange{First=(byte[])r.First.Clone(),Last=(byte[])r.Last.Clone()});
   }return result;
  }
  public static string CanonicalScope(string text){if(text=="*")return "*";var ranges=new List<AddressRange>();foreach(string part in text.Split(','))ranges.Add(AddressRange.Parse(part));var merged=Merge(ranges);return String.Join(",",merged.ConvertAll(r=>r.ToString()).ToArray());}
  public static List<AddressRange> PublicRanges(){
   var allowed=new List<AddressRange>();foreach(string p in PrivateScopes)allowed.Add(AddressRange.Parse(p));allowed=Merge(allowed);
   var blocked=new List<AddressRange>();foreach(int width in new int[]{4,16}){
    byte[] cursor=new byte[width];foreach(var r in allowed){if(r.First.Length!=width)continue;if(AddressRange.Compare(cursor,r.First)<0)blocked.Add(new AddressRange{First=cursor,Last=AddressRange.Step(r.First,-1)});cursor=AddressRange.Step(r.Last,1);if(cursor==null)break;}
    if(cursor!=null){var end=new byte[width];for(int i=0;i<width;i++)end[i]=255;blocked.Add(new AddressRange{First=cursor,Last=end});}
   }return blocked;
  }
  public static string PrivateOnlyBlockScope(){return String.Join(",",PublicRanges().ConvertAll(r=>r.ToString()).ToArray());}
  public static string ClassifyScope(string text){try{string c=CanonicalScope(text);return c=="*"?"Blocked":c==CanonicalScope(PrivateOnlyBlockScope())?"Private":"Modified";}catch{return "Modified";}}
 }
 public static class RuntimeDependencies {
  static string directory;
  public static void Install(string path){directory=System.IO.Path.GetFullPath(path);AppDomain.CurrentDomain.AssemblyResolve+=Resolve;}
  static System.Reflection.Assembly Resolve(object sender,ResolveEventArgs e){string name=new System.Reflection.AssemblyName(e.Name).Name;string path=System.IO.Path.Combine(directory,name+".dll");return System.IO.File.Exists(path)?System.Reflection.Assembly.LoadFrom(path):null;}
 }
}

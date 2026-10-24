using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;

namespace Netzblick {
 public sealed class Country {
  public string Code {get;set;} public string Name {get;set;}
  public double Latitude {get;set;} public double Longitude {get;set;}
  public string Display {get {return Name+" ("+Code+")";} }
 }
 public sealed class Location {
  public string Address {get;set;} public string Code {get;set;} public string Country {get;set;}
  public string Kind {get;set;} public bool CanPlot {get;set;}
  public double Latitude {get;set;} public double Longitude {get;set;}
 }
 public sealed class GeoDatabase {
  readonly byte[] data; readonly int count4,count6,offset6;
  readonly Dictionary<string,Country> countries=new Dictionary<string,Country>(StringComparer.OrdinalIgnoreCase);
  public string Version {get;private set;}
  public List<Country> Countries {get {var c=new List<Country>(countries.Values);c.Sort((a,b)=>StringComparer.CurrentCulture.Compare(a.Name,b.Name));return c;} }
  public GeoDatabase(string directory) {
   Version=File.ReadAllText(Path.Combine(directory,"geo-version.txt"),Encoding.UTF8).Trim();
   foreach(string line in File.ReadAllLines(Path.Combine(directory,"countries.tsv"),Encoding.UTF8)) {
    if(String.IsNullOrWhiteSpace(line) || line.StartsWith("#")) continue;
    var p=line.Split('\t'); if(p.Length!=4) throw new InvalidDataException("Ungültiger Ländereintrag");
    string name=p[3]; try {name=new RegionInfo(p[0]).DisplayName;} catch(ArgumentException){}
    double lat=Double.Parse(p[1],CultureInfo.InvariantCulture),lon=Double.Parse(p[2],CultureInfo.InvariantCulture);
    if(lat < -90 || lat > 90 || lon < -180 || lon > 180)throw new InvalidDataException("Ungültige Kartenkoordinate");
    countries[p[0]]=new Country{Code=p[0],Name=name,Latitude=lat,Longitude=lon};
   }
   data=File.ReadAllBytes(Path.Combine(directory,"geo-country.bin"));
   if(data.Length<12 || Encoding.ASCII.GetString(data,0,4)!="NBG1")throw new InvalidDataException("Ungültige Geo-Datenbank");
   count4=BitConverter.ToInt32(data,4);count6=BitConverter.ToInt32(data,8);
   long end=12L+count4*10L+count6*34L;
   if(count4<0 || count6<0 || end!=data.Length)throw new InvalidDataException("Unvollständige Geo-Datenbank");
   offset6=12+count4*10;
  }
  static bool Prefix(byte[] b, params byte[] prefix) {
   if(b.Length<prefix.Length)return false;
   for(int i=0;i<prefix.Length;i++)if(b[i]!=prefix[i])return false;return true;
  }
  public static string Special(IPAddress address) {
   if(address.IsIPv4MappedToIPv6)address=address.MapToIPv4();
   var b=address.GetAddressBytes();
   if(IPAddress.IsLoopback(address))return "Lokal / Loopback";
   if(b.Length==4) {
    if(b[0]==10 || (b[0]==172 && b[1]>=16 && b[1]<=31) || Prefix(b,192,168))return "Privates Netzwerk";
    if(Prefix(b,169,254))return "Linklokales Netzwerk";
    if(b[0]==100 && b[1]>=64 && b[1]<=127)return "Provider-intern / CGNAT";
    if(b[0]==0 || b[0]>=224 || Prefix(b,192,0,0) || Prefix(b,192,0,2) || Prefix(b,198,51,100) || Prefix(b,203,0,113) || (b[0]==198 && (b[1]==18 || b[1]==19)))return "Spezialadresse / nicht verortet";
   } else {
    if((b[0]&0xfe)==0xfc)return "Privates Netzwerk (IPv6)";
    if(b[0]==0xfe && (b[1]&0xc0)==0x80)return "Linklokales Netzwerk (IPv6)";
    if((b[0]&0xe0)!=0x20 || Prefix(b,0x20,0x01,0x0d,0xb8) || Prefix(b,0x20,0x01,0x00,0x02))return "Spezialadresse / nicht verortet";
   }
   return null;
  }
  int Compare(byte[] target,int offset,int width) {
   for(int i=0;i<width;i++){int d=target[i]-data[offset+i];if(d!=0)return d;}return 0;
  }
  string Find(byte[] bytes) {
   int width=bytes.Length, stride=width*2+2, start=width==4?12:offset6;
   int low=0, high=(width==4?count4:count6)-1;
   while(low<=high){int mid=low+(high-low)/2,off=start+mid*stride;
    if(Compare(bytes,off,width)<0)high=mid-1;
    else if(Compare(bytes,off+width,width)>0)low=mid+1;
    else return Encoding.ASCII.GetString(data,off+width*2,2);
   }
   return null;
  }
  public Location Lookup(string text) {
   IPAddress address;
   if(!IPAddress.TryParse(text,out address))return new Location{Address=text,Code="",Country="Unbekannt",Kind="Keine gültige IP-Adresse"};
   if(address.IsIPv4MappedToIPv6)address=address.MapToIPv4();
   var result=new Location{Address=address.ToString(),Code="",Country="Unbekannt",Kind="Nicht in Geo-Datenbank"};
   string special=Special(address);
   if(special!=null){result.Country=special;result.Kind=special;return result;}
   string code=Find(address.GetAddressBytes());
   if(String.IsNullOrEmpty(code) || code=="ZZ")return result;
   result.Code=code; result.Kind="Land geschätzt · Länderpunkt, kein Serverstandort";
   Country c;
   if(countries.TryGetValue(code,out c)){
    result.Country=c.Name;result.Latitude=c.Latitude;result.Longitude=c.Longitude;result.CanPlot=true;
   }else{
    try{result.Country=new RegionInfo(code).DisplayName;}catch(ArgumentException){result.Country=code;}
    result.Kind="Land geschätzt · keine Kartenkoordinate";
   }
   return result;
  }
 }
}

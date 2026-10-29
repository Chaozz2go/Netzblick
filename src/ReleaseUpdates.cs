using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace Netzblick {
 public sealed class UpdateRelease {
  public string Tag {get;set;} public string Name {get;set;} public string Url {get;set;} public string Notes {get;set;}
  public bool Draft {get;set;} public bool Prerelease {get;set;}
  public string Version {get;set;} public int Build {get;set;}
 }
 public sealed class UpdateResult {
  public string Message {get;set;} public UpdateRelease Release {get;set;} public bool Available {get;set;}
 }
 public static class ReleaseUpdates {
  public const string CurrentVersion="0.18.0";
  public const string RepositoryUrl="https://github.com/Chaozz2go/Netzblick";
  public static int CurrentBuild {get{
   var entry=Assembly.GetEntryAssembly();if(entry==null)return 0;
   var a=entry.GetCustomAttributes(typeof(AssemblyInformationalVersionAttribute),false).Cast<AssemblyInformationalVersionAttribute>().FirstOrDefault();
   int n;return a!=null&&Int32.TryParse(a.InformationalVersion.Split('.').Last(),out n)?n:0;
  }}
  public static bool SafeReleaseUrl(string text){
   Uri u;return Uri.TryCreate(text,UriKind.Absolute,out u)&&u.Scheme=="https"&&u.Host=="github.com"&&u.IsDefaultPort&&String.IsNullOrEmpty(u.UserInfo)&&u.AbsolutePath.StartsWith("/Chaozz2go/Netzblick/releases/",StringComparison.Ordinal)&&String.IsNullOrEmpty(u.Query)&&String.IsNullOrEmpty(u.Fragment);
  }
  public static UpdateRelease Select(string json,string current,int currentBuild,bool includeDrafts,bool includePrereleases){
   var serializer=new JavaScriptSerializer{MaxJsonLength=2097152,RecursionLimit=24};
   var items=serializer.Deserialize<List<Dictionary<string,object>>>(json);
   if(items==null)throw new InvalidDataException("Ungültige Release-Antwort.");
   var candidates=new List<UpdateRelease>();
   foreach(var item in items){
    object raw;string tag=item.TryGetValue("tag_name",out raw)?raw as string:null;
    var match=Regex.Match(tag??"",@"^v?(\d+\.\d+\.\d+)(?:-build-(\d+))?$");
    Version v;if(!match.Success||!System.Version.TryParse(match.Groups[1].Value,out v))continue;
    int build=0;if(match.Groups[2].Success&&!Int32.TryParse(match.Groups[2].Value,out build))continue;
    bool draft=item.TryGetValue("draft",out raw)&&raw is bool&&(bool)raw;
    bool pre=item.TryGetValue("prerelease",out raw)&&raw is bool&&(bool)raw;
    if(draft&&!includeDrafts||pre&&!includePrereleases)continue;
    string url=item.TryGetValue("html_url",out raw)?raw as string:null;if(!SafeReleaseUrl(url))continue;
    object assets;if(!item.TryGetValue("assets",out assets))continue;
    var array=assets as System.Collections.IEnumerable;bool package=false;
    if(array!=null)foreach(var a in array){var asset=a as Dictionary<string,object>;object name;if(asset!=null&&asset.TryGetValue("name",out name)&&name is string&&Regex.IsMatch((string)name,@"^Netzblick-(Setup|Portable)-\d+\.\d+\.\d+-win-x64\.(exe|zip)$"))package=true;}
    if(!package)continue;
    string title=item.TryGetValue("name",out raw)?raw as string:null;
    string notes=item.TryGetValue("body",out raw)?raw as string:null;
    candidates.Add(new UpdateRelease{Tag=tag,Name=title??tag,Url=url,Notes=(notes??"").Substring(0,Math.Min(6000,(notes??"").Length)),Draft=draft,Prerelease=pre,Version=v.ToString(),Build=build});
   }
   return candidates.OrderByDescending(x=>System.Version.Parse(x.Version)).ThenByDescending(x=>x.Build).FirstOrDefault();
  }
  public static bool IsNewer(UpdateRelease release,string version,int build){if(release==null)return false;int c=System.Version.Parse(release.Version).CompareTo(System.Version.Parse(version));return c>0||c==0&&release.Build>build;}
  public static Task<UpdateResult> Start(bool drafts,bool prereleases){return Task.Run(()=>Check(drafts,prereleases));}
  static UpdateResult Check(bool drafts,bool prereleases){
   try{
    ServicePointManager.SecurityProtocol|=SecurityProtocolType.Tls12;
    var request=(HttpWebRequest)WebRequest.Create("https://api.github.com/repos/Chaozz2go/Netzblick/releases?per_page=100");
    request.Method="GET";request.UserAgent="Netzblick/"+CurrentVersion;request.Accept="application/vnd.github+json";request.Timeout=15000;request.ReadWriteTimeout=15000;request.AllowAutoRedirect=false;
    string token=drafts?UpdateCredentials.Read():"";if(token.Length>0)request.Headers[HttpRequestHeader.Authorization]="Bearer "+token;
    using(var response=(HttpWebResponse)request.GetResponse()){
     if(response.StatusCode!=HttpStatusCode.OK)throw new InvalidDataException("GitHub antwortet nicht mit einer Release-Liste.");
     using(var stream=response.GetResponseStream())using(var memory=new MemoryStream()){
      byte[] buffer=new byte[8192];int n;while((n=stream.Read(buffer,0,buffer.Length))>0){memory.Write(buffer,0,n);if(memory.Length>2097152)throw new InvalidDataException("GitHub-Antwort zu groß.");}
      var release=Select(Encoding.UTF8.GetString(memory.ToArray()),CurrentVersion,CurrentBuild,drafts,prereleases);
      return new UpdateResult{Release=release,Available=IsNewer(release,CurrentVersion,CurrentBuild),Message=release==null?"Keine passende veröffentlichte Windows-Version gefunden. Bei Bedarf Testversionen oder Entwürfe einschließen.":IsNewer(release,CurrentVersion,CurrentBuild)?"Neue Version verfügbar: "+release.Tag:"Keine neuere Version gefunden. Neuester passender Stand: "+release.Tag};
     }
    }
   }catch(WebException e){
    using(var response=e.Response as HttpWebResponse){
     int status=response==null?0:(int)response.StatusCode;
     return new UpdateResult{Message=status==401||status==404?"GitHub-Zugriff fehlt oder ist abgelaufen. Die veröffentlichten Updates benötigen keinen Token. „Release-Entwürfe einschließen“ ausschalten oder einen gespeicherten Zugang entfernen.":status==403||status==429?"GitHub verweigert den Zugriff oder das API-Limit ist erreicht. Berechtigungen prüfen oder später erneut versuchen.":"Updateprüfung nicht möglich. Netzwerkverbindung prüfen und später erneut versuchen."};
    }
   }catch{ return new UpdateResult{Message="Updateprüfung nicht möglich. GitHub-Antwort konnte nicht verarbeitet werden. Bei eingeschlossenen Entwürfen den gespeicherten Zugang prüfen."}; }
  }
 }
 public static class UpdateCredentials {
  static readonly byte[] Entropy=Encoding.UTF8.GetBytes("Netzblick.GitHub.Updates.v1");
  static string FilePath {get{return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Netzblick","github-token.bin");}}
  public static bool Exists {get{return File.Exists(FilePath);}}
  public static string Read(){return Exists?Encoding.UTF8.GetString(ProtectedData.Unprotect(File.ReadAllBytes(FilePath),Entropy,DataProtectionScope.CurrentUser)):"";}
  public static void Save(string token){
   token=(token??"").Trim();if(token.Length<10||token.Length>512||token.Any(Char.IsWhiteSpace)||token.Any(Char.IsControl))throw new ArgumentException("Einen gültigen GitHub-Token eingeben.");
   Directory.CreateDirectory(Path.GetDirectoryName(FilePath));byte[] data=ProtectedData.Protect(Encoding.UTF8.GetBytes(token),Entropy,DataProtectionScope.CurrentUser);
   string temp=FilePath+".tmp";File.WriteAllBytes(temp,data);if(File.Exists(FilePath))File.Replace(temp,FilePath,null);else File.Move(temp,FilePath);
  }
  public static void Forget(){if(File.Exists(FilePath))File.Delete(FilePath);}
 }
}

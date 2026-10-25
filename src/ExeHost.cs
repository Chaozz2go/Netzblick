using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("Netzblick")]
[assembly: AssemblyVersion("0.11.0.0")]
[assembly: AssemblyFileVersion("0.11.0.0")]

namespace Netzblick.Desktop {
 // No downloads, external PowerShell process, runtime compiler or LoadFrom.
 // UI scripts run inside the EXE with Windows' existing PowerShell 5.1 engine.
 internal static class Program {
  static readonly Assembly Self=Assembly.GetExecutingAssembly();
  static string root,report;
  static IntPtr nativeLibrary;
  static bool Has(string[] args,string value){return args.Any(a=>String.Equals(a,value,StringComparison.OrdinalIgnoreCase));}
  static Assembly Resolve(object sender,ResolveEventArgs e){
   string name=new AssemblyName(e.Name).Name;
   string resource="Netzblick.Library."+name+".dll";
   using(var stream=Self.GetManifestResourceStream(resource)){
    if(stream==null)return null;
    using(var memory=new MemoryStream()){stream.CopyTo(memory);return Assembly.Load(memory.ToArray());}
   }
  }
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
  static extern IntPtr LoadLibraryEx(string name,IntPtr reserved,uint flags);
  [DllImport("kernel32.dll")] static extern bool FreeLibrary(IntPtr module);
  [STAThread] public static int Main(string[] args){
   AppDomain.CurrentDomain.AssemblyResolve+=Resolve;
   try{
    report=Option(args,"--report");
    for(int i=0;i<args.Length;i++){
     if(String.Equals(args[i],"--report",StringComparison.OrdinalIgnoreCase)){i++;continue;}
     if(!new[]{"--portable","--installed","--tray","--check","--host-check","--smoke-test","--install","--uninstall","--no-tray"}.Any(flag=>String.Equals(flag,args[i],StringComparison.OrdinalIgnoreCase)))throw new ArgumentException("Unbekannter Startparameter: "+args[i]);
    }
    bool check=Has(args,"--check")||Has(args,"--host-check"),smoke=Has(args,"--smoke-test");
    using(var id=WindowsIdentity.GetCurrent()){
     if(!new WindowsPrincipal(id).IsInRole(WindowsBuiltInRole.Administrator)){
      var info=new ProcessStartInfo(Self.Location){Verb="runas",UseShellExecute=true,Arguments=String.Join(" ",args.Select(Quote))};
      using(var p=Process.Start(info)){p.WaitForExit();return p.ExitCode;}
     }
    }
    if(!Environment.Is64BitProcess)throw new NotSupportedException("Netzblick benötigt Windows x64.");
    bool maintenance=Has(args,"--install")||Has(args,"--uninstall");
    string installedRoot=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"Netzblick");
    bool inInstalledFolder=String.Equals(Path.GetDirectoryName(Self.Location),installedRoot,StringComparison.OrdinalIgnoreCase);
    bool portable=Has(args,"--portable")||(!Has(args,"--installed")&&!maintenance&&!inInstalledFolder);
    if(Has(args,"--portable")&&(Has(args,"--installed")||maintenance))throw new ArgumentException("Portable und installierte Betriebsart dürfen nicht kombiniert werden.");
    if(Has(args,"--install")&&Has(args,"--uninstall"))throw new ArgumentException("Installation und Deinstallation dürfen nicht kombiniert werden.");
    if(portable&&!check){
     using(var service=new System.ServiceProcess.ServiceController("NetzblickControl")){
      try{if(service.Status!=System.ServiceProcess.ServiceControllerStatus.Stopped)throw new InvalidOperationException("Der installierte Netzblick-Dienst läuft bereits. Die installierte Version verwenden oder den Dienst zuerst beenden.");}
      catch(InvalidOperationException e){if(e.InnerException==null)throw;}
     }
    }
    string basePath=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),"Netzblick.Runtime");
    SecureDirectory(basePath);
    root=Path.Combine(basePath,Guid.NewGuid().ToString("N"));SecureDirectory(root);
    Unpack(root);
    // Load the exact embedded native dependency from the protected runtime path.
    string native=Path.Combine(root,"lib","amd64","KernelTraceControl.dll");
    if(File.Exists(native)&&(nativeLibrary=LoadLibraryEx(native,IntPtr.Zero,8))==IntPtr.Zero)throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(),"ETW-Komponente konnte nicht geladen werden.");
    return Run(args,portable,check,smoke,maintenance);
   }catch(Exception e){
    string text=e.GetBaseException().Message;WriteReport("FAIL: "+e);
    if(report==null)MessageBox.Show(text,"Netzblick konnte nicht starten",MessageBoxButtons.OK,MessageBoxIcon.Error);
    return 1;
   }finally{
    if(nativeLibrary!=IntPtr.Zero)FreeLibrary(nativeLibrary);
    if(root!=null)try{Directory.Delete(root,true);}catch{}
   }
  }
  static string Option(string[] args,string name){for(int i=0;i<args.Length;i++)if(args[i]==name){if(i+1==args.Length)throw new ArgumentException("Pfad fehlt: "+name);return Path.GetFullPath(args[i+1]);}return null;}
  static string Quote(string value){return "\""+value.Replace("\"","\\\"")+"\"";}
  internal static void SecureDirectory(string path){
   path=Path.GetFullPath(path);
   if(path.StartsWith(@"\\",StringComparison.Ordinal))throw new IOException("Netzblick-Daten müssen auf einem lokalen Laufwerk liegen.");
   for(var p=new DirectoryInfo(path);p!=null;p=p.Parent){if(p.Exists&&(p.Attributes&FileAttributes.ReparsePoint)!=0)throw new IOException("Verknüpfung im Datenpfad: "+p.FullName);}
   if(Directory.Exists(path)){
    string owner=Directory.GetAccessControl(path).GetOwner(typeof(SecurityIdentifier)).Value;
    string current=WindowsIdentity.GetCurrent().User.Value;
    if(owner!="S-1-5-18"&&owner!="S-1-5-32-544"&&owner!=current)throw new IOException("Datenordner gehört einem anderen Konto: "+path);
    foreach(string entry in Directory.GetFileSystemEntries(path))if((File.GetAttributes(entry)&FileAttributes.ReparsePoint)!=0)throw new IOException("Verknüpfung im Datenordner: "+entry);
   }
   var acl=new DirectorySecurity();acl.SetAccessRuleProtection(true,false);
   foreach(var sid in new[]{WellKnownSidType.LocalSystemSid,WellKnownSidType.BuiltinAdministratorsSid})acl.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(sid,null),FileSystemRights.FullControl,InheritanceFlags.ContainerInherit|InheritanceFlags.ObjectInherit,PropagationFlags.None,AccessControlType.Allow));
   Directory.CreateDirectory(path,acl);Directory.SetAccessControl(path,acl);
  }
  static void Unpack(string destination){
   using(var stream=Self.GetManifestResourceStream("Netzblick.Payload"))
   using(var zip=new ZipArchive(stream,ZipArchiveMode.Read)){
    foreach(var entry in zip.Entries){
     string name=entry.FullName.Replace('/',Path.DirectorySeparatorChar);
     string path=Path.GetFullPath(Path.Combine(destination,name));
     if(!path.StartsWith(destination+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("Ungültiger Paketpfad.");
     if(String.IsNullOrEmpty(entry.Name)){Directory.CreateDirectory(path);continue;}
     Directory.CreateDirectory(Path.GetDirectoryName(path));
     using(var source=entry.Open())using(var file=new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.None))source.CopyTo(file);
    }
   }
  }
  [MethodImpl(MethodImplOptions.NoInlining)]
  static int Run(string[] args,bool portable,bool check,bool smoke,bool maintenance){
   // Resolving this method's Core reference only happens after Resolve is installed.
   using(var global=new Mutex(false,@"Global\Netzblick.Runtime.v1")){
    bool owns=false;
    try{
     try{owns=global.WaitOne(0);}catch(AbandonedMutexException){owns=true;}
     if(!owns)throw new InvalidOperationException("Netzblick läuft bereits. Über das Tray öffnen oder vor der Installation beenden.");
     string state=null;
     IDisposable worker=null;
     try{
      if(!portable&&!check&&!maintenance){
       using(var service=new System.ServiceProcess.ServiceController("NetzblickControl")){
        try{
         if(service.Status==System.ServiceProcess.ServiceControllerStatus.StopPending)service.WaitForStatus(System.ServiceProcess.ServiceControllerStatus.Stopped,TimeSpan.FromSeconds(20));
         service.Refresh();if(service.Status==System.ServiceProcess.ServiceControllerStatus.Stopped)service.Start();
         service.WaitForStatus(System.ServiceProcess.ServiceControllerStatus.Running,TimeSpan.FromSeconds(20));
        }catch(InvalidOperationException){/* Keep the UI available for diagnostics if the service is missing. */}
       }
      }
      if(portable&&!check){
       state=Path.Combine(Path.GetDirectoryName(Self.Location),"Netzblick-Daten");SecureDirectory(state);
       worker=Netzblick.ControlService.StartPortable(state);
      }
      var initial=InitialSessionState.CreateDefault();
      initial.ExecutionPolicy=Microsoft.PowerShell.ExecutionPolicy.Bypass;
      using(var runspace=RunspaceFactory.CreateRunspace(initial)){
       runspace.ApartmentState=ApartmentState.STA;runspace.ThreadOptions=PSThreadOptions.UseCurrentThread;runspace.Open();
       using(var ps=PowerShell.Create()){
        ps.Runspace=runspace;
        runspace.SessionStateProxy.SetVariable("NetzblickDistributionRoot",Path.GetDirectoryName(Self.Location));
        if(Has(args,"--host-check")){HostChecks(runspace);WriteReport("PASS: EXE host; suppressed, caught and real PowerShell errors verified.");return 0;}
        if(maintenance){
         ps.AddCommand(Path.Combine(root,"Install-Netzblick.ps1"));
         if(Has(args,"--uninstall"))ps.AddParameter("Uninstall");
         if(Has(args,"--no-tray"))ps.AddParameter("NoTray");
        }else{
         ps.AddCommand(Path.Combine(root,"Netzblick.ps1")).AddParameter("Embedded");
         if(portable)ps.AddParameter("Portable");if(state!=null)ps.AddParameter("StateDirectory",state);
         if(check)ps.AddParameter("Check");if(smoke)ps.AddParameter("SmokeTest");if(Has(args,"--tray"))ps.AddParameter("LaunchInTray");
        }
        string marker=maintenance?"NETZBLICK_MAINTENANCE_OK":check?"OK: XAML":smoke?"PASS: full WPF/tray":"NETZBLICK_UI_OK";
        string text=InvokeChecked(ps,marker);
        if(smoke){
         var status=Netzblick.SetupClient.Send(new Netzblick.SetupCommand{Operation="Status"});if(!status.Ok||!status.Verified)throw new InvalidOperationException("Filtersteuerung nicht bereit: "+status.Error);
        }
        WriteReport(text+Environment.NewLine+"PASS: EXE host; embedded assemblies; "+(portable?"portable":"installed")+".");return 0;
       }
      }
     }finally{if(worker!=null)worker.Dispose();}
    }finally{if(owns)global.ReleaseMutex();}
   }
  }
  static string ErrorDetails(ErrorRecord error){
   if(error==null)return "Kein PowerShell-Fehlerdatensatz verfügbar.";
   return String.Join(Environment.NewLine,new[]{error.ToString(),error.Exception==null?null:error.Exception.ToString(),error.ErrorDetails==null?null:error.ErrorDetails.Message,error.FullyQualifiedErrorId,error.InvocationInfo==null?null:error.InvocationInfo.PositionMessage,error.ScriptStackTrace}.Where(s=>!String.IsNullOrWhiteSpace(s)));
  }
  static string InvokeChecked(PowerShell ps,string marker){
   System.Collections.ObjectModel.Collection<PSObject> output;
   try{output=ps.Invoke();}
   catch(RuntimeException e){throw new InvalidOperationException("PowerShell-Ausführung fehlgeschlagen:"+Environment.NewLine+ErrorDetails(e.ErrorRecord),e);}
   string text=String.Join(Environment.NewLine,output.Select(o=>o.ToString()));
   string state="PowerShell-Status: "+ps.InvocationStateInfo.State+"; HadErrors="+ps.HadErrors+"; Fehlerausgabe="+ps.Streams.Error.Count+"; Kultur="+System.Globalization.CultureInfo.CurrentCulture.Name;
   // HadErrors is also true for explicitly suppressed or successfully caught
   // errors. It is not a success/failure exit code. Require a completed
   // invocation, no unsuppressed errors, and the script's final success marker.
   if(ps.InvocationStateInfo.State!=PSInvocationState.Completed||ps.Streams.Error.Count>0)
    throw new InvalidOperationException("PowerShell-Auftrag fehlgeschlagen. "+state+Environment.NewLine+String.Join(Environment.NewLine,ps.Streams.Error.Select(ErrorDetails)),ps.InvocationStateInfo.Reason);
   if(!text.Contains(marker))throw new InvalidOperationException("PowerShell-Auftrag wurde ohne Erfolgsbestätigung beendet. Erwartet: "+marker+Environment.NewLine+state+Environment.NewLine+text);
   return text+Environment.NewLine+state;
  }
  static void HostChecks(Runspace runspace){
   foreach(string script in new[]{
    "$ErrorActionPreference='Stop'; Write-Error 'EXPECTED_SUPPRESSED' -ErrorAction SilentlyContinue; 'HOST_OK'",
    "$ErrorActionPreference='Stop'; try { throw 'EXPECTED_CAUGHT' } catch {}; 'HOST_OK'"
   })using(var ps=PowerShell.Create()){
    ps.Runspace=runspace;ps.AddScript(script);InvokeChecked(ps,"HOST_OK");
    if(script.Contains("EXPECTED_SUPPRESSED")&&(!ps.HadErrors||ps.Streams.Error.Count!=0))throw new InvalidOperationException("Der ursprüngliche HadErrors-Fehler wurde im Test nicht reproduziert.");
   }
   foreach(string script in new[]{
    "$ErrorActionPreference='Stop'; throw 'EXPECTED_REAL_FAILURE'",
    "$ErrorActionPreference='Continue'; Write-Error 'EXPECTED_REAL_FAILURE'; 'HOST_OK'",
    "$ErrorActionPreference='Stop'; 'Kein Erfolgsmarker'"
   })using(var ps=PowerShell.Create()){
    ps.Runspace=runspace;ps.AddScript(script);bool failed=false;
    try{InvokeChecked(ps,"HOST_OK");}catch(InvalidOperationException e){failed=true;if(String.IsNullOrWhiteSpace(e.Message))throw new InvalidOperationException("Leere Fehlermeldung im Hosttest.");}
    if(!failed)throw new InvalidOperationException("Ein echter Fehler oder fehlender Erfolgsmarker wurde übergangen.");
   }
  }
  static void WriteReport(string text){if(report!=null)File.WriteAllText(report,text);}
 }
}

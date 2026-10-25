using System;
using System.IO;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.ServiceProcess;
using System.Text;
using System.Web.Script.Serialization;

namespace Netzblick {
 public static class SetupWire {
  public static string PipeName="Netzblick.Control.v1";
  internal static uint PortablePid=0;
  public static JavaScriptSerializer Json(){return new JavaScriptSerializer{MaxJsonLength=2097152,RecursionLimit=24};}
  static void Exact(Stream stream,byte[] buffer){int offset=0;while(offset<buffer.Length){var ar=stream.BeginRead(buffer,offset,buffer.Length-offset,null,null);int n;using(ar.AsyncWaitHandle){if(!ar.AsyncWaitHandle.WaitOne(1500)){stream.Dispose();throw new System.TimeoutException("Dienstantwort nicht rechtzeitig erhalten.");}n=stream.EndRead(ar);}if(n==0)throw new EndOfStreamException();offset+=n;}}
  public static string Read(Stream stream){var head=new byte[4];Exact(stream,head);int size=BitConverter.ToInt32(head,0);if(size<1||size>2097152)throw new InvalidDataException("Nachricht zu groß oder leer.");var data=new byte[size];Exact(stream,data);return Encoding.UTF8.GetString(data);}
  public static void Write(Stream stream,string text){byte[] data=Encoding.UTF8.GetBytes(text);if(data.Length>2097152)throw new InvalidDataException("Antwort zu groß.");var bytes=new byte[data.Length+4];Array.Copy(BitConverter.GetBytes(data.Length),bytes,4);Array.Copy(data,0,bytes,4,data.Length);var ar=stream.BeginWrite(bytes,0,bytes.Length,null,null);using(ar.AsyncWaitHandle){if(!ar.AsyncWaitHandle.WaitOne(1500)){stream.Dispose();throw new System.TimeoutException("Dienstnachricht konnte nicht übertragen werden.");}stream.EndWrite(ar);}}
 }
 public static class SetupClient {
  [StructLayout(LayoutKind.Sequential)] struct ServiceStatus {public uint Type,State,Controls,Win32Exit,ServiceExit,Checkpoint,WaitHint,Pid,Flags;}
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetNamedPipeServerProcessId(Microsoft.Win32.SafeHandles.SafePipeHandle pipe,out uint pid);
  [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr OpenSCManager(string machine,string database,uint access);
  [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr OpenService(IntPtr manager,string name,uint access);
  [DllImport("advapi32.dll",SetLastError=true)] static extern bool QueryServiceStatusEx(IntPtr service,int level,out ServiceStatus status,int size,out int needed);
  [DllImport("advapi32.dll")] static extern bool CloseServiceHandle(IntPtr handle);
  static uint ServicePid(){if(SetupWire.PortablePid!=0)return SetupWire.PortablePid;IntPtr manager=OpenSCManager(null,null,1);if(manager==IntPtr.Zero)throw new IOException("Dienstverwaltung nicht verfügbar.");try{IntPtr service=OpenService(manager,"NetzblickControl",4);if(service==IntPtr.Zero)throw new IOException("Netzblick-Dienst fehlt. Bitte Netzblick-Setup.exe ausführen.");try{ServiceStatus status;int needed;if(!QueryServiceStatusEx(service,0,out status,Marshal.SizeOf(typeof(ServiceStatus)),out needed)||status.State!=4||status.Pid==0)throw new IOException("Netzblick-Dienst läuft nicht.");return status.Pid;}finally{CloseServiceHandle(service);}}finally{CloseServiceHandle(manager);}}
  public static SetupStatus Send(SetupCommand command){
   using(var pipe=new NamedPipeClientStream(".",SetupWire.PipeName,PipeDirection.InOut,PipeOptions.Asynchronous)){
    pipe.Connect(700);uint actual;if(!GetNamedPipeServerProcessId(pipe.SafePipeHandle,out actual)||actual!=ServicePid())throw new IOException("Identität des Netzblick-Dienstes nicht bestätigt.");
    SetupWire.Write(pipe,SetupWire.Json().Serialize(command));return SetupWire.Json().Deserialize<SetupStatus>(SetupWire.Read(pipe));
   }
  }
 }
}


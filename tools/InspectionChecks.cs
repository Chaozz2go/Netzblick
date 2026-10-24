using System;
using System.Collections.Generic;
using Netzblick;

public static class InspectionChecks {
 public static int Run(){
  int count=0;
  Action<bool,string> check=(ok,name)=>{if(!ok)throw new Exception("Inspection check failed: "+name);count++;};
  DateTime start=new DateTime(2026,10,24,10,0,0,DateTimeKind.Utc);
  string xml="<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'><System><Provider Name='Microsoft-Windows-Security-Auditing'/><EventID>5157</EventID><TimeCreated SystemTime='2026-10-24T10:00:01.0000000Z'/><EventRecordID>42</EventRecordID></System><EventData><Data Name='ProcessID'>0x64</Data><Data Name='Application'>C:\\Test\\app.exe</Data><Data Name='Direction'>%%14593</Data><Data Name='SourceAddress'>192.168.1.3</Data><Data Name='SourcePort'>49152</Data><Data Name='DestAddress'>8.8.8.8</Data><Data Name='DestPort'>443</Data><Data Name='Protocol'>6</Data></EventData></Event>";
  var parsed=BlockEventParser.Parse(xml);
  check(parsed.Pid==100,"hex PID");check(parsed.RecordId==42,"record id");check(parsed.TimeUtc==start.AddSeconds(1),"UTC timestamp");
  check(parsed.Direction=="Ausgehend" && parsed.Protocol=="TCP","outgoing TCP");check(parsed.Target=="8.8.8.8","outgoing target");
  check(parsed.Program=="app.exe","program basename");
  var inbound=BlockEventParser.Parse(xml.Replace("%%14593","%%14592").Replace(">6</Data>",">17</Data>").Replace(">0x64</Data>",">100</Data>"));
  check(inbound.Pid==100 && inbound.Direction=="Eingehend" && inbound.Protocol=="UDP","decimal PID and incoming UDP");
  check(BlockEventParser.Parse(xml.Replace("%%14593","unknown")).Direction=="Unbekannt","unknown direction stays unknown");
  foreach(string invalid in new string[]{xml.Replace(">5157<",">5156<"),xml.Replace("Microsoft-Windows-Security-Auditing","Other"),xml.Replace("Name='DestAddress'","Name='Wrong'"),xml.Replace("0x64","-1"),xml.Replace("2026-10-24T10:00:01.0000000Z","bad-time"),"<!DOCTYPE Event [<!ENTITY x 'bad'>]>"+xml}){
   bool rejected=false;try{BlockEventParser.Parse(invalid);}catch{rejected=true;}check(rejected,"reject malformed/unrelated event");
  }
  check(ProcessLineage.Normalize("\\??\\c:\\Test\\APP.exe")=="C:\\TEST\\APP.EXE","NT path prefix");
  check(ProcessLineage.Normalize("\\\\?\\c:\\Test\\app.exe")=="C:\\TEST\\APP.EXE","extended DOS path prefix");
  check(ProcessLineage.Normalize("\\\\?\\UNC\\server\\share\\app.exe")=="\\\\SERVER\\SHARE\\APP.EXE","extended UNC normalization");
  check(ProcessLineage.Normalize(" ")=="","empty path");
  var tree=new ProcessLineage("C:\\Test\\app.exe",start);
  var root=new ProcessNode{Pid=100,ParentPid=5,Path="C:\\Test\\app.exe",Name="app.exe",StartUtc=start.AddMilliseconds(10)};
  var child=new ProcessNode{Pid=101,ParentPid=100,Path="C:\\Test\\helper.exe",Name="helper.exe",StartUtc=start.AddMilliseconds(20)};
  var grandchild=new ProcessNode{Pid=102,ParentPid=101,Path="C:\\Test\\worker.exe",Name="worker.exe",StartUtc=start.AddMilliseconds(30)};
  var unrelated=new ProcessNode{Pid=200,ParentPid=5,Path="C:\\Other\\helper.exe",Name="helper.exe",StartUtc=start.AddMilliseconds(40)};
  tree.Observe(new List<ProcessNode>{grandchild,unrelated,child,root},start.AddSeconds(1));
  check(tree.Snapshot().Count==3,"out-of-order descendants resolved");
  check(tree.Snapshot().Find(n=>n.Pid==102).Depth==2,"grandchild depth");
  check(tree.Matches(parsed),"root path matched");
  check(!tree.Matches(new BlockEvent{Application=root.Path,Pid=100,TimeUtc=start.AddTicks(-1)}),"pre-session root event excluded");
  check(tree.Matches(new BlockEvent{Application=child.Path,Pid=101,TimeUtc=start.AddMilliseconds(300)}),"child event matched");
  check(!tree.Matches(new BlockEvent{Application=unrelated.Path,Pid=200,TimeUtc=start.AddMilliseconds(300)}),"unrelated program excluded");
  check(!tree.Matches(new BlockEvent{Application=unrelated.Path,Pid=101,TimeUtc=start.AddMilliseconds(300)}),"PID alone is insufficient");
  check(!tree.Matches(new BlockEvent{Application=child.Path,Pid=101,TimeUtc=start.AddMilliseconds(1)}),"event before child start excluded");
  var reused=new ProcessNode{Pid=101,ParentPid=200,Path=child.Path,Name="helper.exe",StartUtc=start.AddSeconds(2)};
  tree.Observe(new List<ProcessNode>{root,unrelated,reused},start.AddSeconds(3));
  check(!tree.Matches(new BlockEvent{Application=child.Path,Pid=101,TimeUtc=start.AddSeconds(2)}),"same-path PID reuse not attributed to former child");
  check(tree.Matches(new BlockEvent{Application=child.Path,Pid=101,TimeUtc=start.AddSeconds(1)}),"late old-child event still attributed");
  check(tree.Snapshot().Find(n=>n.Pid==101).EndUtc==start.AddSeconds(2),"former child ends at replacement start");
  var bogusParent=new ProcessLineage(root.Path,start);
  var oldChild=new ProcessNode{Pid=301,ParentPid=100,Path="C:\\old.exe",Name="old.exe",StartUtc=start.AddTicks(-10)};
  bogusParent.Observe(new List<ProcessNode>{root,oldChild},start.AddSeconds(1));
  check(bogusParent.Snapshot().Count==1,"child older than session excluded");
  foreach(uint original in new uint[]{0,1,2,3,4}){
   uint applied=InspectionAuditFlags.WithFailure(original);
   check((applied&2)!=0,"failure enabled");check((applied&1)==(original&1),"success setting preserved");
   check(InspectionAuditFlags.CanRestore(original,applied,applied),"unchanged applied flags restorable");
   check(InspectionAuditFlags.CanRestore(original,applied,original),"already restored flags accepted");
  }
  check(!InspectionAuditFlags.CanRestore(4,2,3),"new external success setting not overwritten");
  check(!InspectionAuditFlags.CanRestore(1,3,2),"external success removal not overwritten");
  check(InspectionAuditFlags.Canonical(0)==4,"no-audit canonical representation");
  Console.WriteLine("PASS: "+count+" inspection logic checks. No Windows policy changes.");return count;
 }
}

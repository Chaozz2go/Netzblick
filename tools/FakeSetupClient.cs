using System;
using System.Collections.Generic;
using Netzblick;
// UI fixtures only. This file is never part of the installed app/service.
namespace Netzblick {
 public static class SetupClient {
  static SetupStatus status;
  public static string LastOperation="";
  public static void Scenario(string path,int scenario){
   status=new SetupStatus{Ok=true,Verified=scenario!=3,Error=scenario==3?"Test: Filterprüfung fehlgeschlagen":"",Warning="Beispieldaten – keine Netzwerkfilter aktiv",CheckedUtc=DateTime.UtcNow,StartedUtc=DateTime.UtcNow,Config=new SetupConfig{Ask=scenario>0},Attempts=new List<SetupAttempt>(),History=new List<string>{"12:00 · Testdaten geladen"}};
   if(scenario>0)status.Attempts.Add(new SetupAttempt{Key="fixture",Path=path,Program="powershell.exe",Direction="Ausgehend",Address="10.0.0.10",Protocol=6,Port=636,Count=12,OwnBlock=true,FirstUtc=DateTime.UtcNow,LastUtc=DateTime.UtcNow});
   if(scenario==2){status.Config.Rules.Add(new SetupRule{Id=Guid.NewGuid().ToString(),Name="LDAPS zum DC",Path=path,Direction="Ausgehend",Address="10.0.0.10",Protocol=6,Port=636,Action="Allow",ExpiresUtc=DateTime.UtcNow.AddMinutes(5)});status.RecoveryUtc=DateTime.UtcNow.AddMinutes(2);}
  }
  public static SetupStatus Send(SetupCommand command){
   LastOperation=command.Operation;
   if(command.Operation=="Status"||command.Operation=="Recheck")return status;
   if(command.Operation=="Watch"){if(!status.Verified)throw new InvalidOperationException("Test: Filterprüfung fehlgeschlagen");status.Config.WatchedPaths.Add(command.Path);return status;}
   if(command.Operation=="AllowProgram"){SetupChanges.AllowProgram(status.Config,command.Path);return status;}
   if(command.Operation=="BlockProgram"){SetupChanges.BlockProgram(status.Config,command.Path);return status;}
   if(command.Operation=="ProgramDefault"){SetupChanges.ProgramDefault(status.Config,command.Path);return status;}
   if(command.Operation=="Unwatch"){status.Config.WatchedPaths.Remove(command.Path);return status;}
   if(command.Operation=="Remove"){status.Config.Rules.RemoveAll(r=>r.Id==command.RuleId);return status;}
   if(command.Operation=="Ask"){status.Config.Ask=command.Enabled;return status;}
   if(command.Operation=="Reset"){status.Config=new SetupConfig();status.Attempts.Clear();status.History.Clear();return status;}
   throw new InvalidOperationException("UI-Fixture erlaubt diesen Befehl nicht.");
  }
 }
}


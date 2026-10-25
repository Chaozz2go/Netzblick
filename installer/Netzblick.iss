#define Version "0.8.0"
[Setup]
AppId=Netzblick.Desktop
AppName=Netzblick
AppVersion={#Version}
AppPublisher=Chaozz2go
AppPublisherURL=https://github.com/Chaozz2go/Netzblick
DefaultDirName={autopf}\Netzblick
DisableDirPage=yes
DefaultGroupName=Netzblick
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir=..\dist-install
OutputBaseFilename=Netzblick-Setup-{#Version}-win-x64
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\Netzblick.exe
AppMutex=Global\Netzblick.Runtime.v1
CloseApplications=yes
RestartApplications=no
SetupLogging=yes

[Languages]
Name: "german"; MessagesFile: "compiler:Languages\German.isl"

[Files]
Source: "..\dist\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Netzblick"; Filename: "{app}\Netzblick.exe"; Parameters: "--installed"
Name: "{group}\Netzblick deinstallieren"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\Netzblick.exe"; Parameters: "--installed"; Description: "Netzblick öffnen"; Flags: nowait postinstall skipifsilent runascurrentuser

[Code]
function PrepareToInstall(var NeedsRestart: Boolean): String;
var Code: Integer;
begin
  Result := '';
  { Stop the existing service before replacing its executable on update. }
  Exec(ExpandConstant('{sys}\sc.exe'), 'stop NetzblickControl', '', SW_HIDE, ewWaitUntilTerminated, Code);
  Sleep(1500);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var Code: Integer;
begin
  if CurStep = ssPostInstall then begin
    if not Exec(ExpandConstant('{app}\Netzblick.exe'), '--install --no-tray', '', SW_HIDE, ewWaitUntilTerminated, Code) then
      RaiseException('Netzblick-Dienst konnte nicht eingerichtet werden.');
    if Code <> 0 then RaiseException('Netzblick-Dienstinstallation fehlgeschlagen. Fehlercode: ' + IntToStr(Code));
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var Code: Integer;
begin
  if CurUninstallStep = usUninstall then begin
    if not Exec(ExpandConstant('{app}\Netzblick.exe'), '--uninstall --no-tray', '', SW_HIDE, ewWaitUntilTerminated, Code) then
      RaiseException('Netzblick-Dienst konnte nicht entfernt werden.');
    if Code <> 0 then RaiseException('Netzblick-Dienstentfernung fehlgeschlagen. Fehlercode: ' + IntToStr(Code));
  end;
end;

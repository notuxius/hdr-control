; This bootstrapper delegates installation to the same Setup.ps1 as ZIP installs.
#ifndef SourceRoot
  #error SourceRoot is required
#endif
#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef BuildOutput
  #error BuildOutput is required
#endif

[Setup]
AppId=HdrContextMenu.Bootstrap
AppName=HDR Control
AppVersion={#AppVersion}
AppPublisher=notuxius
AppPublisherURL=https://github.com/notuxius/hdr-control
AppSupportURL=https://github.com/notuxius/hdr-control/issues
AppUpdatesURL=https://github.com/notuxius/hdr-control/releases
VersionInfoVersion={#AppVersion}.0
VersionInfoProductVersion={#AppVersion}.0
VersionInfoProductTextVersion={#AppVersion}
VersionInfoDescription=HDR Control installer
SetupIconFile={#SourceRoot}\HdrEnabled.ico
OutputDir={#BuildOutput}
OutputBaseFilename=HDR-Control-{#AppVersion}-Setup
WizardStyle=modern
DisableWelcomePage=no
DisableDirPage=yes
DisableProgramGroupPage=yes
CreateAppDir=no
Uninstallable=no
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
Compression=lzma2
SolidCompression=yes
CloseApplications=no
RestartApplications=no
SetupLogging=yes

[Messages]
WelcomeLabel2=This will install [name/ver] for your signed-in Windows account.%n%nThe tray helper will restart. Setup may restart Windows Explorer to activate the desktop menu.%n%nClick Next to continue.

[Files]
Source: "{#SourceRoot}\*"; DestDir: "{tmp}\HdrContextMenu"; Flags: dontcopy noencryption

[Code]
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
  Parameters: String;
begin
  Result := '';
  ExtractTemporaryFiles('{tmp}\HdrContextMenu\*');
  Parameters := '-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + ExpandConstant('{tmp}\HdrContextMenu\Setup.ps1') + '"';
  if ExpandConstant('{param:NoRestartShell|0}') = '1' then
    Parameters := Parameters + ' -NoRestart';
  if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Parameters,
    ExpandConstant('{tmp}\HdrContextMenu'), SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    Result := 'Windows could not start the HDR Control installer.';
  if (Result = '') and (ResultCode <> 0) then
    Result := 'HDR Control could not be installed. Setup returned error ' + IntToStr(ResultCode) + '.';
end;

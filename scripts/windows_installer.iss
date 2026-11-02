; The Windows installer (Inno Setup 6). Built by .github/workflows/release.yml:
;
;   ISCC /DAppVersion=0.2.0 /DSourceDir=<flutter's Release folder> /DOutputDir=<where to write> scripts\windows_installer.iss
;
; It installs for the current user only (no administrator prompt) under %LOCALAPPDATA%\Programs\Accompanist.
; Running a newer installer over an older one is how an update happens, so AppId must never change: Windows
; would treat the app as a different one and leave the old copy installed beside it.

#ifndef AppVersion
  #error Pass /DAppVersion=1.2.3
#endif
#ifndef SourceDir
  #error Pass /DSourceDir=<the built app folder>
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif

[Setup]
AppId={{6106144F-9BE8-4E15-90C9-5811BD5177CD}
AppName=Accompanist
AppVersion={#AppVersion}
AppVerName=Accompanist {#AppVersion}
AppPublisher=Accompanist
AppPublisherURL=https://accompanist.app
AppSupportURL=https://accompanist.app
DefaultDirName={localappdata}\Programs\Accompanist
DefaultGroupName=Accompanist
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Windows 10 1809 or later: what Flutter and WebView2 support.
MinVersion=10.0.17763
OutputDir={#OutputDir}
OutputBaseFilename=Accompanist-windows-setup
SetupIconFile=..\frontend\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\Accompanist.exe
UninstallDisplayName=Accompanist
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; An update closes the running app first instead of failing on files in use.
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; The previous version's assets, so nothing it shipped and this one dropped is left behind.
Type: filesandordirs; Name: "{app}\data"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Accompanist"; Filename: "{app}\Accompanist.exe"
Name: "{autodesktop}\Accompanist"; Filename: "{app}\Accompanist.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Accompanist.exe"; Description: "{cm:LaunchProgram,Accompanist}"; Flags: nowait postinstall skipifsilent

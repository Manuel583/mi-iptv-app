; Script de Inno Setup para crear el instalador de Windows de Mi IPTV.
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{7B1E2C4A-5D3F-4E8B-9A61-2C0F7D9E4B13}
AppName=Mi IPTV
AppVersion={#AppVersion}
AppPublisher=Uso personal
DefaultDirName={autopf}\Mi IPTV
DefaultGroupName=Mi IPTV
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\dist
OutputBaseFilename=mi-iptv-windows-instalador
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\mi_iptv.exe
WizardStyle=modern

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Mi IPTV"; Filename: "{app}\mi_iptv.exe"
Name: "{autodesktop}\Mi IPTV"; Filename: "{app}\mi_iptv.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\mi_iptv.exe"; Description: "{cm:LaunchProgram,Mi IPTV}"; Flags: nowait postinstall skipifsilent

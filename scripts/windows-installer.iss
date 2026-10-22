[Setup]
AppId={{30F995AC-7AEE-4CB1-8CC4-5F046026F024}
AppName=Pulse
AppVersion=0.5.6
DefaultDirName={localappdata}\Programs\Pulse
DefaultGroupName=Pulse
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=Pulse-0.5.6-Windows-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\Pulse"; Filename: "{app}\Pulse.exe"
Name: "{autodesktop}\Pulse"; Filename: "{app}\Pulse.exe"; Tasks: desktopicon
[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked
[Run]
Filename: "{app}\Pulse.exe"; Description: "Open Pulse"; Flags: nowait postinstall skipifsilent

[Setup]
AppId={{30F995AC-7AEE-4CB1-8CC4-5F046026F024}
AppName=Pulse Messenger
AppVersion=0.2.0
DefaultDirName={localappdata}\Programs\Pulse Messenger
DefaultGroupName=Pulse Messenger
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=PulseMessenger-0.2.0-Windows-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\Pulse Messenger"; Filename: "{app}\pulse_messenger.exe"
Name: "{autodesktop}\Pulse Messenger"; Filename: "{app}\pulse_messenger.exe"; Tasks: desktopicon
[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked
[Run]
Filename: "{app}\pulse_messenger.exe"; Description: "Open Pulse Messenger"; Flags: nowait postinstall skipifsilent

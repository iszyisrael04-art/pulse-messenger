[Setup]
AppId={{B7DE6748-6B63-4DB7-9E8F-76C54DA37215}
AppName=Pulse Control
AppVersion=0.5.8
DefaultDirName={localappdata}\Programs\PulseControl
DefaultGroupName=Pulse Control
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=Pulse-Control-0.5.8-Windows-Setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\Pulse Control"; Filename: "{app}\PulseControl.exe"

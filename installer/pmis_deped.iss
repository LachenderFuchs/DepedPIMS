#define MyAppName "PMIS DepED"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "DepEd SDO Naga City - SGOD"
#define MyAppExeName "pmis_deped.exe"
#define MyAppSourceDir "..\build\windows\x64\runner\Release"
#define MyResetToolName "PMIS Password Reset Utility"
#define MyResetToolExeName "pmis_password_reset_utility.exe"
#define MyResetToolSourceDir "..\password_reset_utility\build\windows\x64\runner\Release"

[Setup]
AppId={{8E78EA20-7329-4C61-A72D-9F54B6EDB0D1}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppVerName={#MyAppName} {#MyAppVersion}
DefaultDirName={autopf64}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
DisableProgramGroupPage=no
UsePreviousAppDir=yes
UsePreviousGroup=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
CloseApplications=yes
OutputDir=output
OutputBaseFilename=PMIS_DepED_Setup_{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#MyAppSourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "pmis_deped.db,pims_deped.db,archives\*"
Source: "{#MyResetToolSourceDir}\*"; DestDir: "{app}\Password Reset Utility"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{commondesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon
Name: "{group}\{#MyResetToolName}"; Filename: "{app}\Password Reset Utility\{#MyResetToolExeName}"; WorkingDir: "{app}\Password Reset Utility"; Check: FileExists(ExpandConstant('{app}\Password Reset Utility\{#MyResetToolExeName}'))
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

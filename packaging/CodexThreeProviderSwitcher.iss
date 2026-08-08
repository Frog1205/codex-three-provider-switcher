#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif

#define MyAppName "Codex Three-Provider Switcher"
#define MyPublisher "Frog1205"
#define MyRepository "https://github.com/Frog1205/codex-three-provider-switcher"

[Setup]
SourceDir=..
AppId={{5D45E3D0-F32E-4A21-A6D1-6DE7B6377E34}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyPublisher}
AppPublisherURL={#MyRepository}
AppSupportURL={#MyRepository}/issues
AppUpdatesURL={#MyRepository}/releases/latest
DefaultDirName={localappdata}\CodexThreeProviderSwitcher
DefaultGroupName=Codex Three-Provider Switcher
DisableProgramGroupPage=yes
LicenseFile=LICENSE
OutputBaseFilename=Codex-Three-Provider-Switcher-Setup-x64
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={sys}\shell32.dll
CloseApplications=no
RestartApplications=no
SetupLogging=no
VersionInfoVersion={#MyAppVersion}.0
VersionInfoCompany={#MyPublisher}
VersionInfoDescription=Codex three-provider switcher for 64-bit Windows 10 and later
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}

[Languages]
Name: "chinesesimplified"; MessagesFile: "packaging\languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式 / Create a desktop shortcut"; GroupDescription: "快捷方式 / Shortcuts:"; Flags: checkedonce

[Files]
Source: "src\CodexProviderSwitcher.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "src\Get-CodexRateLimits.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "src\ConfigureProviderKeys.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "src\providers.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "src\deepseek-model-catalog.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "SECURITY.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Codex 三线路切换器"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoLogo -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File ""{app}\CodexProviderSwitcher.ps1"""; WorkingDir: "{app}"; IconFilename: "{sys}\shell32.dll"; IconIndex: 44
Name: "{group}\配置 Honknet 和 DeepSeek 密钥"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoLogo -NoProfile -ExecutionPolicy Bypass -File ""{app}\ConfigureProviderKeys.ps1"""; WorkingDir: "{app}"; IconFilename: "{sys}\shell32.dll"; IconIndex: 71
Name: "{group}\卸载 Codex 三线路切换器"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Codex 三线路切换器"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoLogo -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File ""{app}\CodexProviderSwitcher.ps1"""; WorkingDir: "{app}"; IconFilename: "{sys}\shell32.dll"; IconIndex: 44; Tasks: desktopicon

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoLogo -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File ""{app}\CodexProviderSwitcher.ps1"""; WorkingDir: "{app}"; Description: "启动 Codex 三线路切换器 / Launch Codex switcher"; Flags: postinstall nowait skipifsilent

; =====================================================================
; Inno Setup Script for Munajjam Quran Alignment Desktop (منجم للتزمين القرآني)
; =====================================================================

#define MyAppName "منجم - التزمين القرآني الذكي"
#define MyAppNameEn "Munajjam Quran Alignment"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "علي ملص (Itqan Projects)"
#define MyAppURL "https://github.com/alinice1998/colabwis"
#define MyAppExeName "munajjam_desktop.exe"

[Setup]
; App Identity
AppId={{D37F881A-6A34-4C21-B4B2-12499FFB4391}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}

; Destination Directories
DefaultDirName={autopf}\{#MyAppNameEn}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes

; Visuals & Icons
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}

; Output Settings
OutputDir=..\installer_output
OutputBaseFilename=Munajjam_Desktop_Setup_v{#MyAppVersion}
Compression=lzma2/fast
SolidCompression=no
WizardStyle=modern

; Metadata / Version Info
VersionInfoVersion=1.0.0.0
VersionInfoCompany=علي ملص - Itqan Projects
VersionInfoDescription=منصة منجم للتزمين القرآني الذكي بالذكاء الاصطناعي
VersionInfoCopyright=Copyright (C) 2026 Ali Mallas (علي ملص). All rights reserved.
VersionInfoProductName=منجم - التزمين القرآني الذكي
VersionInfoProductVersion=1.0.0

; Permissions & Architecture
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest

[Languages]
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; 1. Flutter Release Windows Binaries
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; 2. Python Backend & Engine Scripts
Source: "..\munajjam_server.py"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\neural_aligner.py"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\start_server_gpu1.bat"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "..\ffmpeg.exe"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "..\requirements.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\hybrid_aligner\*"; DestDir: "{app}\hybrid_aligner"; Flags: ignoreversion recursesubdirs createallsubdirs

; 3. Embedded Python Runtime (100% Standalone Offline)
Source: "..\python_runtime\*"; DestDir: "{app}\python_runtime"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist
Source: "..\backend\*"; DestDir: "{app}\backend"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist

; 4. Data & Quran Text
Source: "..\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

; 5. Optimized AI Models (ONNX Engines Only - Excludes Redundant PyTorch .bin/.safetensors/.cache)
Source: "..\model_zipformer\*"; DestDir: "{app}\model_zipformer"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\model_wav2vec2\*"; DestDir: "{app}\model_wav2vec2"; Excludes: "pytorch_model.bin, *.pt"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\model_segmenter\*"; DestDir: "{app}\model_segmenter"; Excludes: ".cache, *.safetensors, *.pt"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\model_vad\*"; DestDir: "{app}\model_vad"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{group}\تشغيل خادم الذكاء الاصطناعي يدوياً (GPU 1)"; Filename: "{app}\start_server_gpu1.bat"; WorkingDir: "{app}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon; WorkingDir: "{app}"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

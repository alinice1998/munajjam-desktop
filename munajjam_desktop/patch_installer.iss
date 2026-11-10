; Updates the embedded-Python installation distributed after a0bc76b.
; Models, Python runtime, user settings and alignment projects are not payloads.
#define MyAppVersion "1.0.2"
#define MyAppExeName "munajjam_desktop.exe"

[Setup]
AppId={{D37F881A-6A34-4C21-B4B2-12499FFB4391}
AppName=Munajjam Quran Alignment - Update
AppVersion={#MyAppVersion}
AppPublisher=Itqan Projects
DefaultDirName={autopf}\Munajjam Quran Alignment
UsePreviousAppDir=yes
DisableDirPage=no
DisableProgramGroupPage=yes
DirExistsWarning=no
Uninstallable=no
CreateUninstallRegKey=no
SetupIconFile=windows\runner\resources\app_icon.ico
OutputDir=..\installer_output
OutputBaseFilename=Munajjam_Desktop_Patch_v{#MyAppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes
RestartApplications=no
VersionInfoVersion=1.0.2.0
VersionInfoDescription=Munajjam desktop update: audio timing and editor improvements
InfoBeforeFile=patch_notes.txt

[Languages]
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
arabic.InvalidInstall=اختر مجلد تثبيت منجم الحالي الذي يحتوي على munajjam_desktop.exe وmunajjam_server.py وpython_runtime. هذا تحديث للنسخة الكاملة وليس تثبيتًا مستقلًا.
english.InvalidInstall=Select your existing Munajjam installation containing munajjam_desktop.exe, munajjam_server.py and python_runtime. This update requires the full embedded-Python installation.
arabic.FrozenBackend=تحتوي هذه النسخة على خادم تنفيذي مستقل. هذا الباتش مخصص للنسخة التي تستخدم python_runtime؛ تحديث ملفات بايثون وحدها لن يحدّث الخادم التنفيذي.
english.FrozenBackend=This installation contains a standalone server executable. This patch supports the embedded-Python release; Python source updates cannot update a compiled server.

[Files]
; Flutter's executable, DLLs and data/app.so must be updated together.
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Updated engine, including the new alignment_confidence.py module.
Source: "..\hybrid_aligner\*.py"; DestDir: "{app}\hybrid_aligner"; Flags: ignoreversion
Source: "..\munajjam_server.py"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\neural_aligner.py"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\quran_metadata.py"; DestDir: "{app}"; Flags: ignoreversion
; Required by the audio normalization and waveform extraction improvements.
Source: "..\ffmpeg.exe"; DestDir: "{app}"; Flags: ignoreversion

[Code]
function InstallationError: String;
var
  InstallDir: String;
begin
  InstallDir := WizardDirValue;
  Result := '';
  if not FileExists(InstallDir + '\{#MyAppExeName}') or
     not FileExists(InstallDir + '\munajjam_server.py') or
     not FileExists(InstallDir + '\python_runtime\pythonw.exe') then
    Result := CustomMessage('InvalidInstall')
  else if FileExists(InstallDir + '\backend\munajjam_server.exe') or
          FileExists(InstallDir + '\munajjam_server.exe') then
    Result := CustomMessage('FrozenBackend');
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  ErrorMessage: String;
begin
  Result := True;
  if CurPageID = wpSelectDir then begin
    ErrorMessage := InstallationError;
    if ErrorMessage <> '' then begin
      MsgBox(ErrorMessage, mbError, MB_OK);
      Result := False;
    end;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := InstallationError;
end;

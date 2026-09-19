@echo off
chcp 65001 > nul
title "Munajjam AI Server - Dedicated GPU 1"
color 0A

echo ====================================================================
echo          Munajjam Quran Alignment - AI Neural Server [GPU 1]
echo ====================================================================
echo.
echo [*] Forcing Execution on Dedicated High-Performance GPU [Device 1]...

cd /d "%~dp0"

REM Remove Mark of the Web from all files
powershell -ExecutionPolicy Bypass -NoProfile -Command "Get-ChildItem -LiteralPath '%~dp0' -Recurse -ErrorAction SilentlyContinue | Unblock-File" >nul 2>&1

set "CUDA_VISIBLE_DEVICES=1"
set "DML_DEVICE_ID=1"
set "GPU_DEVICE_ID=1"
set "DIRECTML_DEVICE_ID=1"

if exist "%~dp0python_runtime\python.exe" (
    echo [+] Found embedded standalone python runtime.
    set "PY_CMD=%~dp0python_runtime\python.exe"
) else if exist "%~dp0backend\munajjam_server.exe" (
    echo [+] Launching backend\munajjam_server.exe...
    "%~dp0backend\munajjam_server.exe" --host 127.0.0.1 --port 8000
    goto finish
) else if exist "%~dp0munajjam_server.exe" (
    echo [+] Launching munajjam_server.exe...
    "%~dp0munajjam_server.exe" --host 127.0.0.1 --port 8000
    goto finish
) else (
    echo [!] Falling back to system python...
    set "PY_CMD=python"
)

if not exist "%~dp0munajjam_server.py" (
    echo [X] ERROR: munajjam_server.py not found in this folder!
    echo     Please make sure to place this file inside Munajjam installation folder.
    goto finish
)

echo [*] Starting server on: http://127.0.0.1:8000
echo [*] Once online, launch Munajjam Desktop Flutter app. It will connect automatically.
echo --------------------------------------------------------------------
echo.

"%PY_CMD%" "%~dp0munajjam_server.py" --host 127.0.0.1 --port 8000

:finish
echo.
echo ====================================================================
echo Server stopped or an error occurred.
echo ====================================================================
pause

@echo off
chcp 65001 > nul
title تشغيل خادم منجم القرآني (الكرت المنفصل GPU 1)
color 0A

echo ====================================================================
echo          منصة منجم للتزمين القرآني الذكي - خادم الذكاء الاصطناعي
echo ====================================================================
echo.
echo [*] ضبط التشغيل على كرت الشاشة المنفصل عالي الأداء (GPU 1)...

:: الانتقال التلقائي لمجلد البرنامج الرئيسي
cd /d "%~dp0"

:: فك حظر ملفات البرنامج المنزلة من الإنترنت تلقائياً (إزالة قيد Zone.Identifier)
echo [*] فك قيد الحماية عن ملفات ومكتبات البرنامج...
powershell -ExecutionPolicy Bypass -NoProfile -Command "Get-ChildItem -Path '%~dp0' -Recurse -ErrorAction SilentlyContinue | Unblock-File" 2>nul

:: ضبط معرف كرت الشاشة المنفصل (GPU 1) لجميع المحركات (DirectML و CUDA و PyTorch)
set "CUDA_VISIBLE_DEVICES=1"
set "DML_DEVICE_ID=1"
set "GPU_DEVICE_ID=1"
set "DIRECTML_DEVICE_ID=1"

:: التحقق من وجود بيئة بايثون المدمجة المستقلة
if exist "python_runtime\python.exe" (
    echo [+] تم العثور على بيئة بايثون المدمجة مع البرنامج.
    set "PY_CMD=python_runtime\python.exe"
) else if exist "backend\munajjam_server.exe" (
    echo [+] تشغيل ملف السيرفر المجمع backend\munajjam_server.exe...
    backend\munajjam_server.exe --host 127.0.0.1 --port 8000
    goto finish
) else if exist "munajjam_server.exe" (
    echo [+] تشغيل ملف السيرفر المجمع munajjam_server.exe...
    munajjam_server.exe --host 127.0.0.1 --port 8000
    goto finish
) else (
    echo [!] جاري المحاولة عبر بايثون النظام...
    set "PY_CMD=python"
)

if not exist "munajjam_server.py" (
    echo [X] خطأ: لم يتم العثور على ملف munajjam_server.py في هذا المجلد!
    echo     تأكد من وضع هذا الملف داخل مجلد تثبيت برنامج منجم.
    goto finish
)

echo [*] جاري تشغيل السيرفر العصبي على الرابط: http://127.0.0.1:8000
echo [*] بمجرد إقلاع السيرفر، افتح تطبيق فلاتر (Munajjam Desktop) وسيتصل به تلقائياً.
echo --------------------------------------------------------------------
echo.

%PY_CMD% munajjam_server.py --host 127.0.0.1 --port 8000

:finish
echo.
echo ====================================================================
echo تم إيقاف الخادم أو حدث خطأ أثناء التشغيل.
echo ====================================================================
pause

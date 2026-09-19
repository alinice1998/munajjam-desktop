@echo off
chcp 65001 > nul
echo ========================================================
echo   تشغيل خادم مُنجّم للتزمين القرآني (Munajjam Engine)
echo ========================================================
echo.

:: الانتقال إلى مجلد الباك اند
cd /d "%~dp0backend"

:: 1. التحقق من وجود بايثون
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [X] لم يتم العثور على بايثون مثبت في جهازك.
    echo يرجى تثبيت Python 3.9+ أولاً.
    pause
    exit /b
)

:: 2. تثبيت الحزم المطلوبة
echo [*] فحص وتثبيت المتطلبات من requirements.txt...
pip install -r requirements.txt

:: 3. تحميل النماذج إذا لم تكن موجودة
if not exist "..\model_zipformer\tokens.txt" if not exist "model_zipformer\tokens.txt" (
    echo [*] جاري تحميل ملفات النموذج من Hugging Face...
    python download_models.py
)

:: 4. تشغيل السيرفر
echo.
echo [*] جاري تشغيل خادم الذكاء الاصطناعي...
echo الرابط المحلي: http://localhost:8000
echo.
python munajjam_server.py

pause

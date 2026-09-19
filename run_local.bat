@echo off
chcp 65001 > nul
echo ========================================================
echo   تشغيل خادم مُنجّم للتزمين القرآني (Munajjam Engine)
echo ========================================================
echo.

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

:: 3. تحميل النموذج إذا لم يكن محملاً
if not exist "model_zipformer\tokens.txt" (
    echo [*] جاري تحميل ملفات النموذج من Hugging Face...
    python download_model.py
)

:: 4. تشغيل السيرفر
echo.
echo [*] جاري تشغيل الخادم المحلي...
echo الرابط المحلي للواجهة: http://localhost:8000
echo.
python munajjam_server.py

pause

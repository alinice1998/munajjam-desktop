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

:: 3. التحقق من وجود النماذج العصبية وتحميلها
if not exist "model_zipformer\tokens.txt" goto download_models
if not exist "model_segmenter\model.onnx" goto download_models
if not exist "model_vad\silero_vad.onnx" goto download_models
goto start_server

:download_models
echo [*] جاري فحص وتحميل نماذج الذكاء الاصطناعي (ONNX) من Hugging Face...
python download_models.py
if %errorlevel% neq 0 (
    echo [X] فشل في تحميل النماذج. يرجى التحقق من اتصال الإنترنت.
    pause
    exit /b
)

:start_server
:: 4. تشغيل السيرفر
echo.
echo [*] جاري تشغيل الخادم المحلي...
echo الرابط المحلي للواجهة: http://localhost:8000
echo.
python munajjam_server.py

pause

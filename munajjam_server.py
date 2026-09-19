"""
خادم تزمين ومحاذاة التلاوة القرآنية بالذكاء الاصطناعي لمنصة وتطبيق مُنجّم
FastAPI Server for Munajjam Quranic Audio Alignment Engine
"""

import os
import sys

# Ensure UTF-8 output on Windows consoles
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

import re
import json
import time
import shutil
import tempfile
import threading
import subprocess
from contextlib import asynccontextmanager
from typing import List, Optional, Dict, Any

from fastapi import FastAPI, UploadFile, File, Form, HTTPException, BackgroundTasks
from fastapi.responses import JSONResponse, FileResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

import soundfile as sf
import numpy as np

# Import our neural aligner
from neural_aligner import ZipformerNeuralAligner

# Base Paths
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_DIR = os.path.join(BASE_DIR, "model_zipformer")
DATA_DIR = os.path.join(BASE_DIR, "data")

aligner_instance: Optional[ZipformerNeuralAligner] = None
hybrid_aligner_instance: Optional[Any] = None
model_error: Optional[str] = None
JOBS: Dict[str, Dict[str, Any]] = {}

ALIGN_LOCK = threading.Lock()

def get_aligner() -> ZipformerNeuralAligner:
    global aligner_instance, model_error
    if aligner_instance is None:
        try:
            aligner_instance = ZipformerNeuralAligner(MODEL_DIR)
        except Exception as e:
            model_error = str(e)
            print(f"[-] Error loading Zipformer aligner: {e}")
            raise e
    return aligner_instance

def get_hybrid_aligner():
    global hybrid_aligner_instance, model_error
    if hybrid_aligner_instance is None:
        try:
            from hybrid_aligner import HybridQuranAligner
            wav2vec2_dir = os.path.join(BASE_DIR, "model_wav2vec2")
            target_model = wav2vec2_dir if (os.path.exists(wav2vec2_dir) and (os.path.exists(os.path.join(wav2vec2_dir, "model.onnx")) or os.path.exists(os.path.join(wav2vec2_dir, "config.json")))) else "jonatasgrosman/wav2vec2-large-xlsr-53-arabic"
            segmenter_dir = os.path.join(BASE_DIR, "model_segmenter")
            hybrid_aligner_instance = HybridQuranAligner(
                zipformer_dir=MODEL_DIR,
                wav2vec2_dir_or_name=target_model,
                segmenter_dir_or_name=segmenter_dir
            )
        except Exception as e:
            print(f"[-] Error loading Hybrid aligner: {e}")
            raise e
    return hybrid_aligner_instance

@asynccontextmanager
async def lifespan(app: FastAPI):
    try:
        print("[*] Pre-loading Zipformer neural aligner...")
        get_aligner()
    except Exception as e:
        print(f"[-] Startup Zipformer initialization note: {e}")
    try:
        print("[*] Pre-loading Next-Gen Hybrid neural aligner (Segmenter v2 + Zipformer + Wav2Vec2 on GPU)...")
        get_hybrid_aligner()
    except Exception as e:
        print(f"[-] Startup Hybrid initialization note: {e}")
    yield

app = FastAPI(
    title="Munajjam Quran Audio Alignment Server",
    description="خادم تزمين ومحاذاة التلاوة القرآنية بالذكاء الاصطناعي لتطبيق مُنجّم (Munajjam Engine)",
    version="2.0.0",
    lifespan=lifespan
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def load_quran_surah_text(surah_id: int, riwaya: str = "hafsh") -> List[str]:
    """تحميل نصوص الآيات للسورة المحددة من ملفات البيانات المحلية"""
    json_path = os.path.join(DATA_DIR, f"quran_{riwaya}.json")
    if not os.path.exists(json_path):
        json_path = os.path.join(DATA_DIR, "quran_hafsh.json")
    
    if not os.path.exists(json_path):
        return []
        
    try:
        with open(json_path, "r", encoding="utf-8") as f:
            data = json.load(f)
            
        # Dictionary format: {"112": ["...", "..."]}
        if isinstance(data, dict):
            key = str(surah_id)
            if key in data:
                val = data[key]
                if isinstance(val, list):
                    return [str(a).strip() for a in val if str(a).strip()]
                elif isinstance(val, str):
                    return [a.strip() for a in re.split(r'\s*\(\d+\)\s*', val) if a.strip()]

        # List format: [{"id": 112, "text": "..."}]
        if isinstance(data, list):
            for item in data:
                if isinstance(item, dict) and (item.get("id") == surah_id or item.get("surah_id") == surah_id):
                    raw_text = item.get("text", "")
                    if raw_text:
                        return [a.strip() for a in re.split(r'\s*\(\d+\)\s*', raw_text) if a.strip()]
                    elif "ayahs" in item and isinstance(item["ayahs"], list):
                        return [str(a).strip() for a in item["ayahs"] if str(a).strip()]
        return []
    except Exception as e:
        print(f"[-] Error loading surah text from {json_path}: {e}")
        return []

# Mount static files (Web GUI / Assets)
if os.path.exists(os.path.join(BASE_DIR, "css")):
    app.mount("/css", StaticFiles(directory=os.path.join(BASE_DIR, "css")), name="css")
if os.path.exists(os.path.join(BASE_DIR, "js")):
    app.mount("/js", StaticFiles(directory=os.path.join(BASE_DIR, "js")), name="js")
if os.path.exists(os.path.join(BASE_DIR, "data")):
    app.mount("/data", StaticFiles(directory=os.path.join(BASE_DIR, "data")), name="data")

@app.get("/")
def read_root():
    index_file = os.path.join(BASE_DIR, "index.html")
    if os.path.exists(index_file):
        return FileResponse(index_file)
    return health_check()

@app.get("/health")
def health_check():
    loaded = aligner_instance is not None and aligner_instance.recognizer is not None
    
    # Provider & GPU detection
    providers = []
    try:
        import onnxruntime as ort
        providers = ort.get_available_providers()
    except Exception:
        pass

    has_gpu = "CUDAExecutionProvider" in providers or "DmlExecutionProvider" in providers
    provider_name = "NVIDIA CUDA Acceleration" if "CUDAExecutionProvider" in providers else (
        "DirectML Hardware Acceleration (GPU)" if "DmlExecutionProvider" in providers else "CPU Execution Provider"
    )

    return {
        "status": "online",
        "service": "Munajjam Quran Audio Alignment Server",
        "model_loaded": loaded,
        "tokens_count": len(aligner_instance.tokens_dict) if aligner_instance else 0,
        "has_gpu": has_gpu,
        "provider_name": provider_name,
        "providers": providers,
        "error": model_error
    }

def convert_audio_to_wav(input_path: str, output_path: str) -> bool:
    """تحويل أي صيغة صوتية إلى WAV 16kHz Mono بسرعة فائقة باستخدام FFmpeg أو SoundFile"""
    # 1. التجربة الأولى: FFmpeg الفائق السرعة (أقل من ثانية وبدون إظهار أي نافذة كونسول)
    try:
        import subprocess
        local_ffmpeg = os.path.join(BASE_DIR, "ffmpeg.exe")
        ffmpeg_bin = local_ffmpeg if os.path.exists(local_ffmpeg) else "ffmpeg"
        kwargs = {}
        if sys.platform == "win32":
            kwargs["creationflags"] = subprocess.CREATE_NO_WINDOW
        cmd = [
            ffmpeg_bin, "-y", "-i", input_path,
            "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le",
            output_path
        ]
        res = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, **kwargs)
        if res.returncode == 0 and os.path.exists(output_path) and os.path.getsize(output_path) > 0:
            return True
    except Exception:
        pass

    # 2. التجربة الثانية: SoundFile السريع والمباشر
    try:
        data, samplerate = sf.read(input_path)
        if len(data.shape) > 1:
            data = np.mean(data, axis=1)
        if samplerate != 16000:
            import librosa
            data = librosa.resample(data, orig_sr=samplerate, target_sr=16000)
        sf.write(output_path, data, 16000, subtype='PCM_16')
        return True
    except Exception:
        pass

    # 3. التجربة الثالثة: pydub
    try:
        from pydub import AudioSegment
        audio = AudioSegment.from_file(input_path)
        audio = audio.set_frame_rate(16000).set_channels(1).set_sample_width(2)
        audio.export(output_path, format="wav")
        return True
    except Exception as e:
        print(f"[-] All audio conversion methods failed: {e}")
        return False

def _run_alignment_job(
    job_id: str,
    wav_path: str,
    temp_dir: str,
    ayahs: List[str],
    surah_id: int,
    reference_text: Optional[str],
    chunk_duration: float,
    min_silence_ms: Optional[int],
    min_speech_ms: Optional[int],
    pad_ms: Optional[int],
    method: str = "hybrid",
    repetition_attach: str = "next"
):
    """دالة المعالجة في الخلفية لتحديث نسبة التقدم اللحظية بدقة متناهية"""
    try:
        def update_progress(percent: float, message: str, stage: str = "aligning", current_sec: float = 0.0, total_sec: float = 0.0):
            JOBS[job_id]["progress"] = round(percent, 2)
            JOBS[job_id]["message"] = message
            JOBS[job_id]["stage"] = stage
            JOBS[job_id]["current_seconds"] = round(current_sec, 2)
            JOBS[job_id]["total_seconds"] = round(total_sec, 2)

        update_progress(5.0, "جاري تهيئة نموذج الذكاء الاصطناعي والمسرع الرسومي DirectML...", stage="preparing")

        with ALIGN_LOCK:
            if method == "zipformer":
                aligner = get_aligner()
                res = aligner.align_audio_with_progress(
                    wav_path=wav_path,
                    ayahs=ayahs,
                    surah_id=surah_id,
                    reference_text=reference_text,
                    chunk_duration=chunk_duration,
                    progress_callback=update_progress
                )
            else:
                hybrid_aligner = get_hybrid_aligner()
                res = hybrid_aligner.align_recitation(
                    wav_path=wav_path,
                    ayahs_raw=ayahs,
                    surah_id=surah_id,
                    reference_text=reference_text,
                    chunk_duration=chunk_duration,
                    progress_callback=update_progress,
                    min_silence_ms=min_silence_ms,
                    min_speech_ms=min_speech_ms,
                    pad_ms=pad_ms,
                    method=method,
                    repetition_attach=repetition_attach
                )

        JOBS[job_id]["status"] = "completed"
        JOBS[job_id]["progress"] = 100.0
        JOBS[job_id]["stage"] = "finished"
        JOBS[job_id]["message"] = "اكتمل التزمين بنجاح فائق الدقة"
        JOBS[job_id]["result"] = res

    except Exception as e:
        import traceback
        traceback.print_exc()
        JOBS[job_id]["status"] = "failed"
        JOBS[job_id]["progress"] = 0.0
        JOBS[job_id]["stage"] = "error"
        JOBS[job_id]["error"] = str(e)
        JOBS[job_id]["message"] = f"خطأ في المعالجة: {str(e)}"
    finally:
        try:
            if os.path.exists(temp_dir):
                shutil.rmtree(temp_dir)
        except Exception:
            pass

@app.post("/align/job/{surah_id}")
async def create_align_job(
    surah_id: int,
    background_tasks: BackgroundTasks,
    file: Optional[UploadFile] = File(None),
    audio: Optional[UploadFile] = File(None),
    riwaya: str = Form("hafsh"),
    method: str = Form("hybrid"),
    chunk_duration: float = Form(2.0),
    min_silence_ms: Optional[int] = Form(None),
    min_speech_ms: Optional[int] = Form(None),
    pad_ms: Optional[int] = Form(None),
    reference_text: Optional[str] = Form(None),
    ayahs_text: Optional[str] = Form(None),
    repetition_attach: str = Form("next")
):
    """
    نقطة النهاية المستخدمة من تطبيق فلاتر لبدء مهمة التزمين
    """
    upload_file = file or audio
    if upload_file is None:
        raise HTTPException(status_code=400, detail="يرجى إرفاق الملف الصوتي (file أو audio)")
        
    job_id = f"job_{int(time.time() * 1000)}_{os.urandom(4).hex()}"
    
    # 1. التحقق من نصوص الآيات
    ayahs = []
    if ayahs_text and ayahs_text.strip():
        ayahs = [a.strip() for a in ayahs_text.strip().split("\n") if a.strip()]
    else:
        ayahs = load_quran_surah_text(surah_id, riwaya)
        
    if not ayahs:
        raise HTTPException(status_code=400, detail="لم يتم العثور على نصوص الآيات المطلوبة للتزمين.")

    # 2. حفظ الملف الصوتي
    temp_dir = tempfile.mkdtemp(prefix="munajjam_job_")
    orig_ext = os.path.splitext(upload_file.filename)[1] if upload_file.filename else ".mp3"
    input_path = os.path.join(temp_dir, f"input{orig_ext}")
    wav_path = os.path.join(temp_dir, "audio.wav")

    with open(input_path, "wb") as buffer:
        shutil.copyfileobj(upload_file.file, buffer)

    # 3. التحويل إلى WAV 16kHz
    if not convert_audio_to_wav(input_path, wav_path):
        shutil.rmtree(temp_dir)
        raise HTTPException(status_code=400, detail="فشل تحويل الملف الصوتي إلى صيغة WAV.")

    # 4. تسجيل المهمة
    JOBS[job_id] = {
        "status": "processing",
        "progress": 5.0,
        "stage": "starting",
        "message": "جاري بدء المعالجة بالذكاء الاصطناعي...",
        "current_seconds": 0.0,
        "total_seconds": 0.0,
        "result": None,
        "error": None,
        "start_time": time.time()
    }

    # 5. إطلاق المهمة في الخلفية
    background_tasks.add_task(
        _run_alignment_job,
        job_id=job_id,
        wav_path=wav_path,
        temp_dir=temp_dir,
        ayahs=ayahs,
        surah_id=surah_id,
        reference_text=reference_text,
        chunk_duration=chunk_duration,
        min_silence_ms=min_silence_ms,
        min_speech_ms=min_speech_ms,
        pad_ms=pad_ms,
        method=method,
        repetition_attach=repetition_attach
    )

    return {
        "status": "success",
        "job_id": job_id,
        "message": "تم استلام الملف الصوتي وبدء التزمين في الخلفية بنجاح"
    }

@app.get("/align/status/{job_id}")
@app.get("/job-status/{job_id}")
def get_align_job_status(job_id: str):
    """
    استعلام عن حالة وتقدم مهمة التزمين بدعم كامل لتطبيق فلاتر والويب
    """
    if job_id not in JOBS:
        raise HTTPException(status_code=404, detail="المهمة غير موجودة أو انتهت صلاحيتها")
        
    job = JOBS[job_id]
    status_str = "success" if job["status"] == "completed" else job["status"]
    
    res = job.get("result") or {}
    ayahs_data = res.get("data") or res.get("ayahs") or []
    breath_groups = res.get("breath_groups") or []
    
    return {
        "job_id": job_id,
        "status": status_str,
        "progress": int(job["progress"]),
        "message": job["message"],
        "stage": job.get("stage", "processing"),
        "data": ayahs_data,
        "breath_groups": breath_groups,
        "result": res,
        "error": job.get("error")
    }

@app.post("/align-async")
async def align_audio_async(
    background_tasks: BackgroundTasks,
    audio: Optional[UploadFile] = File(None),
    file: Optional[UploadFile] = File(None),
    ayahs_text: Optional[str] = Form(None),
    surah_id: int = Form(1),
    riwaya: str = Form("hafsh"),
    chunk_duration: float = Form(2.0),
    min_silence_ms: Optional[int] = Form(None),
    min_speech_ms: Optional[int] = Form(None),
    pad_ms: Optional[int] = Form(None),
    method: str = Form("hybrid")
):
    upload_file = audio or file
    if upload_file is None:
        raise HTTPException(status_code=400, detail="يرجى إرفاق الملف الصوتي")
    return await create_align_job(
        surah_id=surah_id,
        background_tasks=background_tasks,
        file=upload_file,
        riwaya=riwaya,
        method=method,
        chunk_duration=chunk_duration,
        min_silence_ms=min_silence_ms,
        min_speech_ms=min_speech_ms,
        pad_ms=pad_ms,
        ayahs_text=ayahs_text
    )

@app.post("/align")
async def align_audio_endpoint(
    audio: UploadFile = File(...),
    ayahs_text: Optional[str] = Form(None),
    surah_id: int = Form(1),
    riwaya: str = Form("hafsh"),
    chunk_duration: float = Form(2.0),
    min_silence_ms: Optional[int] = Form(None),
    min_speech_ms: Optional[int] = Form(None),
    pad_ms: Optional[int] = Form(None),
    method: str = Form("hybrid")
):
    """
    نقطة النهاية المتزامنة للمحاذاة المباشرة
    """
    ayahs = []
    if ayahs_text and ayahs_text.strip():
        ayahs = [a.strip() for a in ayahs_text.strip().split("\n") if a.strip()]
    else:
        ayahs = load_quran_surah_text(surah_id, riwaya)
        
    if not ayahs:
        raise HTTPException(status_code=400, detail="لم يتم العثور على نصوص الآيات المطلوبة للتزمين.")

    temp_dir = tempfile.mkdtemp(prefix="munajjam_direct_")
    try:
        orig_ext = os.path.splitext(audio.filename)[1] if audio.filename else ".mp3"
        input_path = os.path.join(temp_dir, f"input{orig_ext}")
        wav_path = os.path.join(temp_dir, "audio.wav")

        with open(input_path, "wb") as buffer:
            shutil.copyfileobj(audio.file, buffer)

        if not convert_audio_to_wav(input_path, wav_path):
            raise HTTPException(status_code=400, detail="فشل تحويل الملف الصوتي إلى صيغة WAV.")

        with ALIGN_LOCK:
            if method == "zipformer":
                aligner = get_aligner()
                res = aligner.align_audio_with_progress(
                    wav_path=wav_path,
                    ayahs=ayahs,
                    surah_id=surah_id,
                    reference_text=None,
                    chunk_duration=chunk_duration
                )
            else:
                hybrid_aligner = get_hybrid_aligner()
                res = hybrid_aligner.align_recitation(
                    wav_path=wav_path,
                    ayahs_raw=ayahs,
                    surah_id=surah_id,
                    reference_text=None,
                    chunk_duration=chunk_duration,
                    min_silence_ms=min_silence_ms,
                    min_speech_ms=min_speech_ms,
                    pad_ms=pad_ms,
                    method=method
                )

        return res

    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"خطأ أثناء معالجة التزمين: {str(e)}")
    finally:
        try:
            if os.path.exists(temp_dir):
                shutil.rmtree(temp_dir)
        except Exception:
            pass

@app.post("/shutdown")
def shutdown_server():
    """إيقاف الخادم بأمان عند إغلاق التطبيق"""
    def _kill():
        time.sleep(0.5)
        os._exit(0)
    threading.Thread(target=_kill, daemon=True).start()
    return {"status": "shutting_down", "message": "Server is stopping..."}

def main():
    import uvicorn
    import argparse
    
    parser = argparse.ArgumentParser(description="Munajjam Quran Audio Alignment Server")
    parser.add_argument("--host", default="127.0.0.1", help="Host IP")
    parser.add_argument("--port", type=int, default=8000, help="Port")
    parser.add_argument("--parent-pid", type=int, default=None, help="Parent process PID to monitor")
    args = parser.parse_args()

    # If launched by Flutter desktop, monitor parent PID to auto-exit if Flutter closes
    if args.parent_pid:
        def monitor_parent():
            import psutil
            parent_pid = args.parent_pid
            while True:
                time.sleep(2)
                try:
                    if not psutil.pid_exists(parent_pid):
                        print(f"[*] Parent process {parent_pid} terminated. Exiting server...")
                        os._exit(0)
                except Exception:
                    pass
        try:
            threading.Thread(target=monitor_parent, daemon=True).start()
        except Exception:
            pass

    print(f"[*] Starting Munajjam Quran Alignment Server on http://{args.host}:{args.port}")
    uvicorn.run(app, host=args.host, port=args.port, log_level="warning")

if __name__ == "__main__":
    main()

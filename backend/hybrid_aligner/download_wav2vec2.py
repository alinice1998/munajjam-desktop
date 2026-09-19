"""
سكريبت تحميل ملفات نموذج Wav2Vec2 XLSR-53 العربي محلياً
Wav2Vec2 Arabic Model Downloader (Hugging Face -> model_wav2vec2/)
"""

import os
import sys

# Ensure UTF-8 output on Windows consoles
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGET_DIR = os.path.join(BASE_DIR, "model_wav2vec2")
MODEL_REPO = "jonatasgrosman/wav2vec2-large-xlsr-53-arabic"

def download_model():
    print("=" * 65)
    print(f"[*] جاري تحميل نموذج Wav2Vec2 العربي من Hugging Face:")
    print(f"[*] المستودع: {MODEL_REPO}")
    print(f"[*] مسار الحفظ المحلي: {TARGET_DIR}")
    print("=" * 65)

    os.makedirs(TARGET_DIR, exist_ok=True)

    try:
        from huggingface_hub import snapshot_download
        print("\n[*] جاري بدء التحميل (يرجى الانتظار بضع دقائق، حجم الأوزان ~1.2GB)...")
        snapshot_download(
            repo_id=MODEL_REPO,
            local_dir=TARGET_DIR,
            local_dir_use_symlinks=False,
            ignore_patterns=["*.msgpack", "*.h5", "flax_model.msgpack", "*.onnx"]
        )
        print("\n" + "=" * 65)
        print("[+] تم تحميل ملفات النموذج بنجاح داخل المجلد:")
        print(f"    {TARGET_DIR}")
        print("=" * 65)
    except Exception as e:
        print(f"\n[X] حدث خطأ أثناء التحميل: {e}")
        print("\nيمكنك أيضاً تحميل الملفات يدوياً من الرابط التالي ووضعها في مجلد model_wav2vec2:")
        print(f"👉 https://huggingface.co/{MODEL_REPO}/tree/main")

if __name__ == "__main__":
    download_model()

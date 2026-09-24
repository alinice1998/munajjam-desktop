"""
سكربت تحميل نموذج تقطيع التلاوة القرآنية ومواضع الوقف recitation-segmenter-v2 بصيغة ONNX
Munajjam Recitation Segmenter ONNX Downloader
المستودع الرسمي: https://huggingface.co/Alimalas/munajjam-onnx-models
"""

import os
import sys

# Ensure UTF-8 output on Windows consoles
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ID = "Alimalas/munajjam-onnx-models"

def download_segmenter(target_dir="model_segmenter"):
    print("=" * 65)
    print("🚀 بدء تحميل نموذج تقطيع الأنفاس recitation-segmenter-v2 (ONNX) من Hugging Face...")
    print(f"📦 المستودع: {REPO_ID}")
    print("=" * 65)

    try:
        from huggingface_hub import snapshot_download
    except ImportError:
        print("❌ مكتبة huggingface_hub غير مثبتة. يرجى تثبيتها عبر:")
        print("   pip install huggingface_hub")
        return False

    os.makedirs(target_dir, exist_ok=True)
    key_file = os.path.join(target_dir, "model.onnx")

    if os.path.exists(key_file):
        print(f"✅ نموذج التقطيع العصبي موجود مسبقاً في: {os.path.abspath(target_dir)}")
        return True

    print(f"📁 المجلد المستهدف: {os.path.abspath(target_dir)}")
    print("⏳ جاري التحميل...")

    try:
        snapshot_download(
            repo_id=REPO_ID,
            allow_patterns=["model_segmenter/*"],
            local_dir=BASE_DIR,
            local_dir_use_symlinks=False,
        )
        print("\n" + "=" * 65)
        print("✅ تم تحميل نموذج تقطيع الأنفاس بنجاح!")
        print(f"📂 المسار: {os.path.abspath(target_dir)}")
        print("=" * 65)
        return True
    except Exception as e:
        print(f"\n❌ حدث خطأ أثناء التحميل: {e}")
        return False

if __name__ == "__main__":
    download_segmenter()

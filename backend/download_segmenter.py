"""
سكربت تحميل نموذج تقطيع التلاوة recitation-segmenter-v2 من Hugging Face
Downloader for obadx/recitation-segmenter-v2
"""

import os
import sys

# Ensure UTF-8 output on Windows consoles
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

def download_segmenter(target_dir="model_segmenter"):
    print("=" * 60)
    print("🚀 بدء تحميل نموذج recitation-segmenter-v2 من Hugging Face...")
    print("=" * 60)
    
    try:
        from huggingface_hub import snapshot_download
    except ImportError:
        print("❌ مكتبة huggingface_hub غير مثبتة. يرجى تثبيتها عبر: pip install huggingface_hub")
        sys.exit(1)
        
    os.makedirs(target_dir, exist_ok=True)
    repo_id = "obadx/recitation-segmenter-v2"
    
    print(f"📦 المستودع: {repo_id}")
    print(f"📁 المجلد المستهدف: {os.path.abspath(target_dir)}")
    print("⏳ جاري التحميل...")
    
    try:
        download_path = snapshot_download(
            repo_id=repo_id,
            local_dir=target_dir,
            local_dir_use_symlinks=False,
            ignore_patterns=["*.git*"]
        )
        print("\n" + "=" * 60)
        print("✅ تم تحميل نموذج التقطيع بنجاح!")
        print(f"📂 المسار: {download_path}")
        print("=" * 60)
        return True
    except Exception as e:
        print(f"\n❌ حدث خطأ أثناء التحميل: {e}")
        return False

if __name__ == "__main__":
    download_segmenter()

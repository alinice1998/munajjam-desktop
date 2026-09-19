"""
سكربت تحميل نموذج QuranLab Zipformer v3 من Hugging Face
QuranLab/zipformer_p-arabic-v3 Model Downloader
"""

import os
import sys

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

def download_model(target_dir="model_zipformer", token=None):
    print("=" * 60)
    print("🚀 بدء تحميل نموذج QuranLab Zipformer v3 من Hugging Face...")
    print("=" * 60)
    
    try:
        from huggingface_hub import snapshot_download, HfFolder
    except ImportError:
        print("❌ مكتبة huggingface_hub غير مثبتة. يرجى تثبيتها عبر:")
        print("   pip install huggingface_hub")
        sys.exit(1)
        
    os.makedirs(target_dir, exist_ok=True)
    repo_id = "Quran-Lab/zipformer_p-arabic-v3"
    
    # Check for token in env or parameter or saved Hugging Face login
    hf_token = token or os.environ.get("HF_TOKEN") or HfFolder.get_token()
    
    print(f"📦 المستودع: {repo_id}")
    print(f"📁 المجلد المستهدف: {os.path.abspath(target_dir)}")
    print("⏳ جاري التحميل...")
    
    try:
        download_path = snapshot_download(
            repo_id=repo_id,
            local_dir=target_dir,
            local_dir_use_symlinks=False,
            token=hf_token,
            ignore_patterns=["*.git*", "*.safetensors.index.json"]
        )
        print("\n" + "=" * 60)
        print("✅ تم تحميل النموذج بنجاح!")
        print(f"📂 المسار: {download_path}")
        
        # Check important files
        files = os.listdir(target_dir)
        print(f"📄 الملفات الموجودة في المجلد ({len(files)} ملف):")
        for f in files:
            size_mb = os.path.getsize(os.path.join(target_dir, f)) / (1024 * 1024)
            print(f"   - {f} ({size_mb:.2f} MB)")
        print("=" * 60)
        return True
    except Exception as e:
        err_msg = str(e)
        print(f"\n❌ حدث خطأ أثناء التحميل: {err_msg}")
        if "restricted" in err_msg.lower() or "401" in err_msg or "gated" in err_msg.lower():
            print("\n" + "⚠️ " * 15)
            print("النموذج يتطلب تسجيل الدخول وقبول شروط الرخصة على Hugging Face:")
            print("1. افتح الرابط في المتصفح: https://huggingface.co/Quran-Lab/zipformer_p-arabic-v3")
            print("2. سجل دخول بحسابك واضغط زر الموافقة على شروط الاستخدام (Agree / Request Access).")
            print("3. احصل على Access Token من: https://huggingface.co/settings/tokens")
            print("4. أعد تشغيل السكربت ومرر التوكن أو نفذ الأمر: huggingface-cli login")
            print("⚠️ " * 15 + "\n")
            
            # Prompt user for token interactively
            try:
                user_token = input("👉 هل ترغب في إدخال Hugging Face Token الآن؟ (ألصق التوكن هنا أو اضغط Enter للإلغاء): ").strip()
                if user_token:
                    return download_model(target_dir, token=user_token)
            except Exception:
                pass
        return False

if __name__ == "__main__":
    download_model()

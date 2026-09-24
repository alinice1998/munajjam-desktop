"""
سكربت رفع نماذج مُنجّم الجاهزة (صيغة ONNX فائقة السرعة) إلى Hugging Face
Munajjam ONNX Models Uploader to Hugging Face Hub
المطور: علي ملص (Ali Malas)
"""

import os
import sys

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

from huggingface_hub import HfApi, login, get_token

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

def main():
    print("=" * 65)
    print("      🚀 مُنجّم: رفع نماذج الذكاء الاصطناعي إلى Hugging Face 🚀")
    print("=" * 65)

    token = get_token()
    if not token:
        print("❌ لم يتم العثور على رمز الدخول لـ Hugging Face!")
        return

    api = HfApi(token=token)
    user_info = api.whoami()
    username = user_info.get("name", "Alimalas")
    target_repo = f"{username}/munajjam-onnx-models"

    print(f"👤 الحساب المعتمد: {username} ({user_info.get('fullname', '')})")
    print(f"📦 المستودع المستهدف: https://huggingface.co/{target_repo}")
    print()

    # 1. إنشاء المستودع إن لم يكن موجوداً
    print("[1/3] التحقق من وجود مستودع النماذج أو إنشاؤه...")
    try:
        repo_url = api.create_repo(
            repo_id=target_repo,
            repo_type="model",
            exist_ok=True,
            private=False
        )
        print(f"✅ المستودع جاهز: {repo_url}")
    except Exception as e:
        print(f"[-] خطأ أثناء إنشاء المستودع: {e}")
        return

    # 2. إنشاء بطاقة النموذج Model Card (README.md)
    readme_content = f"""---
license: mit
language:
- ar
tags:
- quran
- audio-alignment
- onnx
- speech-recognition
- tajweed
pipeline_tag: automatic-speech-recognition
---

# Munajjam ONNX Models (نماذج منصة مُنجّم للتزمين القرآني)

This repository contains pre-exported, highly optimized **ONNX DirectML / CUDA** models for the [Munajjam Quran Alignment](https://github.com/alinice1998/colabwis) platform:

1. **recitation-segmenter-v2 (ONNX)**: Quranic breath & waqf neural segmenter based on Wav2Vec2-BERT.
2. **zipformer_p_arabic_v3 (ONNX)**: Ultra-fast phoneme and word-level alignment engine.
3. **silero_vad (ONNX)**: Voice activity detection.

Developed by **Ali Malas (علي ملص)** - Itqan Projects.
"""
    readme_path = os.path.join(BASE_DIR, "scratch", "HF_README.md")
    os.makedirs(os.path.dirname(readme_path), exist_ok=True)
    with open(readme_path, "w", encoding="utf-8") as f:
        f.write(readme_content)

    api.upload_file(
        path_or_fileobj=readme_path,
        path_in_repo="README.md",
        repo_id=target_repo,
        repo_type="model",
        commit_message="Add Munajjam Model Card"
    )

    # 3. رفع نموذج تقطيع الأنفاس ONNX (مع استثناء ملفات الكاش وملف safetensors الضخم غير المطلوب)
    segmenter_dir = os.path.join(BASE_DIR, "model_segmenter")
    if os.path.isdir(segmenter_dir):
        print("\n[1/4] جاري رفع ملفات نموذج تقطيع الأنفاس model_segmenter (ONNX)...")
        print("⏳ قد يستغرق هذا بضع دقائق بحسب سرعة الرفع لديك...")
        api.upload_folder(
            folder_path=segmenter_dir,
            path_in_repo="model_segmenter",
            repo_id=target_repo,
            repo_type="model",
            ignore_patterns=[".cache*", "*.safetensors", "*.pt", "*.7z"],
            commit_message="Upload recitation-segmenter-v2 ONNX engine"
        )
        print("✅ تم رفع نموذج تقطيع الأنفاس بنجاح!")

    # 4. رفع نموذج Zipformer
    zipformer_dir = os.path.join(BASE_DIR, "model_zipformer")
    if os.path.isdir(zipformer_dir):
        print("\n[2/4] جاري رفع نموذج Zipformer v3 (ONNX)...")
        api.upload_folder(
            folder_path=zipformer_dir,
            path_in_repo="model_zipformer",
            repo_id=target_repo,
            repo_type="model",
            commit_message="Upload zipformer_p_arabic_v3 ONNX model"
        )
        print("✅ تم رفع نموذج Zipformer بنجاح!")

    # 5. رفع نموذج Silero VAD
    vad_dir = os.path.join(BASE_DIR, "model_vad")
    if os.path.isdir(vad_dir):
        print("\n[3/4] جاري رفع نموذج كاشف النشاط الصوتي model_vad (ONNX)...")
        api.upload_folder(
            folder_path=vad_dir,
            path_in_repo="model_vad",
            repo_id=target_repo,
            repo_type="model",
            commit_message="Upload silero_vad ONNX model"
        )
        print("✅ تم رفع نموذج Silero VAD بنجاح!")

    # 6. رفع نموذج Wav2Vec2 ONNX
    wav2vec2_dir = os.path.join(BASE_DIR, "model_wav2vec2")
    if os.path.isdir(wav2vec2_dir):
        print("\n[4/4] جاري رفع نموذج model_wav2vec2 (ONNX)...")
        api.upload_folder(
            folder_path=wav2vec2_dir,
            path_in_repo="model_wav2vec2",
            repo_id=target_repo,
            repo_type="model",
            ignore_patterns=["pytorch_model.bin", "*.pt", "*.bin"],
            commit_message="Upload wav2vec2 ONNX model and configs"
        )
        print("✅ تم رفع نموذج Wav2Vec2 بنجاح!")

    print("\n" + "=" * 65)
    print("🎉 اكتمل رفع جميع النماذج بنجاح على حسابك في Hugging Face!")
    print(f"👉 الرابط: https://huggingface.co/{target_repo}")
    print("=" * 65)

if __name__ == "__main__":
    main()

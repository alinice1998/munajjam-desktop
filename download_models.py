"""
سكربت التحميل الشامل لنماذج منصة مُنجّم من Hugging Face
Munajjam Master Model Downloader
يقوم بتحميل:
1. نموذج Zipformer v3 للتزمين الصوتي (Quran-Lab/zipformer_p-arabic-v3)
2. نموذج تقطيع الأنفاس العصبي (obadx/recitation-segmenter-v2)
"""

import os
import sys

# Ensure UTF-8 output on Windows consoles
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

from download_model import download_model as download_zipformer
from download_segmenter import download_segmenter

def main():
    print("=" * 65)
    print("      🌟 مُنجّم: بدء تنزيل جميع نماذج الذكاء الاصطناعي 🌟")
    print("=" * 65)
    print()

    # 1. Download Zipformer v3
    print("[1/2] تحميل نموذج Zipformer v3...")
    zf_ok = download_zipformer()

    print()
    # 2. Download Recitation Segmenter v2
    print("[2/2] تحميل نموذج تقطيع الأنفاس recitation-segmenter-v2...")
    seg_ok = download_segmenter()

    print()
    print("=" * 65)
    if zf_ok and seg_ok:
        print("🎉 اكتمل تحميل وتجهيز كافة النماذج بنجاح!")
        print("يمكنك الآن إطلاق السيرفر وتطبيق مُنجّم مباشرة.")
    else:
        print("⚠️ تم الانتهاء مع بعض الملاحظات. تأكد من اتصال الإنترنت.")
    print("=" * 65)

if __name__ == "__main__":
    main()

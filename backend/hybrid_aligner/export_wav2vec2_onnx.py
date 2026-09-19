"""
تصدير نموذج Wav2Vec2 XLSR-53 العربي إلى صيغة ONNX الخفيفة
Export Wav2Vec2 XLSR-53 Arabic PyTorch weights to ONNX format
"""

import os
import sys
import json
import numpy as np

# Ensure UTF-8 output
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL_DIR = os.path.join(BASE_DIR, "model_wav2vec2")
ONNX_PATH = os.path.join(MODEL_DIR, "model.onnx")

def export_wav2vec2_to_onnx():
    print("=" * 65)
    print("[*] جاري تصدير نموذج Wav2Vec2 إلى صيغة ONNX...")
    print(f"[*] مسار النموذج المصدر: {MODEL_DIR}")
    print(f"[*] مسار ملف ONNX الناتج: {ONNX_PATH}")
    print("=" * 65)

    import torch
    from transformers import Wav2Vec2ForCTC

    print("[*] تحميل أوزان PyTorch من المجلد المحلي...")
    model = Wav2Vec2ForCTC.from_pretrained(MODEL_DIR)
    model.eval()

    # عينة صوتية وهمية للتحويل (1 ثانية عند 16kHz)
    dummy_input = torch.randn(1, 16000, dtype=torch.float32)

    print("[*] بدء عملية التصدير إلى ONNX مع دعم الأبعاد المتغيرة (Dynamic Axes)...")
    try:
        torch.onnx.export(
            model,
            dummy_input,
            ONNX_PATH,
            export_params=True,
            opset_version=14,
            do_constant_folding=True,
            input_names=["input_values"],
            output_names=["logits"],
            dynamic_axes={
                "input_values": {0: "batch_size", 1: "sequence_length"},
                "logits": {0: "batch_size", 1: "sequence_length"}
            },
            dynamo=False
        )
    except TypeError:
        torch.onnx.export(
            model,
            dummy_input,
            ONNX_PATH,
            export_params=True,
            opset_version=14,
            do_constant_folding=True,
            input_names=["input_values"],
            output_names=["logits"],
            dynamic_axes={
                "input_values": {0: "batch_size", 1: "sequence_length"},
                "logits": {0: "batch_size", 1: "sequence_length"}
            }
        )

    if os.path.exists(ONNX_PATH):
        size_mb = os.path.getsize(ONNX_PATH) / (1024 * 1024)
        print("\n" + "=" * 65)
        print(f"[+] تم تصدير ملف ONNX بنجاح تام! الحجم: {size_mb:.2f} MB")
        print(f"    {ONNX_PATH}")
        print("=" * 65)
        return True
    else:
        print("[X] فشل في إنشاء ملف ONNX.")
        return False

if __name__ == "__main__":
    export_wav2vec2_to_onnx()

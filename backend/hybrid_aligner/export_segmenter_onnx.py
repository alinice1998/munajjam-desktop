"""
تصدير نموذج recitation-segmenter-v2 إلى صيغة ONNX للتشغيل فائق السرعة عبر كرت الشاشة (DirectML / CUDA)
Export recitation-segmenter-v2 to ONNX format
"""

import os
import sys

# Ensure UTF-8 output on Windows consoles
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

import torch
from transformers import AutoModelForAudioFrameClassification

def export_segmenter_to_onnx(model_dir: str = None, output_path: str = None):
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    model_dir = model_dir or os.path.join(base_dir, "model_segmenter")
    output_path = output_path or os.path.join(model_dir, "model.onnx")

    print(f"[*] Loading model from {model_dir} for ONNX export...")
    model = AutoModelForAudioFrameClassification.from_pretrained(model_dir)
    model.eval()

    # Dummy input with 160 stacked filterbanks
    dummy_input = torch.randn(1, 100, 160, dtype=torch.float32)

    print(f"[*] Exporting to ONNX at {output_path} (opset 17)...")
    try:
        # Export with dynamic axes using TorchScript backend
        torch.onnx.export(
            model,
            (dummy_input,),
            output_path,
            input_names=["input_features"],
            output_names=["logits"],
            dynamic_axes={
                "input_features": {0: "batch_size", 1: "sequence_length"},
                "logits": {0: "batch_size", 1: "sequence_length"}
            },
            opset_version=17,
            do_constant_folding=True,
            dynamo=False
        )
        file_size_mb = os.path.getsize(output_path) / (1024 * 1024)
        print(f"[+] ONNX export successful! File size: {file_size_mb:.2f} MB")
        return True
    except Exception as e:
        print(f"[-] ONNX export error: {e}")
        return False

if __name__ == "__main__":
    export_segmenter_to_onnx()

"""
محرك التقطيع العصبي للأنفاس القرآنية باستخدام نموذج recitation-segmenter-v2
Quranic Breath & Waqf Neural Segmentation Engine (ONNX DirectML / CUDA / PyTorch)
"""

import os
import sys

# Ensure UTF-8 output on Windows consoles
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

import time
import gc
import json
import numpy as np
from typing import List, Dict, Any, Tuple, Optional

class QuranRecitationSegmenter:
    """
    محرك متخصص لتقطيع التلاوات القرآنية بحسب النَّفَس والوقف
    مبني على نموذج Wav2Vec2-BERT المخصص للتلاوة (recitation-segmenter-v2)
    يعمل بكفاءة وسرعة فائقة على كرت الشاشة (GPU).
    """

    def __init__(
        self,
        model_dir_or_name: Optional[str] = None,
        device: Optional[str] = None,
        min_silence_duration_ms: int = 200,
        min_speech_duration_ms: int = 750,
        pad_duration_ms: int = 30
    ):
        base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.model_dir = model_dir_or_name or os.path.join(base_dir, "model_segmenter")
        self.device = device
        self.min_silence_duration_ms = min_silence_duration_ms
        self.min_speech_duration_ms = min_speech_duration_ms
        self.pad_duration_ms = pad_duration_ms

        self.processor = None
        self.model = None
        self.onnx_session = None
        self.is_onnx = False
        self.torch_device = None
        self.torch_dtype = None

        self.load_model()

    def load_model(self):
        """تحميل نموذج التقطيع recitation-segmenter-v2 عبر ONNX DirectML على كرت الشاشة VRAM"""
        onnx_file = os.path.join(self.model_dir, "model.onnx") if os.path.isdir(self.model_dir) else None
        
        # 1. التشغيل عبر ONNX Runtime على كرت الشاشة GPU (VRAM)
        if onnx_file and os.path.exists(onnx_file):
            try:
                import onnxruntime as ort
                from transformers import AutoFeatureExtractor

                print(f"[+] Loading Quran Segmenter ONNX model into GPU VRAM: {onnx_file}")
                from .gpu_utils import get_ort_execution_providers
                providers = get_ort_execution_providers()

                sess_opts = ort.SessionOptions()
                sess_opts.enable_mem_pattern = True
                sess_opts.enable_cpu_mem_arena = True
                sess_opts.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
                sess_opts.intra_op_num_threads = min(8, os.cpu_count() or 4)

                self.onnx_session = ort.InferenceSession(onnx_file, sess_opts, providers=providers)
                self._cpu_session = None
                self.onnx_file = onnx_file
                self.processor = AutoFeatureExtractor.from_pretrained(self.model_dir)
                self.is_onnx = True
                active_provider = self.onnx_session.get_providers()[0]
                print(f"[+] Quran Segmenter ONNX Engine loaded into GPU VRAM with provider: {active_provider}")
                return
            except Exception as e_onnx:
                print(f"[-] ONNX GPU load note: {e_onnx}, attempting PyTorch...")

        # 2. خطة بديلة في حال عدم توفر ONNX
        import torch
        from transformers import AutoFeatureExtractor, AutoModelForAudioFrameClassification

        self.torch_device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        self.torch_dtype = torch.float32

        print(f"[+] Loading Quran Segmenter via PyTorch on {self.torch_device}...")
        self.processor = AutoFeatureExtractor.from_pretrained(self.model_dir)
        self.model = AutoModelForAudioFrameClassification.from_pretrained(self.model_dir)
        self.model.to(self.torch_device, dtype=self.torch_dtype)
        self.model.eval()
        self.is_onnx = False
        print(f"[+] Quran Segmenter Engine ready on {self.torch_device}")

    def segment_audio(
        self,
        audio: np.ndarray,
        sr: int = 16000,
        min_silence_ms: Optional[int] = None,
        min_speech_ms: Optional[int] = None,
        pad_ms: Optional[int] = None
    ) -> List[Dict[str, float]]:
        """
        تقطيع التسجيل الصوتي واستخراج فترات النَّفَس الصوتي الحقيقي بالثواني
        """
        if audio is None or len(audio) == 0:
            return []

        if len(audio.shape) > 1:
            audio = audio.mean(axis=1)

        if sr != 16000:
            import librosa
            audio = librosa.resample(audio, orig_sr=sr, target_sr=16000)
            sr = 16000

        total_dur = len(audio) / float(sr)
        min_silence = min_silence_ms if min_silence_ms is not None else self.min_silence_duration_ms
        min_speech = min_speech_ms if min_speech_ms is not None else self.min_speech_duration_ms
        pad_dur = pad_ms if pad_ms is not None else self.pad_duration_ms

        if self.is_onnx and self.onnx_session is not None:
            return self._segment_onnx_gpu(audio, sr, min_silence, min_speech, pad_dur, total_dur)

        # PyTorch fallback
        return self._segment_pytorch(audio, sr, min_silence, min_speech, pad_dur, total_dur)

    def _segment_onnx_gpu(
        self,
        audio: np.ndarray,
        sr: int,
        min_silence_ms: int,
        min_speech_ms: int,
        pad_ms: int,
        total_dur: float
    ) -> List[Dict[str, float]]:
        """
        معالجة فائقة السرعة على كرت الشاشة VRAM عبر ONNX DirectML
        """
        chunk_sec = 20.0
        chunk_samples = int(chunk_sec * sr)
        target_frames = int(chunk_sec * 50)  # 1000 frames for 20.0s (fixed DirectML shape)

        expected_total_frames = int(np.ceil(len(audio) / 320.0))
        all_preds = np.zeros(expected_total_frames, dtype=np.int32)
        
        for start_sample in range(0, len(audio), chunk_samples):
            end_sample = min(len(audio), start_sample + chunk_samples)
            chunk_audio = audio[start_sample:end_sample]
            if len(chunk_audio) < int(0.05 * sr):
                break

            inp = self.processor(chunk_audio, sampling_rate=16000, return_tensors="np")
            feat_np = inp.input_features.astype(np.float32)
            orig_frames = feat_np.shape[1]

            # ترويض DirectML بحجم ثابت يمنع إعادة تصريف الشيدرز ويمنع خطأ Einsum
            if orig_frames < target_frames:
                feat_np = np.pad(feat_np, ((0, 0), (0, target_frames - orig_frames), (0, 0)), mode='constant')
            elif orig_frames > target_frames:
                feat_np = feat_np[:, :target_frames, :]
                orig_frames = target_frames

            try:
                ort_outs = self.onnx_session.run(None, {"input_features": feat_np})
            except Exception as e_gpu:
                if self._cpu_session is None:
                    import onnxruntime as ort
                    sess_opts = ort.SessionOptions()
                    sess_opts.intra_op_num_threads = min(8, os.cpu_count() or 4)
                    self._cpu_session = ort.InferenceSession(self.onnx_file, sess_opts, providers=["CPUExecutionProvider"])
                ort_outs = self._cpu_session.run(None, {"input_features": feat_np})

            logits = ort_outs[0][0][:orig_frames] # shape [orig_frames, 2]
            preds = np.argmax(logits, axis=-1)
            
            # Place in global array based on exact start_sample to prevent cumulative shift
            start_frame = start_sample // 320
            end_frame = start_frame + len(preds)
            if end_frame > expected_total_frames:
                all_preds[start_frame:expected_total_frames] = preds[:expected_total_frames - start_frame]
            else:
                all_preds[start_frame:end_frame] = preds

        if len(all_preds) == 0:
            return [{"start": 0.0, "end": round(total_dur, 3), "duration": round(total_dur, 3)}]

        # استخراج الفترات الأولية
        raw_intervals = []
        in_speech = False
        start_frame = 0
        for f_idx, val in enumerate(all_preds):
            if val == 1 and not in_speech:
                in_speech = True
                start_frame = f_idx
            elif val == 0 and in_speech:
                in_speech = False
                raw_intervals.append([start_frame, f_idx])
        if in_speech:
            raw_intervals.append([start_frame, len(all_preds)])

        if not raw_intervals:
            return [{"start": 0.0, "end": round(total_dur, 3), "duration": round(total_dur, 3)}]

        # تنقية الأنفاس وفق خوارزمية النموذج
        try:
            import torch
            from recitations_segmenter import clean_speech_intervals

            raw_tensor = torch.tensor(raw_intervals, dtype=torch.int64) * 320 # 20ms frame = 320 samples
            clean_out = clean_speech_intervals(
                raw_tensor,
                is_complete=True,
                min_silence_duration_ms=min_silence_ms,
                min_speech_duration_ms=min_speech_ms,
                pad_duration_ms=pad_ms,
                sample_rate=16000,
                return_seconds=True
            )

            result_intervals = []
            for item in clean_out.clean_speech_intervals:
                s = max(0.0, min(total_dur, float(item[0])))
                e = max(s + 0.05, min(total_dur, float(item[1])))
                result_intervals.append({
                    "start": round(s, 3),
                    "end": round(e, 3),
                    "duration": round(e - s, 3)
                })

            return result_intervals or [{"start": 0.0, "end": round(total_dur, 3), "duration": round(total_dur, 3)}]

        except Exception as e_clean:
            print(f"[-] clean_speech_intervals fallback note: {e_clean}")
            # Fallback direct frame conversion
            frame_dur = 0.02
            pad_sec = pad_ms / 1000.0
            min_speech_sec = min_speech_ms / 1000.0
            res = []
            for s_f, e_f in raw_intervals:
                s_t = max(0.0, s_f * frame_dur - pad_sec)
                e_t = min(total_dur, e_f * frame_dur + pad_sec)
                if e_t - s_t >= min_speech_sec:
                    res.append({"start": round(s_t, 3), "end": round(e_t, 3), "duration": round(e_t - s_t, 3)})
            return res or [{"start": 0.0, "end": round(total_dur, 3), "duration": round(total_dur, 3)}]

    def _segment_pytorch(
        self,
        audio: np.ndarray,
        sr: int,
        min_silence_ms: int,
        min_speech_ms: int,
        pad_ms: int,
        total_dur: float
    ) -> List[Dict[str, float]]:
        """
        معالجة عبر PyTorch
        """
        try:
            import torch
            from recitations_segmenter import segment_recitations, clean_speech_intervals

            wav_tensor = torch.from_numpy(audio).float()
            outputs = segment_recitations(
                [wav_tensor],
                self.model,
                self.processor,
                device=self.torch_device or torch.device("cpu"),
                dtype=self.torch_dtype or torch.float32,
                batch_size=4
            )

            if not outputs:
                return [{"start": 0.0, "end": round(total_dur, 3), "duration": round(total_dur, 3)}]

            out_item = outputs[0]
            clean_out = clean_speech_intervals(
                out_item.speech_intervals,
                out_item.is_complete,
                min_silence_duration_ms=min_silence_ms,
                min_speech_duration_ms=min_speech_ms,
                pad_duration_ms=pad_ms,
                return_seconds=True
            )

            result_intervals = []
            for item in clean_out.clean_speech_intervals:
                s = max(0.0, min(total_dur, float(item[0])))
                e = max(s + 0.05, min(total_dur, float(item[1])))
                result_intervals.append({
                    "start": round(s, 3),
                    "end": round(e, 3),
                    "duration": round(e - s, 3)
                })

            return result_intervals or [{"start": 0.0, "end": round(total_dur, 3), "duration": round(total_dur, 3)}]

        except Exception as e:
            print(f"[-] PyTorch segmenter error: {e}")
            return [{"start": 0.0, "end": round(total_dur, 3), "duration": round(total_dur, 3)}]

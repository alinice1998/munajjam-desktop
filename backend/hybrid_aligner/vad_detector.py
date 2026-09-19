"""
كاشف السكت والأنفاس العصبي الفائق باستخدام Silero VAD v5
Neural Voice Activity & Quranic Breath Detector
"""

import os
import numpy as np
import onnxruntime as ort
from typing import List, Dict, Any, Tuple, Optional

class SileroVADDetector:
    def __init__(self, model_path: Optional[str] = None):
        if model_path is None:
            base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            p1 = os.path.join(base_dir, "model_vad", "silero_vad.onnx")
            p2 = os.path.join(os.path.dirname(base_dir), "model_vad", "silero_vad.onnx")
            model_path = p1 if os.path.exists(p1) else p2
        
        if not os.path.exists(model_path):
            raise FileNotFoundError(f"Silero VAD model not found at {model_path}")
        
        self.model_path = model_path
        sess_opts = ort.SessionOptions()
        sess_opts.inter_op_num_threads = 1
        sess_opts.intra_op_num_threads = 2
        
        # Load on CPU (ultra-lightweight < 2ms)
        self.session = ort.InferenceSession(model_path, sess_opts, providers=["CPUExecutionProvider"])
        self.sample_rate = 16000
        self.window_size_samples = 512 # 32ms at 16kHz
        print(f"[+] Silero VAD v5 Neural Breath Detector loaded from {os.path.basename(model_path)}")

    def get_speech_probabilities(self, audio: np.ndarray, sr: int = 16000) -> np.ndarray:
        """حساب مصفوفة احتمالية وجود الصوت لكل إطار 32ms"""
        if sr != 16000:
            import librosa
            audio = librosa.resample(audio, orig_sr=sr, target_sr=16000)
            sr = 16000

        if len(audio.shape) > 1:
            audio = audio.mean(axis=1)

        # Pad audio to multiple of window_size_samples
        pad_len = (self.window_size_samples - (len(audio) % self.window_size_samples)) % self.window_size_samples
        if pad_len > 0:
            audio = np.pad(audio, (0, pad_len), mode='constant')

        state = np.zeros((2, 1, 128), dtype=np.float32)
        sr_tensor = np.array(16000, dtype=np.int64)
        
        num_windows = len(audio) // self.window_size_samples
        probs = np.zeros(num_windows, dtype=np.float32)

        for i in range(num_windows):
            chunk = audio[i * self.window_size_samples : (i + 1) * self.window_size_samples].reshape(1, -1).astype(np.float32)
            out = self.session.run(None, {'input': chunk, 'state': state, 'sr': sr_tensor})
            probs[i] = float(out[0][0][0])
            state = out[1]

        return probs

    def get_speech_timestamps(
        self,
        audio: np.ndarray,
        sr: int = 16000,
        threshold: float = 0.45,
        min_speech_duration_ms: int = 100,
        min_silence_duration_ms: int = 180,
        speech_pad_ms: int = 30
    ) -> List[Dict[str, float]]:
        """
        استخراج مقاطع النَّفَس الصوتية الحقيقية بدقة مللي ثانية
        """
        probs = self.get_speech_probabilities(audio, sr)
        window_sec = self.window_size_samples / 16000.0 # 0.032s

        min_speech_samples = int((min_speech_duration_ms / 1000.0) / window_sec)
        min_silence_samples = int((min_silence_duration_ms / 1000.0) / window_sec)
        speech_pad_samples = int((speech_pad_ms / 1000.0) / window_sec)

        triggered = False
        speech_segments = []
        cur_start = 0
        temp_end = 0

        for i, prob in enumerate(probs):
            if prob >= threshold and not triggered:
                triggered = True
                cur_start = max(0, i - speech_pad_samples)
            elif prob < (threshold - 0.15) and triggered:
                if temp_end == 0:
                    temp_end = i
                if i - temp_end >= min_silence_samples:
                    cur_end = min(len(probs), temp_end + speech_pad_samples)
                    if cur_end - cur_start >= min_speech_samples:
                        speech_segments.append({
                            "start": round(cur_start * window_sec, 3),
                            "end": round(cur_end * window_sec, 3)
                        })
                    triggered = False
                    temp_end = 0
            elif prob >= threshold and triggered:
                temp_end = 0

        if triggered:
            cur_end = min(len(probs), len(probs) + speech_pad_samples)
            if cur_end - cur_start >= min_speech_samples:
                speech_segments.append({
                    "start": round(cur_start * window_sec, 3),
                    "end": round(cur_end * window_sec, 3)
                })

        return speech_segments

    def is_silence_between(self, audio: np.ndarray, sr: int, start_sec: float, end_sec: float, threshold: float = 0.35) -> bool:
        """فحص ما إذا كانت الفترة الفاصلة بين توقيتين تحتوي سكوتاً حقيقياً"""
        if end_sec <= start_sec or (end_sec - start_sec) < 0.06:
            return False
        
        start_idx = max(0, int(start_sec * sr))
        end_idx = min(len(audio), int(end_sec * sr))
        chunk = audio[start_idx:end_idx]
        
        if len(chunk) < self.window_size_samples:
            rms = np.sqrt(np.mean(chunk**2) + 1e-12)
            return float(20 * np.log10(rms + 1e-12)) < -28.0

        probs = self.get_speech_probabilities(chunk, sr)
        return float(np.mean(probs)) < threshold

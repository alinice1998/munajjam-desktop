"""
محرك المحاذاة القسرية الصوتي المجهري باستخدام نموذج Wav2Vec2 XLSR-53 العربي
Wav2Vec2 XLSR-53 Arabic CTC Forced Aligner Engine
"""

import os
import sys

# Ensure UTF-8 output on Windows consoles
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

import re
import numpy as np
from typing import List, Dict, Any, Tuple, Optional

try:
    import numba
    _HAS_NUMBA = True
except ImportError:
    _HAS_NUMBA = False

if _HAS_NUMBA:
    @numba.njit(fastmath=True)
    def _viterbi_trellis_numba(log_probs: np.ndarray, target_tokens: np.ndarray, blank_id: int) -> np.ndarray:
        T = log_probs.shape[0]
        N = target_tokens.shape[0]
        if T == 0 or N == 0:
            return np.zeros(0, dtype=np.int32)
        S = 2 * N + 1
        trellis = np.full((T, S), -1e30, dtype=np.float32)
        trellis[0, 0] = log_probs[0, blank_id]
        trellis[0, 1] = log_probs[0, target_tokens[0]]

        for t in range(1, T):
            lp_blank = log_probs[t, blank_id]
            trellis[t, 0] = trellis[t - 1, 0] + lp_blank

            for s in range(1, S):
                if s % 2 == 0:
                    prev_tok_sc = trellis[t - 1, s - 1]
                    stay_blank_sc = trellis[t - 1, s]
                    best_s = prev_tok_sc if prev_tok_sc > stay_blank_sc else stay_blank_sc
                    trellis[t, s] = best_s + lp_blank
                else:
                    tok_idx = (s + 1) // 2 - 1
                    tok_id = target_tokens[tok_idx]
                    lp_tok = log_probs[t, tok_id]
                    stay_tok = trellis[t - 1, s]
                    from_blank = trellis[t - 1, s - 1]

                    if s >= 3 and target_tokens[tok_idx] != target_tokens[tok_idx - 1]:
                        from_prev_tok = trellis[t - 1, s - 2]
                        best_prev = stay_tok if stay_tok > from_blank else from_blank
                        if from_prev_tok > best_prev:
                            best_prev = from_prev_tok
                    else:
                        best_prev = stay_tok if stay_tok > from_blank else from_blank
                    trellis[t, s] = best_prev + lp_tok

        best_final_s = (S - 1) if trellis[T - 1, S - 1] >= trellis[T - 1, S - 2] else (S - 2)
        path = np.zeros(T, dtype=np.int32)
        curr_s = best_final_s
        path[T - 1] = curr_s

        for t in range(T - 1, 0, -1):
            if curr_s % 2 == 0:
                prev_tok_sc = trellis[t - 1, curr_s - 1] if curr_s > 0 else -1e30
                stay_blank_sc = trellis[t - 1, curr_s]
                if prev_tok_sc >= stay_blank_sc:
                    curr_s = curr_s - 1
            else:
                tok_idx = (curr_s + 1) // 2 - 1
                stay_tok = trellis[t - 1, curr_s]
                from_blank = trellis[t - 1, curr_s - 1] if curr_s > 0 else -1e30
                if curr_s >= 3 and target_tokens[tok_idx] != target_tokens[tok_idx - 1]:
                    from_prev_tok = trellis[t - 1, curr_s - 2]
                    best_score = stay_tok if stay_tok > from_blank else from_blank
                    if from_prev_tok > best_score:
                        best_score = from_prev_tok

                    if best_score == from_prev_tok:
                        curr_s = curr_s - 2
                    elif best_score == from_blank:
                        curr_s = curr_s - 1
                else:
                    if from_blank >= stay_tok:
                        curr_s = curr_s - 1
            path[t - 1] = curr_s
        return path

class Wav2Vec2ForcedAligner:
    def __init__(self, model_dir_or_name: Optional[str] = None, device: Optional[str] = None):
        self.model_dir_or_name = model_dir_or_name or "jonatasgrosman/wav2vec2-large-xlsr-53-arabic"
        self.model = None
        self.processor = None
        self.onnx_session = None
        self.is_onnx = False
        self.device = device or "cpu"
        self.vocab = {}
        self.blank_id = 0
        self.load_model()

    def load_model(self):
        """تحميل نموذج Wav2Vec2 (عبر ONNX Runtime أو PyTorch)"""
        load_path = self.model_dir_or_name
        onnx_file = os.path.join(load_path, "model.onnx") if os.path.isdir(load_path) else None

        # 1. فحص توفر نموذج ONNX للتشغيل فائق السرعة وبدون تورش
        if onnx_file and os.path.exists(onnx_file):
            import onnxruntime as ort
            import json

            print(f"[+] Loading Wav2Vec2 from ONNX model: {onnx_file}")
            from .gpu_utils import get_ort_execution_providers
            providers = get_ort_execution_providers()

            sess_options = ort.SessionOptions()
            sess_options.enable_mem_pattern = True
            sess_options.enable_cpu_mem_arena = True
            sess_options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
            sess_options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
            sess_options.intra_op_num_threads = min(8, os.cpu_count() or 4)
            self.onnx_file = onnx_file
            self.onnx_session = ort.InferenceSession(onnx_file, sess_options, providers=providers)
            self._cpu_session = None
            self.is_onnx = True

            vocab_path = os.path.join(load_path, "vocab.json")
            if os.path.exists(vocab_path):
                with open(vocab_path, "r", encoding="utf-8") as f:
                    self.vocab = json.load(f)
            self.blank_id = self.vocab.get("<pad>", 0)
            print(f"[+] Wav2Vec2 ONNX Engine ready with provider: {self.onnx_session.get_providers()[0]}")
            return

        # 2. التشغيل عبر PyTorch كخيار بديل
        import torch
        from transformers import Wav2Vec2ForCTC, Wav2Vec2Processor

        if torch.cuda.is_available():
            self.device = "cuda"
        else:
            self.device = "cpu"

        if os.path.isdir(load_path) and os.path.exists(os.path.join(load_path, "config.json")):
            print(f"[+] Loading Wav2Vec2 model from local directory: {load_path}")
        else:
            print(f"[+] Loading Wav2Vec2 model: {self.model_dir_or_name}")

        self.processor = Wav2Vec2Processor.from_pretrained(load_path)
        self.model = Wav2Vec2ForCTC.from_pretrained(load_path).to(self.device)
        self.model.eval()

        self.vocab = self.processor.tokenizer.get_vocab()
        self.blank_id = self.processor.tokenizer.pad_token_id or 0
        print(f"[+] Wav2Vec2 Arabic Aligner ready on device: {self.device}")

    @staticmethod
    def normalize_arabic_text(text: str) -> str:
        """
        تنظيف ومعالجة النص القرآني ومطابقته صوتياً بدقة مع أبجدية نموذج Wav2Vec2 العربي
        """
        t = text
        # 1. إزالة علامات الوقف والرموز القرآنية
        t = re.sub(r'[\u06D6-\u06ED\uFD3E\uFD3F﴿﴾0-9\(\)\.\,\!\؟\:\;\-\_ۖۗۚۘۙۛۜ۩۞]', '', t)

        # 2. معالجة الألفات الخنجرية والرسم العثماني صوتياً قبل حذف التشكيل
        # رسم الصلاة والزكاة والحياة: وٰ -> ا
        t = re.sub(r'([وي])\u0670', 'ا', t)
        # الألف الخنجرية المستقلة: ٰ -> ا (مثل: الرحمن -> الرحمان، السماوات، إلهكم -> إلاهكم)
        t = t.replace('\u0670', 'ا')
        # همزة الوصل: ٱ -> ا
        t = t.replace('\u0671', 'ا')
        # واو الصلة الصغرى: ۥ -> و (مثل: فأتبعهۥ -> فأتبعوه)
        t = t.replace('\u06e5', 'و')
        # ياء الصلة الصغرى: ۦ -> ي (مثل: بهۦ -> بهي)
        t = t.replace('\u06e6', 'ي')

        # 3. حذف التشكيل وحركات الضبط وعلامة التطويل
        t = re.sub(r'[\u064B-\u065F\u0640]', '', t)

        # 4. توحيد الرموز النادرة والمعدلة
        t = t.replace('\u06ba', 'ن') # ں
        t = t.replace('\u06fe', 'م') # ۾
        t = t.replace('\u0619', 'ن') # ؙ
        t = t.replace('\u06dc', 'س') # ۜ
        t = t.replace('\u0687', '')  # ڇ

        t = re.sub(r'\s+', ' ', t).strip()
        return t

    @staticmethod
    def track_voice_end(
        audio_segment: np.ndarray,
        sr: int,
        min_time_sec: float,
        max_time_sec: float,
        silence_thresh_db: float = -34.0
    ) -> float:
        """
        تتبع تلاشي الطاقة الصوتية لصوت القارئ (RMS Voice Decay Tracking)
        لحفظ امتداد الحرف الأخير والمدود وأحرف القلقلة ومنع البتر، مع التوقف فور هبوط الصوت إلى السكون لمنع التقاط أصوات الشهيق أو بداية الآية التالية.
        """
        if len(audio_segment) == 0 or max_time_sec <= min_time_sec:
            return min_time_sec

        hop_length = int(0.01 * sr)     # 10ms hops
        frame_length = int(0.025 * sr)  # 25ms window

        start_sample = max(0, int(min_time_sec * sr))
        end_sample = min(len(audio_segment), int(max_time_sec * sr))

        if end_sample <= start_sample:
            return min_time_sec

        sub_audio = audio_segment[start_sample:end_sample]
        if len(sub_audio) < frame_length:
            return min_time_sec

        rms_frames = []
        num_hops = (len(sub_audio) - frame_length) // hop_length + 1
        for h in range(num_hops):
            w = sub_audio[h * hop_length : h * hop_length + frame_length]
            val = np.sqrt(np.mean(w**2) + 1e-12)
            rms_frames.append(20 * np.log10(val + 1e-12))

        if not rms_frames:
            return min_time_sec

        last_voiced_hop = 0
        consecutive_silent_hops = 0
        for h_idx, db in enumerate(rms_frames):
            if db >= silence_thresh_db:
                last_voiced_hop = h_idx
                consecutive_silent_hops = 0
            else:
                consecutive_silent_hops += 1
                # التوقف فوراً عند مواجهة سكون حقيقي لمدة 20ms (قفزتان) لمنع القفز إلى أصوات الشهيق أو الآية التالية
                if consecutive_silent_hops >= 2:
                    break

        if last_voiced_hop > 0:
            voiced_dur = (last_voiced_hop * hop_length + frame_length) / sr
            actual_end = min_time_sec + voiced_dur
        else:
            actual_end = min_time_sec

        return min(max_time_sec, actual_end)

    def align_segment(
        self,
        audio_segment: np.ndarray,
        words: List[str],
        sr: int = 16000
    ) -> List[Dict[str, Any]]:
        """
        المحاذاة القسرية الدقيقة لمقطع صوتي قصير مع كلماته المرجعية
        بالاعتماد بنسبة 100% على مصفوفة المسار العصبي ومؤشرات فريمات الحالات (CTC Trellis State Partitioning)
        مع تطبيق المحاذاة الفونيمية التجويدية لأحكام الوصل (همزة الوصل واللام الشمسية والقمرية).
        """
        if len(words) == 0 or len(audio_segment) == 0:
            return []

        # 1. المعالجة الصوتية التجويدية للكلمات (إسقاط همزة الوصل واللام الشمسية في الوصل الصوتي داخل النَّفَس)
        sun_letters = set("تثدذرزسشصضطظلن")
        relative_pronouns = {"الذين", "الذي", "التي", "اللائي", "اللاتي", "اللذين", "اللتين"}
        cleaned_words = []
        for w_idx, w in enumerate(words):
            norm = self.normalize_arabic_text(w)
            if w_idx > 0:
                if norm in relative_pronouns:
                    norm = norm[1:]  # الأسماء الموصولة (الذين): تسقط همزة الوصل وتبقى اللام المشددة المنطوقة 'ل'
                elif norm.startswith("ال") and len(norm) > 2:
                    if norm[2] in sun_letters:
                        norm = norm[2:]  # حذف 'ال' الشمسية الساقطة وصلاً
                    else:
                        norm = norm[1:]  # حذف همزة الوصل 'ا' الساقطة وصلاً وإبقاء اللام القمرية 'ل'
                elif norm.startswith("ا") and len(norm) > 1:
                    norm = norm[1:]      # حذف همزة الوصل المنفردة الساقطة وصلاً
            cleaned_words.append(norm if norm else "ا")

        tokens_list = []
        word_spans = []

        curr_token_pos = 0
        for w_idx, w_clean in enumerate(cleaned_words):
            chars = list(w_clean.replace(" ", ""))
            if not chars:
                chars = ["ا"]

            w_start_tok = curr_token_pos
            for c in chars:
                tok_id = self.vocab.get(c, self.vocab.get("<unk>", 3))
                tokens_list.append(tok_id)
                curr_token_pos += 1
            w_end_tok = curr_token_pos

            word_spans.append({
                "word_index": w_idx,
                "original_word": words[w_idx],
                "start_tok": w_start_tok,
                "end_tok": w_end_tok
            })

            if w_idx < len(cleaned_words) - 1 and "|" in self.vocab:
                tokens_list.append(self.vocab["|"])
                curr_token_pos += 1

        if not tokens_list:
            return []

        # 2. استخراج مصفوفة احتمالات الإطارات الصوتية (Log-Softmax)
        orig_sample_count = len(audio_segment)
        if self.is_onnx and self.onnx_session is not None:
            mean = np.mean(audio_segment)
            std = np.std(audio_segment) + 1e-7
            norm_audio = ((audio_segment - mean) / std).astype(np.float32)

            # Length Bucketing (Step-Padding to 1.0s = 16,000 samples)
            # This ensures DirectML/GPU reuses fixed memory allocations across all segments
            # without accumulating dynamic shapes that exhaust VRAM and RAM.
            bucket_step = 16000
            target_len = int(np.ceil(orig_sample_count / bucket_step) * bucket_step)
            target_len = max(bucket_step, target_len)

            if orig_sample_count < target_len:
                padded_audio = np.pad(norm_audio, (0, target_len - orig_sample_count), mode='constant')
            else:
                padded_audio = norm_audio[:target_len]

            input_tensor = np.expand_dims(padded_audio, axis=0)

            try:
                logits = self.onnx_session.run(None, {"input_values": input_tensor})[0][0]
            except Exception as e_gpu:
                print(f"[!] GPU inference warning ({e_gpu}), switching permanently to CPU for remaining segments...")
                if self._cpu_session is None:
                    import onnxruntime as ort
                    cpu_options = ort.SessionOptions()
                    cpu_options.intra_op_num_threads = min(8, os.cpu_count() or 4)
                    self._cpu_session = ort.InferenceSession(self.onnx_file, cpu_options, providers=["CPUExecutionProvider"])
                self.onnx_session = self._cpu_session
                logits = self.onnx_session.run(None, {"input_values": input_tensor})[0][0]

            # Receptive field trimming: Wav2Vec2 conv stride is 320 samples per frame (50 fps at 16kHz)
            expected_frames = max(1, min(logits.shape[0], int(np.round(orig_sample_count / 320.0))))
            logits = logits[:expected_frames]

            # Stable Log-Softmax
            max_logits = np.max(logits, axis=-1, keepdims=True)
            exp_logits = np.exp(logits - max_logits)
            log_probs = (logits - max_logits) - np.log(np.sum(exp_logits, axis=-1, keepdims=True))
        else:
            import torch
            inputs = self.processor(
                audio_segment,
                sampling_rate=sr,
                return_tensors="pt"
            ).input_values.to(self.device)

            with torch.no_grad():
                logits = self.model(inputs).logits
                log_probs = torch.nn.functional.log_softmax(logits, dim=-1)[0].cpu().numpy()

        num_frames = log_probs.shape[0]
        total_duration = len(audio_segment) / sr
        frame_duration = total_duration / max(num_frames, 1)

        # 3. تنفيذ خوارزمية مسار فيتربي العصبية واستخراج مسار الحالات الكامل
        path = self._viterbi_trellis_path(
            log_probs=log_probs,
            target_tokens=tokens_list,
            blank_id=self.blank_id
        )

        if len(path) == 0:
            return []

        # 4. استخراج حدود الكلمات مباشرة من مسار الحالات العصبية (Model Trellis Partitioning)
        refined_results = []
        for w_idx, item in enumerate(word_spans):
            s_tok = item["start_tok"]
            e_tok = item["end_tok"]

            # 1. توقيت الحرف الأول للكلمة (بالطريقة السابقة المعتمدة على أول ظهور لحالة الحرف الأول)
            first_char_state = 2 * s_tok + 1
            first_char_frames = [t for t in range(num_frames) if path[t] == first_char_state]
            if not first_char_frames:
                first_char_frames = [t for t in range(num_frames) if path[t] >= first_char_state]
            first_char_onset = min(first_char_frames) if first_char_frames else 0

            # 2. حالات باقي حروف الكلمة وامتدادها
            word_states = set(range(2 * s_tok + 1, 2 * (e_tok - 1) + 3))
            w_frames = [t for t in range(num_frames) if path[t] in word_states]

            if not w_frames:
                w_start_frame = first_char_onset
                w_end_frame = first_char_onset + 2
            else:
                w_start_frame = first_char_onset
                w_end_frame = max(w_frames) + 1

                if w_idx < len(word_spans) - 1:
                    next_s_tok = word_spans[w_idx + 1]["start_tok"]
                    next_first_state = 2 * next_s_tok + 1
                    next_first_frames = [t for t in range(num_frames) if path[t] == next_first_state]
                    if not next_first_frames:
                        next_first_frames = [t for t in range(num_frames) if path[t] >= next_first_state]
                    next_first_onset = min(next_first_frames) if next_first_frames else w_end_frame

                    # نهاية الكلمة الحالية: تقف عند بداية مخرج الحرف الأول للكلمة التالية دون التعدي عليه
                    space_tok = e_tok
                    space_states = {2 * space_tok + 1, 2 * space_tok + 2}
                    space_frames = [t for t in range(num_frames) if path[t] in space_states]

                    if space_frames:
                        w_end_frame = min(space_frames)
                    else:
                        w_end_frame = min(w_end_frame, next_first_onset)
                else:
                    # الكلمة الأخيرة في مقطع النَّفَس: تنتهي عند ذروة وإطلاق الحرف الأخير مع هامش تلاشٍ صوتي طبيعي
                    # دون ابتلاع فراغ السكون اللاحق للقطعة
                    last_char_state = 2 * (e_tok - 1) + 1
                    last_char_frames = [t for t in range(num_frames) if path[t] == last_char_state]
                    if last_char_frames:
                        w_end_frame = min(num_frames, max(last_char_frames) + 3)
                    else:
                        w_end_frame = max(w_frames) + 1

            w_start_sec = max(0, w_start_frame) * frame_duration
            w_end_sec = max(w_start_frame + 1, w_end_frame) * frame_duration

            # إذا كان هناك تداخل مع نهاية الكلمة السابقة، نضبط البداية عند نهاية السابقة
            if refined_results and w_start_sec < refined_results[-1]["end"]:
                w_start_sec = refined_results[-1]["end"]

            w_start_sec = max(0.0, min(total_duration, w_start_sec))
            w_end_sec = max(w_start_sec + 0.04, min(total_duration, w_end_sec))

            refined_results.append({
                "word": item["original_word"],
                "start": round(float(w_start_sec), 3),
                "end": round(float(w_end_sec), 3)
            })

        return refined_results

    def _viterbi_trellis_path(
        self,
        log_probs: np.ndarray,
        target_tokens: List[int],
        blank_id: int
    ) -> np.ndarray:
        """
        خوارزمية البرمجة الديناميكية Viterbi Trellis المعيارية الفائقة السرعة عبر Numba JIT
        """
        if _HAS_NUMBA:
            target_tokens_arr = np.array(target_tokens, dtype=np.int64)
            return _viterbi_trellis_numba(log_probs, target_tokens_arr, blank_id)

        T = log_probs.shape[0]
        N = len(target_tokens)

        if T == 0 or N == 0:
            return np.array([], dtype=np.int32)

        S = 2 * N + 1
        trellis = np.full((T, S), -np.inf, dtype=np.float32)

        trellis[0, 0] = log_probs[0, blank_id]
        trellis[0, 1] = log_probs[0, target_tokens[0]]

        for t in range(1, T):
            lp = log_probs[t]
            lp_blank = lp[blank_id]
            trellis[t, 0] = trellis[t - 1, 0] + lp_blank

            for s in range(1, S):
                if s % 2 == 0:
                    prev_tok_sc = trellis[t - 1, s - 1]
                    stay_blank_sc = trellis[t - 1, s]
                    trellis[t, s] = max(prev_tok_sc, stay_blank_sc) + lp_blank
                else:
                    tok_idx = (s + 1) // 2 - 1
                    tok_id = target_tokens[tok_idx]
                    lp_tok = lp[tok_id]
                    stay_tok = trellis[t - 1, s]
                    from_blank = trellis[t - 1, s - 1]

                    if s >= 3 and target_tokens[tok_idx] != target_tokens[tok_idx - 1]:
                        from_prev_tok = trellis[t - 1, s - 2]
                        best_prev = max(stay_tok, from_blank, from_prev_tok)
                    else:
                        best_prev = max(stay_tok, from_blank)
                    trellis[t, s] = best_prev + lp_tok

        best_final_s = (S - 1) if trellis[T - 1, S - 1] >= trellis[T - 1, S - 2] else (S - 2)
        path = np.zeros(T, dtype=np.int32)
        curr_s = best_final_s
        path[T - 1] = curr_s

        for t in range(T - 1, 0, -1):
            if curr_s % 2 == 0:
                prev_tok_sc = trellis[t - 1, curr_s - 1] if curr_s > 0 else -np.inf
                stay_blank_sc = trellis[t - 1, curr_s]
                if prev_tok_sc >= stay_blank_sc:
                    curr_s = curr_s - 1
            else:
                tok_idx = (curr_s + 1) // 2 - 1
                stay_tok = trellis[t - 1, curr_s]
                from_blank = trellis[t - 1, curr_s - 1] if curr_s > 0 else -np.inf
                if curr_s >= 3 and target_tokens[tok_idx] != target_tokens[tok_idx - 1]:
                    from_prev_tok = trellis[t - 1, curr_s - 2]
                    best_score = max(stay_tok, from_blank, from_prev_tok)
                    if best_score == from_prev_tok:
                        curr_s = curr_s - 2
                    elif best_score == from_blank:
                        curr_s = curr_s - 1
                else:
                    if from_blank >= stay_tok:
                        curr_s = curr_s - 1
            path[t - 1] = curr_s

        return path

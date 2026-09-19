"""
محرك المحاذاة والتزمين بالذكاء الاصطناعي باستخدام نموذج QuranLab Zipformer v3
Neural Alignment & Smart Quranic Breath Segmentation Engine
"""

import os
import sys

# Ensure UTF-8 output on Windows consoles
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

import re
import json
import numpy as np
import soundfile as sf
import librosa
from typing import List, Dict, Any, Tuple, Optional, Set

try:
    import numba
    _HAS_NUMBA_ALIGN = True
except ImportError:
    _HAS_NUMBA_ALIGN = False

_ZIP_CHARS = "ابتثجحخدذرزسشصضطظعغفقكلمنهويءآأإةىئؤ "
_ZIP_CHAR_MAP = {c: i + 1 for i, c in enumerate(_ZIP_CHARS)}

_ZIP_MATCH_MATRIX = np.full((len(_ZIP_CHARS) + 2, len(_ZIP_CHARS) + 2), -2.0, dtype=np.float32)
for c1, id1 in _ZIP_CHAR_MAP.items():
    for c2, id2 in _ZIP_CHAR_MAP.items():
        if id1 == id2:
            _ZIP_MATCH_MATRIX[id1, id2] = 4.5
        elif c1 in c2 or c2 in c1:
            _ZIP_MATCH_MATRIX[id1, id2] = 4.0
        elif c1 == 'ا' and c2 in 'وي':
            _ZIP_MATCH_MATRIX[id1, id2] = 2.5
        elif c1 in 'سص' and c2 in 'سص':
            _ZIP_MATCH_MATRIX[id1, id2] = 2.0
        elif c1 in 'تط' and c2 in 'تط':
            _ZIP_MATCH_MATRIX[id1, id2] = 2.0
        elif c1 in 'ذزظ' and c2 in 'ذزظ':
            _ZIP_MATCH_MATRIX[id1, id2] = 2.0
        elif c1 in 'دض' and c2 in 'دض':
            _ZIP_MATCH_MATRIX[id1, id2] = 2.0

if _HAS_NUMBA_ALIGN:
    @numba.njit(fastmath=True)
    def _align_tokens_dp_numba(ref_codes: np.ndarray, rec_codes: np.ndarray, match_matrix: np.ndarray) -> np.ndarray:
        N = ref_codes.shape[0]
        M = rec_codes.shape[0]
        dp = np.full((N + 1, M + 1), -1e9, dtype=np.float32)
        for j in range(M + 1):
            dp[0, j] = 0.0
        for i in range(1, N + 1):
            dp[i, 0] = -i * 2.0

        for i in range(1, N + 1):
            ref_c = ref_codes[i - 1]
            for j in range(1, M + 1):
                rec_c = rec_codes[j - 1]
                match_score = match_matrix[ref_c, rec_c]
                
                score_diag = dp[i - 1, j - 1] + match_score
                score_del = dp[i - 1, j] - 1.5
                score_ins = dp[i, j - 1] - 0.6
                
                best = score_diag if score_diag > score_del else score_del
                if score_ins > best:
                    best = score_ins
                dp[i, j] = best
                
        return dp

class ZipformerNeuralAligner:
    def __init__(self, model_dir: str):
        self.model_dir = model_dir
        self.model_path = os.path.join(model_dir, "zipformer_p_arabic_v3.int8.onnx")
        if not os.path.exists(self.model_path):
            self.model_path = os.path.join(model_dir, "zipformer_p_arabic_v3.onnx")
        self.tokens_path = os.path.join(model_dir, "tokens.txt")
        self.recognizer = None
        self.tokens_dict = {}
        self.load_model()

    def load_model(self):
        if not os.path.exists(self.model_path) or not os.path.exists(self.tokens_path):
            raise FileNotFoundError(f"ملفات النموذج غير متوفرة في {self.model_dir}")

        import sherpa_onnx
        print(f"[+] Loading Zipformer v3 model: {os.path.basename(self.model_path)}")
        cpu_count = os.cpu_count() or 4
        optimal_threads = max(4, min(16, cpu_count))
        self.recognizer = sherpa_onnx.OnlineRecognizer.from_zipformer2_ctc(
            tokens=self.tokens_path,
            model=self.model_path,
            num_threads=optimal_threads,
            sample_rate=16000,
            feature_dim=80,
            enable_endpoint_detection=False,
            decoding_method="greedy_search",
            debug=False
        )

        with open(self.tokens_path, "r", encoding="utf-8") as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) >= 2:
                    self.tokens_dict[parts[0]] = int(parts[1])
                elif len(parts) == 1:
                    self.tokens_dict[parts[0]] = len(self.tokens_dict)

        print(f"[+] Zipformer Engine ready with {len(self.tokens_dict)} tokens using {optimal_threads} CPU threads")

    def transcribe_with_timestamps(
        self,
        wav_path: str,
        chunk_duration: float = 2.0,
        progress_callback: Optional[Any] = None
    ) -> Tuple[List[Dict[str, Any]], float, np.ndarray, int]:
        try:
            audio, sr = sf.read(wav_path, dtype='float32')
            if len(audio.shape) > 1:
                audio = audio.mean(axis=1)
            if sr != 16000:
                audio = librosa.resample(audio, orig_sr=sr, target_sr=16000)
                sr = 16000
        except Exception:
            audio, sr = librosa.load(wav_path, sr=16000, mono=True)
        total_duration = len(audio) / sr

        stream = self.recognizer.create_stream()

        # إذا لم يُطلب كولباك تحديث النسبة (مثل المرحلة 2 في المحرك الهجين)، نُغذي الصوت كاملاً دفعة واحدة لسرعة قصوى
        if progress_callback is None:
            stream.accept_waveform(sr, audio)
            stream.input_finished()
            while self.recognizer.is_ready(stream):
                self.recognizer.decode_stream(stream)
        else:
            # تغذية بشرائح أكبر (10 ثوانٍ كحد أدنى) لتقليل الـ Python loop overhead مع الحفاظ على نعومة شريط التقدم
            chunk_size = max(int(10.0 * sr), int(chunk_duration * sr))
            total_chunks = max(1, len(range(0, len(audio), chunk_size)))

            for chunk_idx, start_idx in enumerate(range(0, len(audio), chunk_size)):
                chunk = audio[start_idx : start_idx + chunk_size]
                stream.accept_waveform(sr, chunk)
                while self.recognizer.is_ready(stream):
                    self.recognizer.decode_stream(stream)

                if (chunk_idx % 2 == 0 or chunk_idx == total_chunks - 1):
                    pct = int((chunk_idx / total_chunks) * 80)
                    progress_callback(pct, "جاري المعالجة العصبية للإطارات الصوتية...")

            stream.input_finished()
            while self.recognizer.is_ready(stream):
                self.recognizer.decode_stream(stream)

        if progress_callback:
            progress_callback(85, "جاري استخراج الرموز والأحكام التجويدية...")

        raw_res = self.recognizer.get_result_as_json_string(stream)
        res_data = json.loads(raw_res)

        tokens = res_data.get("tokens", [])
        timestamps = res_data.get("timestamps", [])

        token_events = []
        for i, tok in enumerate(tokens):
            if tok and tok != "<blank>":
                t_sec = timestamps[i] if i < len(timestamps) else (i * 0.04)
                token_events.append({
                    "token": tok,
                    "time": round(float(t_sec), 3)
                })

        return token_events, total_duration, audio, sr

    @staticmethod
    def phonetic_normalize(token_str: str) -> str:
        """
        التحويل الصوتي التجويدي لرموز QuranLab
        """
        if not token_str:
            return ""
        t = token_str
        # 1. تحويل الأحرف العثمانية والصلة الصغرى قبل مسح التشكيل
        t = t.replace('\u06ba', 'ن') # ں
        t = t.replace('\u06fe', 'م') # ۾
        t = t.replace('\u0619', 'ن') # ؙ
        t = t.replace('\u06dc', 'س') # ۜ
        t = t.replace('\u0687', '')  # ڇ
        t = t.replace('\u06e5', 'و') # ۥ -> و
        t = t.replace('\u06e6', 'ي') # ۦ -> ي
        t = t.replace('ٱ', 'ا').replace('إ', 'ا').replace('أ', 'ا').replace('آ', 'ا').replace('ٰ', 'ا')
        
        # 2. مسح الحركات التشكيلية والتنوين
        t = re.sub(r'[\u064B-\u065F\u0610-\u061A\u06D6-\u06E4\u06E7-\u06ED\uFD3E\uFD3F﴿﴾0-9\(\)\.\,\!\؟\s]', '', t)
        
        # 3. توحيد الهمزات والأحرف المتشابهة صوتياً
        t = re.sub(r'[ءأإآ]', 'ا', t)
        t = t.replace('ة', 'ه').replace('ى', 'ي').replace('ئ', 'ي').replace('ؤ', 'و')
        t = t.replace('ذ', 'د').replace('ث', 'ت').replace('ظ', 'ض')
        
        # 4. دمج التكرارات المتجاورة
        t = re.sub(r'(.)\1+', r'\1', t)
        return t

    def detect_special_phrases(self, token_events: List[Dict[str, Any]], surah_id: int = 1) -> Dict[str, Any]:
        """
        كشف وعزل المقدمات (الاستعاذة والبسملة) والخواتم (آمين) بدقة متناهية
        """
        if not token_events:
            return {
                "has_istiadha": False,
                "has_basmalah": False,
                "has_ameen": False,
                "surah_start_token_idx": 0,
                "surah_end_token_idx": 0,
                "istiadha_end_idx": 0,
                "basmalah_start_idx": 0,
                "basmalah_end_idx": 0,
                "ameen_start_idx": 0
            }

        raw_chars = [self.phonetic_normalize(e["token"]) for e in token_events]
        head_chars = raw_chars[:min(60, len(raw_chars))]
        head_text = "".join(head_chars)
        
        has_istiadha = any(p in head_text for p in ["اعود", "اعوذ", "شيطان", "شيط", "رجيم", "رجي"])
        has_basmalah = ("بسم" in head_text and any(p in head_text for p in ["رحمان", "رحمن", "رحيم", "رحي"]))
        
        # 1. تحديد موقع بداية ونهاية البسملة
        basmalah_start_idx = 0
        basmalah_end_idx = 0
        if has_basmalah:
            pos_b = head_text.find("بسم")
            if pos_b != -1:
                c_acc = 0
                for idx, c in enumerate(head_chars):
                    if c_acc == pos_b:
                        basmalah_start_idx = idx
                        break
                    c_acc += len(c)
            
            for k in range(basmalah_start_idx, min(basmalah_start_idx + 25, len(token_events))):
                sub = "".join(raw_chars[basmalah_start_idx:k+1])
                if "بسم" in sub and any(p in sub for p in ["رحيم", "رحي"]):
                    basmalah_end_idx = k + 1
                    break

        # 2. تحديد موقع نهاية الاستعاذة
        istiadha_end_idx = 0
        if has_istiadha:
            if has_basmalah and basmalah_start_idx > 0:
                istiadha_end_idx = basmalah_start_idx
            else:
                for k in range(min(30, len(token_events))):
                    sub = "".join(raw_chars[:k+1])
                    if any(p in sub for p in ["رجيم", "رجي", "شيطان"]):
                        istiadha_end_idx = k + 1

        # 3. تحديد موقع بداية آمين في الخاتمة (خاص بسورة الفاتحة فقط surah_id == 1)
        ameen_start_idx = len(token_events)
        has_ameen = False
        if surah_id == 1:
            tail_start_pos = int(len(raw_chars) * 0.70)
            tail_chars = raw_chars[tail_start_pos:]
            tail_text = "".join(tail_chars)
            has_ameen = any(p in tail_text for p in ["امين", "اميين"])
            if has_ameen:
                pos_a = -1
                for kw in ["امين", "اميين"]:
                    pos_a = tail_text.find(kw)
                    if pos_a != -1:
                        break
                if pos_a != -1:
                    c_acc = 0
                    for idx, c in enumerate(tail_chars):
                        if c_acc >= pos_a:
                            ameen_start_idx = tail_start_pos + idx
                            break
                        c_acc += len(c)

        # 4. تحديد نطاق توكنات السورة الصافية
        if surah_id == 1:
            # الفاتحة برواية حفص: البسملة هي الآية رقم 1
            surah_start_token_idx = basmalah_start_idx if has_basmalah else istiadha_end_idx
        else:
            # بقية السور 2..114: السورة تبدأ بعد البسملة والاستعاذة
            if has_basmalah:
                surah_start_token_idx = basmalah_end_idx
            elif has_istiadha:
                surah_start_token_idx = istiadha_end_idx
            else:
                surah_start_token_idx = 0

        surah_end_token_idx = ameen_start_idx if (surah_id == 1 and has_ameen) else len(token_events)

        return {
            "has_istiadha": has_istiadha,
            "has_basmalah": has_basmalah,
            "has_ameen": has_ameen,
            "surah_start_token_idx": surah_start_token_idx,
            "surah_end_token_idx": surah_end_token_idx,
            "istiadha_end_idx": istiadha_end_idx,
            "basmalah_start_idx": basmalah_start_idx,
            "basmalah_end_idx": basmalah_end_idx,
            "ameen_start_idx": ameen_start_idx
        }

    @staticmethod
    def clean_quran_words(raw_text: str) -> List[str]:
        """
        تنظيف وتقسيم كلمات الآية القرآنية ودمج علامات الوقف والرموز في الكلمة المناسبة
        """
        waqf_symbols = set(['ۖ', 'ۗ', 'ۚ', 'ۘ', 'ۙ', 'ۛ', 'ۜ', '۩', '۞'])
        raw_words = [w.strip() for w in raw_text.split() if w.strip()]
        cleaned = []
        for w in raw_words:
            if w in waqf_symbols:
                if cleaned:
                    cleaned[-1] = f"{cleaned[-1]} {w}"
                else:
                    cleaned.append(w)
            else:
                if cleaned and cleaned[-1] in waqf_symbols:
                    cleaned[-1] = f"{cleaned[-1]} {w}"
                else:
                    cleaned.append(w)
        return cleaned

    def align_recitation(
        self,
        wav_path: str,
        ayahs_raw: List[str],
        surah_id: int = 1,
        reference_text: Optional[str] = None,
        chunk_duration: float = 2.0,
        progress_callback: Optional[Any] = None
    ) -> Dict[str, Any]:
        """
        المحاذاة العصبية والتقسيم القرآني للنَّفَس
        """
        token_events, total_dur, audio, sr = self.transcribe_with_timestamps(
            wav_path,
            chunk_duration=chunk_duration,
            progress_callback=progress_callback
        )
        special = self.detect_special_phrases(token_events, surah_id=surah_id)

        if progress_callback:
            progress_callback(90, "جاري مطابقة الكلمات والآيات عصبياً...")

        # تجهيز الكلمات المرجعية المدمجة بنظافة دون رموز منفصلة
        full_ref_words = []
        ayah_words_map = []

        if reference_text:
            raw_words = self.clean_quran_words(reference_text)
            full_ref_words = raw_words
            ayah_words_map.append({
                "ayah_number": 1,
                "text": reference_text,
                "start_idx": 0,
                "end_idx": len(raw_words),
                "words": raw_words
            })
        else:
            for a_idx, a_text in enumerate(ayahs_raw):
                words = self.clean_quran_words(a_text)
                start_pos = len(full_ref_words)
                full_ref_words.extend(words)
                end_pos = len(full_ref_words)
                ayah_words_map.append({
                    "ayah_number": a_idx + 1,
                    "text": a_text,
                    "start_idx": start_pos,
                    "end_idx": end_pos,
                    "words": words
                })

        if not token_events:
            print("[-] No tokens decoded")
            return self._fallback_align(full_ref_words, ayah_words_map, total_dur)

        # عزل رموز الاستعاذة والبسملة التمهيدية وكذلك آمين في الختام
        s_start = special.get("surah_start_token_idx", 0)
        s_end = special.get("surah_end_token_idx", len(token_events))
        surah_tokens = token_events[s_start:s_end]
        if not surah_tokens:
            surah_tokens = token_events

        # تمثيل الحروف لكل كلمة طبيعياً
        ref_char_to_word = []
        for w_idx, w in enumerate(full_ref_words):
            w_norm = self.phonetic_normalize(w)
            for c in w_norm:
                ref_char_to_word.append((c, w_idx))

        # مطابقة DTW العصبية
        alignments_by_word, word_token_indices = self._align_tokens_to_words(
            token_events=surah_tokens,
            ref_char_to_word=ref_char_to_word,
            full_ref_words=full_ref_words,
            total_duration=total_dur
        )

        # تطبيق معالجة فواصل الكلمات (تم ضبطها على 0.0 لاستخراج التوقيت الخام)
        alignments_by_word = self.apply_word_transition_offset(alignments_by_word, shift_sec=0.0, total_dur=total_dur)

        # تقسيم النَّفَس القرآني المعاير:
        # 1. عند رؤوس الآيات: إذا سكت القارئ (gap >= 0.45s) يعتبر نفساً جديداً.
        # 2. داخل الآية الواحدة: لا ينفصل النَّفَس إلا في سكتات الوقف الحقيقية الطويلة (gap >= 1.25s).
        # 3. وصل الكلمات المتصلة صوتياً في النَّفَس الواحد تلقائياً.
        breath_groups = self._segment_by_quranic_breaths(
            alignments=alignments_by_word,
            ayah_words_map=ayah_words_map,
            audio=audio,
            sr=sr
        )

        # تجميع توقيتات الآيات
        ayahs_data = []
        for mapping in ayah_words_map:
            s_idx = mapping["start_idx"]
            e_idx = mapping["end_idx"]
            sub_words_align = alignments_by_word[s_idx:e_idx]
            
            if sub_words_align:
                a_start = sub_words_align[0]["start"]
                a_end = sub_words_align[-1]["end"]
            else:
                a_start = 0.0
                a_end = total_dur

            ayahs_data.append({
                "ayah_number": mapping["ayah_number"],
                "start_time": a_start,
                "end_time": a_end,
                "text": mapping["text"],
                "words": sub_words_align
            })

        return {
            "status": "success",
            "model": "QuranLab Zipformer v3 (Neural CTC)",
            "surah_id": surah_id,
            "total_duration": total_dur,
            "detected_phrases": {
                "istiadha": special["has_istiadha"],
                "basmalah": special["has_basmalah"],
                "ameen": special["has_ameen"]
            },
            "data": ayahs_data,
            "alignments": alignments_by_word,
            "breath_groups": breath_groups
        }

    def _align_tokens_to_words(
        self,
        token_events: List[Dict[str, Any]],
        ref_char_to_word: List[Tuple[str, int]],
        full_ref_words: List[str],
        total_duration: float
    ) -> Tuple[List[Dict[str, Any]], Dict[int, List[int]]]:
        """
        المحاذاة العصبية التجويدية الأساسية لنموذج Zipformer
        """
        num_words = len(full_ref_words)
        N = len(ref_char_to_word)
        M = len(token_events)

        if N == 0 or M == 0:
            return [], {}

        rec_chars = [self.phonetic_normalize(e["token"]) for e in token_events]

        if _HAS_NUMBA_ALIGN:
            ref_codes = np.array([_ZIP_CHAR_MAP.get(ref_char_to_word[k][0], 0) for k in range(N)], dtype=np.int32)
            rec_codes = np.array([_ZIP_CHAR_MAP.get(rec_chars[k], 0) for k in range(M)], dtype=np.int32)
            dp = _align_tokens_dp_numba(ref_codes, rec_codes, _ZIP_MATCH_MATRIX)
        else:
            dp = np.full((N + 1, M + 1), -1e9, dtype=np.float32)
            for j in range(M + 1):
                dp[0, j] = 0.0
            for i in range(1, N + 1):
                dp[i, 0] = -i * 2.0

            for i in range(1, N + 1):
                ref_c = ref_char_to_word[i - 1][0]
                for j in range(1, M + 1):
                    rec_c = rec_chars[j - 1]

                    if ref_c == rec_c:
                        match_score = 4.5
                    elif ref_c in rec_c or rec_c in ref_c:
                        match_score = 4.0
                    elif ref_c == 'ا' and rec_c in 'وي':
                        match_score = 2.5
                    elif ref_c in 'سص' and rec_c in 'سص':
                        match_score = 2.0
                    elif ref_c in 'تط' and rec_c in 'تط':
                        match_score = 2.0
                    elif ref_c in 'ذزظ' and rec_c in 'ذزظ':
                        match_score = 2.0
                    elif ref_c in 'دض' and rec_c in 'دض':
                        match_score = 2.0
                    else:
                        match_score = -2.0

                    score_diag = dp[i - 1, j - 1] + match_score
                    score_del = dp[i - 1, j] - 1.5
                    score_ins = dp[i, j - 1] - 0.6
                    dp[i, j] = max(score_diag, score_del, score_ins)

        best_j = int(np.argmax(dp[N, :]))
        i = N
        j = best_j

        word_timestamps = {w_idx: [] for w_idx in range(num_words)}
        word_token_indices = {w_idx: [] for w_idx in range(num_words)}

        while i > 0 and j > 0:
            current_score = dp[i, j]
            ref_c = ref_char_to_word[i - 1][0]
            w_idx = ref_char_to_word[i - 1][1]
            t_event = token_events[j - 1]
            rec_c = rec_chars[j - 1]

            match_sc = 4.5 if (ref_c == rec_c) else (4.0 if (ref_c in rec_c or rec_c in ref_c) else -2.0)
            score_diag = dp[i - 1, j - 1] + match_sc
            score_del = dp[i - 1, j] - 1.5

            if abs(current_score - score_diag) < 1e-3:
                word_timestamps[w_idx].append(t_event["time"])
                word_token_indices[w_idx].append(j - 1)
                i -= 1
                j -= 1
            elif abs(current_score - score_del) < 1e-3:
                i -= 1
            else:
                j -= 1

        alignments = []
        last_end = 0.0

        for w_idx in range(num_words):
            times = word_timestamps.get(w_idx, [])
            w_text = full_ref_words[w_idx]
            
            if times:
                raw_start = min(times)
                raw_end = max(times)
                w_start = max(0.0, raw_start)
                w_end = raw_end
            else:
                w_start = last_end
                w_end = last_end + max(0.05 * len(w_text), 0.10)

            if w_start < last_end:
                w_start = last_end
            if w_end <= w_start:
                w_end = w_start + 0.05

            w_end = min(w_end, total_duration)

            alignments.append({
                "word": w_text,
                "start": round(float(w_start), 2),
                "end": round(float(w_end), 2)
            })
            last_end = w_end

        return alignments, word_token_indices

    def _is_silence_or_breath(
        self,
        audio: np.ndarray,
        sr: int,
        start_sec: float,
        end_sec: float,
        base_silence_db: float = -28.0
    ) -> bool:
        """
        التحقق من وجود سكون صوتي أو صوت نَفَس/شهيق في الفجوة الفاصلة
        """
        if audio is None or len(audio) == 0 or end_sec <= start_sec:
            return False
        
        start_sample = max(0, int(start_sec * sr))
        end_sample = min(len(audio), int(end_sec * sr))
        
        if end_sample - start_sample < int(0.04 * sr):
            return False
        
        segment = audio[start_sample:end_sample]
        rms = np.sqrt(np.mean(segment**2) + 1e-12)
        rms_db = 20 * np.log10(rms + 1e-12)
        
        return bool(rms_db < base_silence_db)

    def _segment_by_quranic_breaths(
        self,
        alignments: List[Dict[str, Any]],
        ayah_words_map: List[Dict[str, Any]],
        audio: np.ndarray,
        sr: int
    ) -> List[Dict[str, Any]]:
        """
        التقسيم القرآني الذكي لمقاطع النَّفَس والوقف المعاير بدقة
        """
        if not alignments:
            return []

        waqf_chars = set('\u06d6\u06d7\u06d8\u06d9\u06da\u06db\u06dc\u06de\u06e9')
        ayah_end_indices = set(m["end_idx"] - 1 for m in ayah_words_map)
        groups = []
        current_group_words = [alignments[0]]

        for i in range(1, len(alignments)):
            prev_word = alignments[i - 1]
            curr_word = alignments[i]
            gap_dur = curr_word["start"] - prev_word["end"]
            is_ayah_end = (i - 1) in ayah_end_indices
            is_waqf = any(c in prev_word["word"] for c in waqf_chars)

            # فحص الطاقة الصوتية في الفجوة إذا كان الصوت متاحاً
            has_acoustic_silence = False
            if gap_dur >= 0.14 and audio is not None and len(audio) > 0:
                has_acoustic_silence = self._is_silence_or_breath(
                    audio, sr, prev_word["end"], curr_word["start"], base_silence_db=-28.0
                )

            # فحص المدة الزمنية التراكمية لمقطع النَّفَس الحالي
            curr_group_dur = curr_word["end"] - current_group_words[0]["start"]
            is_long_breath = curr_group_dur >= 20.0

            is_breath_pause = False

            if is_ayah_end:
                # عند رأس الآية: وقفة سكون أخذ نَفَس >= 0.22s أو فجوة >= 0.14s مع هبوط طاقة الصوت، أو إذا كان النَّفَس طويلاً (>=20s)
                if gap_dur >= 0.22 or (gap_dur >= 0.14 and has_acoustic_silence) or (is_long_breath and gap_dur >= 0.04):
                    is_breath_pause = True
            elif is_waqf:
                # عند علامات الوقف القرآنية داخل الآية: يشترط وجود سكون صوتي حقيقي (Silence Drop) مع فجوة >= 0.40s
                # أو إذا تجاوز النَّفَس سقف الأمان (>= 20s) مع فجوة طفيفة
                if (gap_dur >= 0.40 and has_acoustic_silence) or gap_dur >= 1.40 or (is_long_breath and gap_dur >= 0.10):
                    is_breath_pause = True
            else:
                # بين الكلمات العادية داخل الآية: سكتة طويلة جداً (>= 1.60s) أو إذا تجاوز النَّفَس سقف الأمان الأقصى
                if gap_dur >= 1.60 or (curr_group_dur >= 24.0 and gap_dur >= 0.10) or (curr_group_dur >= 28.0 and gap_dur >= 0.04):
                    is_breath_pause = True

            if is_breath_pause:
                g_start = current_group_words[0]["start"]
                g_end = current_group_words[-1]["end"]
                g_text = " ".join([w["word"] for w in current_group_words])
                groups.append({
                    "group_index": len(groups) + 1,
                    "start_time": round(float(g_start), 2),
                    "end_time": round(float(g_end), 2),
                    "duration": round(float(g_end - g_start), 2),
                    "text": g_text,
                    "words": current_group_words
                })
                current_group_words = [curr_word]
            else:
                # كلمات موصولة في نفس النَّفَس:
                # الحفاظ على الحدود الصوتية النقية لكل كلمة ومنع ابتلاع الكلمة السابقة لمخرج الحرف الأول من الكلمة التالية
                if gap_dur < 0:
                    # في حال وجود تداخل طفيف، يتم حسم نهاية الكلمة السابقة لتقف عند بداية الكلمة التالية بالضبط
                    alignments[i - 1]["end"] = alignments[i]["start"]

                current_group_words.append(curr_word)

        if current_group_words:
            g_start = current_group_words[0]["start"]
            g_end = current_group_words[-1]["end"]
            g_text = " ".join([w["word"] for w in current_group_words])
            groups.append({
                "group_index": len(groups) + 1,
                "start_time": round(float(g_start), 2),
                "end_time": round(float(g_end), 2),
                "duration": round(float(g_end - g_start), 2),
                "text": g_text,
                "words": current_group_words
            })

        return groups

    @staticmethod
    def bridge_word_gaps_with_breath_rules(
        words: List[Dict[str, Any]],
        breath_boundaries: Set[int],
        total_dur: float = None
    ) -> List[Dict[str, Any]]:
        """
        إغلاق جميع الفجوات الزمنية بين الكلمات بالكامل وفق القواعد التالية:
        1. في حال عدم وجود نفس بين الكلمتين (وصل صوتي):
           يتم إضافة 1/6 المسافة الزمنية للكلمة التالية والباقي (5/6) للكلمة السابقة.
        2. في حال وجود نفس بين الكلمتين:
           - إذا كانت المسافة أكبر من 0.4 ثانية: يوضع 0.15 ثانية مع الكلمة التالية والباقي مع الكلمة السابقة.
           - إذا كانت المسافة بين 0.2 و 0.4 ثانية: يوضع 0.10 ثانية مع الكلمة التالية والباقي مع الكلمة السابقة.
           - إذا كانت المسافة أقل من 0.2 ثانية: يوضع 0.05 ثانية مع الكلمة التالية والباقي مع الكلمة السابقة.
        دون ترك أي فجوات زمنية نهائياً.
        """
        if not words:
            return words

        for i in range(len(words) - 1):
            curr_w = words[i]
            next_w = words[i + 1]
            gap = float(next_w["start"]) - float(curr_w["end"])
            is_breath = i in breath_boundaries

            if is_breath:
                if gap > 0.40:
                    shift_next = min(0.15, max(0.0, gap))
                elif gap >= 0.20:
                    shift_next = min(0.10, max(0.0, gap))
                elif gap > 0.0:
                    shift_next = min(0.05, max(0.0, gap))
                else:
                    shift_next = 0.0

                split_point = float(next_w["start"]) - shift_next
                split_point = max(float(curr_w["start"]) + 0.04, split_point)
                curr_w["end"] = split_point
                next_w["start"] = split_point
            else:
                if gap > 0.0:
                    shift_next = gap * (1.0 / 6.0)
                    split_point = float(next_w["start"]) - shift_next
                    split_point = max(float(curr_w["start"]) + 0.04, split_point)
                    curr_w["end"] = split_point
                    next_w["start"] = split_point
                else:
                    mid = (float(curr_w["end"]) + float(next_w["start"])) / 2.0
                    curr_w["end"] = mid
                    next_w["start"] = mid

        for w in words:
            w["start"] = round(float(w["start"]), 3)
            w["end"] = round(float(w["end"]), 3)
            if total_dur is not None:
                w["start"] = max(0.0, min(total_dur, w["start"]))
                w["end"] = max(w["start"] + 0.02, min(total_dur, w["end"]))

        return words

    @staticmethod
    def apply_word_transition_offset(words: List[Dict[str, Any]], shift_sec: float = 0.0, total_dur: float = None) -> List[Dict[str, Any]]:
        return words

    def _fallback_align(self, full_ref_words, ayah_words_map, total_dur):
        num_words = len(full_ref_words)
        dur_per_word = (total_dur - 0.2) / max(num_words, 1)
        alignments = []
        for i, w in enumerate(full_ref_words):
            alignments.append({
                "word": w,
                "start": round(0.1 + i * dur_per_word, 3),
                "end": round(0.1 + (i + 1) * dur_per_word, 3)
            })
        return {"status": "success", "data": [], "alignments": alignments, "breath_groups": []}

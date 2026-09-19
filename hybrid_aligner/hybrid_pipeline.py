"""
خط الإنتاج الهجين المطور لتزمين التلاوات القرآنية
(QuranRecitationSegmenter GPU + Zipformer v3 + Wav2Vec2 XLSR-53 GPU)
Two-Stage Hybrid Quranic Alignment Pipeline with Neural Breath Segmentation
"""

import os
import sys

# Ensure UTF-8 output on Windows consoles
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

import gc
import re
import json
import librosa
import numpy as np
from typing import List, Dict, Any, Tuple, Optional, Set

# Import core components
from neural_aligner import ZipformerNeuralAligner
from .wav2vec2_aligner import Wav2Vec2ForcedAligner
from .recitation_segmenter import QuranRecitationSegmenter

class HybridQuranAligner:
    """
    محرك المحاذاة الهجين الثلاثي:
    1. محرك التقطيع العصبي (recitation-segmenter-v2 على GPU): مسؤول حصرياً عن التقطيع الفيزيائي الدقيق للأنفاس والوقف.
    2. محرك Zipformer v3: مسؤول عن كشف الاستعاذة والبسملة والخواتم ومطابقة الكلمات المرجعية.
    3. محرك Wav2Vec2 XLSR-53 (على GPU): مسؤول عن المحاذاة القسرية المجهرية بدقة الفريم لكل مقطع نَفَس.
    """

    def __init__(
        self,
        zipformer_dir: str,
        wav2vec2_dir_or_name: Optional[str] = None,
        segmenter_dir_or_name: Optional[str] = None
    ):
        self.zipformer_dir = zipformer_dir
        self.wav2vec2_dir_or_name = wav2vec2_dir_or_name or "model_wav2vec2"
        self.segmenter_dir_or_name = segmenter_dir_or_name or "model_segmenter"
        self.zipformer = None
        self.wav2vec2 = None
        self.segmenter = None
        self.load_models()

    def load_models(self):
        """تحميل النماذج الثلاثة للعمل بتناغم كامل على كرت الشاشة GPU"""
        print("[+] Initializing Next-Gen Hybrid Quranic Alignment Engine...")
        self.zipformer = ZipformerNeuralAligner(self.zipformer_dir)
        self.wav2vec2 = Wav2Vec2ForcedAligner(self.wav2vec2_dir_or_name)
        self.segmenter = QuranRecitationSegmenter(self.segmenter_dir_or_name)
        print("[+] Full Hybrid Engine (Segmenter v2 + Zipformer v3 + Wav2Vec2) ready on GPU!")

    def align_recitation(
        self,
        wav_path: str,
        ayahs_raw: List[str],
        surah_id: int = 1,
        reference_text: Optional[str] = None,
        chunk_duration: float = 2.0,
        progress_callback: Optional[Any] = None,
        min_silence_ms: Optional[int] = None,
        min_speech_ms: Optional[int] = None,
        pad_ms: Optional[int] = None,
        method: str = "hybrid",
        repetition_attach: str = "next"
    ) -> Dict[str, Any]:
        """
        توجيه التزمين إما للنموذج الهجين الذكي v2 (مع recitation-segmenter-v2)
        أو النموذج الهجين الكلاسيكي v1 (Zipformer v3 + Wav2Vec2)
        """
        if method in ("hybrid_fuzzy", "fuzzy", "fuzzy_zipformer"):
            return self._align_hybrid_fuzzy(
                wav_path=wav_path,
                ayahs_raw=ayahs_raw,
                surah_id=surah_id,
                reference_text=reference_text,
                chunk_duration=chunk_duration,
                progress_callback=progress_callback,
                min_silence_ms=min_silence_ms,
                min_speech_ms=min_speech_ms,
                pad_ms=pad_ms
            )
        else:
            return self._align_hybrid_v2(
                wav_path=wav_path,
                ayahs_raw=ayahs_raw,
                surah_id=surah_id,
                reference_text=reference_text,
                chunk_duration=chunk_duration,
                progress_callback=progress_callback,
                min_silence_ms=min_silence_ms,
                min_speech_ms=min_speech_ms,
                pad_ms=pad_ms,
                repetition_attach=repetition_attach
            )
    @staticmethod
    def _phonetic_clean_fuzzy(text: str) -> str:
        """تحويل تجويدي وتنظيف فونيمي لرموز وتوكنات التلاوة"""
        t = text
        t = t.replace('\u06e5', 'و').replace('\u06e6', 'ي').replace('\u0670', 'ا').replace('\u0671', 'ا')
        t = re.sub(r'[\u064B-\u065F\u0610-\u061A\u06D6-\u06ED\uFD3E\uFD3F0-9\(\)\.\,\!\؟\s]', '', t)
        t = re.sub(r'[ءأإآ]', 'ا', t)
        t = t.replace('ة', 'ه').replace('ى', 'ي').replace('ئ', 'ي').replace('ؤ', 'و')
        t = t.replace('ذ', 'د').replace('ث', 'ت').replace('ظ', 'ض')
        # دمج الأحرف المكررة المتتالية في التوكنات (مثل 'لل' -> 'ل', 'رر' -> 'ر')
        t = re.sub(r'(.)\1+', r'\1', t)
        return t

    def _match_tokens_to_words_fuzzy(
        self,
        ref_words: List[str],
        token_events: List[Dict[str, Any]],
        total_duration: float
    ) -> List[Dict[str, Any]]:
        """
        المطابقة الضبابية التجويدية بين توكنات Zipformer الحرة والنص المرجعي القرآني
        تستخرج الحدود الطبيعية لكل كلمة دون محاذاة قسرية ودون تداخل أو نزف بين الكلمات
        """
        if not ref_words:
            return []
        if not token_events:
            avg_dur = total_duration / max(1, len(ref_words))
            return [
                {
                    "word": w,
                    "start": round(i * avg_dur, 3),
                    "end": round((i + 1) * avg_dur, 3)
                }
                for i, w in enumerate(ref_words)
            ]

        ref_phonetics = [self._phonetic_clean_fuzzy(w) for w in ref_words]
        tok_phonetics = [self._phonetic_clean_fuzzy(ev.get("token", "")) for ev in token_events]
        tok_times = [float(ev.get("time", 0.0)) for ev in token_events]

        ref_chars = []
        char_to_word = []
        for w_idx, ph in enumerate(ref_phonetics):
            for c in ph:
                ref_chars.append(c)
                char_to_word.append(w_idx)

        tok_chars = []
        char_to_tok = []
        for t_idx, ph in enumerate(tok_phonetics):
            for c in ph:
                tok_chars.append(c)
                char_to_tok.append(t_idx)

        N = len(ref_chars)
        M = len(tok_chars)

        if N == 0 or M == 0:
            avg_dur = total_duration / max(1, len(ref_words))
            return [
                {"word": w, "start": round(i * avg_dur, 3), "end": round((i + 1) * avg_dur, 3)}
                for i, w in enumerate(ref_words)
            ]

        # مصفوفة البرمجة الديناميكية للمطابقة الضبابية
        dp = np.full((N + 1, M + 1), -1e9, dtype=np.float32)
        for j in range(M + 1):
            dp[0, j] = 0.0
        for i in range(1, N + 1):
            dp[i, 0] = -i * 1.5

        for i in range(1, N + 1):
            rc = ref_chars[i - 1]
            for j in range(1, M + 1):
                tc = tok_chars[j - 1]
                if rc == tc:
                    score_match = 4.0
                elif rc in 'اوي' and tc in 'اوي':
                    score_match = 2.0
                elif rc in 'سص' and tc in 'سص':
                    score_match = 2.0
                elif rc in 'تط' and tc in 'تط':
                    score_match = 2.0
                elif rc in 'دض' and tc in 'دض':
                    score_match = 2.0
                else:
                    score_match = -2.0

                d = dp[i - 1, j - 1] + score_match
                del_sc = dp[i - 1, j] - 1.2
                ins_sc = dp[i, j - 1] - 0.5
                dp[i, j] = max(d, del_sc, ins_sc)

        # التتبع الخلفي (Backtracking)
        best_j = int(np.argmax(dp[N, :]))
        i = N
        j = best_j

        word_times = {w_idx: [] for w_idx in range(len(ref_words))}
        while i > 0 and j > 0:
            curr_val = dp[i, j]
            rc = ref_chars[i - 1]
            tc = tok_chars[j - 1]
            w_idx = char_to_word[i - 1]
            t_idx = char_to_tok[j - 1]

            match_sc = 4.0 if rc == tc else (-2.0)
            d = dp[i - 1, j - 1] + match_sc
            del_sc = dp[i - 1, j] - 1.2

            if abs(curr_val - d) < 1e-3:
                word_times[w_idx].append(tok_times[t_idx])
                i -= 1
                j -= 1
            elif abs(curr_val - del_sc) < 1e-3:
                i -= 1
            else:
                j -= 1

        results = []
        last_end = 0.0
        for w_idx, w in enumerate(ref_words):
            times = word_times.get(w_idx, [])
            if times:
                s = min(times)
                e = max(times) + 0.14  # تغطية زمن التوكن الأخير
            else:
                s = last_end
                e = last_end + max(0.08 * len(w), 0.20)

            s = max(last_end, s)
            e = max(s + 0.08, e)
            s = min(s, total_duration)
            e = min(e, total_duration)

            results.append({
                "word": w,
                "start": round(float(s), 3),
                "end": round(float(e), 3)
            })
            last_end = e

        return results

    def _align_hybrid_fuzzy(
        self,
        wav_path: str,
        ayahs_raw: List[str],
        surah_id: int = 1,
        reference_text: Optional[str] = None,
        chunk_duration: float = 2.0,
        progress_callback: Optional[Any] = None,
        min_silence_ms: Optional[int] = None,
        min_speech_ms: Optional[int] = None,
        pad_ms: Optional[int] = None
    ) -> Dict[str, Any]:
        """
        المسار الضبابي الذكي v3 (Fuzzy Zipformer + Segmenter):
        1. تقطيع الأنفاس عصبياً عبر recitation-segmenter-v2 على GPU
        2. تفريغ الرموز والأوقات الحرة وكشف البسملة والاستعاذة عبر Zipformer v3
        3. مطابقة ضبابية صوتية ذكية (Phonetic Fuzzy Sequence Matching) مع النص المرجعي للمصحف
        4. تحديد الحدود الطبيعية للكلمات بدون أي محاذاة قسرية ودون نزف الحرف الأول
        """
        try:
            import soundfile as sf
            audio, sr = sf.read(wav_path, dtype='float32')
            if len(audio.shape) > 1:
                audio = audio.mean(axis=1)
            if sr != 16000:
                audio = librosa.resample(audio, orig_sr=sr, target_sr=16000)
                sr = 16000
        except Exception:
            audio, sr = librosa.load(wav_path, sr=16000, mono=True)
            sr = 16000

        total_dur = len(audio) / float(sr)

        # 1. تقطيع الأنفاس عصبياً
        if progress_callback:
            progress_callback(20, "المرحلة 1: كشف وتقطيع الأنفاس والوقف العصبي عبر recitation-segmenter-v2...")

        neural_breath_intervals = self.segmenter.segment_audio(
            audio,
            sr=sr,
            min_silence_ms=min_silence_ms,
            min_speech_ms=min_speech_ms,
            pad_ms=pad_ms
        )
        print(f"[+] [Fuzzy Engine v3] Segmenter detected {len(neural_breath_intervals)} breath intervals.")

        # 2. تفريغ Zipformer الحر
        if progress_callback:
            progress_callback(50, "المرحلة 2: التفريغ الصوتي التجويدي الحر واستخراج التوكنات عبر Zipformer v3...")

        token_events, _, _, _ = self.zipformer.transcribe_with_timestamps(
            wav_path,
            chunk_duration=chunk_duration,
            progress_callback=None
        )
        special = self.zipformer.detect_special_phrases(token_events, surah_id=surah_id)

        # 3. إعداد الكلمات المرجعية
        full_ref_words = []
        ayah_words_map = []

        if reference_text:
            raw_words = self.zipformer.clean_quran_words(reference_text)
            full_ref_words = raw_words
            ayah_words_map.append({
                "ayah_number": 1,
                "text": reference_text,
                "words": raw_words
            })
        else:
            for a_idx, a_text in enumerate(ayahs_raw):
                words = self.zipformer.clean_quran_words(a_text)
                full_ref_words.extend(words)
                ayah_words_map.append({
                    "ayah_number": a_idx + 1,
                    "text": a_text,
                    "words": words
                })

        # عزل توكنات الاستعاذة والبسملة
        s_start = special.get("surah_start_token_idx", 0)
        s_end = special.get("surah_end_token_idx", len(token_events))
        surah_tokens = token_events[s_start:s_end] if token_events else []
        if not surah_tokens:
            surah_tokens = token_events

        # 4. المطابقة الضبابية التجويدية
        if progress_callback:
            progress_callback(75, "المرحلة 3: المطابقة الصوتية الضبابية (Fuzzy Matching) وتحديد حدود الكلمات...")

        aligned_words = self._match_tokens_to_words_fuzzy(
            ref_words=full_ref_words,
            token_events=surah_tokens,
            total_duration=total_dur
        )

        # 5. تعيين الكلمات إلى مقاطع الأنفاس
        if progress_callback:
            progress_callback(90, "المرحلة 4: بناء مقاطع الأنفاس المستقلة والآيات...")

        word_interval_indices = []
        for w_item in aligned_words:
            w_mid = (w_item["start"] + w_item["end"]) / 2.0
            best_int_idx = 0
            best_dist = float("inf")
            for int_idx, interval in enumerate(neural_breath_intervals):
                if interval["start"] <= w_mid <= interval["end"]:
                    best_int_idx = int_idx
                    best_dist = 0.0
                    break
                dist = min(abs(w_mid - interval["start"]), abs(w_mid - interval["end"]))
                if dist < best_dist:
                    best_dist = dist
                    best_int_idx = int_idx
            word_interval_indices.append(best_int_idx)

        # فرض الرتابة
        for k in range(1, len(word_interval_indices)):
            if word_interval_indices[k] < word_interval_indices[k - 1]:
                word_interval_indices[k] = word_interval_indices[k - 1]

        final_breath_groups = []
        for int_idx, interval in enumerate(neural_breath_intervals):
            group_words = [aligned_words[i] for i, m_idx in enumerate(word_interval_indices) if m_idx == int_idx]
            if not group_words:
                continue
            g_start = group_words[0]["start"]
            g_end = group_words[-1]["end"]
            g_text = " ".join([w["word"] for w in group_words])
            final_breath_groups.append({
                "group_index": len(final_breath_groups) + 1,
                "start_time": g_start,
                "end_time": g_end,
                "duration": round(g_end - g_start, 3),
                "text": g_text,
                "words": group_words
            })

        # 6. تجميع الآيات
        ayahs_data = []
        word_cursor = 0
        for mapping in ayah_words_map:
            a_count = len(mapping["words"])
            a_words = aligned_words[word_cursor : word_cursor + a_count]
            word_cursor += a_count
            if a_words:
                a_start = a_words[0]["start"]
                a_end = a_words[-1]["end"]
            else:
                a_start = 0.0
                a_end = total_dur

            ayahs_data.append({
                "ayah_number": mapping["ayah_number"],
                "start_time": a_start,
                "end_time": a_end,
                "text": mapping["text"],
                "words": a_words
            })

        for i in range(len(ayahs_data) - 1):
            ayahs_data[i]["end_time"] = ayahs_data[i + 1]["start_time"]
            ayahs_data[i]["duration"] = round(float(ayahs_data[i]["end_time"] - ayahs_data[i]["start_time"]), 3)

        if ayahs_data:
            ayahs_data[-1]["end_time"] = round(float(total_dur), 3)
            ayahs_data[-1]["duration"] = round(float(total_dur - ayahs_data[-1]["start_time"]), 3)

        if progress_callback:
            progress_callback(100, "اكتمل التزمين بالنموذج الضبابي الذكي v3 بنجاح فائق!")

        return {
            "status": "success",
            "model": "Smart Fuzzy Engine v3 (recitation-segmenter-v2 + Zipformer Free Decoding + Fuzzy Matcher)",
            "surah_id": surah_id,
            "total_duration": total_dur,
            "detected_phrases": {
                "istiadha": special.get("has_istiadha", False),
                "basmalah": special.get("has_basmalah", False),
                "ameen": special.get("has_ameen", False)
            },
            "data": ayahs_data,
            "alignments": aligned_words,
            "breath_groups": final_breath_groups
        }

    def _align_hybrid_v2(
        self,
        wav_path: str,
        ayahs_raw: List[str],
        surah_id: int = 1,
        reference_text: Optional[str] = None,
        chunk_duration: float = 2.0,
        progress_callback: Optional[Any] = None,
        min_silence_ms: Optional[int] = None,
        min_speech_ms: Optional[int] = None,
        pad_ms: Optional[int] = None,
        repetition_attach: str = "next"
    ) -> Dict[str, Any]:
        """
        المسار الهجين الذكي v2:
        1. التقطيع العصبي للأنفاس والوقف عبر recitation-segmenter-v2 على GPU
        2. كشف البسملة والاستعاذة ومطابقة تسلسل الكلمات عبر Zipformer v3
        3. المحاذاة القسرية المجهرية لكل مقطع نَفَس عبر Wav2Vec2 على GPU
        4. إغلاق الفجوات الزمنية وفق قواعد الوصل والنَّفَس
        """
        try:
            import soundfile as sf
            audio, sr = sf.read(wav_path, dtype='float32')
            if len(audio.shape) > 1:
                audio = audio.mean(axis=1)
            if sr != 16000:
                audio = librosa.resample(audio, orig_sr=sr, target_sr=16000)
                sr = 16000
        except Exception:
            audio, sr = librosa.load(wav_path, sr=16000, mono=True)
            sr = 16000

        total_dur = len(audio) / float(sr)

        # =========================================================================
        # المرحلة 1: التقطيع العصبي للأنفاس والوقف عبر recitation-segmenter-v2 على GPU
        # =========================================================================
        if progress_callback:
            progress_callback(10, "المرحلة 1: كشف وتقطيع الأنفاس والوقف العصبي عبر recitation-segmenter-v2 على GPU...")

        neural_breath_intervals = self.segmenter.segment_audio(
            audio,
            sr=sr,
            min_silence_ms=min_silence_ms,
            min_speech_ms=min_speech_ms,
            pad_ms=pad_ms
        )
        print(f"[+] recitation-segmenter-v2 detected {len(neural_breath_intervals)} breath intervals (silence={min_silence_ms or self.segmenter.min_silence_duration_ms}ms, speech={min_speech_ms or self.segmenter.min_speech_duration_ms}ms).")

        # =========================================================================
        # المرحلة 2: كشف البسملة والاستعاذة ومطابقة تسلسل الكلمات عبر Zipformer v3
        # =========================================================================
        if progress_callback:
            progress_callback(30, "المرحلة 2: كشف البسملة والاستعاذة ومطابقة الكلمات عبر Zipformer v3...")

        zip_res = self.zipformer.align_recitation(
            wav_path=wav_path,
            ayahs_raw=ayahs_raw,
            surah_id=surah_id,
            reference_text=reference_text,
            chunk_duration=chunk_duration,
            progress_callback=None
        )

        detected_phrases = zip_res.get("detected_phrases", {})
        baseline_alignments = zip_res.get("alignments", [])
        original_ayahs = zip_res.get("data", [])

        if not baseline_alignments:
            print("[-] Baseline alignment failed, returning zipformer fallback.")
            return zip_res

        # =========================================================================
        # المرحلة 3: توزيع الكلمات بدقة على مقاطع النَّفَس المستخرجة عصبياً
        # =========================================================================
        if progress_callback:
            progress_callback(50, "المرحلة 3: تعيين وتوزيع الكلمات على مقاطع النَّفَس الحقيقية...")

        num_words = len(baseline_alignments)
        num_intervals = len(neural_breath_intervals)

        # تعيين كل كلمة للمقطع النَّفَسي الذي بدأ فيه نطقها قبل السكت
        word_interval_indices = []
        for w_idx, w_item in enumerate(baseline_alignments):
            w_start = w_item["start"]
            w_mid = (w_item["start"] + w_item["end"]) / 2.0
            
            assigned = -1
            # 1. فحص وقوع بداية الكلمة داخل المقطع النَّفَسي
            for k in range(num_intervals):
                it = neural_breath_intervals[k]
                if it["start"] - 0.15 <= w_start <= it["end"] + 0.10:
                    assigned = k
                    break
                    
            # 2. إذا وقعت في فترة السكت الفاصل بين مقطعين
            if assigned == -1:
                for k in range(num_intervals - 1):
                    if neural_breath_intervals[k]["end"] < w_start < neural_breath_intervals[k + 1]["start"]:
                        mid_pause = (neural_breath_intervals[k]["end"] + neural_breath_intervals[k + 1]["start"]) / 2.0
                        assigned = k if w_start <= mid_pause else (k + 1)
                        break
                        
            # 3. خطة احتياطية لأقرب مقطع
            if assigned == -1:
                best_dist = float("inf")
                assigned = 0
                for k in range(num_intervals):
                    d = min(abs(w_mid - neural_breath_intervals[k]["start"]), abs(w_mid - neural_breath_intervals[k]["end"]))
                    if d < best_dist:
                        best_dist = d
                        assigned = k
                        
            word_interval_indices.append(assigned)

        # فرض الرتابة الزمنية الصارمة (Monotonicity) لمنع ارتداد الكلمات للخلف
        for i in range(1, len(word_interval_indices)):
            if word_interval_indices[i] < word_interval_indices[i - 1]:
                word_interval_indices[i] = word_interval_indices[i - 1]

        # تجميع مقاطع النَّفَس والكلمات التابعة لها مع إكمال الكلمات الناقصة في نهاية النَّفَس
        raw_breath_groups = []
        for int_idx, interval in enumerate(neural_breath_intervals):
            group_word_indices = [i for i, mapped_idx in enumerate(word_interval_indices) if mapped_idx == int_idx]
            if not group_word_indices:
                continue

            # التحقق التلقائي الذكي من الكلمات الساقطة عند نهاية النَّفَس قبل السكت
            last_idx = group_word_indices[-1]
            last_w_end = baseline_alignments[last_idx]["end"]

            next_int_start = total_dur
            if int_idx + 1 < num_intervals:
                next_int_start = neural_breath_intervals[int_idx + 1]["start"]

            while last_idx + 1 < num_words:
                next_cand = baseline_alignments[last_idx + 1]
                # الكلمة التالية لا يمكن أن تنتمي لهذا النَّفَس إذا بدأت مع أو بعد النَّفَس التالي أو بعد نهاية النَّفَس الحالي بفاصل واضح
                if next_cand.get("start", 0.0) >= next_int_start - 0.10 or next_cand.get("start", 0.0) > interval["end"] + 0.35:
                    break

                test_words = [baseline_alignments[idx]["word"] for idx in group_word_indices] + [next_cand["word"]]
                seg_s = max(0.0, interval["start"] - 0.1)
                seg_e = min(total_dur, max(interval["end"] + 0.6, next_int_start))
                seg_audio = audio[int(seg_s * sr):int(seg_e * sr)]
                try:
                    seg_res = self.wav2vec2.align_segment(seg_audio, test_words, sr)
                    if len(seg_res) == len(test_words):
                        cand_dur = seg_res[-1]["end"] - seg_res[-1]["start"]
                        cand_aligned_end = seg_s + seg_res[-1]["end"]
                        # يجب أن تكون الكلمة ذات مدة طبيعية وتكتمل قبل انطلاق نطق النَّفَس التالي
                        if cand_dur >= 0.08 and cand_aligned_end <= next_int_start + 0.05:
                            claimed_idx = last_idx + 1
                            group_word_indices.append(claimed_idx)
                            word_interval_indices[claimed_idx] = int_idx
                            last_idx += 1
                            last_w_end = cand_aligned_end
                            interval["end"] = max(interval["end"], cand_aligned_end)
                            continue
                except Exception:
                    pass
                break

            g_words = [baseline_alignments[i] for i in group_word_indices]
            g_text = " ".join([w["word"] for w in g_words])
            raw_breath_groups.append({
                "group_index": len(raw_breath_groups) + 1,
                "start_time": interval["start"],
                "end_time": interval["end"],
                "text": g_text,
                "words": g_words,
                "word_indices": group_word_indices
            })

        # في حال عدم وجود أي مقطع مطابق، نعتمد مقاطع Zipformer الأصلية كإجراء أمان
        if not raw_breath_groups:
            raw_breath_groups = zip_res.get("breath_groups", [])

        # =========================================================================
        # المرحلة 4: المحاذاة المجهرية القسرية بـ Wav2Vec2 لكل مقطع نَفَس على GPU
        # =========================================================================
        gc.collect()
        if progress_callback:
            progress_callback(65, "المرحلة 4: المحاذاة المجهرية للحروف والكلمات عبر Wav2Vec2 على GPU...")

        total_groups = len(raw_breath_groups)
        refined_alignments_list = [None] * num_words

        for g_idx, group in enumerate(raw_breath_groups):
            g_start = max(0.0, group["start_time"])
            g_end = min(total_dur, group["end_time"])
            group_words_raw = [w["word"] for w in group.get("words", [])]
            group_word_indices = group.get("word_indices", [])

            if not group_words_raw or g_end <= g_start:
                continue

            # استقطاع المقطع الصوتي للنَّفَس مع هامش أمان خفيف
            pad_before = 0.25
            pad_after = 0.25

            if g_idx > 0:
                prev_end = max(0.0, raw_breath_groups[g_idx - 1].get("end_time", 0.0))
                if g_start > prev_end:
                    mid_prev = (prev_end + g_start) / 2.0
                    safe_start = max(mid_prev, g_start - pad_before)
                else:
                    safe_start = max(0.0, g_start - pad_before)
            else:
                safe_start = max(0.0, g_start - pad_before)

            if g_idx < total_groups - 1:
                next_start = min(total_dur, raw_breath_groups[g_idx + 1].get("start_time", total_dur))
                if next_start > g_end:
                    mid_next = (g_end + next_start) / 2.0
                    safe_end = min(mid_next, g_end + pad_after)
                else:
                    safe_end = min(total_dur, g_end + pad_after)
            else:
                safe_end = min(total_dur, g_end + pad_after)

            safe_start = max(0.0, min(total_dur, safe_start))
            safe_end = max(safe_start + 0.1, min(total_dur, safe_end))

            s_sample = int(safe_start * sr)
            e_sample = int(safe_end * sr)
            chunk_audio = audio[s_sample:e_sample]
            chunk_start_sec = safe_start

            # محاذاة مقطع النَّفَس قسرياً بدقة الإطار الواحد عبر Wav2Vec2
            segment_alignments = self.wav2vec2.align_segment(
                audio_segment=chunk_audio,
                words=group_words_raw,
                sr=sr
            )

            # تحويل التوقيت النسبي إلى توقيت التسجيل الإجمالي
            if segment_alignments and len(segment_alignments) == len(group_words_raw):
                group_aligned_words = []
                for local_i, w_item in enumerate(segment_alignments):
                    global_start = float(chunk_start_sec + w_item["start"])
                    global_end = float(chunk_start_sec + w_item["end"])

                    global_start = max(0.0, min(total_dur, global_start))
                    global_end = max(global_start + 0.04, min(total_dur, global_end))

                    w_dict = {
                        "word": w_item["word"],
                        "start": round(global_start, 3),
                        "end": round(global_end, 3),
                        "confidence": w_item.get("confidence", 1.0)
                    }
                    group_aligned_words.append(w_dict)
                    orig_w_idx = group_word_indices[local_i]
                    refined_alignments_list[orig_w_idx] = dict(w_dict)
                group["words"] = group_aligned_words
            else:
                # خطة احتياطية: اعتماد توقيتات الأساس
                fallback_words = []
                for local_i, w_item in enumerate(group.get("words", [])):
                    w_dict = {
                        "word": w_item["word"],
                        "start": max(0.0, min(total_dur, float(w_item.get("start", g_start)))),
                        "end": max(0.0, min(total_dur, float(w_item.get("end", g_end))))
                    }
                    fallback_words.append(w_dict)
                    orig_w_idx = group_word_indices[local_i]
                    refined_alignments_list[orig_w_idx] = dict(w_dict)
                group["words"] = fallback_words

            if progress_callback and (g_idx % 4 == 0 or g_idx == total_groups - 1):
                pct = 65 + int((g_idx / max(1, total_groups)) * 25)
                progress_callback(pct, f"المرحلة 4: محاذاة مقطع النَّفَس {g_idx + 1} من {total_groups} على GPU...")

        # ملء أي كلمات متبقية إن وجدت
        for w_idx in range(num_words):
            if refined_alignments_list[w_idx] is None:
                refined_alignments_list[w_idx] = baseline_alignments[w_idx]

        gc.collect()

        # =========================================================================
        # المرحلة 5: إغلاق الفجوات وتجميع مقاطع النَّفَس والآيات
        # =========================================================================
        if progress_callback:
            progress_callback(92, "المرحلة 5: إغلاق الفجوات وتطبيق أحكام الوصل والنَّفَس...")

        # تحديد الفواصل بين مقاطع النَّفَس الحقيقية
        breath_boundaries = set()
        for group in raw_breath_groups[:-1]:
            indices = group.get("word_indices", [])
            if indices:
                breath_boundaries.add(indices[-1])

        # تطبيق قواعد إغلاق الفجوات بدقة تامة باستخدام كشف وادي الطاقة الطيفية
        refined_alignments = self.bridge_word_gaps_with_breath_rules(
            words=refined_alignments_list,
            breath_boundaries=breath_boundaries,
            total_dur=total_dur,
            audio=audio,
            sr=sr
        )

        # كشف تكرار الوقف والابتداء وإعادة الآيات بين مقاطع الأنفاس عبر فحص تفريغ Zipformer
        repetition_meta = self.detect_breath_repetitions(
            audio=audio,
            sr=sr,
            intervals=raw_breath_groups,
            zipformer_recognizer=self.zipformer.recognizer
        )

        # بناء خريطة ربط الفهرس الأصلي لكل كلمة برقم آيتها
        word_idx_to_ayah_num = {}
        curr_w = 0
        for a_info in original_ayahs:
            a_num = a_info["ayah_number"]
            a_count = len(a_info.get("words", []))
            for wi in range(curr_w, curr_w + a_count):
                word_idx_to_ayah_num[wi] = a_num
            curr_w += a_count

        # 1. إعادة بناء مقاطع النَّفَس النهائية المحدثة مع وسوم التكرار والتحكم بموضع الضم (next / prev)
        # 1. إعادة بناء مقاطع النَّفَس النهائية المحدثة مع وسوم التكرار واعتماد الوقف بحسب نموذج model_segmenter
        final_breath_groups = []
        for g_idx, group in enumerate(raw_breath_groups):
            g_indices = group.get("word_indices", [])
            # نعتمد الكلمات المحاذاة الدقيقة من refined_alignments لضمان تحديث الأزمنة وتطبيق فجوات الطاقة
            if g_indices:
                g_words_aligned = [dict(refined_alignments[i]) for i in g_indices if i < len(refined_alignments) and refined_alignments[i]]
                for idx_in_g, global_idx in enumerate(g_indices):
                    if idx_in_g < len(g_words_aligned):
                        g_words_aligned[idx_in_g]["ayah_number"] = word_idx_to_ayah_num.get(global_idx)
            else:
                g_words_aligned = [dict(w) for w in group.get("words", [])]

            rep_info = repetition_meta[g_idx] if g_idx < len(repetition_meta) else {}
            is_rep = rep_info.get("is_repetition", False)
            rep_type = rep_info.get("repetition_type", None)

            if not g_words_aligned:
                continue

            # 1. تحديد حدود الوقف بحسب نموذج التقطيع العصبي model_segmenter
            seg_waqf = float(group.get("end_time", g_words_aligned[-1]["end"]))

            # فحص إذا كان المقطع التالي تكراراً للمقطع الحالي
            next_is_rep = False
            next_overlap_str = ""
            if g_idx < len(raw_breath_groups) - 1:
                next_rep_info = repetition_meta[g_idx + 1] if (g_idx + 1) < len(repetition_meta) else {}
                if next_rep_info.get("is_repetition", False):
                    next_is_rep = True
                    next_overlap_str = next_rep_info.get("overlap_text", "")

            # تحديد بداية التلاوة للنفس التالي بحسب نموذج التقطيع العصبي model_segmenter
            # نعتمد دوماً start_time الخاص بالمقطع التالي كحد أقصى لمنع أي اقتطاع من التكرار أو تسرب صوته للسابق
            if g_idx < len(raw_breath_groups) - 1:
                next_grp = raw_breath_groups[g_idx + 1]
                next_speech_start = float(next_grp.get("start_time", total_dur))
            else:
                next_speech_start = float(total_dur)

            # ضمان اكتمال نطق الكلمة الأخيرة بالكامل بحسب نموذج model_segmenter ومطابقة الذيل الصوتي
            # وإضافة 30 ميلي ثانية في نهايته لضمان عدم بتر أي ذيل صوتي مع حظر تجاوز بداية النَّفَس التالي
            max_safe_bound = min(next_speech_start - 0.04, max(float(g_words_aligned[-1]["end"]), seg_waqf))
            t_true_speech_end = max(max_safe_bound, self.find_madd_tail_end(
                audio=audio,
                sr=sr,
                t_word_end=max_safe_bound,
                t_max_bound=next_speech_start - 0.02
            ))
            t_true_speech_end = min(next_speech_start - 0.015, t_true_speech_end + 0.030)
            g_words_aligned[-1]["end"] = t_true_speech_end
            if g_indices and g_indices[-1] < len(refined_alignments):
                refined_alignments[g_indices[-1]]["end"] = t_true_speech_end

            # تحديد الحد الفاصل بين النَّفَسين في منتصف السكت الصامت بعد الوقف مع إضافة 30 ميلي ثانية لصالح نهاية النفس وخصمها من بداية التالي
            if g_idx < len(raw_breath_groups) - 1:
                if next_speech_start > t_true_speech_end:
                    split_boundary = (t_true_speech_end + next_speech_start) / 2.0 + 0.030
                    split_boundary = max(t_true_speech_end + 0.015, min(next_speech_start - 0.015, split_boundary))
                    g_actual_end = split_boundary
                else:
                    g_actual_end = next_speech_start
            else:
                g_actual_end = float(total_dur)

            rep_words = []
            if repetition_attach == "next":
                # إذا كان المقطع الحالي هو مقطع التكرار، يتم استنساخ الكلمات المكررة من نهاية المقطع السابق
                if is_rep and g_idx > 0 and final_breath_groups:
                    prev_group = final_breath_groups[-1]
                    prev_words = prev_group.get("words", [])
                    num_rep = self.identify_repeated_word_count(prev_words, rep_info.get("overlap_text", ""))
                    if num_rep > 0 and len(prev_words) >= num_rep:
                        rep_words = [dict(w) for w in prev_words[-num_rep:]]
                        for rw in rep_words:
                            rw["is_repetition"] = True
                            rw["repetition_type"] = rep_type or "waqf_ibtida"

                        def _clean_w(s: str) -> str:
                            s = re.sub(r'[\u064B-\u065F\u0610-\u061A\u06D6-\u06ED\uFD3E\uFD3Fۖۗۚۛۜ۠ۥۦ]', '', s)
                            s = re.sub(r'[ٱإأآء]', 'ا', s)
                            s = s.replace('ة', 'ه').replace('ى', 'ي').replace('ئ', 'ي').replace('ؤ', 'و')
                            s = s.replace('ذ', 'د').replace('ث', 'ت').replace('ظ', 'ض')
                            return re.sub(r'[^\w]', '', s).strip()

                        # إزالة التكرار من بداية كلمات المقطع الحالي إذا كانت تشمل نهاية الكلمات المكررة المستنسخة
                        matched_overlap_prefix = 0
                        for k in range(min(len(rep_words), len(g_words_aligned)), 0, -1):
                            rep_tail_words = [_clean_w(w["word"]) for w in rep_words[-k:]]
                            curr_head_words = [_clean_w(w["word"]) for w in g_words_aligned[:k]]
                            if rep_tail_words == curr_head_words:
                                matched_overlap_prefix = k
                                break

                        remaining_g_words = g_words_aligned[matched_overlap_prefix:]
                        all_group_words = [rw["word"] for rw in rep_words] + [w["word"] for w in remaining_g_words]
                        g_s = max(0.0, group["start_time"] - 0.25)
                        g_e = min(total_dur, group["end_time"] + 0.25)
                        chunk_audio = audio[int(g_s * sr):int(g_e * sr)]
                        try:
                            aligned_sub = self.wav2vec2.align_segment(chunk_audio, all_group_words, sr)
                            if len(aligned_sub) == len(all_group_words):
                                new_words_aligned = []
                                for idx_w, sub_w in enumerate(aligned_sub):
                                    is_this_rep = (idx_w < len(rep_words))
                                    if is_this_rep:
                                        a_num = rep_words[idx_w].get("ayah_number")
                                    else:
                                        rem_idx = idx_w - len(rep_words)
                                        a_num = remaining_g_words[rem_idx].get("ayah_number") if rem_idx < len(remaining_g_words) else None

                                    new_words_aligned.append({
                                        "word": sub_w["word"],
                                        "start": round(g_s + sub_w["start"], 3),
                                        "end": round(g_s + sub_w["end"], 3),
                                        "confidence": sub_w.get("confidence", 1.0),
                                        "ayah_number": a_num,
                                        "is_repetition": is_this_rep,
                                        "repetition_type": rep_type if is_this_rep else None
                                    })
                                g_words_aligned = new_words_aligned
                                if g_idx < len(raw_breath_groups) - 1:
                                    t_rep_end = min(next_speech_start - 0.04, max(float(g_words_aligned[-1]["end"]), seg_waqf))
                                    t_rep_end = max(t_rep_end, self.find_madd_tail_end(
                                        audio=audio,
                                        sr=sr,
                                        t_word_end=t_rep_end,
                                        t_max_bound=next_speech_start - 0.02
                                    ))
                                    t_rep_end = min(next_speech_start - 0.015, t_rep_end + 0.030)
                                    g_words_aligned[-1]["end"] = t_rep_end
                                    if next_speech_start > t_rep_end:
                                        split_boundary = (t_rep_end + next_speech_start) / 2.0 + 0.030
                                        split_boundary = max(t_rep_end + 0.015, min(next_speech_start - 0.015, split_boundary))
                                        g_actual_end = split_boundary
                                    else:
                                        g_actual_end = next_speech_start
                                else:
                                    g_actual_end = float(total_dur)
                        except Exception as e_w2v:
                            print(f"[-] Repetition alignment fallback: {e_w2v}")
                            
                    if not rep_words:
                        is_rep = False
                        rep_type = None

            elif repetition_attach == "prev":
                # في خيار "ضم الإعادة للنفس السابق":
                if next_is_rep and g_idx < len(raw_breath_groups) - 1:
                    next_group = raw_breath_groups[g_idx + 1]
                    next_indices = next_group.get("word_indices", [])
                    if next_indices and next_indices[0] < len(refined_alignments):
                        first_cont_word = refined_alignments[next_indices[0]]
                        t_split = self.find_energy_valley(audio, sr, first_cont_word["start"], window_before=0.04, window_after=0.04)
                        g_actual_end = t_split

            # ربط بداية النَّفَس بسلاسة مع نهاية النَّفَس السابق لضمان استمرارية التلاوة ومنع أي فجوات ميتة
            if g_idx > 0 and final_breath_groups:
                prev_end = final_breath_groups[-1]["end_time"]
                g_actual_start = prev_end
            else:
                g_actual_start = 0.0 if group.get("start_time", 0.0) < 0.3 else max(0.0, float(group.get("start_time", 0.0)) - 0.1)

            # التأكد من أن حدود النَّفَس تحتضن الكلمات تماماً ولا تبترها
            if g_words_aligned:
                if g_idx == 0:
                    g_actual_start = min(g_actual_start, g_words_aligned[0]["start"])
                g_actual_end = max(g_actual_end, g_words_aligned[-1]["end"])

            # إبقاء الكلمات بأزمنتها الصوتية الحقيقية (بدون مطها لملء صمت النَّفَس)
            # if g_words_aligned:
            #     g_words_aligned[0]["start"] = round(float(g_actual_start), 3)
            #     g_words_aligned[-1]["end"] = round(float(g_actual_end), 3)

            # مزامنة الكلمات غير المكررة للعودة إلى refined_alignments لضمان تحديث الأزمنة دون الكتابة فوق كلمات المصحف
            if g_indices and g_words_aligned:
                offset = len(rep_words) if (is_rep and repetition_attach == "next" and rep_words) else 0
                for idx_in_g, global_idx in enumerate(g_indices):
                    src_idx = offset + idx_in_g
                    if global_idx < len(refined_alignments) and src_idx < len(g_words_aligned):
                        refined_alignments[global_idx] = dict(g_words_aligned[src_idx])

            bg_ayah_nums = sorted(list(set(w.get("ayah_number") for w in g_words_aligned if w.get("ayah_number") is not None)))
            final_breath_groups.append({
                "group_index": g_idx + 1,
                "start_time": round(float(g_actual_start), 3),
                "end_time": round(float(g_actual_end), 3),
                "duration": round(float(g_actual_end - g_actual_start), 3),
                "text": " ".join([w["word"] for w in g_words_aligned]),
                "words": g_words_aligned,
                "word_indices": g_indices,
                "ayah_numbers": bg_ayah_nums,
                "is_repetition": is_rep,
                "repetition_type": rep_type,
                "overlap_text": rep_info.get("overlap_text", "")
            })

        # 2. تجميع الكلمات الفعلية المنطوقة لكل آية (بما فيها كلمات التكرار والكلمات المستمرة كاملة)
        ayah_words_collected = {a_info["ayah_number"]: [] for a_info in original_ayahs}

        for bg in final_breath_groups:
            for w in bg.get("words", []):
                a_num = w.get("ayah_number")
                if a_num in ayah_words_collected:
                    ayah_words_collected[a_num].append(dict(w))

        ayahs_data = []
        for a_idx, a_info in enumerate(original_ayahs):
            a_num = a_info["ayah_number"]
            a_words_aligned = ayah_words_collected.get(a_num, [])

            if not a_words_aligned:
                cnt = len(a_info.get("words", []))
                start_w = sum(len(original_ayahs[k].get("words", [])) for k in range(a_idx))
                a_words_aligned = [dict(w) for w in refined_alignments[start_w : start_w + cnt]]

            if a_words_aligned:
                a_start = a_words_aligned[0]["start"]
                a_end = a_words_aligned[-1]["end"]
            else:
                a_start = a_info.get("start_time", 0.0)
                a_end = a_info.get("end_time", total_dur)

            ayahs_data.append({
                "ayah_number": a_num,
                "start_time": a_start,
                "end_time": a_end,
                "text": a_info["text"],
                "words": a_words_aligned
            })

        # مطابقة نهاية الآية ونهاية آخر كلمة مع نهاية النَّفَس في حال وجود وقف عند نهاية الآية
        for i, a_item in enumerate(ayahs_data):
            if a_item.get("words"):
                a_last_w = a_item["words"][-1]
                matched_bg = None
                for bg in final_breath_groups:
                    if bg.get("words"):
                        bg_last_w = bg["words"][-1]
                        if (bg_last_w.get("id") and bg_last_w.get("id") == a_last_w.get("id")) or \
                           (bg_last_w["start"] == a_last_w["start"] and bg_last_w["word"] == a_last_w["word"]):
                            matched_bg = bg
                            break

                if matched_bg:
                    a_item["end_time"] = matched_bg["end_time"]
                    a_item["words"][-1]["end"] = matched_bg["words"][-1]["end"]
                    if i + 1 < len(ayahs_data):
                        ayahs_data[i + 1]["start_time"] = matched_bg["end_time"]
                else:
                    # في حال الوصل بين آيتين داخل نفس النَّفَس
                    if i + 1 < len(ayahs_data):
                        if ayahs_data[i + 1].get("words") and a_item.get("words"):
                            next_w_start = ayahs_data[i + 1]["words"][0]["start"]
                            curr_w_end = a_item["words"][-1]["end"]
                            a_item["words"][-1]["end"] = min(next_w_start - 0.010, curr_w_end + 0.030)
                            mid_wasl = (a_item["words"][-1]["end"] + next_w_start) / 2.0 + 0.030
                            mid_wasl = min(next_w_start - 0.010, max(a_item["words"][-1]["end"] + 0.010, mid_wasl))
                            a_item["end_time"] = round(mid_wasl, 3)
                            ayahs_data[i + 1]["start_time"] = round(mid_wasl, 3)
                        else:
                            a_item["end_time"] = ayahs_data[i + 1]["start_time"]
            else:
                if i + 1 < len(ayahs_data):
                    a_item["end_time"] = ayahs_data[i + 1]["start_time"]

        # ضبط بداية الآية الأولى ونهاية الآية الأخيرة
        if ayahs_data and final_breath_groups:
            ayahs_data[0]["start_time"] = final_breath_groups[0]["start_time"]
            ayahs_data[-1]["end_time"] = round(float(total_dur), 3)

        # ضمان تطابق الكلمات الأولى والأخيرة لكل آية مع حدود الآية تماماً (الكلمات تتبع حدود الآية)
        for a_item in ayahs_data:
            if a_item.get("words"):
                a_item["words"][0]["start"] = a_item["start_time"]
                a_item["words"][-1]["end"] = a_item["end_time"]
            a_item["duration"] = round(float(a_item["end_time"] - a_item["start_time"]), 3)

        if progress_callback:
            progress_callback(100, "اكتملت المحاذاة الهجينة المزدوجة بالتقطيع العصبي بنجاح تام!")

        return {
            "status": "success",
            "model": "Hybrid v2 (recitation-segmenter-v2 GPU + Zipformer v3 + Wav2Vec2 XLSR-53 GPU)",
            "surah_id": surah_id,
            "total_duration": total_dur,
            "detected_phrases": detected_phrases,
            "data": ayahs_data,
            "ayahs": ayahs_data,
            "alignments": refined_alignments,
            "breath_groups": final_breath_groups
        }

    @staticmethod
    def detect_breath_repetitions(
        audio: np.ndarray,
        sr: int,
        intervals: List[Dict[str, Any]],
        zipformer_recognizer: Any
    ) -> List[Dict[str, Any]]:
        """
        كشف فائق الدقة والسرعة لتكرار الوقف والابتداء وإعادة الآيات بين مقاطع الأنفاس
        باستخدام تفريغ Zipformer اللحظي
        """
        if not intervals or zipformer_recognizer is None:
            return [{"is_repetition": False, "repetition_type": None, "overlap_text": ""} for _ in intervals]

        def _clean_arabic(s: str) -> str:
            s = re.sub(r'[\u064B-\u065F\u0610-\u061A\u06D6-\u06ED\uFD3E\uFD3Fۖۗۚۛۜ۠ۥۦ]', '', s)
            s = re.sub(r'[ٱإأآ]', 'ا', s)
            s = s.replace('ة', 'ه').replace('ى', 'ي').replace('ئ', 'ي').replace('ؤ', 'و')
            s = s.replace('ذ', 'د').replace('ث', 'ت').replace('ظ', 'ض')
            return re.sub(r'[^\w]', '', s).strip()

        clean_texts = []
        for seg in intervals:
            s_sec = seg.get("start", seg.get("start_time", 0.0))
            e_sec = seg.get("end", seg.get("end_time", 0.0))
            chunk = audio[int(s_sec * sr):int(e_sec * sr)]
            if len(chunk) < 1600:
                clean_texts.append("")
                continue
            stream = zipformer_recognizer.create_stream()
            stream.accept_waveform(sr, chunk)
            while zipformer_recognizer.is_ready(stream):
                zipformer_recognizer.decode_stream(stream)
            stream.input_finished()
            while zipformer_recognizer.is_ready(stream):
                zipformer_recognizer.decode_stream(stream)
            raw_res = zipformer_recognizer.get_result_as_json_string(stream)
            tokens = json.loads(raw_res).get("tokens", [])
            raw_t = "".join([t for t in tokens if t != "<blank>"]).replace(" ", " ").strip()
            clean_texts.append(_clean_arabic(raw_t))

        repetition_results = []
        for i in range(len(intervals)):
            if i == 0 or not clean_texts[i] or not clean_texts[i - 1]:
                repetition_results.append({
                    "is_repetition": False,
                    "repetition_type": None,
                    "overlap_chars": 0,
                    "overlap_text": ""
                })
                continue

            curr_clean = clean_texts[i]
            prev_clean = clean_texts[i - 1]
            prev_tail = prev_clean[-min(45, len(prev_clean)):]

            max_overlap_len = 0
            best_overlap_str = ""

            for length in range(min(40, len(curr_clean)), 2, -1):
                prefix = curr_clean[:length]
                loc = prev_clean.rfind(prefix)
                if loc != -1:
                    # يجب أن يصل التطابق إلى نهاية النَّفَس السابق (ذروة الوقف)
                    # نوسع مسافة البحث إلى 15 حرفاً لالتقاط أي تكرار حقيقي حتى لو هلوس الموديل بعض الأحرف
                    reaches_tail = (len(prev_clean) - (loc + len(prefix))) <= 15
                    if reaches_tail:
                        max_overlap_len = length
                        best_overlap_str = prefix
                        break

            # نكتفي بتطابق 4 أحرف كحد أدنى في تفريغ ASR، وسيقوم فلتر التطابق مع النص الحقيقي لاحقاً بإسقاط الوهمية
            if max_overlap_len >= 4:
                is_full = (max_overlap_len >= len(curr_clean) - 3)
                repetition_results.append({
                    "is_repetition": True,
                    "repetition_type": "verse_retake" if is_full else "waqf_ibtida",
                    "overlap_chars": max_overlap_len,
                    "overlap_text": best_overlap_str
                })
            else:
                repetition_results.append({
                    "is_repetition": False,
                    "repetition_type": None,
                    "overlap_chars": 0,
                    "overlap_text": ""
                })

        return repetition_results

    @staticmethod
    def identify_repeated_word_count(prev_words: List[Dict[str, Any]], overlap_str: str) -> int:
        """
        تحديد عدد الكلمات المتطابقة من نهاية النَّفَس السابق بدقة رياضية متناهية
        """
        if not prev_words or not overlap_str:
            return 0

        import difflib

        def _clean(s: str) -> str:
            s = re.sub(r'[\u064B-\u065F\u0610-\u061A\u06D6-\u06ED\uFD3E\uFD3Fۖۗۚۛۜ۠ۥۦ]', '', s)
            s = re.sub(r'[ٱإأآء]', 'ا', s)
            s = s.replace('ة', 'ه').replace('ى', 'ي').replace('ئ', 'ي').replace('ؤ', 'و')
            s = s.replace('ذ', 'د').replace('ث', 'ت').replace('ظ', 'ض')
            return re.sub(r'[^\w]', '', s).strip()

        clean_overlap = _clean(overlap_str)
        best_k = 1
        best_sim = -1.0

        for k in range(1, min(len(prev_words) + 1, 12)):
            tail = _clean("".join([w["word"] for w in prev_words[-k:]]))
            sim = difflib.SequenceMatcher(None, tail, clean_overlap).ratio()
            if sim > best_sim:
                best_sim = sim
                best_k = k

        # فلترة التكرارات الوهمية الناتجة عن هلوسات ASR
        # إذا كانت نسبة التطابق مع النص الحقيقي أقل من 65%، فهذا يعني أنه تكرار وهمي
        if best_sim < 0.65:
            return 0

        return best_k

    @staticmethod
    def find_energy_valley(
        audio: np.ndarray,
        sr: int,
        t_center: float,
        window_before: float = 0.060,
        window_after: float = 0.025,
        min_time: float = 0.0,
        max_time: float = float("inf")
    ) -> float:
        """
        البحث عن وادي الطاقة الصوتية (Local Energy Minimum) حول نقطة الانتقال التقديرية
        لتحديد لحظة الانتقال الحقيقية بين الكلمتين ومنع اقتطاع أو نزف مخرج الحرف الأول.
        """
        if audio is None or len(audio) == 0:
            return t_center

        t_min = max(min_time, t_center - window_before)
        t_max = min(max_time, t_center + window_after)
        if t_max <= t_min:
            return t_center

        s_start = int(t_min * sr)
        s_end = int(t_max * sr)
        sub = audio[s_start:s_end]

        win = int(0.010 * sr)  # نافذة 10ms (160 عينة عند 16kHz)
        hop = int(0.002 * sr)  # قفزة 2ms (32 عينة عند 16kHz)
        if len(sub) < win:
            return t_center

        num_hops = (len(sub) - win) // hop + 1
        energies = []
        times = []
        for h in range(num_hops):
            w = sub[h * hop : h * hop + win]
            rms = np.sqrt(np.mean(w ** 2) + 1e-12)
            energies.append(rms)
            times.append(t_min + (h * hop + win / 2.0) / sr)

        if not energies:
            return t_center

        # تنعيم ثلاثي لتفادي النقاط الشاذة الناتجة عن الضجيج اللحظي
        if len(energies) >= 3:
            energies = np.convolve(energies, [0.2, 0.6, 0.2], mode='same')

        min_idx = int(np.argmin(energies))
        return round(float(times[min_idx]), 3)

    @staticmethod
    def find_madd_tail_end(
        audio: np.ndarray,
        sr: int,
        t_word_end: float,
        t_max_bound: float
    ) -> float:
        """
        البحث عن نهاية الصوت الطبيعي للمدود أو الحروف الموقوف عليها (مثل الهاء أو النون أو المد العارض)
        قبل السكت الفاصل لمنع قطش آخر الكلمة في نهاية النَّفَس.
        """
        if audio is None or len(audio) == 0 or t_max_bound <= t_word_end:
            return t_word_end

        t_start = max(0.0, t_word_end - 0.25)
        t_end = min(len(audio) / float(sr), t_max_bound)
        if t_end <= t_start:
            return t_word_end

        s_start = int(t_start * sr)
        s_end = int(t_end * sr)
        sub = audio[s_start:s_end]

        win = int(0.020 * sr)
        hop = int(0.005 * sr)
        if len(sub) < win:
            return t_word_end

        num_hops = (len(sub) - win) // hop + 1
        energies = []
        times = []
        for h in range(num_hops):
            w = sub[h * hop : h * hop + win]
            rms = np.sqrt(np.mean(w ** 2) + 1e-12)
            energies.append(rms)
            times.append(t_start + (h * hop + win / 2.0) / sr)

        if not energies:
            return t_word_end

        peak_e = max(energies)
        noise_floor = float(np.percentile(energies, 10))
        silence_thresh = max(noise_floor * 1.6, max(0.008, peak_e * 0.05))

        silence_count = 0
        needed_silence = int(0.035 / 0.005)  # 35ms من الصمت المتصل
        tail_t = t_word_end

        for t, e in zip(times, energies):
            if t >= t_word_end:
                if t >= t_max_bound - 0.02:
                    break
                if e > silence_thresh:
                    silence_count = 0
                    tail_t = t + 0.02
                else:
                    silence_count += 1
                    if silence_count >= needed_silence:
                        break

        return round(float(min(t_max_bound - 0.02, max(t_word_end, tail_t))), 3)

    @staticmethod
    def bridge_word_gaps_with_breath_rules(
        words: List[Dict[str, Any]],
        breath_boundaries: Set[int],
        total_dur: float = None,
        audio: Optional[np.ndarray] = None,
        sr: int = 16000
    ) -> List[Dict[str, Any]]:
        """
        إغلاق جميع الفجوات الزمنية بين الكلمات بالكامل وفق القواعد التالية:
        1. في حال عدم وجود نَفَس بين الكلمتين (وصل صوتي داخل نفس المقطع):
           يتم تطبيق كشف وادي الطاقة الصوتية (Energy Valley Detection) للبحث عن نقطة
           الانخفاض الأدنى للطاقة (Dip) في نافذة ضيقة حول الحد، مما يضمن قطع الكلمة السابقة
           قبل انطلاق مخرج الحرف الأول للكلمة التالية بالمللي ثانية، ومنع قراءة أول الحرف مع السابقة.
        2. في حال وجود نَفَس حقيقي بين الكلمتين (فاصل بين مقطعي نَفَس):
           - إذا كانت المسافة أكبر من 0.4 ثانية: يوضع 0.12 ثانية مع الكلمة التالية والباقي مع الكلمة السابقة.
           - إذا كانت المسافة بين 0.2 و 0.4 ثانية: يوضع 0.08 ثانية مع الكلمة التالية والباقي مع الكلمة السابقة.
           - إذا كانت المسافة أقل من 0.2 ثانية: يوضع 0.04 ثانية مع الكلمة التالية والباقي مع الكلمة السابقة.
        دون ترك أي فجوات زمنية نهائياً.
        """
        if not words:
            return words

        has_audio = audio is not None and len(audio) > 0

        for i in range(len(words) - 1):
            curr_w = words[i]
            next_w = words[i + 1]
            gap = float(next_w["start"]) - float(curr_w["end"])
            is_breath = i in breath_boundaries

            if is_breath:
                # حالة وجود نَفَس حقيقي بين مقاطع النَّفَس:
                # نمد آخر الكلمة فقط ليغطي المد الطبيعي أو مخرج الحرف الموقوف عليه دون تجاوز بداية النَّفَس التالي
                if gap > 0.0 and has_audio:
                    curr_w["end"] = HybridQuranAligner.find_madd_tail_end(
                        audio=audio,
                        sr=sr,
                        t_word_end=float(curr_w["end"]),
                        t_max_bound=float(next_w["start"])
                    )
                elif gap > 0.0:
                    curr_w["end"] = min(float(curr_w["end"]) + 0.05, float(next_w["start"]))
            else:
                # حالة عدم وجود نَفَس بين الكلمتين (وصل صوتي متصل داخل نفس النَّفَس)
                # استخدام كشف وادي الطاقة الصوتية متمحوراً حول نهاية الكلمة السابقة لمنع نزف الحرف الأول
                search_center = float(curr_w["end"])
                min_safe = float(curr_w["start"]) + 0.04
                max_safe = float(next_w["end"]) - 0.04

                if max_safe > min_safe and has_audio:
                    split_point = HybridQuranAligner.find_energy_valley(
                        audio=audio,
                        sr=sr,
                        t_center=search_center,
                        window_before=0.035,  # 35ms للخلف
                        window_after=0.045,   # 45ms للأمام
                        min_time=min_safe,
                        max_time=max_safe
                    )
                    shift_ms = (split_point - search_center) * 1000.0
                    if abs(shift_ms) > 1.0:
                        print(f"  [Energy Dip] '{curr_w.get('word','')}' -> '{next_w.get('word','')}': {search_center:.3f}s -> {split_point:.3f}s (shift: {shift_ms:+.1f}ms)")
                else:
                    if gap > 0.0:
                        split_point = float(curr_w["end"]) + min(0.025, gap * 0.5)
                    else:
                        split_point = (float(curr_w["end"]) + float(next_w["start"])) / 2.0
                    split_point = max(min_safe, min(max_safe, split_point))

                curr_w["end"] = split_point
                next_w["start"] = split_point

        for w in words:
            w["start"] = round(float(w["start"]), 3)
            w["end"] = round(float(w["end"]), 3)
            if total_dur is not None:
                w["start"] = max(0.0, min(total_dur, w["start"]))
                w["end"] = max(w["start"] + 0.02, min(total_dur, w["end"]))

        return words

"""
حزمة المحاذاة القرآنية الهجينة (Hybrid Quranic Alignment Package)
المرحلة 1: تقطيع النَّفَس والوقف القرآني عبر recitation-segmenter-v2 (GPU)
المرحلة 2: كشف البسملة والاستعاذة والخواتم ومطابقة الكلمات عبر QuranLab Zipformer v3
المرحلة 3: المحاذاة القسرية الدقيقة على مستوى الكلمة والحرف عبر Wav2Vec2 XLSR-53 Arabic (GPU)
"""

from .wav2vec2_aligner import Wav2Vec2ForcedAligner
from .recitation_segmenter import QuranRecitationSegmenter
from .hybrid_pipeline import HybridQuranAligner

__all__ = ["Wav2Vec2ForcedAligner", "QuranRecitationSegmenter", "HybridQuranAligner"]

"""Acoustic alignment confidence, not a calibrated recitation correctness score."""
import math


def word_alignment_confidence(log_probs, path, tokens, start_token, end_token, frames):
    """Average token posteriors on nonblank Viterbi states, weighting tokens equally.

    A missing target token receives zero support. Blank/silence frames do not
    inflate confidence, and longer letters do not dominate the word score.
    """
    if end_token <= start_token:
        return None
    scores = {index: [] for index in range(start_token, end_token)}
    for frame in frames:
        state = int(path[frame])
        if state % 2 == 0:
            continue
        index = (state - 1) // 2
        if index in scores:
            value = float(log_probs[frame][tokens[index]])
            probability = math.exp(min(0.0, value)) if math.isfinite(value) else 0.0
            scores[index].append(probability)
    return sum(sum(values) / len(values) if values else 0.0
               for values in scores.values()) / len(scores)

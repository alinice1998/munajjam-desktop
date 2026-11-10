enum AlignmentGranularity { ayah, breath, word }

enum WordListScope { surah, ayah, breath }

double measuredReliability(double supplied, Iterable<WordSegment> words) {
  if (supplied.isFinite) return supplied.clamp(0.0, 1.0);
  final measured = words
      .map((w) => w.reliability)
      .where((v) => v.isFinite)
      .toList();
  if (measured.isEmpty) return double.nan;
  return measured.reduce((a, b) => a + b) / measured.length;
}

class AlignedWordEntry {
  final WordSegment segment;
  final int? ayahIndex;
  final int? wordIndex;
  const AlignedWordEntry(this.segment, {this.ayahIndex, this.wordIndex});
}

class ReviewItem {
  final AlignmentGranularity level;
  final int index;
  final int? ayahIndex;
  final double start;
  final double end;
  final double reliability;
  final String text;
  final bool isError;
  const ReviewItem({
    required this.level,
    required this.index,
    this.ayahIndex,
    required this.start,
    required this.end,
    required this.reliability,
    required this.text,
    this.isError = false,
  });
}

class WordSegment {
  final String word;
  double start;
  double end;
  final int? ayahNumber;
  final double confidence;
  final bool isRepetition;
  final bool isError;
  final String? repetitionType;

  WordSegment({
    required this.word,
    required this.start,
    required this.end,
    this.ayahNumber,
    this.confidence = double.nan,
    this.isRepetition = false,
    this.isError = false,
    this.repetitionType,
  });

  double get duration => end - start;
  double get reliability =>
      confidence.isFinite ? confidence.clamp(0.0, 1.0) : double.nan;

  Map<String, dynamic> toJson() => {
    'word': word,
    'start': double.parse(start.toStringAsFixed(3)),
    'end': double.parse(end.toStringAsFixed(3)),
    if (ayahNumber != null) 'ayah_number': ayahNumber,
    if (confidence.isFinite) 'confidence': confidence,
    if (isRepetition) 'is_repetition': true,
    if (isError) 'is_error': true,
    if (repetitionType != null) 'repetition_type': repetitionType,
  };

  factory WordSegment.fromJson(Map<String, dynamic> json) {
    return WordSegment(
      word: json['word'] ?? '',
      start: (json['start'] as num?)?.toDouble() ?? 0.0,
      end: (json['end'] as num?)?.toDouble() ?? 0.0,
      ayahNumber: json['ayah_number'] as int?,
      confidence: (json['confidence'] as num?)?.toDouble() ?? double.nan,
      isRepetition: json['is_repetition'] == true,
      isError: json['is_error'] == true || json['has_error'] == true,
      repetitionType: json['repetition_type'] as String?,
    );
  }

  WordSegment copyWith({
    String? word,
    double? start,
    double? end,
    int? ayahNumber,
    double? confidence,
    bool? isRepetition,
    bool? isError,
    String? repetitionType,
  }) {
    return WordSegment(
      word: word ?? this.word,
      start: start ?? this.start,
      end: end ?? this.end,
      ayahNumber: ayahNumber ?? this.ayahNumber,
      confidence: confidence ?? this.confidence,
      isRepetition: isRepetition ?? this.isRepetition,
      isError: isError ?? this.isError,
      repetitionType: repetitionType ?? this.repetitionType,
    );
  }
}

class BreathGroup {
  final double confidence;
  final bool isError;
  int groupIndex;
  double startTime;
  double endTime;
  double duration;
  String text;
  List<WordSegment> words;
  List<int> ayahNumbers;
  bool isRepetition;
  String? repetitionType;
  String? overlapText;

  BreathGroup({
    this.confidence = double.nan,
    this.isError = false,
    required this.groupIndex,
    required this.startTime,
    required this.endTime,
    required this.duration,
    required this.text,
    required this.words,
    required this.ayahNumbers,
    this.isRepetition = false,
    this.repetitionType,
    this.overlapText,
  });

  double get reliability => measuredReliability(confidence, words);

  Map<String, dynamic> toJson() => {
    'group_index': groupIndex,
    if (confidence.isFinite) 'confidence': confidence,
    if (isError) 'is_error': true,
    'start_time': double.parse(startTime.toStringAsFixed(3)),
    'end_time': double.parse(endTime.toStringAsFixed(3)),
    'duration': double.parse(duration.toStringAsFixed(3)),
    'text': text,
    'words': words.map((w) => w.toJson()).toList(),
    'ayah_numbers': ayahNumbers,
    if (isRepetition) 'is_repetition': true,
    if (repetitionType != null) 'repetition_type': repetitionType,
    if (overlapText != null) 'overlap_text': overlapText,
  };

  factory BreathGroup.fromJson(Map<String, dynamic> json) {
    var rawWords = json['words'] as List? ?? [];
    return BreathGroup(
      confidence:
          (json['confidence'] as num?)?.toDouble() ??
          (json['similarity'] as num?)?.toDouble() ??
          double.nan,
      groupIndex: json['group_index'] ?? 1,
      isError: json['is_error'] == true || json['has_error'] == true,
      startTime: (json['start_time'] as num?)?.toDouble() ?? 0.0,
      endTime: (json['end_time'] as num?)?.toDouble() ?? 0.0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
      text: json['text'] ?? '',
      words: rawWords
          .map((w) => WordSegment.fromJson(Map<String, dynamic>.from(w as Map)))
          .toList(),
      ayahNumbers:
          (json['ayah_numbers'] as List?)?.map((e) => e as int).toList() ?? [],
      isRepetition: json['is_repetition'] == true,
      repetitionType: json['repetition_type'] as String?,
      overlapText: json['overlap_text'] as String?,
    );
  }

  BreathGroup copyWith({
    double? confidence,
    bool? isError,
    int? groupIndex,
    double? startTime,
    double? endTime,
    double? duration,
    String? text,
    List<WordSegment>? words,
    List<int>? ayahNumbers,
    bool? isRepetition,
    String? repetitionType,
    String? overlapText,
  }) {
    return BreathGroup(
      confidence: confidence ?? this.confidence,
      groupIndex: groupIndex ?? this.groupIndex,
      isError: isError ?? this.isError,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      duration:
          duration ??
          (endTime != null && startTime != null
              ? endTime - startTime
              : this.duration),
      text: text ?? this.text,
      words: words ?? this.words.map((w) => w.copyWith()).toList(),
      ayahNumbers: ayahNumbers ?? List.from(this.ayahNumbers),
      isRepetition: isRepetition ?? this.isRepetition,
      repetitionType: repetitionType ?? this.repetitionType,
      overlapText: overlapText ?? this.overlapText,
    );
  }
}

class AyahSegment {
  final bool isError;
  final int ayahNumber;
  double start;
  double end;
  String text;
  double similarity;
  List<WordSegment> words;

  AyahSegment({
    this.isError = false,
    required this.ayahNumber,
    required this.start,
    required this.end,
    required this.text,
    this.similarity = double.nan,
    this.words = const [],
  });

  double get duration => end - start;

  /// Use a supplied score, or measured word confidences; absent scores stay unknown.
  double get reliability => measuredReliability(similarity, words);

  Map<String, dynamic> toJson() => {
    'ayah_number': ayahNumber,
    if (isError) 'is_error': true,
    'start': double.parse(start.toStringAsFixed(3)),
    'end': double.parse(end.toStringAsFixed(3)),
    'text': text,
    if (similarity.isFinite) 'similarity': similarity,
    'words': words.map((w) => w.toJson()).toList(),
  };

  factory AyahSegment.fromJson(Map<String, dynamic> json) {
    var rawWords = json['words'] as List? ?? [];
    return AyahSegment(
      ayahNumber: json['ayah_number'] ?? 1,
      isError: json['is_error'] == true || json['has_error'] == true,
      start:
          (json['start'] as num?)?.toDouble() ??
          (json['start_time'] as num?)?.toDouble() ??
          0.0,
      end:
          (json['end'] as num?)?.toDouble() ??
          (json['end_time'] as num?)?.toDouble() ??
          0.0,
      text: json['text'] ?? '',
      similarity:
          (json['similarity'] as num?)?.toDouble() ??
          (json['confidence'] as num?)?.toDouble() ??
          double.nan,
      words: rawWords.map((w) => WordSegment.fromJson(w)).toList(),
    );
  }

  AyahSegment copyWith({
    bool? isError,
    int? ayahNumber,
    double? start,
    double? end,
    String? text,
    double? similarity,
    List<WordSegment>? words,
  }) {
    return AyahSegment(
      ayahNumber: ayahNumber ?? this.ayahNumber,
      isError: isError ?? this.isError,
      start: start ?? this.start,
      end: end ?? this.end,
      text: text ?? this.text,
      similarity: similarity ?? this.similarity,
      words: words ?? this.words.map((w) => w.copyWith()).toList(),
    );
  }
}

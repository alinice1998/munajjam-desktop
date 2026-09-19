enum AlignmentGranularity {
  ayah,
  breath,
  word,
}

class WordSegment {
  final String word;
  double start;
  double end;
  final int? ayahNumber;
  final double confidence;
  final bool isRepetition;
  final String? repetitionType;

  WordSegment({
    required this.word,
    required this.start,
    required this.end,
    this.ayahNumber,
    this.confidence = 1.0,
    this.isRepetition = false,
    this.repetitionType,
  });

  double get duration => end - start;

  Map<String, dynamic> toJson() => {
        'word': word,
        'start': double.parse(start.toStringAsFixed(3)),
        'end': double.parse(end.toStringAsFixed(3)),
        if (ayahNumber != null) 'ayah_number': ayahNumber,
        'confidence': confidence,
        if (isRepetition) 'is_repetition': true,
        if (repetitionType != null) 'repetition_type': repetitionType,
      };

  factory WordSegment.fromJson(Map<String, dynamic> json) {
    return WordSegment(
      word: json['word'] ?? '',
      start: (json['start'] as num?)?.toDouble() ?? 0.0,
      end: (json['end'] as num?)?.toDouble() ?? 0.0,
      ayahNumber: json['ayah_number'] as int?,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      isRepetition: json['is_repetition'] == true,
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
    String? repetitionType,
  }) {
    return WordSegment(
      word: word ?? this.word,
      start: start ?? this.start,
      end: end ?? this.end,
      ayahNumber: ayahNumber ?? this.ayahNumber,
      confidence: confidence ?? this.confidence,
      isRepetition: isRepetition ?? this.isRepetition,
      repetitionType: repetitionType ?? this.repetitionType,
    );
  }
}

class BreathGroup {
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

  Map<String, dynamic> toJson() => {
        'group_index': groupIndex,
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
      groupIndex: json['group_index'] ?? 1,
      startTime: (json['start_time'] as num?)?.toDouble() ?? 0.0,
      endTime: (json['end_time'] as num?)?.toDouble() ?? 0.0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
      text: json['text'] ?? '',
      words: rawWords.map((w) => WordSegment.fromJson(w as Map<String, dynamic>)).toList(),
      ayahNumbers: (json['ayah_numbers'] as List?)?.map((e) => e as int).toList() ?? [],
      isRepetition: json['is_repetition'] == true,
      repetitionType: json['repetition_type'] as String?,
      overlapText: json['overlap_text'] as String?,
    );
  }

  BreathGroup copyWith({
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
      groupIndex: groupIndex ?? this.groupIndex,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      duration: duration ?? (endTime != null && startTime != null ? endTime - startTime : this.duration),
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
  final int ayahNumber;
  double start;
  double end;
  String text;
  double similarity;
  List<WordSegment> words;

  AyahSegment({
    required this.ayahNumber,
    required this.start,
    required this.end,
    required this.text,
    this.similarity = 0.98,
    this.words = const [],
  });

  double get duration => end - start;

  Map<String, dynamic> toJson() => {
        'ayah_number': ayahNumber,
        'start': double.parse(start.toStringAsFixed(3)),
        'end': double.parse(end.toStringAsFixed(3)),
        'text': text,
        'similarity': similarity,
        'words': words.map((w) => w.toJson()).toList(),
      };

  factory AyahSegment.fromJson(Map<String, dynamic> json) {
    var rawWords = json['words'] as List? ?? [];
    return AyahSegment(
      ayahNumber: json['ayah_number'] ?? 1,
      start: (json['start'] as num?)?.toDouble() ?? (json['start_time'] as num?)?.toDouble() ?? 0.0,
      end: (json['end'] as num?)?.toDouble() ?? (json['end_time'] as num?)?.toDouble() ?? 0.0,
      text: json['text'] ?? '',
      similarity: (json['similarity'] as num?)?.toDouble() ?? 0.98,
      words: rawWords.map((w) => WordSegment.fromJson(w)).toList(),
    );
  }

  AyahSegment copyWith({
    int? ayahNumber,
    double? start,
    double? end,
    String? text,
    double? similarity,
    List<WordSegment>? words,
  }) {
    return AyahSegment(
      ayahNumber: ayahNumber ?? this.ayahNumber,
      start: start ?? this.start,
      end: end ?? this.end,
      text: text ?? this.text,
      similarity: similarity ?? this.similarity,
      words: words ?? this.words.map((w) => w.copyWith()).toList(),
    );
  }
}

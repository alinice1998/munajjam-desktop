import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/alignment_models.dart';
import '../models/surah_model.dart';
import '../services/quran_data_service.dart';
import '../services/quran_metadata.dart';

class AlignmentProvider extends ChangeNotifier {
  int _selectedSurahId = 1;
  String _reciterName = '';
  String _riwaya = 'hafsh';
  String? _alignmentRiwaya;
  AlignmentGranularity _activeGranularity = AlignmentGranularity.ayah;

  List<AyahSegment> _segments = [];
  List<BreathGroup> _breathGroups = [];
  List<AyahSegment> _originalSegments = [];
  List<BreathGroup> _originalBreathGroups = [];

  int? _currentSegmentIndex;
  int? _currentBreathIndex;
  int? _currentWordIndex;
  double? _currentWordStart;
  WordListScope _wordListScope = WordListScope.surah;
  final Map<AlignmentGranularity, double> _reviewThresholds = {
    for (final level in AlignmentGranularity.values) level: 0.90,
  };
  double? get currentWordStart => _currentWordStart;
  WordListScope get wordListScope => _wordListScope;
  double reviewThreshold(AlignmentGranularity level) =>
      _reviewThresholds[level]!;
  void setReviewThreshold(AlignmentGranularity level, double value) {
    if (!value.isFinite) return;
    value = value.clamp(0.0, 1.0);
    if (_reviewThresholds[level] == value) return;
    _reviewThresholds[level] = value;
    _reviewCache.remove(level);
    _reviewPositionsCache.remove(level);
    _reviewIndicesCache.remove(level);
    if (level == AlignmentGranularity.word) _reviewWordStartsCache = null;
    ++_timingRevision;
    notifyListeners();
  }

  bool needsReview(
    AlignmentGranularity level,
    double reliability, {
    bool isError = false,
  }) =>
      isError || (reliability.isFinite && reliability < reviewThreshold(level));

  void setWordListScope(WordListScope scope) {
    if (_wordListScope == scope) return;
    _wordListScope = scope;
    notifyListeners();
  }

  int _alignmentRevision = 0;
  int get alignmentRevision => _alignmentRevision;
  List<AlignedWordEntry>? _wordEntriesCache;
  List<WordSegment>? _waveWordsCache;
  List<double>? _ayahReliabilitiesCache;
  final Map<AlignmentGranularity, List<ReviewItem>> _reviewCandidatesCache = {};
  final Map<AlignmentGranularity, List<ReviewItem>> _reviewCache = {};
  final Map<AlignmentGranularity, List<double>> _reviewPositionsCache = {};
  final Map<AlignmentGranularity, Set<int>> _reviewIndicesCache = {};
  Set<double>? _reviewWordStartsCache;
  List<({double start, double end, String text, String? type})>?
  _repetitionsCache;
  List<double>? _repetitionPositionsCache;
  double? _averageSimilarityCache;
  Object? _visibleWordsKey;
  List<AlignedWordEntry>? _visibleWordsCache;

  /// Call after externally replacing imported model data; internal edits use it automatically.
  void refreshAlignment({bool notify = true}) {
    ++_alignmentRevision;
    ++_timingRevision;
    _wordEntriesCache = null;
    _waveWordsCache = null;
    _ayahReliabilitiesCache = null;
    _reviewCandidatesCache.clear();
    _reviewCache.clear();
    _reviewPositionsCache.clear();
    _reviewIndicesCache.clear();
    _reviewWordStartsCache = null;
    _repetitionsCache = null;
    _repetitionPositionsCache = null;
    _averageSimilarityCache = null;
    _visibleWordsKey = null;
    _visibleWordsCache = null;
    if (notify) notifyListeners();
  }

  List<WordSegment> get waveformWords => _waveWordsCache ??= List.unmodifiable(
    allWordEntries.map((e) => e.segment),
  );
  List<double> get ayahReliabilities {
    if (_ayahReliabilitiesCache != null) return _ayahReliabilitiesCache!;
    final scores = List<double>.filled(_segments.length, double.nan);
    for (final item in _reviewCandidates(AlignmentGranularity.ayah)) {
      scores[item.index] = item.reliability;
    }
    return _ayahReliabilitiesCache = List.unmodifiable(scores);
  }

  Set<int> reviewIndices(AlignmentGranularity level) =>
      _reviewIndicesCache.putIfAbsent(
        level,
        () => Set.unmodifiable(reviewItems(level).map((i) => i.index)),
      );
  Set<double> get reviewWordStarts =>
      _reviewWordStartsCache ??= Set.unmodifiable(
        reviewItems(AlignmentGranularity.word).map((i) => i.start),
      );

  List<AlignedWordEntry> get allWordEntries {
    if (_wordEntriesCache != null) return _wordEntriesCache!;
    final entries = <AlignedWordEntry>[];
    final seen = <String>{};
    String key(WordSegment word) =>
        '${word.start.toStringAsFixed(3)}:${word.word}';
    for (int a = 0; a < _segments.length; a++) {
      for (int w = 0; w < _segments[a].words.length; w++) {
        final word = _segments[a].words[w];
        if (seen.add(key(word))) {
          entries.add(AlignedWordEntry(word, ayahIndex: a, wordIndex: w));
        }
      }
    }
    for (final word in _breathGroups.expand((b) => b.words)) {
      if (seen.add(key(word))) entries.add(AlignedWordEntry(word));
    }
    entries.sort((a, b) => a.segment.start.compareTo(b.segment.start));
    return _wordEntriesCache = List.unmodifiable(entries);
  }

  List<AlignedWordEntry> get visibleWordEntries {
    if (_wordListScope == WordListScope.surah) return allWordEntries;
    final key = (
      _wordListScope,
      _currentSegmentIndex,
      _currentBreathIndex,
      _alignmentRevision,
    );
    if (_visibleWordsKey == key && _visibleWordsCache != null) {
      return _visibleWordsCache!;
    }
    _visibleWordsKey = key;
    return _visibleWordsCache = List.unmodifiable(_filterVisibleWords());
  }

  List<AlignedWordEntry> _filterVisibleWords() {
    final words = allWordEntries;
    if (_wordListScope == WordListScope.surah) return words;
    if (_wordListScope == WordListScope.ayah) {
      final index = _currentSegmentIndex;
      if (index == null) return [];
      final ayah = _segments[index];
      return words
          .where(
            (e) =>
                e.ayahIndex == index ||
                (e.ayahIndex == null &&
                    e.segment.start >= ayah.start &&
                    e.segment.start < ayah.end),
          )
          .toList();
    }
    final index = _currentBreathIndex;
    if (index == null) return [];
    final breath = _breathGroups[index];
    return words
        .where(
          (e) =>
              e.segment.start >= breath.startTime - 0.001 &&
              e.segment.start < breath.endTime,
        )
        .toList();
  }

  Timer? _saveTimer;
  int _timingRevision = 0;
  int get timingRevision => _timingRevision;
  String _saveStatus = 'idle'; // idle, saving, saved, error
  bool _isLocalSession = false;
  String? _localAudioPath;

  String _repetitionMode =
      'visual'; // visual (show badges), final_take (skip repeated takes)

  // Getters
  int get selectedSurahId => _selectedSurahId;
  String get reciterName => _reciterName;
  String get riwaya => _riwaya;
  String get repetitionMode => _repetitionMode;
  AlignmentGranularity get activeGranularity => _activeGranularity;
  List<AyahSegment> get segments => _segments;
  List<BreathGroup> get breathGroups => _breathGroups;
  int? get currentSegmentIndex => _currentSegmentIndex;
  int? get currentBreathIndex => _currentBreathIndex;
  int? get currentWordIndex => _currentWordIndex;
  String get saveStatus => _saveStatus;
  bool get isLocalSession => _isLocalSession;
  String? get localAudioPath => _localAudioPath;
  SurahInfo get currentSurah => getSurahById(_selectedSurahId);

  double get averageSimilarity {
    if (_averageSimilarityCache != null) return _averageSimilarityCache!;
    final measured = _segments
        .map((s) => s.reliability)
        .where((s) => s.isFinite)
        .toList();
    if (measured.isEmpty) return _averageSimilarityCache = double.nan;
    return _averageSimilarityCache =
        measured.reduce((a, b) => a + b) / measured.length;
  }

  void setSurahId(int id) {
    _selectedSurahId = id;
    notifyListeners();
  }

  void setReciterName(String name) {
    _reciterName = name;
    notifyListeners();
  }

  void setRiwaya(String riwaya) {
    _riwaya = riwaya;
    notifyListeners();
  }

  void setGranularity(AlignmentGranularity granularity) {
    if (_activeGranularity == granularity) return;
    _activeGranularity = granularity;
    notifyListeners();
  }

  void setRepetitionMode(String mode) {
    _repetitionMode = mode;
    notifyListeners();
  }

  Object get _selectionKey => (
    _currentSegmentIndex,
    _currentBreathIndex,
    _currentWordIndex,
    _currentWordStart,
  );

  void selectAyah(int index) {
    if (index < 0 || index >= _segments.length) return;
    final previous = _selectionKey;
    updateCurrentTime(_segments[index].start, notify: false);
    _currentSegmentIndex = index;
    if (_selectionKey != previous) notifyListeners();
  }

  void selectBreath(int index) {
    if (index < 0 || index >= _breathGroups.length) return;
    final previous = _selectionKey;
    updateCurrentTime(_breathGroups[index].startTime, notify: false);
    _currentBreathIndex = index;
    if (_selectionKey != previous) notifyListeners();
  }

  void updateCurrentTime(double seconds, {bool notify = true}) {
    int? newAyahIdx;
    for (int i = 0; i < _segments.length; i++) {
      if (seconds >= _segments[i].start && seconds < _segments[i].end) {
        newAyahIdx = i;
        break;
      }
    }

    int? newBreathIdx;
    for (int i = 0; i < _breathGroups.length; i++) {
      if (seconds >= _breathGroups[i].startTime &&
          seconds < _breathGroups[i].endTime) {
        newBreathIdx = i;
        break;
      }
    }

    int? newWordIdx;
    if (newAyahIdx != null) {
      final words = _segments[newAyahIdx].words;
      for (int i = 0; i < words.length; i++) {
        if (seconds >= words[i].start && seconds < words[i].end) {
          newWordIdx = i;
          break;
        }
      }
    }
    double? wordStart;
    if (newAyahIdx != null && newWordIdx != null) {
      wordStart = _segments[newAyahIdx].words[newWordIdx].start;
    } else if (newBreathIdx != null) {
      for (final word in _breathGroups[newBreathIdx].words) {
        if (seconds >= word.start && seconds < word.end) {
          wordStart = word.start;
          break;
        }
      }
    }
    if (wordStart != _currentWordStart ||
        newAyahIdx != _currentSegmentIndex ||
        newBreathIdx != _currentBreathIndex ||
        newWordIdx != _currentWordIndex) {
      _currentSegmentIndex = newAyahIdx;
      _currentBreathIndex = newBreathIdx;
      _currentWordIndex = newWordIdx;
      _currentWordStart = wordStart;
      if (notify) notifyListeners();
    }
  }

  void selectWord(int ayahIndex, int wordIndex) {
    if (ayahIndex < 0 || ayahIndex >= _segments.length) return;
    if (wordIndex < 0 || wordIndex >= _segments[ayahIndex].words.length) return;
    final previous = _selectionKey;
    updateCurrentTime(
      _segments[ayahIndex].words[wordIndex].start,
      notify: false,
    );
    _currentSegmentIndex = ayahIndex;
    _currentWordIndex = wordIndex;
    if (_selectionKey != previous) notifyListeners();
  }

  /// Return the selected start time so both keyboard surfaces use the same navigation.
  double? navigate(int direction, double currentTime) {
    if (_activeGranularity == AlignmentGranularity.word) {
      final words = allWordEntries;
      if (words.isEmpty) return null;
      final current = words.lastIndexWhere(
        (e) => e.segment.start <= currentTime + 0.001,
      );
      final target = words[(current + direction).clamp(0, words.length - 1)];
      if (target.ayahIndex != null && target.wordIndex != null) {
        selectWord(target.ayahIndex!, target.wordIndex!);
      } else {
        updateCurrentTime(target.segment.start);
      }
      return target.segment.start;
    }
    final entries = <({double start, int index, int? word})>[];
    if (_activeGranularity == AlignmentGranularity.breath) {
      for (int i = 0; i < _breathGroups.length; i++) {
        entries.add((start: _breathGroups[i].startTime, index: i, word: null));
      }
    } else {
      for (int i = 0; i < _segments.length; i++) {
        if (_activeGranularity == AlignmentGranularity.ayah) {
          entries.add((start: _segments[i].start, index: i, word: null));
        } else {
          for (int w = 0; w < _segments[i].words.length; w++) {
            entries.add((
              start: _segments[i].words[w].start,
              index: i,
              word: w,
            ));
          }
        }
      }
    }
    if (entries.isEmpty) return null;
    entries.sort((a, b) => a.start.compareTo(b.start));
    int current = entries.lastIndexWhere((e) => e.start <= currentTime + 0.001);
    final target = entries[(current + direction).clamp(0, entries.length - 1)];
    if (_activeGranularity == AlignmentGranularity.breath) {
      selectBreath(target.index);
    } else if (target.word != null) {
      selectWord(target.index, target.word!);
    } else {
      selectAyah(target.index);
    }
    return target.start;
  }

  List<({double start, double end, String text, String? type})>
  get repetitions {
    if (_repetitionsCache != null) return _repetitionsCache!;
    final result = <({double start, double end, String text, String? type})>[];
    final groups = _breathGroups.where((b) => b.isRepetition).toList();
    for (final breath in groups) {
      result.add((
        start: breath.startTime,
        end: breath.endTime,
        text: breath.text,
        type: breath.repetitionType,
      ));
    }
    final seen = groups.map((b) => b.startTime).toSet();
    for (final word in [
      ..._segments.expand((s) => s.words),
      ..._breathGroups.expand((b) => b.words),
    ]) {
      if (!word.isRepetition ||
          groups.any(
            (b) => word.start >= b.startTime && word.start < b.endTime,
          ) ||
          !seen.add(word.start)) {
        continue;
      }
      result.add((
        start: word.start,
        end: word.end,
        text: word.word,
        type: word.repetitionType,
      ));
    }
    result.sort((a, b) => a.start.compareTo(b.start));
    return _repetitionsCache = List.unmodifiable(result);
  }

  List<double> get repetitionPositions => _repetitionPositionsCache ??=
      List.unmodifiable(repetitions.map((r) => r.start));

  List<ReviewItem> reviewItems(AlignmentGranularity level) =>
      _reviewCache.putIfAbsent(
        level,
        () => List.unmodifiable(
          _reviewCandidates(level).where(
            (item) =>
                needsReview(level, item.reliability, isError: item.isError),
          ),
        ),
      );

  List<ReviewItem> _reviewCandidates(AlignmentGranularity level) {
    if (_reviewCandidatesCache.containsKey(level)) {
      return _reviewCandidatesCache[level]!;
    }
    final items = <ReviewItem>[];
    if (level == AlignmentGranularity.ayah) {
      for (int i = 0; i < _segments.length; i++) {
        final a = _segments[i];
        items.add(
          ReviewItem(
            level: level,
            index: i,
            start: a.start,
            end: a.end,
            text: a.text,
            reliability: a.reliability,
            isError: a.isError || a.words.any((w) => w.isError),
          ),
        );
      }
    } else if (level == AlignmentGranularity.breath) {
      for (int i = 0; i < _breathGroups.length; i++) {
        final b = _breathGroups[i];
        items.add(
          ReviewItem(
            level: level,
            index: i,
            start: b.startTime,
            end: b.endTime,
            text: b.text,
            reliability: b.reliability,
            isError: b.isError || b.words.any((w) => w.isError),
          ),
        );
      }
    } else {
      for (final entry in allWordEntries) {
        final w = entry.segment;
        items.add(
          ReviewItem(
            level: level,
            index: entry.wordIndex ?? -1,
            ayahIndex: entry.ayahIndex,
            start: w.start,
            end: w.end,
            text: w.word,
            reliability: w.reliability,
            isError: w.isError,
          ),
        );
      }
    }
    items.sort((a, b) => a.start.compareTo(b.start));
    return _reviewCandidatesCache[level] = List.unmodifiable(items);
  }

  List<double> get errorPositions => _reviewPositionsCache.putIfAbsent(
    _activeGranularity,
    () => List.unmodifiable(
      reviewItems(_activeGranularity).map((i) => i.start).toSet().toList()
        ..sort(),
    ),
  );

  void selectReviewItem(ReviewItem item) {
    setGranularity(item.level);
    if (item.level == AlignmentGranularity.ayah) {
      selectAyah(item.index);
    } else if (item.level == AlignmentGranularity.breath) {
      selectBreath(item.index);
    } else if (item.ayahIndex != null && item.index >= 0) {
      selectWord(item.ayahIndex!, item.index);
    } else {
      updateCurrentTime(item.start);
    }
  }

  double? nextIssue(
    double time, {
    required bool repetition,
    int direction = 1,
  }) {
    final positions = repetition ? repetitionPositions : errorPositions;
    if (positions.isEmpty) return null;
    final target = direction < 0
        ? positions.lastWhere(
            (p) => p < time - 0.001,
            orElse: () => positions.last,
          )
        : positions.firstWhere(
            (p) => p > time + 0.001,
            orElse: () => positions.first,
          );
    updateCurrentTime(target);
    return target;
  }

  Future<void> applyAlignmentResult({
    required List<AyahSegment> ayahs,
    required List<BreathGroup> breaths,
    required int surahId,
    String? reciterName,
    String? audioPath,
    bool preserveText = false,
  }) async {
    _alignmentRiwaya = _riwaya;
    _selectedSurahId = surahId;
    if (reciterName != null && reciterName.trim().isNotEmpty) {
      _reciterName = reciterName.trim();
    } else if (audioPath != null) {
      final name = audioPath.split(RegExp(r'[\\/]')).last;
      _reciterName = name.replaceAll(RegExp(r'\.[^.]+$'), '');
    }
    _isLocalSession = true;
    _localAudioPath = audioPath;

    // Merge Quran text
    final quranText = await QuranDataService().getSurahAyahs(
      surahId,
      riwaya: _riwaya,
    );
    _segments = preserveText
        ? ayahs
        : QuranDataService().mergeQuranTextIntoSegments(ayahs, quranText);

    if (breaths.isNotEmpty) {
      _breathGroups = breaths;
    } else {
      // Fallback breath groups from ayahs
      _breathGroups = _segments.asMap().entries.map((entry) {
        final s = entry.value;
        return BreathGroup(
          groupIndex: entry.key + 1,
          startTime: s.start,
          endTime: s.end,
          duration: s.end - s.start,
          text: s.text,
          words: s.words,
          ayahNumbers: [s.ayahNumber],
        );
      }).toList();
    }

    _originalSegments = _segments.map((s) => s.copyWith()).toList();
    _originalBreathGroups = _breathGroups.map((b) => b.copyWith()).toList();

    _currentSegmentIndex = 0;
    _currentBreathIndex = 0;
    _currentWordIndex = null;
    _currentWordStart = null;
    refreshAlignment();
  }

  /// استيراد التزمين مباشرة من ملف JSON (يدعم صيغ متنوعة منها segments و munajjam)
  Future<bool> importAlignmentFromJson({
    required String jsonString,
    String? audioPath,
    int? overrideSurahId,
  }) async {
    final parsed = QuranDataService().parseAlignmentJson(
      jsonString,
      defaultSurahId: overrideSurahId ?? _selectedSurahId,
    );

    if (parsed == null) return false;
    final importedRiwaya = parsed['riwaya'] as String?;
    if (importedRiwaya != null) _riwaya = importedRiwaya;

    final ayahs = parsed['ayahs'] as List<AyahSegment>;
    final breaths = parsed['breathGroups'] as List<BreathGroup>;
    final surahId = parsed['surahId'] as int;

    await applyAlignmentResult(
      ayahs: ayahs,
      breaths: breaths,
      surahId: surahId,
      reciterName: _reciterName.isNotEmpty ? _reciterName : null,
      audioPath: audioPath ?? _localAudioPath,
      preserveText: true,
    );

    return true;
  }

  // Apply shared boundaries atomically, rejecting crossings at every level.
  bool _moveBoundaries(Map<double, double> changes) {
    double moved(double value) {
      for (final entry in changes.entries) {
        if ((value - entry.key).abs() < 0.0011) return entry.value;
      }
      return value;
    }

    bool valid(double start, double end) =>
        moved(start).isFinite &&
        moved(end).isFinite &&
        moved(start) >= 0 &&
        moved(end) > moved(start);
    final allWords = [
      ..._segments.expand((a) => a.words),
      ..._breathGroups.expand((b) => b.words),
    ];
    if (_segments.any((a) => !valid(a.start, a.end)) ||
        _breathGroups.any((b) => !valid(b.startTime, b.endTime)) ||
        allWords.any((w) => !valid(w.start, w.end))) {
      return false;
    }
    bool staysInside(WordSegment word, double start, double end) {
      // Preserve containment for valid imported children; tolerate pre-existing
      // outliers rather than blocking all corrections to an imperfect import.
      if (word.start < start - 0.001 || word.end > end + 0.001) {
        return true;
      }
      return moved(word.start) >= moved(start) - 0.001 &&
          moved(word.end) <= moved(end) + 0.001;
    }

    if (_segments.any(
          (a) => a.words.any((w) => !staysInside(w, a.start, a.end)),
        ) ||
        _breathGroups.any(
          (b) => b.words.any((w) => !staysInside(w, b.startTime, b.endTime)),
        )) {
      return false;
    }
    // Mutate each shared word object once (fallback groups can share references).
    for (final word in allWords.toSet()) {
      word.start = moved(word.start);
      word.end = moved(word.end);
    }
    for (final ayah in _segments) {
      ayah.start = moved(ayah.start);
      ayah.end = moved(ayah.end);
    }
    for (final breath in _breathGroups) {
      breath.startTime = moved(breath.startTime);
      breath.endTime = moved(breath.endTime);
      breath.duration = breath.endTime - breath.startTime;
    }
    _triggerSaveIndicator();
    return true;
  }

  void _addEdge(
    Map<double, double> changes,
    double old,
    double target,
    Iterable<WordSegment> words,
    bool isStart,
  ) {
    changes[old] = target;
    // Alignment padding can separate a parent edge from its first/last word.
    final ordered = words.toList()..sort((a, b) => a.start.compareTo(b.start));
    if (ordered.isNotEmpty) {
      final edge = isStart ? ordered.first.start : ordered.last.end;
      if ((edge - old).abs() <= 0.15) changes[edge] = target;
    }
    for (final breath in _breathGroups) {
      final edge = isStart ? breath.startTime : breath.endTime;
      if ((edge - old).abs() <= 0.05) changes[edge] = target;
    }
    for (final ayah in _segments) {
      final edge = isStart ? ayah.start : ayah.end;
      if ((edge - old).abs() <= 0.05) changes[edge] = target;
    }
  }

  void updateAyahSegment(int index, {double? start, double? end}) {
    if (index < 0 || index >= _segments.length) return;
    final ayah = _segments[index];
    final changes = <double, double>{};
    if (start != null) {
      _addEdge(changes, ayah.start, _rounded(start), ayah.words, true);
    }
    if (end != null) {
      _addEdge(changes, ayah.end, _rounded(end), ayah.words, false);
    }
    _moveBoundaries(changes);
  }

  void updateBreathGroup(int index, {double? start, double? end}) {
    if (index < 0 || index >= _breathGroups.length) return;
    final breath = _breathGroups[index];
    final changes = <double, double>{};
    if (start != null) {
      _addEdge(changes, breath.startTime, _rounded(start), breath.words, true);
    }
    if (end != null) {
      _addEdge(changes, breath.endTime, _rounded(end), breath.words, false);
    }
    _moveBoundaries(changes);
  }

  void updateWordSegment(
    int ayahIndex,
    int wordIndex, {
    double? start,
    double? end,
  }) {
    if (ayahIndex < 0 || ayahIndex >= _segments.length) return;
    final words = _segments[ayahIndex].words;
    if (wordIndex < 0 || wordIndex >= words.length) return;
    final word = words[wordIndex];
    final changes = <double, double>{};
    if (start != null) {
      _addEdge(changes, word.start, _rounded(start), [word], true);
    }
    if (end != null) _addEdge(changes, word.end, _rounded(end), [word], false);
    _moveBoundaries(changes);
  }

  double _rounded(double time) => double.parse(time.toStringAsFixed(3));

  void moveMarker(
    int index,
    bool isStart,
    double target, {
    int? wordAyahIndex,
    bool syncAdjacent = true,
  }) {
    final changes = <double, double>{};
    target = _rounded(target);
    if (_activeGranularity == AlignmentGranularity.word) {
      if (wordAyahIndex == null) return;
      final words = _segments[wordAyahIndex].words;
      if (index < 0 || index >= words.length) return;
      final word = words[index];
      _addEdge(changes, isStart ? word.start : word.end, target, [
        word,
      ], isStart);
      final flat = _segments.expand((a) => a.words).toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      final adjacent = flat.indexOf(word) + (isStart ? -1 : 1);
      if (syncAdjacent && adjacent >= 0 && adjacent < flat.length) {
        changes[isStart ? flat[adjacent].end : flat[adjacent].start] = target;
      }
    } else if (_activeGranularity == AlignmentGranularity.ayah) {
      if (index < 0 || index >= _segments.length) return;
      final ayah = _segments[index];
      _addEdge(
        changes,
        isStart ? ayah.start : ayah.end,
        target,
        ayah.words,
        isStart,
      );
      final adjacent = index + (isStart ? -1 : 1);
      if (syncAdjacent && adjacent >= 0 && adjacent < _segments.length) {
        final other = _segments[adjacent];
        _addEdge(
          changes,
          isStart ? other.end : other.start,
          target,
          other.words,
          !isStart,
        );
      }
    } else {
      if (index < 0 || index >= _breathGroups.length) return;
      final breath = _breathGroups[index];
      _addEdge(
        changes,
        isStart ? breath.startTime : breath.endTime,
        target,
        breath.words,
        isStart,
      );
      final adjacent = index + (isStart ? -1 : 1);
      if (syncAdjacent && adjacent >= 0 && adjacent < _breathGroups.length) {
        final other = _breathGroups[adjacent];
        _addEdge(
          changes,
          isStart ? other.endTime : other.startTime,
          target,
          other.words,
          !isStart,
        );
      }
    }
    _moveBoundaries(changes);
  }

  void splitBreath(int index, double splitTime) {
    if (index < 0 || index >= _breathGroups.length) return;
    final target = _breathGroups[index];
    if (splitTime <= target.startTime || splitTime >= target.endTime) return;

    final formattedSplit = double.parse(splitTime.toStringAsFixed(3));
    final wordsBefore = target.words.where((w) => w.end <= splitTime).toList();
    final wordsAfter = target.words.where((w) => w.end > splitTime).toList();

    final group1 = BreathGroup(
      groupIndex: target.groupIndex,
      startTime: target.startTime,
      endTime: formattedSplit,
      duration: formattedSplit - target.startTime,
      text: wordsBefore.map((w) => w.word).join(' '),
      words: wordsBefore,
      ayahNumbers: target.ayahNumbers,
    );

    final group2 = BreathGroup(
      groupIndex: target.groupIndex + 1,
      startTime: formattedSplit,
      endTime: target.endTime,
      duration: target.endTime - formattedSplit,
      text: wordsAfter.map((w) => w.word).join(' '),
      words: wordsAfter,
      ayahNumbers: target.ayahNumbers,
    );

    _breathGroups.removeAt(index);
    _breathGroups.insert(index, group2);
    _breathGroups.insert(index, group1);

    // Re-index
    for (int i = 0; i < _breathGroups.length; i++) {
      _breathGroups[i].groupIndex = i + 1;
    }

    _triggerSaveIndicator();
  }

  void splitAyah(int index, double splitTime) {
    if (index < 0 || index >= _segments.length) return;
    final target = _segments[index];
    if (splitTime <= target.start || splitTime >= target.end) return;

    final formattedSplit = double.parse(splitTime.toStringAsFixed(3));
    final wordsBefore = target.words.where((w) => w.end <= splitTime).toList();
    final wordsAfter = target.words.where((w) => w.end > splitTime).toList();

    final seg1 = target.copyWith(
      end: formattedSplit,
      text: wordsBefore.isNotEmpty
          ? wordsBefore.map((w) => w.word).join(' ')
          : target.text,
      words: wordsBefore,
    );

    final seg2 = target.copyWith(
      start: formattedSplit,
      text: wordsAfter.isNotEmpty
          ? wordsAfter.map((w) => w.word).join(' ')
          : target.text,
      words: wordsAfter,
    );

    _segments.removeAt(index);
    _segments.insert(index, seg2);
    _segments.insert(index, seg1);

    _triggerSaveIndicator();
  }

  /// نقل أقرب علامة تقسيم إلى موضع زمني محدد فورياً دون قطع التشغيل
  bool moveNearestMarkerTo(double targetTime) {
    if (targetTime < 0) return false;
    final formattedTime = double.parse(targetTime.toStringAsFixed(3));

    if (_activeGranularity == AlignmentGranularity.breath) {
      if (_breathGroups.isEmpty) return false;
      int bestIndex = -1;
      bool isStartOfFirst = false;
      bool isEndOfLast = false;
      double minDiff = double.infinity;

      final diffFirst = (formattedTime - _breathGroups.first.startTime).abs();
      if (diffFirst < minDiff) {
        minDiff = diffFirst;
        isStartOfFirst = true;
      }

      for (int i = 0; i < _breathGroups.length - 1; i++) {
        final boundary =
            (_breathGroups[i].endTime + _breathGroups[i + 1].startTime) / 2;
        final diff = (formattedTime - boundary).abs();
        if (diff < minDiff) {
          minDiff = diff;
          bestIndex = i;
          isStartOfFirst = false;
          isEndOfLast = false;
        }
      }

      final diffLast = (formattedTime - _breathGroups.last.endTime).abs();
      if (diffLast < minDiff) {
        minDiff = diffLast;
        bestIndex = _breathGroups.length - 1;
        isStartOfFirst = false;
        isEndOfLast = true;
      }

      if (isStartOfFirst) {
        if (formattedTime < _breathGroups.first.endTime - 0.05) {
          updateBreathGroup(0, start: formattedTime);
          _breathGroups.first.duration =
              _breathGroups.first.endTime - _breathGroups.first.startTime;
        }
      } else if (isEndOfLast) {
        if (formattedTime > _breathGroups.last.startTime + 0.05) {
          updateBreathGroup(_breathGroups.length - 1, end: formattedTime);
          _breathGroups.last.duration =
              _breathGroups.last.endTime - _breathGroups.last.startTime;
        }
      } else if (bestIndex >= 0 && bestIndex < _breathGroups.length - 1) {
        final prev = _breathGroups[bestIndex];
        final next = _breathGroups[bestIndex + 1];
        if (formattedTime > prev.startTime + 0.05 &&
            formattedTime < next.endTime - 0.05) {
          moveMarker(bestIndex, false, formattedTime);
        }
      }

      _triggerSaveIndicator();
      return true;
    } else if (_activeGranularity == AlignmentGranularity.ayah) {
      if (_segments.isEmpty) return false;
      int bestIndex = -1;
      bool isStartOfFirst = false;
      bool isEndOfLast = false;
      double minDiff = double.infinity;

      final diffFirst = (formattedTime - _segments.first.start).abs();
      if (diffFirst < minDiff) {
        minDiff = diffFirst;
        isStartOfFirst = true;
      }

      for (int i = 0; i < _segments.length - 1; i++) {
        final boundary = (_segments[i].end + _segments[i + 1].start) / 2;
        final diff = (formattedTime - boundary).abs();
        if (diff < minDiff) {
          minDiff = diff;
          bestIndex = i;
          isStartOfFirst = false;
          isEndOfLast = false;
        }
      }

      final diffLast = (formattedTime - _segments.last.end).abs();
      if (diffLast < minDiff) {
        minDiff = diffLast;
        bestIndex = _segments.length - 1;
        isStartOfFirst = false;
        isEndOfLast = true;
      }

      if (isStartOfFirst) {
        if (formattedTime < _segments.first.end - 0.05) {
          updateAyahSegment(0, start: formattedTime);
        }
      } else if (isEndOfLast) {
        if (formattedTime > _segments.last.start + 0.05) {
          updateAyahSegment(_segments.length - 1, end: formattedTime);
        }
      } else if (bestIndex >= 0 && bestIndex < _segments.length - 1) {
        final prev = _segments[bestIndex];
        final next = _segments[bestIndex + 1];
        if (formattedTime > prev.start + 0.05 &&
            formattedTime < next.end - 0.05) {
          moveMarker(bestIndex, false, formattedTime);
        }
      }

      _triggerSaveIndicator();
      return true;
    } else {
      int? foundAyahIdx;
      int? foundWordIdx;
      double minDiff = double.infinity;
      for (int a = 0; a < _segments.length; a++) {
        final words = _segments[a].words;
        for (int w = 0; w < words.length - 1; w++) {
          final boundary = (words[w].end + words[w + 1].start) / 2;
          final diff = (formattedTime - boundary).abs();
          if (diff < minDiff) {
            minDiff = diff;
            foundAyahIdx = a;
            foundWordIdx = w;
          }
        }
      }
      if (foundAyahIdx != null && foundWordIdx != null) {
        final ayah = _segments[foundAyahIdx];
        final words = ayah.words;
        final prev = words[foundWordIdx];
        final next = words[foundWordIdx + 1];
        if (formattedTime > prev.start + 0.02 &&
            formattedTime < next.end - 0.02) {
          updateWordSegment(foundAyahIdx, foundWordIdx, end: formattedTime);
          updateWordSegment(
            foundAyahIdx,
            foundWordIdx + 1,
            start: formattedTime,
          );
        }
      }
      _triggerSaveIndicator();
      return true;
    }
  }

  /// إضافة علامة تقسيم جديدة عند موضع زمني محدد فورياً دون قطع التشغيل
  bool addNewMarkerAt(double targetTime) {
    if (targetTime <= 0) return false;
    final formattedTime = double.parse(targetTime.toStringAsFixed(3));

    if (_activeGranularity == AlignmentGranularity.breath) {
      if (_breathGroups.isEmpty) return false;
      for (int i = 0; i < _breathGroups.length; i++) {
        final bg = _breathGroups[i];
        if (formattedTime > bg.startTime + 0.08 &&
            formattedTime < bg.endTime - 0.08) {
          splitBreath(i, formattedTime);
          return true;
        }
      }
      for (int i = 0; i < _breathGroups.length; i++) {
        final bg = _breathGroups[i];
        if (formattedTime >= bg.startTime && formattedTime <= bg.endTime) {
          splitBreath(i, formattedTime);
          return true;
        }
      }
      return false;
    } else if (_activeGranularity == AlignmentGranularity.ayah) {
      if (_segments.isEmpty) return false;
      for (int i = 0; i < _segments.length; i++) {
        final seg = _segments[i];
        if (formattedTime > seg.start + 0.08 &&
            formattedTime < seg.end - 0.08) {
          splitAyah(i, formattedTime);
          return true;
        }
      }
      return false;
    } else {
      return false;
    }
  }

  void mergeBreathWithNext(int index) {
    if (index < 0 || index >= _breathGroups.length - 1) return;
    final current = _breathGroups[index];
    final next = _breathGroups[index + 1];

    final merged = BreathGroup(
      groupIndex: current.groupIndex,
      startTime: current.startTime,
      endTime: next.endTime,
      duration: next.endTime - current.startTime,
      text: '${current.text} ${next.text}'.trim(),
      words: [...current.words, ...next.words],
      ayahNumbers: {...current.ayahNumbers, ...next.ayahNumbers}.toList(),
    );

    _breathGroups.removeAt(index + 1);
    _breathGroups[index] = merged;

    for (int i = 0; i < _breathGroups.length; i++) {
      _breathGroups[i].groupIndex = i + 1;
    }

    _triggerSaveIndicator();
  }

  void bridgeSilenceGaps() {
    for (int i = 0; i < _segments.length - 1; i++) {
      final gap = _segments[i + 1].start - _segments[i].end;
      if (gap > 0 && gap < 0.25) {
        final mid = (_segments[i].end + _segments[i + 1].start) / 2;
        _segments[i].end = double.parse(mid.toStringAsFixed(3));
        _segments[i + 1].start = double.parse(mid.toStringAsFixed(3));
      }
    }

    for (int i = 0; i < _breathGroups.length - 1; i++) {
      final gap = _breathGroups[i + 1].startTime - _breathGroups[i].endTime;
      if (gap > 0 && gap < 0.3) {
        final mid =
            (_breathGroups[i].endTime + _breathGroups[i + 1].startTime) / 2;
        _breathGroups[i].endTime = double.parse(mid.toStringAsFixed(3));
        _breathGroups[i + 1].startTime = double.parse(mid.toStringAsFixed(3));
      }
    }

    _triggerSaveIndicator();
  }

  void resetToOriginal() {
    if (_originalSegments.isEmpty) return;
    _segments = _originalSegments.map((s) => s.copyWith()).toList();
    _breathGroups = _originalBreathGroups.map((b) => b.copyWith()).toList();
    _triggerSaveIndicator();
  }

  void _triggerSaveIndicator() {
    refreshAlignment(notify: false);
    _saveStatus = 'saved';
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () {
      _saveStatus = 'idle';
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  String generateExportJson() {
    final exportData = {
      ...QuranMetadata.exportAlignment(
        riwaya: _alignmentRiwaya ?? _riwaya,
        surahNumber: _selectedSurahId,
        ayahs: _segments,
        breaths: _breathGroups,
      ),
      'surah_name': currentSurah.nameArabic,
      if (_reciterName.isNotEmpty) 'reciter': _reciterName,
      if (_localAudioPath != null)
        'audio_file': _localAudioPath!.split(RegExp(r'[\\/]')).last,
    };
    return const JsonEncoder.withIndent('  ').convert(exportData);
  }
}

import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/alignment_models.dart';
import '../models/surah_model.dart';
import '../services/audio_service.dart';
import '../services/quran_data_service.dart';

class AlignmentProvider extends ChangeNotifier {
  int _selectedSurahId = 1;
  String _reciterName = '';
  String _riwaya = 'hafsh';
  AlignmentGranularity _activeGranularity = AlignmentGranularity.ayah;

  List<AyahSegment> _segments = [];
  List<BreathGroup> _breathGroups = [];
  List<AyahSegment> _originalSegments = [];
  List<BreathGroup> _originalBreathGroups = [];

  int? _currentSegmentIndex;
  int? _currentBreathIndex;
  String _saveStatus = 'idle'; // idle, saving, saved, error
  bool _isLocalSession = false;
  String? _localAudioPath;

  String _repetitionMode = 'visual'; // visual (show badges), final_take (skip repeated takes)

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
  String get saveStatus => _saveStatus;
  bool get isLocalSession => _isLocalSession;
  String? get localAudioPath => _localAudioPath;
  SurahInfo get currentSurah => getSurahById(_selectedSurahId);

  double get averageSimilarity {
    if (_segments.isEmpty) return 1.0;
    final total = _segments.fold<double>(0.0, (sum, item) => sum + item.similarity);
    return total / _segments.length;
  }

  /// جميع مواضع التكرار في السورة (كلمات أو أنفاس مكررة)
  List<double> get repetitionTimestamps {
    final list = <double>[];
    for (final seg in _segments) {
      for (final w in seg.words) {
        if (w.isRepetition) list.add(w.start);
      }
    }
    for (final bg in _breathGroups) {
      if (bg.isRepetition) list.add(bg.startTime);
    }
    final sorted = list.toSet().toList()..sort();
    return sorted;
  }

  /// تفاصيل جميع مواضع التكرار في السورة للعرض في النافذة التفاعلية
  List<RepetitionDetail> get detailedRepetitions {
    final list = <RepetitionDetail>[];
    int idx = 1;
    for (final seg in _segments) {
      for (final w in seg.words) {
        if (w.isRepetition) {
          list.add(RepetitionDetail(
            index: idx++,
            timestamp: w.start,
            endTime: w.end,
            text: w.word,
            ayahText: seg.text,
            ayahNumber: seg.ayahNumber,
            isWord: true,
            repetitionType: w.repetitionType,
          ));
        }
      }
    }
    for (final bg in _breathGroups) {
      if (bg.isRepetition) {
        int? ayahNum;
        String aText = bg.text;
        for (final seg in _segments) {
          if (bg.startTime >= seg.start - 0.1 && bg.startTime <= seg.end + 0.1) {
            ayahNum = seg.ayahNumber;
            aText = seg.text;
            break;
          }
        }
        list.add(RepetitionDetail(
          index: idx++,
          timestamp: bg.startTime,
          endTime: bg.endTime,
          text: bg.text.isNotEmpty ? bg.text : 'سكتة #${bg.groupIndex}',
          ayahText: aText,
          ayahNumber: ayahNum,
          isWord: false,
          repetitionType: bg.repetitionType,
        ));
      }
    }
    list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return list;
  }

  /// جميع مواضع المراجعة/الخطأ المحتملة (دقة منخفضة أقل من 95%)
  List<double> get errorTimestamps {
    final list = <double>[];
    for (final seg in _segments) {
      if (seg.similarity < 0.95) {
        list.add(seg.start);
      }
      for (final w in seg.words) {
        if (w.confidence < 0.90) {
          list.add(w.start);
        }
      }
    }
    final sorted = list.toSet().toList()..sort();
    return sorted;
  }

  double? getNextRepetition(double currentSec) {
    final reps = repetitionTimestamps;
    if (reps.isEmpty) return null;
    return reps.firstWhere((t) => t > currentSec + 0.1, orElse: () => reps.first);
  }

  double? getPrevRepetition(double currentSec) {
    final reps = repetitionTimestamps;
    if (reps.isEmpty) return null;
    return reps.lastWhere((t) => t < currentSec - 0.1, orElse: () => reps.last);
  }

  double? getNextError(double currentSec) {
    final errors = errorTimestamps;
    if (errors.isEmpty) return null;
    return errors.firstWhere((t) => t > currentSec + 0.1, orElse: () => errors.first);
  }

  double? getPrevError(double currentSec) {
    final errors = errorTimestamps;
    if (errors.isEmpty) return null;
    return errors.lastWhere((t) => t < currentSec - 0.1, orElse: () => errors.last);
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
    _activeGranularity = granularity;
    notifyListeners();
  }

  void setRepetitionMode(String mode) {
    _repetitionMode = mode;
    notifyListeners();
  }

  void selectAyah(int index) {
    if (index >= 0 && index < _segments.length) {
      _currentSegmentIndex = index;
      final ayah = _segments[index];
      // Find corresponding breath group if any
      int? foundBreathIdx;
      for (int i = 0; i < _breathGroups.length; i++) {
        if (_breathGroups[i].startTime >= ayah.start - 0.05 && _breathGroups[i].startTime <= ayah.end + 0.05) {
          foundBreathIdx = i;
          break;
        }
      }
      _currentBreathIndex = foundBreathIdx;
      notifyListeners();
    }
  }

  void selectBreath(int index) {
    if (index >= 0 && index < _breathGroups.length) {
      _currentBreathIndex = index;
      final breath = _breathGroups[index];
      // Find corresponding ayah that covers this breath's start time
      int? foundAyahIdx;
      for (int i = 0; i < _segments.length; i++) {
        final seg = _segments[i];
        if (breath.startTime >= seg.start - 0.1 && breath.startTime <= seg.end + 0.1) {
          foundAyahIdx = i;
          break;
        }
      }

      // If not directly found inside an interval, find the closest ayah
      if (foundAyahIdx == null && _segments.isNotEmpty) {
        int bestIdx = 0;
        double minDiff = double.infinity;
        for (int i = 0; i < _segments.length; i++) {
          final diff = (breath.startTime - _segments[i].start).abs();
          if (diff < minDiff) {
            minDiff = diff;
            bestIdx = i;
          }
        }
        foundAyahIdx = bestIdx;
      }

      _currentSegmentIndex = foundAyahIdx;
      notifyListeners();
    }
  }

  void updateCurrentTime(double seconds) {
    int? newAyahIdx;
    for (int i = 0; i < _segments.length; i++) {
      final seg = _segments[i];
      final nextStart = (i < _segments.length - 1) ? _segments[i + 1].start : double.infinity;
      // An ayah is active if seconds is at/after its start, AND before the next ayah starts
      if (seconds >= seg.start - 0.01 && seconds < nextStart) {
        newAyahIdx = i;
        break;
      }
    }

    if (newAyahIdx == null && _segments.isNotEmpty) {
      if (seconds >= _segments.last.start - 0.01) {
        newAyahIdx = _segments.length - 1;
      }
    }

    int? newBreathIdx;
    for (int i = 0; i < _breathGroups.length; i++) {
      final bg = _breathGroups[i];
      final nextStart = (i < _breathGroups.length - 1) ? _breathGroups[i + 1].startTime : double.infinity;
      if (seconds >= bg.startTime - 0.01 && seconds < nextStart) {
        newBreathIdx = i;
        break;
      }
    }

    if (newBreathIdx == null && _breathGroups.isNotEmpty) {
      if (seconds >= _breathGroups.last.startTime - 0.01) {
        newBreathIdx = _breathGroups.length - 1;
      }
    }

    if (newAyahIdx != _currentSegmentIndex || newBreathIdx != _currentBreathIndex) {
      _currentSegmentIndex = newAyahIdx;
      _currentBreathIndex = newBreathIdx;
      notifyListeners();
    }
  }

  void navigatePrevious() {
    if (_activeGranularity == AlignmentGranularity.ayah) {
      if (_segments.isEmpty) return;
      final current = _currentSegmentIndex ?? 0;
      if (current > 0) {
        final target = current - 1;
        selectAyah(target);
        AudioService().seek(_segments[target].start);
      }
    } else if (_activeGranularity == AlignmentGranularity.breath) {
      if (_breathGroups.isEmpty) return;
      final current = _currentBreathIndex ?? 0;
      if (current > 0) {
        final target = current - 1;
        selectBreath(target);
        AudioService().seek(_breathGroups[target].startTime);
      }
    } else {
      _stepWordNavigation(forward: false);
    }
  }

  void navigateNext() {
    if (_activeGranularity == AlignmentGranularity.ayah) {
      if (_segments.isEmpty) return;
      final current = _currentSegmentIndex ?? -1;
      if (current < _segments.length - 1) {
        final target = current + 1;
        selectAyah(target);
        AudioService().seek(_segments[target].start);
      }
    } else if (_activeGranularity == AlignmentGranularity.breath) {
      if (_breathGroups.isEmpty) return;
      final current = _currentBreathIndex ?? -1;
      if (current < _breathGroups.length - 1) {
        final target = current + 1;
        selectBreath(target);
        AudioService().seek(_breathGroups[target].startTime);
      }
    } else {
      _stepWordNavigation(forward: true);
    }
  }

  void _stepWordNavigation({required bool forward}) {
    final curSec = AudioService().currentSeconds;
    final allWords = <({int ayahIdx, WordSegment word})>[];
    for (int a = 0; a < _segments.length; a++) {
      for (final w in _segments[a].words) {
        allWords.add((ayahIdx: a, word: w));
      }
    }
    if (allWords.isEmpty) return;

    if (forward) {
      for (final item in allWords) {
        if (item.word.start > curSec + 0.05) {
          selectAyah(item.ayahIdx);
          AudioService().seek(item.word.start);
          return;
        }
      }
    } else {
      for (int i = allWords.length - 1; i >= 0; i--) {
        final item = allWords[i];
        if (item.word.start < curSec - 0.1) {
          selectAyah(item.ayahIdx);
          AudioService().seek(item.word.start);
          return;
        }
      }
    }
  }

  void stepBackward() {
    final curSec = AudioService().currentSeconds;
    if (_activeGranularity == AlignmentGranularity.ayah) {
      if (_segments.isEmpty) return;
      int targetIdx = 0;
      for (int i = _segments.length - 1; i >= 0; i--) {
        if (_segments[i].start < curSec - 0.2) {
          targetIdx = i;
          break;
        }
      }
      selectAyah(targetIdx);
      AudioService().seek(_segments[targetIdx].start);
    } else if (_activeGranularity == AlignmentGranularity.breath) {
      if (_breathGroups.isEmpty) return;
      int targetIdx = 0;
      for (int i = _breathGroups.length - 1; i >= 0; i--) {
        if (_breathGroups[i].startTime < curSec - 0.2) {
          targetIdx = i;
          break;
        }
      }
      selectBreath(targetIdx);
      AudioService().seek(_breathGroups[targetIdx].startTime);
    } else {
      double? prevWordStart;
      int? foundAyahIdx;
      for (int a = 0; a < _segments.length; a++) {
        for (final w in _segments[a].words) {
          if (w.start < curSec - 0.15) {
            prevWordStart = w.start;
            foundAyahIdx = a;
          }
        }
      }
      if (prevWordStart != null) {
        if (foundAyahIdx != null) selectAyah(foundAyahIdx);
        AudioService().seek(prevWordStart);
      }
    }
  }

  void stepForward() {
    final curSec = AudioService().currentSeconds;
    if (_activeGranularity == AlignmentGranularity.ayah) {
      if (_segments.isEmpty) return;
      int targetIdx = _segments.length - 1;
      for (int i = 0; i < _segments.length; i++) {
        if (_segments[i].start > curSec + 0.1) {
          targetIdx = i;
          break;
        }
      }
      selectAyah(targetIdx);
      AudioService().seek(_segments[targetIdx].start);
    } else if (_activeGranularity == AlignmentGranularity.breath) {
      if (_breathGroups.isEmpty) return;
      int targetIdx = _breathGroups.length - 1;
      for (int i = 0; i < _breathGroups.length; i++) {
        if (_breathGroups[i].startTime > curSec + 0.1) {
          targetIdx = i;
          break;
        }
      }
      selectBreath(targetIdx);
      AudioService().seek(_breathGroups[targetIdx].startTime);
    } else {
      double? nextWordStart;
      int? foundAyahIdx;
      for (int a = 0; a < _segments.length; a++) {
        for (final w in _segments[a].words) {
          if (w.start > curSec + 0.1) {
            nextWordStart = w.start;
            foundAyahIdx = a;
            break;
          }
        }
        if (nextWordStart != null) break;
      }
      if (nextWordStart != null) {
        if (foundAyahIdx != null) selectAyah(foundAyahIdx);
        AudioService().seek(nextWordStart);
      }
    }
  }

  void applyAlignmentResult({
    required List<AyahSegment> ayahs,
    required List<BreathGroup> breaths,
    required int surahId,
    String? reciterName,
    String? audioPath,
  }) async {
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
    final quranText = await QuranDataService().getSurahAyahs(surahId, riwaya: _riwaya);
    _segments = QuranDataService().mergeQuranTextIntoSegments(ayahs, quranText);

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
    notifyListeners();
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

    final ayahs = parsed['ayahs'] as List<AyahSegment>;
    final breaths = parsed['breathGroups'] as List<BreathGroup>;
    final surahId = parsed['surahId'] as int;

    applyAlignmentResult(
      ayahs: ayahs,
      breaths: breaths,
      surahId: surahId,
      reciterName: _reciterName.isNotEmpty ? _reciterName : null,
      audioPath: audioPath ?? _localAudioPath,
    );

    return true;
  }

  void updateAyahSegment(int index, {double? start, double? end, bool syncLinked = true}) {
    if (index < 0 || index >= _segments.length) return;
    final current = _segments[index];
    final oldStart = current.start;
    final oldEnd = current.end;
    final updatedStart = start != null ? double.parse(start.toStringAsFixed(3)) : current.start;
    final updatedEnd = end != null ? double.parse(end.toStringAsFixed(3)) : current.end;

    if (updatedEnd <= updatedStart) return;

    List<WordSegment> updatedWords = List<WordSegment>.from(current.words);
    if (syncLinked && updatedWords.isNotEmpty) {
      if (start != null) {
        updatedWords[0] = updatedWords[0].copyWith(start: updatedStart);
      }
      if (end != null) {
        updatedWords[updatedWords.length - 1] = updatedWords.last.copyWith(end: updatedEnd);
      }
    }

    _segments[index] = current.copyWith(
      start: updatedStart,
      end: updatedEnd,
      words: updatedWords,
    );

    // Sync corresponding breath groups
    if (syncLinked) {
      for (int i = 0; i < _breathGroups.length; i++) {
        final bg = _breathGroups[i];
        if (start != null && (bg.startTime - oldStart).abs() < 0.15) {
          bg.startTime = updatedStart;
          bg.duration = bg.endTime - bg.startTime;
          if (bg.words.isNotEmpty) {
            bg.words[0] = bg.words[0].copyWith(start: updatedStart);
          }
        }
        if (end != null && (bg.endTime - oldEnd).abs() < 0.15) {
          bg.endTime = updatedEnd;
          bg.duration = bg.endTime - bg.startTime;
          if (bg.words.isNotEmpty) {
            bg.words[bg.words.length - 1] = bg.words.last.copyWith(end: updatedEnd);
          }
        }
      }
    }

    _triggerSaveIndicator();
    notifyListeners();
  }

  void updateBreathGroup(int index, {double? start, double? end, bool syncLinked = true}) {
    if (index < 0 || index >= _breathGroups.length) return;
    final current = _breathGroups[index];
    final oldStart = current.startTime;
    final oldEnd = current.endTime;
    final updatedStart = start != null ? double.parse(start.toStringAsFixed(3)) : current.startTime;
    final updatedEnd = end != null ? double.parse(end.toStringAsFixed(3)) : current.endTime;

    if (updatedEnd <= updatedStart) return;

    List<WordSegment> updatedWords = List<WordSegment>.from(current.words);
    if (syncLinked && updatedWords.isNotEmpty) {
      if (start != null) {
        updatedWords[0] = updatedWords[0].copyWith(start: updatedStart);
      }
      if (end != null) {
        updatedWords[updatedWords.length - 1] = updatedWords.last.copyWith(end: updatedEnd);
      }
    }

    _breathGroups[index] = current.copyWith(
      startTime: updatedStart,
      endTime: updatedEnd,
      duration: updatedEnd - updatedStart,
      words: updatedWords,
    );

    // Sync corresponding ayah boundaries
    if (syncLinked) {
      for (int i = 0; i < _segments.length; i++) {
        final seg = _segments[i];
        if (start != null && (seg.start - oldStart).abs() < 0.15) {
          updateAyahSegment(i, start: updatedStart, syncLinked: false);
        }
        if (end != null && (seg.end - oldEnd).abs() < 0.15) {
          updateAyahSegment(i, end: updatedEnd, syncLinked: false);
        }
      }
    }

    _triggerSaveIndicator();
    notifyListeners();
  }

  void updateWordSegment(int ayahIndex, int wordIndex, {double? start, double? end, bool syncLinked = true}) {
    if (ayahIndex < 0 || ayahIndex >= _segments.length) return;
    final ayah = _segments[ayahIndex];
    if (wordIndex < 0 || wordIndex >= ayah.words.length) return;

    final word = ayah.words[wordIndex];
    final updatedStart = start != null ? double.parse(start.toStringAsFixed(3)) : word.start;
    final updatedEnd = end != null ? double.parse(end.toStringAsFixed(3)) : word.end;

    if (updatedEnd <= updatedStart) return;

    final updatedWords = List<WordSegment>.from(ayah.words);
    updatedWords[wordIndex] = word.copyWith(start: updatedStart, end: updatedEnd);

    double newAyahStart = ayah.start;
    double newAyahEnd = ayah.end;

    if (syncLinked) {
      if (wordIndex == 0 && start != null) {
        newAyahStart = updatedStart;
      }
      if (wordIndex == ayah.words.length - 1 && end != null) {
        newAyahEnd = updatedEnd;
      }
    }

    _segments[ayahIndex] = ayah.copyWith(
      start: newAyahStart,
      end: newAyahEnd,
      words: updatedWords,
    );

    // Sync matching word inside breathGroups
    if (syncLinked) {
      for (final bg in _breathGroups) {
        for (int w = 0; w < bg.words.length; w++) {
          final bw = bg.words[w];
          if (bw.word == word.word && (bw.start - word.start).abs() < 0.05) {
            bg.words[w] = bw.copyWith(start: updatedStart, end: updatedEnd);
            if (w == 0 && start != null) {
              bg.startTime = updatedStart;
              bg.duration = bg.endTime - bg.startTime;
            }
            if (w == bg.words.length - 1 && end != null) {
              bg.endTime = updatedEnd;
              bg.duration = bg.endTime - bg.startTime;
            }
          }
        }
      }
    }

    _triggerSaveIndicator();
    notifyListeners();
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
    notifyListeners();
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
      text: wordsBefore.isNotEmpty ? wordsBefore.map((w) => w.word).join(' ') : target.text,
      words: wordsBefore,
    );

    final seg2 = target.copyWith(
      start: formattedSplit,
      text: wordsAfter.isNotEmpty ? wordsAfter.map((w) => w.word).join(' ') : target.text,
      words: wordsAfter,
    );

    _segments.removeAt(index);
    _segments.insert(index, seg2);
    _segments.insert(index, seg1);

    _triggerSaveIndicator();
    notifyListeners();
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
        final boundary = (_breathGroups[i].endTime + _breathGroups[i + 1].startTime) / 2;
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
          _breathGroups.first.startTime = formattedTime;
          _breathGroups.first.duration = _breathGroups.first.endTime - _breathGroups.first.startTime;
        }
      } else if (isEndOfLast) {
        if (formattedTime > _breathGroups.last.startTime + 0.05) {
          _breathGroups.last.endTime = formattedTime;
          _breathGroups.last.duration = _breathGroups.last.endTime - _breathGroups.last.startTime;
        }
      } else if (bestIndex >= 0 && bestIndex < _breathGroups.length - 1) {
        final prev = _breathGroups[bestIndex];
        final next = _breathGroups[bestIndex + 1];
        if (formattedTime > prev.startTime + 0.05 && formattedTime < next.endTime - 0.05) {
          prev.endTime = formattedTime;
          prev.duration = prev.endTime - prev.startTime;
          next.startTime = formattedTime;
          next.duration = next.endTime - next.startTime;
        }
      }

      _triggerSaveIndicator();
      notifyListeners();
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
          _segments.first = _segments.first.copyWith(start: formattedTime);
        }
      } else if (isEndOfLast) {
        if (formattedTime > _segments.last.start + 0.05) {
          _segments.last = _segments.last.copyWith(end: formattedTime);
        }
      } else if (bestIndex >= 0 && bestIndex < _segments.length - 1) {
        final prev = _segments[bestIndex];
        final next = _segments[bestIndex + 1];
        if (formattedTime > prev.start + 0.05 && formattedTime < next.end - 0.05) {
          _segments[bestIndex] = prev.copyWith(end: formattedTime);
          _segments[bestIndex + 1] = next.copyWith(start: formattedTime);
        }
      }

      _triggerSaveIndicator();
      notifyListeners();
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
        if (formattedTime > prev.start + 0.02 && formattedTime < next.end - 0.02) {
          updateWordSegment(foundAyahIdx, foundWordIdx, end: formattedTime);
          updateWordSegment(foundAyahIdx, foundWordIdx + 1, start: formattedTime);
        }
      }
      _triggerSaveIndicator();
      notifyListeners();
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
        if (formattedTime > bg.startTime + 0.08 && formattedTime < bg.endTime - 0.08) {
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
        if (formattedTime > seg.start + 0.08 && formattedTime < seg.end - 0.08) {
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
    notifyListeners();
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
        final mid = (_breathGroups[i].endTime + _breathGroups[i + 1].startTime) / 2;
        _breathGroups[i].endTime = double.parse(mid.toStringAsFixed(3));
        _breathGroups[i + 1].startTime = double.parse(mid.toStringAsFixed(3));
      }
    }

    _triggerSaveIndicator();
    notifyListeners();
  }

  void resetToOriginal() {
    if (_originalSegments.isEmpty) return;
    _segments = _originalSegments.map((s) => s.copyWith()).toList();
    _breathGroups = _originalBreathGroups.map((b) => b.copyWith()).toList();
    _triggerSaveIndicator();
    notifyListeners();
  }

  void _triggerSaveIndicator() {
    _saveStatus = 'saved';
    notifyListeners();
    Future.delayed(const Duration(seconds: 2), () {
      _saveStatus = 'idle';
      notifyListeners();
    });
  }

  String generateExportJson() {
    final exportData = {
      'surah_id': _selectedSurahId,
      'surah_name': currentSurah.nameArabic,
      if (_reciterName.isNotEmpty) 'reciter': _reciterName,
      if (_localAudioPath != null)
        'audio_file': _localAudioPath!.split(RegExp(r'[\\/]')).last,
      'total_ayahs': _segments.length,
      'total_breath_groups': _breathGroups.length,
      'ayahs': _segments.map((s) => s.toJson()).toList(),
      'breath_groups': _breathGroups.map((b) => b.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(exportData);
  }
}

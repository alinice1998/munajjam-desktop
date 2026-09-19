import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/alignment_models.dart';
import '../models/surah_model.dart';
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
    if (_segments.isEmpty) return 0.98;
    final total = _segments.fold<double>(0.0, (sum, item) => sum + item.similarity);
    return total / _segments.length;
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
      if (seconds >= _segments[i].start && seconds <= _segments[i].end + 0.05) {
        newAyahIdx = i;
        break;
      }
    }

    int? newBreathIdx;
    for (int i = 0; i < _breathGroups.length; i++) {
      if (seconds >= _breathGroups[i].startTime && seconds <= _breathGroups[i].endTime + 0.05) {
        newBreathIdx = i;
        break;
      }
    }

    if (newAyahIdx != _currentSegmentIndex || newBreathIdx != _currentBreathIndex) {
      _currentSegmentIndex = newAyahIdx;
      _currentBreathIndex = newBreathIdx;
      notifyListeners();
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

  void updateAyahSegment(int index, {double? start, double? end}) {
    if (index < 0 || index >= _segments.length) return;
    final current = _segments[index];
    final updatedStart = start != null ? double.parse(start.toStringAsFixed(3)) : current.start;
    final updatedEnd = end != null ? double.parse(end.toStringAsFixed(3)) : current.end;

    if (updatedEnd <= updatedStart) return;

    _segments[index] = current.copyWith(start: updatedStart, end: updatedEnd);
    _triggerSaveIndicator();
    notifyListeners();
  }

  void updateBreathGroup(int index, {double? start, double? end}) {
    if (index < 0 || index >= _breathGroups.length) return;
    final current = _breathGroups[index];
    final updatedStart = start != null ? double.parse(start.toStringAsFixed(3)) : current.startTime;
    final updatedEnd = end != null ? double.parse(end.toStringAsFixed(3)) : current.endTime;

    if (updatedEnd <= updatedStart) return;

    _breathGroups[index] = current.copyWith(
      startTime: updatedStart,
      endTime: updatedEnd,
      duration: updatedEnd - updatedStart,
    );
    _triggerSaveIndicator();
    notifyListeners();
  }

  void updateWordSegment(int ayahIndex, int wordIndex, {double? start, double? end}) {
    if (ayahIndex < 0 || ayahIndex >= _segments.length) return;
    final ayah = _segments[ayahIndex];
    if (wordIndex < 0 || wordIndex >= ayah.words.length) return;

    final word = ayah.words[wordIndex];
    final updatedStart = start != null ? double.parse(start.toStringAsFixed(3)) : word.start;
    final updatedEnd = end != null ? double.parse(end.toStringAsFixed(3)) : word.end;

    if (updatedEnd <= updatedStart) return;

    final updatedWords = List<WordSegment>.from(ayah.words);
    updatedWords[wordIndex] = word.copyWith(start: updatedStart, end: updatedEnd);
    _segments[ayahIndex] = ayah.copyWith(words: updatedWords);
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

import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/alignment_models.dart';

class QuranDataService {
  static final QuranDataService _instance = QuranDataService._internal();
  factory QuranDataService() => _instance;
  QuranDataService._internal();

  Map<String, List<String>> _hafshData = {};
  Map<String, List<String>> _warshData = {};
  bool _loaded = false;

  Future<void> loadData() async {
    if (_loaded) return;
    try {
      final hafshString = await rootBundle.loadString('assets/data/quran_hafsh.json');
      final Map<String, dynamic> hafshJson = jsonDecode(hafshString);
      _hafshData = hafshJson.map((k, v) => MapEntry(k, (v as List).map((e) => e.toString()).toList()));
    } catch (_) {}

    try {
      final warshString = await rootBundle.loadString('assets/data/quran_warsh.json');
      final Map<String, dynamic> warshJson = jsonDecode(warshString);
      _warshData = warshJson.map((k, v) => MapEntry(k, (v as List).map((e) => e.toString()).toList()));
    } catch (_) {}

    _loaded = true;
  }

  Future<List<String>> getSurahAyahs(int surahId, {String riwaya = 'hafsh'}) async {
    await loadData();
    final key = surahId.toString();
    if (riwaya == 'warsh' && _warshData.containsKey(key)) {
      return _warshData[key]!;
    }
    if (_hafshData.containsKey(key)) {
      return _hafshData[key]!;
    }
    return [];
  }

  List<AyahSegment> mergeQuranTextIntoSegments(List<AyahSegment> segments, List<String> quranText) {
    if (quranText.isEmpty) return segments;

    final result = <AyahSegment>[];
    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final text = i < quranText.length ? quranText[i] : seg.text;
      result.add(seg.copyWith(text: text));
    }
    return result;
  }

  /// فك وتحليل ملفات التزمين الخارجية بصيغ JSON المختلفة
  Map<String, dynamic>? parseAlignmentJson(String jsonString, {int defaultSurahId = 1}) {
    try {
      final dynamic decoded = jsonDecode(jsonString);
      if (decoded is! Map<String, dynamic>) return null;
      final data = decoded;

      // 1. صيغة segments (مثل ملف tmpdve8r7_6.json أو ملفات Ground Truth)
      if (data.containsKey('segments') && data['segments'] is List) {
        final segmentsList = data['segments'] as List;
        final Map<int, List<WordSegment>> ayahWordsMap = {};
        final Map<String, List<WordSegment>> splitGroupMap = {};
        int detectedSurahId = defaultSurahId;

        for (final item in segmentsList) {
          if (item is! Map) continue;
          final s = Map<String, dynamic>.from(item);
          final matchedText = (s['matched_text'] ?? '').toString().trim();
          final timeFrom = (s['time_from'] as num?)?.toDouble() ?? 0.0;
          final timeTo = (s['time_to'] as num?)?.toDouble() ?? 0.0;
          final refFrom = (s['ref_from'] ?? '').toString();
          final specialType = s['special_type'];
          final splitGroupId = s['split_group_id']?.toString();

          if (matchedText.isEmpty) continue;

          int ayahNum = 1;
          if (refFrom.isNotEmpty && refFrom.contains(':')) {
            final parts = refFrom.split(':');
            if (parts.length >= 2) {
              detectedSurahId = int.tryParse(parts[0]) ?? detectedSurahId;
              ayahNum = int.tryParse(parts[1]) ?? 1;
            }
          } else if (specialType == 'Basmala') {
            ayahNum = 1;
          } else if (specialType == "Isti'adha") {
            continue;
          }

          final isRep = s['has_repeated_words'] == true || s['is_repetition'] == true;
          final wordSeg = WordSegment(
            word: matchedText,
            start: timeFrom,
            end: timeTo,
            ayahNumber: ayahNum,
            confidence: (s['confidence'] as num?)?.toDouble() ?? 1.0,
            isRepetition: isRep,
            repetitionType: isRep ? (s['repetition_type'] ?? 'waqf_ibtida') : null,
          );

          ayahWordsMap.putIfAbsent(ayahNum, () => []).add(wordSeg);

          if (splitGroupId != null && splitGroupId.isNotEmpty) {
            splitGroupMap.putIfAbsent(splitGroupId, () => []).add(wordSeg);
          }
        }

        final ayahs = <AyahSegment>[];
        final sortedAyahKeys = ayahWordsMap.keys.toList()..sort();
        for (final aNum in sortedAyahKeys) {
          final wList = ayahWordsMap[aNum]!;
          wList.sort((a, b) => a.start.compareTo(b.start));
          ayahs.add(AyahSegment(
            ayahNumber: aNum,
            start: wList.first.start,
            end: wList.last.end,
            text: wList.map((w) => w.word).join(' '),
            words: wList,
          ));
        }

        final breaths = <BreathGroup>[];
        if (splitGroupMap.isNotEmpty) {
          int gIdx = 1;
          for (final entry in splitGroupMap.entries) {
            final wList = entry.value;
            wList.sort((a, b) => a.start.compareTo(b.start));
            final distinctAyahs = wList.map((w) => w.ayahNumber ?? 1).toSet().toList()..sort();
            breaths.add(BreathGroup(
              groupIndex: gIdx++,
              startTime: wList.first.start,
              endTime: wList.last.end,
              duration: wList.last.end - wList.first.start,
              text: wList.map((w) => w.word).join(' '),
              words: wList,
              ayahNumbers: distinctAyahs,
            ));
          }
          breaths.sort((a, b) => a.startTime.compareTo(b.startTime));
          for (int i = 0; i < breaths.length; i++) {
            breaths[i].groupIndex = i + 1;
          }
        } else {
          breaths.addAll(ayahs.asMap().entries.map((e) {
            final s = e.value;
            return BreathGroup(
              groupIndex: e.key + 1,
              startTime: s.start,
              endTime: s.end,
              duration: s.end - s.start,
              text: s.text,
              words: s.words,
              ayahNumbers: [s.ayahNumber],
            );
          }));
        }

        return {
          'surahId': detectedSurahId,
          'ayahs': ayahs,
          'breathGroups': breaths,
        };
      }

      // 2. صيغة Munajjam الرسمية أو صيغة الخادم ('ayahs' أو 'data')
      final rawAyahs = (data['ayahs'] ?? data['data']) as List?;
      final rawBreaths = (data['breath_groups'] ?? data['breaths']) as List?;
      final surahId = (data['surah_id'] as num?)?.toInt() ?? defaultSurahId;

      if (rawAyahs != null) {
        final ayahs = rawAyahs.map((a) => AyahSegment.fromJson(Map<String, dynamic>.from(a as Map))).toList();
        final breaths = rawBreaths != null
            ? rawBreaths.map((b) => BreathGroup.fromJson(Map<String, dynamic>.from(b as Map))).toList()
            : <BreathGroup>[];
        return {
          'surahId': surahId,
          'ayahs': ayahs,
          'breathGroups': breaths,
        };
      }

      return null;
    } catch (e) {
      return null;
    }
  }
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:munajjam_desktop/models/alignment_models.dart';
import 'package:munajjam_desktop/providers/alignment_provider.dart';
import 'package:munajjam_desktop/services/quran_data_service.dart';

Future<AlignmentProvider> fixture({bool sharedWords = false}) async {
  final provider = AlignmentProvider();
  final ayahs = List.generate(
    3,
    (a) => AyahSegment(
      ayahNumber: a + 1,
      start: a * 2.0,
      end: (a + 1) * 2.0,
      text: 'آية',
      words: List.generate(
        2,
        (w) => WordSegment(
          word: 'كلمة',
          start: a * 2.0 + w,
          end: a * 2.0 + w + 1,
          ayahNumber: a + 1,
          confidence: a == 1 && w == 1 ? 0.8 : double.nan,
          isRepetition: a == 2 && w == 0,
        ),
      ),
    ),
  );
  await provider.applyAlignmentResult(
    ayahs: ayahs,
    breaths: sharedWords
        ? []
        : List.generate(
            3,
            (a) => BreathGroup(
              groupIndex: a + 1,
              startTime: a * 2.0,
              endTime: (a + 1) * 2.0,
              duration: 2,
              text: 'نفس',
              words: ayahs[a].words.map((w) => w.copyWith()).toList(),
              ayahNumbers: [a + 1],
              isRepetition: a == 2,
            ),
          ),
    surahId: 1,
  );
  return provider;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('moving a padded parent edge cannot exclude its first word', () async {
    final p = AlignmentProvider();
    addTearDown(p.dispose);
    await p.applyAlignmentResult(
      ayahs: [
        AyahSegment(
          ayahNumber: 1,
          start: 0,
          end: 4,
          text: 'آية',
          words: [WordSegment(word: 'كلمة', start: 1, end: 2)],
        ),
      ],
      breaths: [],
      surahId: 1,
    );
    p.updateAyahSegment(0, start: 1.5);
    expect(p.segments.single.start, 0);
    expect(p.segments.single.words.single.start, 1);
  });

  test(
    'explicit error metadata survives import and export without a score',
    () async {
      final p = AlignmentProvider();
      addTearDown(p.dispose);
      final imported = await p.importAlignmentFromJson(
        jsonString: jsonEncode({
          'ayahs': [
            {
              'ayah_number': 1,
              'start': 0,
              'end': 2,
              'words': [
                {'word': 'كلمة', 'start': 1, 'end': 2, 'is_error': true},
              ],
            },
          ],
        }),
      );
      expect(imported, isTrue);
      p.setGranularity(AlignmentGranularity.word);
      expect(p.errorPositions, [1]);
      final exported = jsonDecode(p.generateExportJson());
      expect(exported['ayahs'][0]['words'][0]['is_error'], isTrue);
    },
  );

  test('missing reliability stays unknown and exports valid JSON', () {
    final ayah = AyahSegment.fromJson({'ayah_number': 1, 'start': 0, 'end': 2});
    expect(ayah.reliability.isNaN, isTrue);
    expect(
      jsonDecode(jsonEncode(ayah.toJson())).containsKey('similarity'),
      isFalse,
    );
    final measured = AyahSegment.fromJson({
      'words': [
        {'word': 'أ', 'confidence': 0.6},
        {'word': 'ب', 'confidence': 0.8},
        {'word': 'ج'},
      ],
    });
    expect(measured.reliability, closeTo(0.7, 0.0001));
  });

  test(
    'keyboard navigation follows the chosen level and crosses verses',
    () async {
      final p = await fixture();
      addTearDown(p.dispose);
      expect(p.navigate(1, 0), 2);
      expect(p.currentSegmentIndex, 1);
      p.setGranularity(AlignmentGranularity.breath);
      expect(p.navigate(-1, 2), 0);
      p.setGranularity(AlignmentGranularity.word);
      expect(p.navigate(1, 1), 2);
      expect(p.currentSegmentIndex, 1);
      expect(p.currentWordIndex, 0);
      expect(p.navigate(-1, 2), 1);
      expect(p.currentSegmentIndex, 0);
      expect(p.currentWordIndex, 1);
      expect(p.navigate(-1, 0), 0);
      expect(p.navigate(1, 5), 5);
    },
  );

  test('a shared boundary belongs to the following word and verse', () async {
    final p = await fixture();
    addTearDown(p.dispose);
    p.updateCurrentTime(2);
    expect(p.currentSegmentIndex, 1);
    expect(p.currentBreathIndex, 1);
    expect(p.currentWordIndex, 0);
    p.updateCurrentTime(2.5);
    expect(p.currentWordIndex, 0);
    p.selectBreath(1);
    expect(p.currentSegmentIndex, 1);
    expect(p.currentWordIndex, 0);
  });

  for (final level in AlignmentGranularity.values) {
    test('dragging $level synchronizes all levels atomically', () async {
      final p = await fixture();
      addTearDown(p.dispose);
      p.setGranularity(level);
      p.moveMarker(
        level == AlignmentGranularity.word ? 1 : 0,
        false,
        2.2,
        wordAyahIndex: level == AlignmentGranularity.word ? 0 : null,
      );
      expect(p.segments[0].end, 2.2);
      expect(p.segments[1].start, 2.2);
      expect(p.segments[0].words.last.end, 2.2);
      expect(p.segments[1].words.first.start, 2.2);
      expect(p.breathGroups[0].endTime, 2.2);
      expect(p.breathGroups[1].startTime, 2.2);
      expect(p.breathGroups[0].words.last.end, 2.2);
      expect(p.breathGroups[1].words.first.start, 2.2);
      expect(p.breathGroups[0].duration, 2.2);
      final before = p.generateExportJson();
      p.moveMarker(
        level == AlignmentGranularity.word ? 1 : 0,
        false,
        3.5,
        wordAyahIndex: level == AlignmentGranularity.word ? 0 : null,
      );
      expect(
        p.generateExportJson(),
        before,
        reason: 'Cannot cross the next word end',
      );
      p.resetToOriginal();
      expect(p.segments[0].end, 2);
      expect(p.breathGroups[1].startTime, 2);
    });
  }

  test(
    'shared fallback words update once and original timings survive',
    () async {
      final p = await fixture(sharedWords: true);
      addTearDown(p.dispose);
      p.updateWordSegment(0, 1, end: 2.2);
      expect(p.breathGroups[0].words.last.end, 2.2);
      p.resetToOriginal();
      expect(p.segments[0].words.last.end, 2);
    },
  );

  test(
    'issue navigation wraps and targets the actual low-confidence word',
    () async {
      final p = await fixture();
      addTearDown(p.dispose);
      expect(p.repetitionPositions, [4]);
      p.setGranularity(AlignmentGranularity.word);
      expect(p.errorPositions, [3]);
      expect(p.nextIssue(0, repetition: false), 3);
      expect(p.currentWordIndex, 1);
      expect(p.nextIssue(5, repetition: true), 4);
      expect(p.currentSegmentIndex, 2);
      expect(p.averageSimilarity, closeTo(0.8, 0.0001));
    },
  );

  test('previous and next repetitions navigate and wrap without duplicated word entries', () async {
    final p = await fixture();
    addTearDown(p.dispose);
    p.breathGroups[0].isRepetition = true;
    p.refreshAlignment();
    expect(p.repetitionPositions, [0, 4]);
    expect(p.repetitions.length, 2);
    expect(p.nextIssue(0, repetition: true), 4);
    expect(p.nextIssue(4, repetition: true, direction: -1), 0);
    expect(p.nextIssue(0, repetition: true, direction: -1), 4);
    expect(p.nextIssue(4, repetition: true), 0);
  });

  test('Quran text uses verse numbers when the alignment starts mid-surah', () {
    final result = QuranDataService().mergeQuranTextIntoSegments(
      [AyahSegment(ayahNumber: 3, start: 0, end: 1, text: 'recognized')],
      ['الأولى', 'الثانية', 'الثالثة'],
    );
    expect(result.single.text, 'الثالثة');
  });
}

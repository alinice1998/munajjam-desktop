import 'package:flutter_test/flutter_test.dart';
import 'package:munajjam_desktop/models/alignment_models.dart';
import 'package:munajjam_desktop/providers/alignment_provider.dart';
import 'package:flutter/foundation.dart';

import 'alignment_editor_test.dart' show fixture;

Future<AlignmentProvider> largeFixture() async {
  final p = AlignmentProvider();
  final ayahs = List.generate(
    286,
    (a) => AyahSegment(
      ayahNumber: a + 1,
      start: a * 4.0,
      end: a * 4.0 + 4,
      text: 'آية ${a + 1}',
      words: List.generate(
        20,
        (w) => WordSegment(
          word: 'كلمة $w',
          ayahNumber: a + 1,
          start: a * 4.0 + w * 0.2,
          end: a * 4.0 + (w + 1) * 0.2,
          confidence: w % 4 == 0 ? 0.85 : 0.99,
        ),
      ),
    ),
  );
  final breaths = <BreathGroup>[];
  for (final ayah in ayahs) {
    for (int part = 0; part < 4; part++) {
      final words = ayah.words.sublist(part * 5, part * 5 + 5);
      breaths.add(
        BreathGroup(
          groupIndex: breaths.length + 1,
          startTime: words.first.start,
          endTime: words.last.end,
          duration: 1,
          text: 'نَفَس ${breaths.length + 1}',
          words: words,
          ayahNumbers: [ayah.ayahNumber],
        ),
      );
    }
  }
  await p.applyAlignmentResult(ayahs: ayahs, breaths: breaths, surahId: 2);
  return p;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'cached paint scores retain source indices for nonchronological imports',
    () async {
      final p = await fixture();
      addTearDown(p.dispose);
      final first = p.segments[0];
      p.segments[0] = p.segments[1];
      p.segments[1] = first;
      p.refreshAlignment();
      expect(p.ayahReliabilities[0], 0.8);
      expect(p.ayahReliabilities[1].isNaN, isTrue);
      expect(p.reviewIndices(AlignmentGranularity.ayah), {0});
    },
  );
  test('large-surah warm navigation and threshold changes reuse the data index', () async {
    final p = await largeFixture();
    addTearDown(p.dispose);
    final words = p.allWordEntries;
    final watch = Stopwatch()..start();
    for (int i = 0; i < 100; i++) {
      p.setGranularity(AlignmentGranularity.word);
      p.navigate(1, i * 4.0);
      p.setReviewThreshold(AlignmentGranularity.word, i.isEven ? 0.90 : 0.95);
      p.reviewItems(AlignmentGranularity.word);
      expect(identical(words, p.allWordEntries), isTrue);
    }
    watch.stop();
    expect(words, hasLength(5720));
    debugPrint(
      '5720 words: 100 navigation/filter interactions in ${watch.elapsedMilliseconds}ms (test host).',
    );
  });
  test('navigation reuses word, review and repetition computations', () async {
    final p = await fixture();
    addTearDown(p.dispose);
    final words = p.allWordEntries;
    final waveform = p.waveformWords;
    final review = p.reviewItems(AlignmentGranularity.word);
    final repetitions = p.repetitions;
    for (int i = 0; i < 100; i++) {
      p.updateCurrentTime((i % 6).toDouble());
      expect(identical(words, p.allWordEntries), isTrue);
      expect(identical(waveform, p.waveformWords), isTrue);
      expect(
        identical(review, p.reviewItems(AlignmentGranularity.word)),
        isTrue,
      );
      expect(identical(repetitions, p.repetitions), isTrue);
    }
    final breathReview = p.reviewItems(AlignmentGranularity.breath);
    p.setReviewThreshold(AlignmentGranularity.word, 0.7);
    expect(p.reviewItems(AlignmentGranularity.word), isEmpty);
    expect(
      identical(breathReview, p.reviewItems(AlignmentGranularity.breath)),
      isTrue,
    );
    expect(identical(words, p.allWordEntries), isTrue);
    p.updateWordSegment(0, 1, end: 2.2);
    expect(identical(words, p.allWordEntries), isFalse);
    expect(p.allWordEntries[1].segment.end, 2.2);
    expect(p.waveformWords[1].end, 2.2);
  });

  test('selection emits one synchronized notification and identical settings emit none', () async {
    final p = await fixture();
    addTearDown(p.dispose);
    var notifications = 0;
    p.addListener(() => notifications++);
    p.selectBreath(1);
    expect(notifications, 1);
    p.selectBreath(1);
    expect(notifications, 1);
    p.setGranularity(p.activeGranularity);
    p.setWordListScope(p.wordListScope);
    p.setReviewThreshold(
      AlignmentGranularity.word,
      p.reviewThreshold(AlignmentGranularity.word),
    );
    expect(notifications, 1);
  });
}

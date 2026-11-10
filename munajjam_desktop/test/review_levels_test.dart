import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:munajjam_desktop/models/alignment_models.dart';
import 'package:munajjam_desktop/views/widgets/waveform_painter.dart';

import 'alignment_editor_test.dart' show fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('independent review thresholds apply to each level and unknown stays unknown', () async {
    final p = await fixture();
    addTearDown(p.dispose);
    expect(p.reviewItems(AlignmentGranularity.ayah).map((i) => i.start), [2]);
    expect(p.reviewItems(AlignmentGranularity.breath).map((i) => i.start), [2]);
    expect(p.reviewItems(AlignmentGranularity.word).map((i) => i.start), [3]);
    p.setReviewThreshold(AlignmentGranularity.breath, 0.7);
    expect(p.reviewItems(AlignmentGranularity.breath), isEmpty);
    expect(p.reviewItems(AlignmentGranularity.ayah), hasLength(1));
    expect(p.reviewItems(AlignmentGranularity.word), hasLength(1));
    p.setReviewThreshold(AlignmentGranularity.word, 0.8);
    expect(p.reviewItems(AlignmentGranularity.word), isEmpty);
    expect(p.needsReview(AlignmentGranularity.ayah, double.nan), isFalse);
    expect(
      p.needsReview(AlignmentGranularity.ayah, double.nan, isError: true),
      isTrue,
    );
    p.setReviewThreshold(AlignmentGranularity.breath, 0.9);
    p.selectReviewItem(p.reviewItems(AlignmentGranularity.breath).single);
    expect(p.activeGranularity, AlignmentGranularity.breath);
    expect(p.currentBreathIndex, 1);
  });

  test('word scopes follow current verse and breath, including breath-only words', () async {
    final p = await fixture();
    addTearDown(p.dispose);
    p.updateCurrentTime(2.5);
    expect(p.visibleWordEntries, hasLength(6));
    p.setWordListScope(WordListScope.ayah);
    expect(p.visibleWordEntries.map((e) => e.segment.start), [2, 3]);
    p.setWordListScope(WordListScope.breath);
    expect(p.visibleWordEntries.map((e) => e.segment.start), [2, 3]);
    p.updateCurrentTime(4.5);
    expect(p.visibleWordEntries.map((e) => e.segment.start), [4, 5]);
    p.updateCurrentTime(10);
    expect(p.visibleWordEntries, isEmpty);
    p.setWordListScope(WordListScope.surah);
    expect(p.visibleWordEntries, hasLength(6));
    p.segments[2].words = [];
    p.refreshAlignment();
    p.updateCurrentTime(4.5);
    p.setWordListScope(WordListScope.breath);
    expect(p.visibleWordEntries.map((e) => e.segment.start), [4, 5]);
    expect(p.currentWordStart, 4);
    p.setGranularity(AlignmentGranularity.word);
    expect(p.navigate(1, 4), 5);
    expect(p.currentWordStart, 5);
    // A breath can cross a verse boundary; the two scopes must remain distinct.
    p.breathGroups[0].endTime = 4;
    p.refreshAlignment();
    p.updateCurrentTime(2.5);
    p.setWordListScope(WordListScope.breath);
    expect(p.visibleWordEntries.map((e) => e.segment.start), [0, 1, 2, 3]);
    p.setWordListScope(WordListScope.ayah);
    expect(p.visibleWordEntries.map((e) => e.segment.start), [2, 3]);
  });

  test('breath supplied confidence survives JSON and otherwise averages measured words', () {
    final b = BreathGroup.fromJson({'confidence': 0.65, 'words': []});
    expect(b.reliability, 0.65);
    expect(b.copyWith().toJson()['confidence'], 0.65);
    final computed = BreathGroup.fromJson({
      'words': [
        {'confidence': 0.6},
        {'confidence': 0.8},
        {},
      ],
    });
    expect(computed.reliability, closeTo(0.7, 0.0001));
    expect(BreathGroup.fromJson({}).reliability.isNaN, isTrue);
  });

  for (final level in AlignmentGranularity.values) {
    test(
      'painted $level regions turn red at configured threshold, including active regions',
      () async {
        final word = WordSegment(word: 'أ', start: 0, end: 2, confidence: 0.8);
        final ayah = AyahSegment(
          ayahNumber: 1,
          start: 0,
          end: 2,
          text: 'أ',
          similarity: 0.8,
          words: [word],
        );
        final breath = BreathGroup(
          groupIndex: 1,
          startTime: 0,
          endTime: 2,
          duration: 2,
          text: 'أ',
          words: [word],
          ayahNumbers: [1],
        );
        Future<List<int>> pixel(double threshold) async {
          final recorder = ui.PictureRecorder();
          final painter = WaveformPainter(
            peaks: [],
            totalDuration: 3,
            currentPosition: 0.5,
            pixelsPerSecond: 100,
            granularity: level,
            ayahs: [ayah],
            breaths: [breath],
            activeIndex: 0,
            ayahReviewThreshold: threshold,
            breathReviewThreshold: threshold,
            wordReviewThreshold: threshold,
          );
          painter.paint(Canvas(recorder), const Size(300, 180));
          final picture = recorder.endRecording();
          final image = await picture.toImage(300, 180);
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final bytes = data!.buffer.asUint8List();
          final result = bytes.sublist(
            (150 * 300 + 70) * 4,
            (150 * 300 + 70) * 4 + 4,
          );
          image.dispose();
          picture.dispose();
          return result;
        }

        final red = await pixel(0.9);
        expect(red[0], greaterThan(red[1] * 2));
        expect(red[0], greaterThan(red[2] * 2));
        final accepted = await pixel(0.7);
        expect(accepted[1], greaterThan(accepted[0]));
      },
    );
  }
}

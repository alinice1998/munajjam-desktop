import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:munajjam_desktop/providers/alignment_provider.dart';
import 'package:munajjam_desktop/models/alignment_models.dart';
import 'package:munajjam_desktop/services/audio_service.dart';
import 'package:munajjam_desktop/views/qa_screen.dart';
import 'package:munajjam_desktop/views/widgets/ayah_list_view.dart';
import 'package:munajjam_desktop/views/widgets/waveform_editor.dart';
import 'package:munajjam_desktop/views/widgets/waveform_painter.dart';

import 'alignment_editor_test.dart' show fixture;
import 'performance_cache_test.dart' show largeFixture;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <String>[];
  int position = 0;
  setUp(() {
    calls.clear();
    position = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (_) async => 1,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global/events'),
      (_) async => null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async {
        calls.add(call.method);
        if (call.method == 'create') {
          final id = (call.arguments as Map)['playerId'];
          binding.defaultBinaryMessenger.setMockMethodCallHandler(
            MethodChannel('xyz.luan/audioplayers/events/$id'),
            (_) async => null,
          );
        }
        if (call.method == 'seek') {
          position = (call.arguments as Map)['position'] as int;
          final id = (call.arguments as Map)['playerId'];
          binding.channelBuffers.push(
            'xyz.luan/audioplayers/events/$id',
            const StandardMethodCodec().encodeSuccessEnvelope({
              'event': 'audio.onSeekComplete',
            }),
            (_) {},
          );
        }
        if (call.method == 'getCurrentPosition') return position;
        return 1;
      },
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (_) async => false,
    );
  });

  testWidgets(
    'editor keyboard, playback following, full-surah zoom and resize',
    (tester) async {
      tester.view.physicalSize = const Size(2400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final p = (await tester.runAsync(() => fixture()))!;
      addTearDown(p.dispose);
      final audio = AudioService();
      audio.durationNotifier.value = const Duration(minutes: 30);
      audio.positionNotifier.value = Duration.zero;
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: p,
          child: const MaterialApp(home: QAScreen()),
        ),
      );
      await tester.pump();

      // No click in either editor panel: the screen's autofocus receives all four arrows.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(audio.currentSeconds, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(audio.currentSeconds, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(audio.currentSeconds, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(audio.currentSeconds, 0);

      await tester.ensureVisible(find.byTooltip('عرض السورة كاملة'));
      await tester.tap(find.byTooltip('عرض السورة كاملة'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(audio.currentSeconds, 2);
      expect(p.currentSegmentIndex, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(audio.currentSeconds, 0);

      await tester.ensureVisible(find.byTooltip('عرض السورة كاملة'));
      await tester.tap(find.byTooltip('عرض السورة كاملة'));
      await tester.pump();
      await tester.pump();
      final paint = tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byType(WaveformEditor),
              matching: find.byType(CustomPaint),
            ),
          )
          .firstWhere((widget) => widget.painter is WaveformPainter);
      final painter = paint.painter! as WaveformPainter;
      expect(painter.pixelsPerSecond * 1800, closeTo(painter.visibleWidth, 1));

      final originalHeight = paint.size.height;
      await tester.ensureVisible(
        find.byKey(const ValueKey('waveform_resize_handle')),
      );
      await tester.drag(
        find.byKey(const ValueKey('waveform_resize_handle')),
        const Offset(0, 80),
      );
      await tester.pump();
      final resized = tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byType(WaveformEditor),
              matching: find.byType(CustomPaint),
            ),
          )
          .firstWhere((widget) => widget.painter is WaveformPainter);
      expect(resized.size.height, greaterThan(originalHeight));

      await tester.ensureVisible(find.byType(AyahListView));
      await tester.ensureVisible(find.text('انقر للتشغيل والمزامنة'));
      await tester.tap(find.text('انقر للتشغيل والمزامنة'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(audio.currentSeconds, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(audio.currentSeconds, 0);

      audio.playerStateNotifier.value = PlayerState.playing;
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(calls, contains('pause'));
      audio.playerStateNotifier.value = PlayerState.paused;

      p.setGranularity(AlignmentGranularity.word);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(p.currentWordIndex, 1);
      expect(audio.currentSeconds, 1);
      final breathScope = find.byKey(const ValueKey('word_scope_breath'));
      final ayahScope = find.byKey(const ValueKey('word_scope_ayah'));
      final surahScope = find.byKey(const ValueKey('word_scope_surah'));
      expect(find.byType(DropdownButton<WordListScope>), findsNothing);
      await tester.ensureVisible(breathScope);
      await tester.tap(breathScope);
      await tester.pump();
      expect(p.wordListScope, WordListScope.breath);
      expect(p.visibleWordEntries, hasLength(2));
      final contextCard = find.byKey(const ValueKey('word_scope_context'));
      expect(
        find.descendant(of: contextCard, matching: find.text('نفس')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: contextCard, matching: find.text('النَّفَس 1')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(
        find.descendant(of: contextCard, matching: find.text('النَّفَس 2')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.tap(ayahScope);
      await tester.pump();
      expect(p.wordListScope, WordListScope.ayah);
      expect(
        find.descendant(
          of: contextCard,
          matching: find.text(p.segments[0].text),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: contextCard, matching: find.text('الآية 1')),
        findsOneWidget,
      );
      await tester.tap(surahScope);
      await tester.pump();
      expect(p.wordListScope, WordListScope.surah);
      expect(contextCard, findsNothing);

      p.setGranularity(AlignmentGranularity.ayah);
      audio.positionNotifier.value = const Duration(seconds: 4);
      await tester.pump();
      expect(p.currentSegmentIndex, 2);
      final listScrollable = tester
          .stateList<ScrollableState>(
            find.descendant(
              of: find.byType(AyahListView),
              matching: find.byType(Scrollable),
            ),
          )
          .firstWhere((state) => state.position.axis == Axis.vertical);
      final currentRow = find.byKey(const ValueKey('alignment_row_ayah_2'));
      final currentViewport = find.descendant(
        of: find.byType(AyahListView),
        matching: find.byType(CustomScrollView),
      );
      expect(
        tester.getRect(currentRow).top,
        closeTo(tester.getRect(currentViewport).top, 1),
      );
      // Disabling playback follow preserves the current scroll position.
      audio.playerStateNotifier.value = PlayerState.playing;
      final followButton = find.byKey(const ValueKey('follow_current_ayah'));
      await tester.ensureVisible(followButton);
      await tester.tap(followButton);
      await tester.pump();
      listScrollable.position.jumpTo(60);
      final frozenOffset = listScrollable.position.pixels;
      audio.positionNotifier.value = Duration.zero;
      await tester.pump();
      expect(p.currentSegmentIndex, 0);
      expect(listScrollable.position.pixels, frozenOffset);
      final locate = find.byKey(const ValueKey('locate_current_item'));
      await tester.ensureVisible(locate);
      await tester.tap(locate);
      await tester.pump();
      expect(listScrollable.position.pixels, lessThan(frozenOffset));
      expect(find.byTooltip('تفعيل تثبيت الآية أعلى القائمة'), findsOneWidget);
      listScrollable.position.jumpTo(frozenOffset);
      await tester.tap(followButton);
      await tester.pump();
      expect(listScrollable.position.pixels, lessThan(frozenOffset));
      audio.playerStateNotifier.value = PlayerState.paused;

      // Selecting the breath body seeks without starting snippet playback.
      p.setGranularity(AlignmentGranularity.breath);
      await tester.pump();
      final secondBreath = find.byKey(const ValueKey('breath_row_1'));
      await tester.ensureVisible(secondBreath);
      final breathText = find.descendant(
        of: secondBreath,
        matching: find.text('نفس'),
      );
      await tester.tap(breathText);
      await tester.pump();
      expect(audio.currentSeconds, 2);
      expect(p.currentBreathIndex, 1);

      // Review window exposes three independent thresholds and live review results.
      final reviewButton = find.byKey(const ValueKey('review_list_button'));
      await tester.ensureVisible(reviewButton);
      await tester.tap(reviewButton);
      await tester.pumpAndSettle();
      expect(find.text('مراجعة الموثوقية'), findsOneWidget);
      for (final level in AlignmentGranularity.values) {
        expect(
          find.byKey(ValueKey('review_threshold_${level.name}')),
          findsOneWidget,
        );
      }
      tester
          .widget<Slider>(find.byKey(const ValueKey('review_threshold_breath')))
          .onChanged!(70);
      await tester.pump();
      expect(p.reviewThreshold(AlignmentGranularity.breath), 0.7);
      expect(find.byKey(const ValueKey('review_item_breath_0')), findsNothing);
      tester
          .widget<Slider>(find.byKey(const ValueKey('review_threshold_breath')))
          .onChanged!(90);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('review_item_breath_0')));
      await tester.pumpAndSettle();
      expect(audio.currentSeconds, 2);
      expect(find.byType(AlertDialog), findsNothing);

      // Repetition list provides text and time, and selecting an entry seeks.
      await tester.ensureVisible(
        find.byKey(const ValueKey('repetition_list_button')),
      );
      await tester.tap(find.byKey(const ValueKey('repetition_list_button')));
      await tester.pumpAndSettle();
      expect(find.text('التكرارات (1)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('repetition_0')));
      await tester.pumpAndSettle();
      expect(audio.currentSeconds, 4);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.ensureVisible(find.byTooltip('التكرار السابق'));
      await tester.tap(find.byTooltip('التكرار السابق'));
      await tester.pump();
      expect(audio.currentSeconds, 4); // a single repetition wraps to itself

      // Navigation groups each have their own colored border and a visible gap.
      final repeatGroup = find.byKey(
        const ValueKey('repetition_navigation_group'),
      );
      final reviewGroup = find.byKey(const ValueKey('review_navigation_group'));
      final repeatDecoration =
          tester.widget<Container>(repeatGroup).decoration! as BoxDecoration;
      final reviewDecoration =
          tester.widget<Container>(reviewGroup).decoration! as BoxDecoration;
      expect(repeatDecoration.border, isNotNull);
      expect(reviewDecoration.border, isNotNull);
      expect(repeatDecoration.color, isNot(reviewDecoration.color));
      final repeatRect = tester.getRect(repeatGroup);
      final reviewRect = tester.getRect(reviewGroup);
      final groupGap = repeatRect.left < reviewRect.left
          ? reviewRect.left - repeatRect.right
          : repeatRect.left - reviewRect.right;
      expect(groupGap, greaterThanOrEqualTo(9));
      expect(repeatRect.center.dy, closeTo(reviewRect.center.dy, 1));

      // Zoom slider and icons share one vertical center, on a single toolbar row.
      await tester.ensureVisible(find.byIcon(Icons.zoom_out));
      final sliders = find.descendant(
        of: find.byType(WaveformEditor),
        matching: find.byType(Slider),
      );
      final sliderCenter = tester.getCenter(sliders.first).dy;
      expect(
        tester.getCenter(find.byIcon(Icons.zoom_out)).dy,
        closeTo(sliderCenter, 1),
      );
      expect(
        tester.getCenter(find.byIcon(Icons.zoom_in)).dy,
        closeTo(sliderCenter, 1),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('waveform_toolbar'))).height,
        44,
      );
      // Even a focused slider cannot consume the editor's arrow navigation.
      final pixelsBeforeKey =
          (tester
                      .widgetList<CustomPaint>(
                        find.descendant(
                          of: find.byType(WaveformEditor),
                          matching: find.byType(CustomPaint),
                        ),
                      )
                      .firstWhere((widget) => widget.painter is WaveformPainter)
                      .painter!
                  as WaveformPainter)
              .pixelsPerSecond;
      Focus.of(tester.element(sliders.first)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(audio.currentSeconds, 2);
      final pixelsAfterKey =
          (tester
                      .widgetList<CustomPaint>(
                        find.descendant(
                          of: find.byType(WaveformEditor),
                          matching: find.byType(CustomPaint),
                        ),
                      )
                      .firstWhere((widget) => widget.painter is WaveformPainter)
                      .painter!
                  as WaveformPainter)
              .pixelsPerSecond;
      expect(pixelsAfterKey, pixelsBeforeKey);
      final listHeader = find.descendant(
        of: find.byType(AyahListView),
        matching: find.text('انقر للتشغيل والمزامنة'),
      );
      expect(
        tester.getCenter(listHeader).dy,
        closeTo(
          tester
              .getCenter(find.byKey(const ValueKey('follow_current_ayah')))
              .dy,
          1,
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 350));
      final large = (await tester.runAsync(() => largeFixture()))!;
      addTearDown(large.dispose);
      large.setGranularity(AlignmentGranularity.breath);
      large.selectBreath(900);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: large,
          child: const MaterialApp(
            home: Scaffold(body: SizedBox(width: 960, child: AyahListView())),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      Finder materializedRows() => find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'alignment_row_breath_',
            ),
      );
      expect(large.breathGroups, hasLength(1144));
      expect(
        materializedRows().evaluate().length,
        lessThan(16),
        reason: 'Tab switching must not build all 1144 breath cards',
      );
      large.selectBreath(1143);
      await tester.pump();
      await tester.pump();
      final lastRow = find.byKey(const ValueKey('alignment_row_breath_1143'));
      final largeViewport = find.descendant(
        of: find.byType(AyahListView),
        matching: find.byType(CustomScrollView),
      );
      expect(
        tester.getRect(lastRow).top,
        closeTo(tester.getRect(largeViewport).top, 1),
      );
      expect(materializedRows().evaluate().length, lessThan(16));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 350));
      tester.view.physicalSize = const Size(960, 1200);
      await tester.pumpWidget(
        ChangeNotifierProvider<AlignmentProvider>.value(
          value: p,
          child: const MaterialApp(
            home: Scaffold(
              body: Column(children: [WaveformEditor(), AyahListView()]),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byTooltip('عرض السورة كاملة'));
      await tester.tap(find.byTooltip('عرض السورة كاملة'));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 350));
    },
  );
}

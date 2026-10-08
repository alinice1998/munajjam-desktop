import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/alignment_models.dart';

class WaveformPainter extends CustomPainter {
  final List<double> peaks;
  final double totalDuration;
  final double currentPosition;
  final double pixelsPerSecond;
  final AlignmentGranularity granularity;
  final List<AyahSegment> ayahs;
  final List<BreathGroup> breaths;
  final int? activeIndex;
  final int? hoveredIndex;
  final bool? hoveredIsStart;
  final int? draggingIndex;
  final bool isDraggingStart;
  final bool isShiftPressed;
  final double? dragTimeSec;
  final double visibleStartX;
  final double visibleWidth;
  final double ayahThreshold;
  final double breathThreshold;
  final double wordThreshold;

  WaveformPainter({
    required this.peaks,
    required this.totalDuration,
    required this.currentPosition,
    required this.pixelsPerSecond,
    required this.granularity,
    required this.ayahs,
    required this.breaths,
    this.activeIndex,
    this.hoveredIndex,
    this.hoveredIsStart,
    this.draggingIndex,
    this.isDraggingStart = false,
    this.isShiftPressed = false,
    this.dragTimeSec,
    this.visibleStartX = 0.0,
    this.visibleWidth = 10000.0,
    this.ayahThreshold = 0.95,
    this.breathThreshold = 0.95,
    this.wordThreshold = 0.90,
  });

  @override
  void paint(Canvas canvas, Size size) {
    double duration = totalDuration;
    if (duration <= 0 || duration.isNaN) {
      if (ayahs.isNotEmpty && ayahs.last.end > 0) {
        duration = ayahs.last.end;
      } else if (breaths.isNotEmpty && breaths.last.endTime > 0) {
        duration = breaths.last.endTime;
      }
    }
    if (duration <= 0 || duration.isNaN) return;

    final width = duration * pixelsPerSecond;
    final height = size.height;
    final rulerHeight = 24.0;
    final waveHeight = height - rulerHeight;
    final centerY = rulerHeight + (waveHeight / 2);

    final double validStartX = (visibleStartX.isNaN || visibleStartX < 0) ? 0.0 : visibleStartX;
    final double validWidth = (visibleWidth.isNaN || visibleWidth <= 0) ? 2000.0 : visibleWidth;

    final double startVisibleX = max(0.0, validStartX - (pixelsPerSecond * 2)); // 2s buffer
    final double endVisibleX = min(width, validStartX + validWidth + (pixelsPerSecond * 2));
    final double startVisibleSec = startVisibleX / pixelsPerSecond;
    final double endVisibleSec = endVisibleX / pixelsPerSecond;

    // 1. Draw Time Ruler (top bar)
    final visibleRectX = startVisibleX.clamp(0.0, width);
    final visibleRectW = (endVisibleX.clamp(0.0, width) - visibleRectX);
    if (visibleRectW > 0) {
      final rulerPaint = Paint()..color = const Color(0xFF1E293B);
      canvas.drawRect(Rect.fromLTWH(visibleRectX, 0, visibleRectW, rulerHeight), rulerPaint);
    }

    final linePaint = Paint()
      ..color = AppColors.glassBorder
      ..strokeWidth = 1;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    // Major markers every 1 or 5 seconds depending on zoom
    final stepSeconds = pixelsPerSecond > 60 ? 1 : (pixelsPerSecond > 30 ? 2 : 5);
    final double startSec = ((startVisibleSec / stepSeconds).floor() * stepSeconds).toDouble();
    
    for (double sec = startSec; sec <= duration && sec <= endVisibleSec; sec += stepSeconds) {
      if (sec < 0) continue;
      final x = sec * pixelsPerSecond;
      final isMajor = sec % 5 == 0;
      canvas.drawLine(
        Offset(x, rulerHeight - (isMajor ? 12 : 6)),
        Offset(x, rulerHeight),
        linePaint..color = isMajor ? Colors.white.withOpacity(0.5) : Colors.white.withOpacity(0.2),
      );

      if (isMajor || pixelsPerSecond > 50) {
        final mins = (sec / 60).floor();
        final secs = (sec % 60).floor();
        final timeStr = '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
        textPainter.text = TextSpan(
          text: timeStr,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(x + 2, 2));
      }
    }

    // 2. Draw Regions (Ayahs / Breaths / Words)
    if (granularity == AlignmentGranularity.ayah) {
      _drawAyahRegions(canvas, rulerHeight, waveHeight, startVisibleSec, endVisibleSec);
    } else if (granularity == AlignmentGranularity.breath) {
      _drawBreathRegions(canvas, rulerHeight, waveHeight, startVisibleSec, endVisibleSec);
    } else {
      _drawWordRegions(canvas, rulerHeight, waveHeight, startVisibleSec, endVisibleSec);
    }

    // 3. Draw Center Track Baseline (Zero-line for pauses & silence)
    final visibleRectX2 = startVisibleX.clamp(0.0, width);
    final visibleRectW2 = (endVisibleX.clamp(0.0, width) - visibleRectX2);
    if (visibleRectW2 > 0) {
      final baselinePaint = Paint()
        ..color = Colors.white.withOpacity(0.10)
        ..strokeWidth = 1.0;
      canvas.drawLine(
        Offset(visibleRectX2, centerY),
        Offset(visibleRectX2 + visibleRectW2, centerY),
        baselinePaint,
      );
    }

    // 4. Draw Waveform Peaks (True Physical Audio Envelope)
    if (peaks.isNotEmpty) {
      const double step = 2.4;
      
      final int startI = (startVisibleX / step).floor().clamp(0, (width / step).ceil());
      final int endI = (endVisibleX / step).ceil().clamp(0, (width / step).ceil());

      final double barWidth = 1.8;

      final wavePaintPlayed = Paint()
        ..color = AppColors.primaryEmerald.withOpacity(0.95)
        ..strokeCap = StrokeCap.round
        ..strokeWidth = barWidth;

      final wavePaintUnplayed = Paint()
        ..color = const Color(0xFF64748B)
        ..strokeCap = StrokeCap.round
        ..strokeWidth = barWidth;

      final double playX = currentPosition * pixelsPerSecond;

      for (int i = startI; i < endI; i++) {
        final double x = i * step;
        final double progress = x / width;
        final int peakIdx = (progress * (peaks.length - 1)).round().clamp(0, peaks.length - 1);
        final double val = peaks[peakIdx];

        final double minBarHeight = 1.5;
        final double barH = max(minBarHeight, val * (waveHeight / 2) * 0.95);

        final bool isPlayed = x <= playX;
        final paintToUse = isPlayed ? wavePaintPlayed : wavePaintUnplayed;

        canvas.drawLine(
          Offset(x, centerY - barH),
          Offset(x, centerY + barH),
          paintToUse,
        );
      }
    }

    // 5. Draw Playhead (Glowing playback needle)
    final playX = currentPosition * pixelsPerSecond;
    if (playX >= startVisibleX - 10 && playX <= endVisibleX + 10) {
      final glowPaint = Paint()
        ..color = AppColors.playhead.withOpacity(0.35)
        ..strokeWidth = 6;
      canvas.drawLine(Offset(playX, 0), Offset(playX, height), glowPaint);

      final playheadPaint = Paint()
        ..color = AppColors.playhead
        ..strokeWidth = 2;

      canvas.drawLine(Offset(playX, 0), Offset(playX, height), playheadPaint);

      final headPath = Path();
      headPath.moveTo(playX - 6, 0);
      headPath.lineTo(playX + 6, 0);
      headPath.lineTo(playX + 6, 12);
      headPath.lineTo(playX, 18);
      headPath.lineTo(playX - 6, 12);
      headPath.close();

      final headPaint = Paint()..color = AppColors.primaryEmerald;
      canvas.drawPath(headPath, headPaint);
    }
  }

  void _drawAyahRegions(Canvas canvas, double topY, double height, double startVisibleSec, double endVisibleSec) {
    for (int i = 0; i < ayahs.length; i++) {
      final a = ayahs[i];
      if (a.end < startVisibleSec || a.start > endVisibleSec) continue;

      final startX = a.start * pixelsPerSecond;
      final endX = a.end * pixelsPerSecond;
      final rect = Rect.fromLTWH(startX, topY, endX - startX, height);

      final isActive = i == activeIndex;
      final isLow = a.similarity < ayahThreshold;
      final isCriticallyLow = a.similarity < 0.85;

      final color = isLow
          ? (isCriticallyLow ? AppColors.regionLow : AppColors.regionMed)
          : (a.similarity >= 0.95 ? AppColors.regionHigh : AppColors.regionMed);

      final fillPaint = Paint()
        ..color = isActive ? AppColors.regionSelected : color
        ..style = PaintingStyle.fill;
      canvas.drawRect(rect, fillPaint);

      final borderPaint = Paint()
        ..color = isActive
            ? AppColors.primaryTeal
            : (isLow ? AppColors.dangerRed : Colors.white.withOpacity(0.2))
        ..strokeWidth = (isActive || isLow) ? 2 : 1
        ..style = PaintingStyle.stroke;
      canvas.drawRect(rect, borderPaint);

      final isStartDragging = draggingIndex == i && isDraggingStart;
      final isEndDragging = draggingIndex == i && !isDraggingStart;
      final isStartHovered = hoveredIndex == i && hoveredIsStart == true;
      final isEndHovered = hoveredIndex == i && hoveredIsStart == false;

      _drawHandle(
        canvas,
        startX,
        topY,
        height,
        isStart: true,
        isHovered: isStartHovered,
        isDragging: isStartDragging,
        timeSec: isStartDragging ? (dragTimeSec ?? a.start) : a.start,
      );
      _drawHandle(
        canvas,
        endX,
        topY,
        height,
        isStart: false,
        isHovered: isEndHovered,
        isDragging: isEndDragging,
        timeSec: isEndDragging ? (dragTimeSec ?? a.end) : a.end,
      );

      final lowSuffix = isLow ? ' (${(a.similarity * 100).toInt()}%)' : '';
      final tp = TextPainter(
        text: TextSpan(
          text: 'آية ${a.ayahNumber}$lowSuffix',
          style: TextStyle(
            color: isLow ? const Color(0xFFFECACA) : Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            backgroundColor: isLow ? const Color(0xCC991B1B) : Colors.black.withOpacity(0.5),
          ),
        ),
        textDirection: TextDirection.rtl,
      );
      tp.layout();
      tp.paint(canvas, Offset(startX + 6, topY + 4));
    }
  }

  void _drawBreathRegions(Canvas canvas, double topY, double height, double startVisibleSec, double endVisibleSec) {
    for (int i = 0; i < breaths.length; i++) {
      final b = breaths[i];
      if (b.endTime < startVisibleSec || b.startTime > endVisibleSec) continue;

      final startX = b.startTime * pixelsPerSecond;
      final endX = b.endTime * pixelsPerSecond;
      final rect = Rect.fromLTWH(startX, topY, endX - startX, height);

      final isActive = i == activeIndex;
      final isRep = b.isRepetition;
      final isLow = b.similarity < breathThreshold;
      final isCriticallyLow = b.similarity < 0.85;

      final Color regionFill = isRep
          ? (isActive ? AppColors.repetitionPurple.withOpacity(0.55) : AppColors.repetitionRegion)
          : (isLow
              ? (isCriticallyLow ? AppColors.regionLow : const Color(0x4DF59E0B))
              : (isActive ? AppColors.regionSelected : const Color(0x400D9488)));

      final Color regionBorder = isRep
          ? AppColors.repetitionPurple
          : (isLow
              ? (isCriticallyLow ? AppColors.dangerRed : const Color(0xFFF59E0B))
              : (isActive ? AppColors.primaryEmerald : const Color(0xFF14B8A6).withOpacity(0.5)));

      final fillPaint = Paint()
        ..color = regionFill
        ..style = PaintingStyle.fill;
      canvas.drawRect(rect, fillPaint);

      final borderPaint = Paint()
        ..color = regionBorder
        ..strokeWidth = (isActive || isRep || isLow) ? 2 : 1
        ..style = PaintingStyle.stroke;
      canvas.drawRect(rect, borderPaint);

      final isStartDragging = draggingIndex == i && isDraggingStart;
      final isEndDragging = draggingIndex == i && !isDraggingStart;
      final isStartHovered = hoveredIndex == i && hoveredIsStart == true;
      final isEndHovered = hoveredIndex == i && hoveredIsStart == false;

      _drawHandle(
        canvas,
        startX,
        topY,
        height,
        isStart: true,
        isHovered: isStartHovered,
        isDragging: isStartDragging,
        timeSec: isStartDragging ? (dragTimeSec ?? b.startTime) : b.startTime,
      );
      _drawHandle(
        canvas,
        endX,
        topY,
        height,
        isStart: false,
        isHovered: isEndHovered,
        isDragging: isEndDragging,
        timeSec: isEndDragging ? (dragTimeSec ?? b.endTime) : b.endTime,
      );

      final repSuffix = isRep ? ' 🔁 تكرار' : '';
      final lowSuffix = isLow ? ' (${(b.similarity * 100).toInt()}%)' : '';
      final tp = TextPainter(
        text: TextSpan(
          text: 'سكتة ${b.groupIndex} (${b.duration.toStringAsFixed(1)}s)$repSuffix$lowSuffix',
          style: TextStyle(
            color: isRep
                ? const Color(0xFFE9D5FF)
                : (isLow ? const Color(0xFFFECACA) : Colors.white),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            backgroundColor: isRep
                ? const Color(0xCC581C87)
                : (isLow ? const Color(0xCC991B1B) : Colors.black.withOpacity(0.5)),
          ),
        ),
        textDirection: TextDirection.rtl,
      );
      tp.layout();
      tp.paint(canvas, Offset(startX + 6, topY + 4));
    }
  }

  void _drawWordRegions(Canvas canvas, double topY, double height, double startVisibleSec, double endVisibleSec) {
    for (int i = 0; i < ayahs.length; i++) {
      final a = ayahs[i];
      if (a.end < startVisibleSec || a.start > endVisibleSec) continue;

      for (int w = 0; w < a.words.length; w++) {
        final word = a.words[w];
        if (word.end < startVisibleSec || word.start > endVisibleSec) continue;

        final startX = word.start * pixelsPerSecond;
        final endX = word.end * pixelsPerSecond;
        final rect = Rect.fromLTWH(startX, topY, endX - startX, height);
        final isRep = word.isRepetition;
        final isLow = word.confidence < wordThreshold;
        final isCriticallyLow = word.confidence < 0.85;

        final Color wordFill = isRep
            ? AppColors.repetitionRegion
            : (isLow
                ? (isCriticallyLow ? AppColors.regionLow : const Color(0x4DF59E0B))
                : const Color(0x336366F1));

        final Color wordBorder = isRep
            ? AppColors.repetitionPurple
            : (isLow
                ? (isCriticallyLow ? AppColors.dangerRed : const Color(0xFFF59E0B))
                : const Color(0xFF818CF8).withOpacity(0.5));

        final fillPaint = Paint()
          ..color = wordFill
          ..style = PaintingStyle.fill;
        canvas.drawRect(rect, fillPaint);

        final borderPaint = Paint()
          ..color = wordBorder
          ..strokeWidth = (isRep || isLow) ? 1.5 : 1
          ..style = PaintingStyle.stroke;
        canvas.drawRect(rect, borderPaint);

        _drawHandle(canvas, startX, topY, height, isStart: true);
        _drawHandle(canvas, endX, topY, height, isStart: false);

        if (endX - startX > 20) {
          final tp = TextPainter(
            text: TextSpan(
              text: word.word,
              style: TextStyle(
                color: isLow ? const Color(0xFFFECACA) : Colors.white,
                fontSize: 10,
                fontWeight: isLow ? FontWeight.bold : FontWeight.normal,
                backgroundColor: isLow ? const Color(0xCC991B1B) : Colors.black.withOpacity(0.4),
              ),
            ),
            textDirection: TextDirection.rtl,
          );
          tp.layout(maxWidth: max(10, endX - startX - 4));
          tp.paint(canvas, Offset(startX + 4, topY + 4));
        }
      }
    }
  }

  void _drawHandle(
    Canvas canvas,
    double x,
    double topY,
    double height, {
    required bool isStart,
    bool isHovered = false,
    bool isDragging = false,
    double? timeSec,
  }) {
    final isLinked = !isShiftPressed;
    final handlePaint = Paint()
      ..color = isDragging
          ? (isLinked ? AppColors.primaryEmerald : const Color(0xFFF59E0B))
          : (isHovered ? Colors.white : Colors.white.withOpacity(0.6))
      ..strokeWidth = isDragging ? 3.0 : (isHovered ? 2.5 : 1.5);

    // Glowing vertical edge line
    canvas.drawLine(Offset(x, topY), Offset(x, topY + height), handlePaint);

    // Grip circle in the center
    final gripPaint = Paint()
      ..color = isDragging
          ? (isLinked ? AppColors.primaryEmerald : const Color(0xFFF59E0B))
          : (isStart ? AppColors.primaryEmerald : AppColors.accentCyan);
    final gripY = topY + (height / 2);
    final radius = isDragging ? 6.5 : (isHovered ? 5.5 : 4.0);
    canvas.drawCircle(Offset(x, gripY), radius, gripPaint);

    final borderGripPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(Offset(x, gripY), radius, borderGripPaint);

    // If dragging, draw a live floating timestamp badge on top of the handle
    if (isDragging && timeSec != null) {
      final mins = (timeSec / 60).floor();
      final secs = (timeSec % 60).floor();
      final ms = ((timeSec % 1) * 1000).floor();
      final text = '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}.${ms.toString().padLeft(3, '0')}';

      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();

      final badgeRect = Rect.fromCenter(
        center: Offset(x, topY - 10),
        width: tp.width + 10,
        height: 18,
      );

      final badgePaint = Paint()
        ..color = isLinked ? const Color(0xFF0F172A) : const Color(0xFF78350F)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(RRect.fromRectAndRadius(badgeRect, const Radius.circular(5)), badgePaint);
      tp.paint(canvas, Offset(x - (tp.width / 2), topY - 18));
    }
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.currentPosition != currentPosition ||
        oldDelegate.pixelsPerSecond != pixelsPerSecond ||
        oldDelegate.granularity != granularity ||
        oldDelegate.activeIndex != activeIndex ||
        oldDelegate.hoveredIndex != hoveredIndex ||
        oldDelegate.hoveredIsStart != hoveredIsStart ||
        oldDelegate.draggingIndex != draggingIndex ||
        oldDelegate.isDraggingStart != isDraggingStart ||
        oldDelegate.isShiftPressed != isShiftPressed ||
        oldDelegate.dragTimeSec != dragTimeSec ||
        oldDelegate.visibleStartX != visibleStartX ||
        oldDelegate.visibleWidth != visibleWidth ||
        oldDelegate.ayahs != ayahs ||
        oldDelegate.breaths != breaths ||
        oldDelegate.peaks != peaks ||
        oldDelegate.ayahThreshold != ayahThreshold ||
        oldDelegate.breathThreshold != breathThreshold ||
        oldDelegate.wordThreshold != wordThreshold;
  }
}

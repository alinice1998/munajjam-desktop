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
    // Only draw the background for the visible area to save fill rate
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
      // Fixed on-screen step between vertical bars for maximum visual density (2.4px spacing)
      const double step = 2.4;
      
      final int startI = (startVisibleX / step).floor().clamp(0, (width / step).ceil());
      final int endI = (endVisibleX / step).ceil().clamp(0, (width / step).ceil());

      final double barWidth = 1.8;

      final wavePaintPlayed = Paint()
        ..color = AppColors.primaryEmerald.withOpacity(0.95)
        ..strokeCap = StrokeCap.round
        ..strokeWidth = barWidth;

      final wavePaintPlayedSilent = Paint()
        ..color = AppColors.primaryEmerald.withOpacity(0.35)
        ..strokeCap = StrokeCap.round
        ..strokeWidth = barWidth;

      final wavePaintUnplayed = Paint()
        ..color = Colors.white.withOpacity(0.65)
        ..strokeCap = StrokeCap.round
        ..strokeWidth = barWidth;

      final wavePaintUnplayedSilent = Paint()
        ..color = Colors.white.withOpacity(0.18)
        ..strokeCap = StrokeCap.round
        ..strokeWidth = barWidth;

      final playheadX = currentPosition * pixelsPerSecond;
      final peaksCount = peaks.length;

      for (int i = startI; i <= endI; i++) {
        final x = i * step;
        final timeSec = x / pixelsPerSecond;
        if (timeSec > duration) break;

        // Continuous sampling / interpolation from peak envelope
        final floatIdx = duration > 0 ? (timeSec / duration) * (peaksCount - 1) : 0.0;
        final idx0 = floatIdx.floor().clamp(0, peaksCount - 1);
        final idx1 = floatIdx.ceil().clamp(0, peaksCount - 1);
        final frac = floatIdx - idx0;
        final amp = (peaks[idx0] * (1.0 - frac) + peaks[idx1] * frac);

        final barHeight = (amp * (waveHeight * 0.85)).clamp(2.5, waveHeight * 0.90);
        final top = centerY - (barHeight / 2);
        final bottom = centerY + (barHeight / 2);

        final isSilent = amp < 0.035;
        final paint = x <= playheadX
            ? (isSilent ? wavePaintPlayedSilent : wavePaintPlayed)
            : (isSilent ? wavePaintUnplayedSilent : wavePaintUnplayed);

        canvas.drawLine(Offset(x, top), Offset(x, bottom), paint);
      }
    }

    // 4. Draw Playhead (Current Time Indicator)
    final playX = currentPosition * pixelsPerSecond;
    if (playX >= startVisibleX && playX <= endVisibleX) {
      final playheadPaint = Paint()
        ..color = AppColors.playhead
        ..strokeWidth = 2;

      // Glowing vertical line
      canvas.drawLine(Offset(playX, 0), Offset(playX, height), playheadPaint);

      // Playhead head handle
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
      final color = a.similarity >= 0.95
          ? AppColors.regionHigh
          : (a.similarity >= 0.90 ? AppColors.regionMed : AppColors.regionLow);

      final fillPaint = Paint()
        ..color = isActive ? AppColors.regionSelected : color
        ..style = PaintingStyle.fill;
      canvas.drawRect(rect, fillPaint);

      final borderPaint = Paint()
        ..color = isActive ? AppColors.primaryTeal : Colors.white.withOpacity(0.2)
        ..strokeWidth = isActive ? 2 : 1
        ..style = PaintingStyle.stroke;
      canvas.drawRect(rect, borderPaint);

      // Drag handles on left/right edges
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

      // Label
      final tp = TextPainter(
        text: TextSpan(
          text: 'آية ${a.ayahNumber}',
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            backgroundColor: Colors.black.withOpacity(0.5),
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

      final Color regionFill = isRep
          ? (isActive ? AppColors.repetitionPurple.withOpacity(0.55) : AppColors.repetitionRegion)
          : (isActive ? AppColors.regionSelected : const Color(0x400D9488));

      final Color regionBorder = isRep
          ? AppColors.repetitionPurple
          : (isActive ? AppColors.primaryEmerald : const Color(0xFF14B8A6).withOpacity(0.5));

      final fillPaint = Paint()
        ..color = regionFill
        ..style = PaintingStyle.fill;
      canvas.drawRect(rect, fillPaint);

      final borderPaint = Paint()
        ..color = regionBorder
        ..strokeWidth = (isActive || isRep) ? 2 : 1
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
      final tp = TextPainter(
        text: TextSpan(
          text: 'سكتة ${b.groupIndex} (${b.duration.toStringAsFixed(1)}s)$repSuffix',
          style: TextStyle(
            color: isRep ? const Color(0xFFE9D5FF) : Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            backgroundColor: isRep ? const Color(0xCC581C87) : Colors.black.withOpacity(0.5),
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
        final fillPaint = Paint()
          ..color = isRep ? AppColors.repetitionRegion : const Color(0x336366F1)
          ..style = PaintingStyle.fill;
        canvas.drawRect(rect, fillPaint);

        final borderPaint = Paint()
          ..color = isRep ? AppColors.repetitionPurple : const Color(0xFF818CF8).withOpacity(0.5)
          ..strokeWidth = isRep ? 1.5 : 1
          ..style = PaintingStyle.stroke;
        canvas.drawRect(rect, borderPaint);

        _drawHandle(canvas, startX, topY, height, isStart: true);
        _drawHandle(canvas, endX, topY, height, isStart: false);

        if (endX - startX > 25) {
          final tp = TextPainter(
            text: TextSpan(
              text: word.word,
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                backgroundColor: Colors.black.withOpacity(0.4),
              ),
            ),
            textDirection: TextDirection.rtl,
          );
          tp.layout(maxWidth: endX - startX - 4);
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
      final timeStr = '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}.${ms.toString().padLeft(3, '0')}s';
      final badgeText = isShiftPressed ? '$timeStr (🔓 منفرد)' : '$timeStr (🔗 متزامن)';

      final tp = TextPainter(
        text: TextSpan(
          text: badgeText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();

      final badgeRect = Rect.fromLTWH(
        x - (tp.width / 2) - 6,
        topY - 20,
        tp.width + 12,
        18,
      );
      final badgePaint = Paint()
        ..color = isShiftPressed ? const Color(0xFFD97706) : const Color(0xFF047857)
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
        oldDelegate.peaks != peaks;
  }
}

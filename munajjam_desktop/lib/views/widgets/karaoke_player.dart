import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/alignment_models.dart';
import '../../providers/alignment_provider.dart';
import '../../services/audio_service.dart';

class KaraokePlayer extends StatelessWidget {
  final String localeCode;

  const KaraokePlayer({super.key, this.localeCode = 'ar'});

  String _formatSegmentTime(double seconds) {
    if (seconds.isNaN || seconds < 0) return '00:00.00';
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    final ms = (((seconds % 1) * 100).floor()).toString().padLeft(2, '0');
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}.$ms';
  }

  @override
  Widget build(BuildContext context) {
    final alignProvider = context.watch<AlignmentProvider>();
    final isRTL = localeCode == 'ar';
    final audioService = AudioService();
    final segments = alignProvider.segments;
    final breathGroups = alignProvider.breathGroups;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.glassCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
      padding: const EdgeInsets.all(20),
      child: ValueListenableBuilder<Duration>(
        valueListenable: audioService.positionNotifier,
        builder: (context, pos, _) {
          final currentTime = pos.inMilliseconds / 1000.0;

          // 1. Precise Ayah Segment Matching Algorithm (identical to QAPlayer.tsx)
          AyahSegment? currentSegment;

          if (segments.isNotEmpty) {
            const boundaryBuffer = 0.08;
            for (int i = 0; i < segments.length; i++) {
              final segment = segments[i];
              final nextStart = i < segments.length - 1 ? segments[i + 1].start : double.infinity;
              final cappedUpperBound = min(segment.end, nextStart - boundaryBuffer);
              final upperBound = cappedUpperBound > segment.start ? cappedUpperBound : segment.end;

              if (currentTime >= segment.start && currentTime < upperBound) {
                currentSegment = segment;
                break;
              }
            }

            // Fallback: find last started segment
            if (currentSegment == null) {
              for (int i = segments.length - 1; i >= 0; i--) {
                if (currentTime >= segments[i].start) {
                  currentSegment = segments[i];
                  break;
                }
              }
            }

            // Default to selected index or first ayah if stopped at beginning
            if (currentSegment == null) {
              final selIdx = alignProvider.currentSegmentIndex ?? 0;
              if (selIdx < segments.length) {
                currentSegment = segments[selIdx];
              }
            }
          }

          // 2. Active Breath Group Matching Algorithm
          BreathGroup? currentBreathGroup;
          if (breathGroups.isNotEmpty) {
            for (int i = 0; i < breathGroups.length; i++) {
              final bg = breathGroups[i];
              if (currentTime >= bg.startTime && currentTime <= bg.endTime + 0.05) {
                currentBreathGroup = bg;
                break;
              }
            }
            if (currentBreathGroup == null && alignProvider.currentBreathIndex != null) {
              final bIdx = alignProvider.currentBreathIndex!;
              if (bIdx < breathGroups.length) {
                currentBreathGroup = breathGroups[bIdx];
              }
            }
          }

          // 3. Active Word Index Matching Algorithm (Non-jumping ultra-smooth karaoke)
          int activeWordIndex = -1;
          if (currentSegment != null && currentSegment.words.isNotEmpty) {
            final words = currentSegment.words;
            for (int i = 0; i < words.length; i++) {
              final w = words[i];
              final nextStart = i < words.length - 1 ? words[i + 1].start : w.end;
              final upperBound = max(w.end, nextStart);
              if (currentTime >= w.start && currentTime < upperBound) {
                activeWordIndex = i;
                break;
              }
            }
          }

          if (currentSegment == null) {
            return const SizedBox(
              height: 280,
              child: Center(
                child: Text(
                  'لا توجد آية مشغلة حالياً',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.mic_none_rounded, color: AppColors.primaryEmerald, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        isRTL ? 'الآية الحالية' : 'CURRENT AYAH',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textMuted,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (currentBreathGroup != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: currentBreathGroup.isRepetition
                            ? AppColors.repetitionPurple.withValues(alpha: 0.2)
                            : AppColors.primaryTeal.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: currentBreathGroup.isRepetition
                              ? AppColors.repetitionPurple.withValues(alpha: 0.5)
                              : AppColors.primaryTeal.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (currentBreathGroup.isRepetition) ...[
                            const Icon(Icons.repeat_rounded, size: 12, color: AppColors.repetitionPurple),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            currentBreathGroup.isRepetition
                                ? 'سكتة #${currentBreathGroup.groupIndex} (تكرار ابتداء)'
                                : 'سكتة #${currentBreathGroup.groupIndex}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: currentBreathGroup.isRepetition
                                  ? AppColors.repetitionPurple
                                  : AppColors.primaryTeal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'الآية ${currentSegment.ayahNumber}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Main Quran Display Box with Fluid Word-by-Word Glowing Highlight
              Container(
                constraints: const BoxConstraints(minHeight: 110),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.surfaceCard.withValues(alpha: 0.8),
                      AppColors.surfaceDark.withValues(alpha: 0.95),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                alignment: Alignment.center,
                child: currentSegment.words.isNotEmpty
                    ? Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 10,
                        textDirection: TextDirection.rtl,
                        children: List.generate(currentSegment.words.length, (idx) {
                          final w = currentSegment!.words[idx];
                          final isWordActive = idx == activeWordIndex;
                          final isRep = w.isRepetition;

                          return InkWell(
                            onTap: () => audioService.playSnippet(w.start, w.end),
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 100),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isWordActive
                                    ? (isRep ? AppColors.repetitionPurple.withValues(alpha: 0.35) : AppColors.primaryEmerald.withValues(alpha: 0.3))
                                    : (isRep ? AppColors.repetitionBadgeBg : Colors.transparent),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isWordActive
                                      ? (isRep ? AppColors.repetitionPurple.withValues(alpha: 0.8) : AppColors.primaryEmerald.withValues(alpha: 0.8))
                                      : (isRep ? AppColors.repetitionPurple.withValues(alpha: 0.3) : Colors.transparent),
                                  width: 1.5,
                                ),
                                boxShadow: isWordActive
                                    ? [
                                        BoxShadow(
                                          color: (isRep ? AppColors.repetitionPurple : AppColors.primaryEmerald).withValues(alpha: 0.45),
                                          blurRadius: 18,
                                        )
                                      ]
                                    : [],
                              ),
                              child: Text(
                                w.word,
                                textDirection: TextDirection.rtl,
                                style: GoogleFonts.amiri(
                                  fontSize: 26,
                                  fontWeight: isWordActive ? FontWeight.bold : FontWeight.normal,
                                  color: isWordActive
                                      ? (isRep ? const Color(0xFFDDD6FE) : const Color(0xFFA7F3D0))
                                      : (isRep ? const Color(0xFFC4B5FD) : Colors.white.withValues(alpha: 0.9)),
                                ),
                              ),
                            ),
                          );
                        }),
                      )
                    : Text(
                        currentSegment.text,
                        textAlign: TextAlign.center,
                        textDirection: TextDirection.rtl,
                        style: GoogleFonts.amiri(
                          fontSize: 26,
                          color: Colors.white,
                          height: 1.8,
                        ),
                      ),
              ),

              const SizedBox(height: 16),

              // Playback Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => audioService.playSnippet(currentSegment!.start, currentSegment.end),
                    icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 16),
                    label: const Text(
                      'تشغيل الآية فقط',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryEmerald.withValues(alpha: 0.35),
                      side: BorderSide(color: AppColors.primaryEmerald.withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () {
                      audioService.seek(currentSegment!.start);
                      audioService.play();
                    },
                    icon: const Icon(Icons.fast_forward_rounded, color: Colors.white, size: 16),
                    label: const Text(
                      'تشغيل مستمر',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Timestamps & Similarity (Matching QAPlayer.tsx)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'البداية: ${_formatSegmentTime(currentSegment.start)}',
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'النهاية: ${_formatSegmentTime(currentSegment.end)}',
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: AppColors.textSecondary),
                  ),
                  if (currentSegment.similarity < 1.0) ...[
                    const SizedBox(width: 16),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'الدقة: ',
                          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                        Text(
                          '${(currentSegment.similarity * 100).toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                            color: currentSegment.similarity >= 0.95
                                ? AppColors.scoreHigh
                                : (currentSegment.similarity >= 0.90 ? AppColors.scoreMed : AppColors.scoreLow),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

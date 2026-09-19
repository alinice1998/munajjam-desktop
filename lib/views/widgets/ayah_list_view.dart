import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/alignment_models.dart';
import '../../providers/alignment_provider.dart';
import '../../services/audio_service.dart';

class AyahListView extends StatefulWidget {
  final String localeCode;

  const AyahListView({super.key, this.localeCode = 'ar'});

  @override
  State<AyahListView> createState() => _AyahListViewState();
}

class _AyahListViewState extends State<AyahListView> {
  int? _expandedAyahIndex;

  @override
  Widget build(BuildContext context) {
    final alignProvider = context.watch<AlignmentProvider>();
    final isRTL = widget.localeCode == 'ar';
    final audioService = AudioService();

    final activeGranularity = alignProvider.activeGranularity;

    return Container(
      height: 380,
      decoration: BoxDecoration(
        color: AppColors.glassCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Header with 3-Tab Granularity Switcher
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceDark,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTab(
                        AlignmentGranularity.ayah,
                        '📜 الآيات (${alignProvider.segments.length})',
                        alignProvider,
                      ),
                      _buildTab(
                        AlignmentGranularity.breath,
                        '🌬️ السكتات (${alignProvider.breathGroups.length})',
                        alignProvider,
                      ),
                      _buildTab(
                        AlignmentGranularity.word,
                        '🔤 الكلمات',
                        alignProvider,
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  'انقر للتشغيل والمزامنة',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: AppColors.glassBorder),

          // 2. Tab Content List
          Expanded(
            child: activeGranularity == AlignmentGranularity.ayah
                ? _buildAyahTab(alignProvider, audioService, isRTL)
                : (activeGranularity == AlignmentGranularity.breath
                    ? _buildBreathTab(alignProvider, audioService, isRTL)
                    : _buildWordTab(alignProvider, audioService, isRTL)),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(AlignmentGranularity g, String label, AlignmentProvider provider) {
    final isSelected = provider.activeGranularity == g;
    return InkWell(
      onTap: () => provider.setGranularity(g),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (g == AlignmentGranularity.ayah
                  ? AppColors.primaryEmerald
                  : (g == AlignmentGranularity.breath ? AppColors.primaryTeal : const Color(0xFF6366F1)))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  // 1. AYAH TAB
  Widget _buildAyahTab(AlignmentProvider alignProvider, AudioService audioService, bool isRTL) {
    final segments = alignProvider.segments;
    if (segments.isEmpty) {
      return const Center(child: Text('لا توجد آيات محملة', style: TextStyle(color: AppColors.textMuted)));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(10),
      itemCount: segments.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final ayah = segments[index];
        final isSelected = index == alignProvider.currentSegmentIndex;
        final isExpanded = _expandedAyahIndex == index;

        return Container(
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryEmerald.withValues(alpha: 0.12) : AppColors.surfaceDark.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.primaryEmerald.withValues(alpha: 0.5) : AppColors.glassBorder,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Main Row
              InkWell(
                onTap: () {
                  alignProvider.selectAyah(index);
                  audioService.seek(ayah.start);
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
                    children: [
                      // Ayah badge
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primaryEmerald : AppColors.primaryEmerald.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${ayah.ayahNumber}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : AppColors.primaryEmerald,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Text and Timings
                      Expanded(
                        child: Column(
                          crossAxisAlignment: isRTL ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                          children: [
                            Text(
                              ayah.text,
                              textDirection: TextDirection.rtl,
                              style: GoogleFonts.amiri(
                                fontSize: 16,
                                height: 1.6,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? Colors.white : AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
                              children: [
                                Text(
                                  '${ayah.start.toStringAsFixed(2)}s - ${ayah.end.toStringAsFixed(2)}s (${ayah.duration.toStringAsFixed(2)}s)',
                                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.textMuted),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: ayah.similarity >= 0.95
                                        ? AppColors.scoreHigh.withValues(alpha: 0.15)
                                        : AppColors.scoreMed.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${(ayah.similarity * 100).toStringAsFixed(0)}% دقة',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: ayah.similarity >= 0.95 ? AppColors.scoreHigh : AppColors.scoreMed,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Action Toolbar for this Ayah
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                  border: const Border(top: BorderSide(color: AppColors.glassBorder)),
                ),
                child: Row(
                  textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
                  children: [
                    // Play Ayah Only Button
                    ElevatedButton.icon(
                      onPressed: () {
                        alignProvider.selectAyah(index);
                        audioService.playSnippet(ayah.start, ayah.end);
                      },
                      icon: const Icon(Icons.play_arrow_rounded, size: 14, color: Colors.white),
                      label: const Text('الآية فقط', style: TextStyle(fontSize: 11, color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryEmerald.withValues(alpha: 0.4),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),

                    const SizedBox(width: 6),

                    // Continuous Play Button
                    OutlinedButton.icon(
                      onPressed: () {
                        alignProvider.selectAyah(index);
                        audioService.seek(ayah.start);
                        audioService.play();
                      },
                      icon: const Icon(Icons.fast_forward_rounded, size: 14, color: Colors.white),
                      label: const Text('مستمر', style: TextStyle(fontSize: 11, color: Colors.white)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        side: const BorderSide(color: AppColors.glassBorder),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),

                    const Spacer(),

                    // Expand Words Toggle
                    if (ayah.words.isNotEmpty)
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _expandedAyahIndex = isExpanded ? null : index;
                          });
                        },
                        icon: Icon(
                          isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.auto_awesome,
                          size: 14,
                          color: AppColors.primaryTeal,
                        ),
                        label: Text(
                          isExpanded ? 'إخفاء' : '${ayah.words.length} كلمات',
                          style: const TextStyle(fontSize: 11, color: AppColors.primaryTeal),
                        ),
                      ),
                  ],
                ),
              ),

              // Expanded Words Breakdown
              if (isExpanded && ayah.words.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(10),
                  color: Colors.black.withValues(alpha: 0.4),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    textDirection: TextDirection.rtl,
                    children: ayah.words.map((w) {
                      return InkWell(
                        onTap: () => audioService.playSnippet(w.start, w.end),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceDark,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.glassBorder),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.play_circle_outline, size: 12, color: AppColors.primaryEmerald),
                              const SizedBox(width: 4),
                              Text(
                                w.word,
                                style: GoogleFonts.amiri(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${(w.end - w.start).toStringAsFixed(2)}s',
                                style: const TextStyle(fontSize: 9, fontFamily: 'monospace', color: AppColors.textMuted),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // 2. BREATH TAB
  Widget _buildBreathTab(AlignmentProvider alignProvider, AudioService audioService, bool isRTL) {
    final breaths = alignProvider.breathGroups;
    if (breaths.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد بيانات سكتات (قم بإجراء التزمين الهجين لاستخراجها تلقائياً)',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(10),
      itemCount: breaths.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final breath = breaths[index];
        final isSelected = index == alignProvider.currentBreathIndex;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryTeal.withValues(alpha: 0.15) : AppColors.surfaceDark.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.primaryTeal.withValues(alpha: 0.5) : AppColors.glassBorder,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top info & actions
              Row(
                textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primaryTeal.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'سكتة #${breath.groupIndex}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryTeal),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${breath.startTime.toStringAsFixed(2)}s - ${breath.endTime.toStringAsFixed(2)}s (${breath.duration.toStringAsFixed(2)}s)',
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.textMuted),
                  ),
                  const Spacer(),

                  // Play Breath Only
                  IconButton(
                    onPressed: () {
                      alignProvider.selectBreath(index);
                      audioService.playSnippet(breath.startTime, breath.endTime);
                    },
                    icon: const Icon(Icons.play_circle_fill_rounded, color: AppColors.primaryTeal, size: 22),
                    tooltip: 'استماع لهذا النَّفَس فقط',
                  ),

                  // Continuous play
                  IconButton(
                    onPressed: () {
                      alignProvider.selectBreath(index);
                      audioService.seek(breath.startTime);
                      audioService.play();
                    },
                    icon: const Icon(Icons.fast_forward_rounded, color: Colors.white, size: 18),
                    tooltip: 'تشغيل مستمر من هذا النَّفَس',
                  ),

                  // Split Breath
                  IconButton(
                    onPressed: () {
                      final mid = (breath.startTime + breath.endTime) / 2;
                      alignProvider.splitBreath(index, mid);
                    },
                    icon: const Icon(Icons.content_cut_rounded, color: AppColors.warningAmber, size: 16),
                    tooltip: 'تقسيم النَّفَس من المنتصف',
                  ),

                  // Merge with next
                  if (index < breaths.length - 1)
                    IconButton(
                      onPressed: () => alignProvider.mergeBreathWithNext(index),
                      icon: const Icon(Icons.merge_type_rounded, color: AppColors.primaryEmerald, size: 18),
                      tooltip: 'دمج مع النَّفَس التالي',
                    ),
                ],
              ),

              const SizedBox(height: 6),

              // Breath Text
              Text(
                breath.text.isNotEmpty ? breath.text : 'مقطع نَفَس',
                textDirection: TextDirection.rtl,
                style: GoogleFonts.amiri(
                  fontSize: 15,
                  height: 1.6,
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                ),
              ),

              // Breath Words
              if (breath.words.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  textDirection: TextDirection.rtl,
                  children: breath.words.map((w) {
                    return InkWell(
                      onTap: () => audioService.playSnippet(w.start, w.end),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceDark,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: Text(
                          w.word,
                          style: GoogleFonts.amiri(fontSize: 13, color: AppColors.textSecondary),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // 3. WORD TAB
  Widget _buildWordTab(AlignmentProvider alignProvider, AudioService audioService, bool isRTL) {
    final segments = alignProvider.segments;
    if (segments.isEmpty || segments.every((s) => s.words.isEmpty)) {
      return const Center(child: Text('لا توجد كلمات محاذاة', style: TextStyle(color: AppColors.textMuted)));
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'اضغط على أي كلمة للاستماع لنطقها منفردة بدقة ومراجعة توقيتها:',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              itemCount: segments.length,
              itemBuilder: (context, index) {
                final ayah = segments[index];
                if (ayah.words.isEmpty) return const SizedBox.shrink();

                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    textDirection: TextDirection.rtl,
                    children: ayah.words.map((w) {
                      return InkWell(
                        onTap: () => audioService.playSnippet(w.start, w.end),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceDark,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.glassBorder),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.play_arrow_rounded, size: 12, color: AppColors.primaryEmerald),
                                  const SizedBox(width: 4),
                                  Text(
                                    w.word,
                                    style: GoogleFonts.amiri(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                ],
                              ),
                              Text(
                                '${w.start.toStringAsFixed(2)}s - ${w.end.toStringAsFixed(2)}s',
                                style: const TextStyle(fontSize: 9, fontFamily: 'monospace', color: AppColors.textMuted),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

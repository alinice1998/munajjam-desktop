import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/alignment_models.dart';
import '../../providers/alignment_provider.dart';
import '../../services/audio_service.dart';

class ReviewModal extends StatefulWidget {
  final String localeCode;
  final Function(double timestamp)? onNavigate;

  const ReviewModal({
    super.key,
    this.localeCode = 'ar',
    this.onNavigate,
  });

  @override
  State<ReviewModal> createState() => _ReviewModalState();
}

class _ReviewModalState extends State<ReviewModal> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  AlignmentGranularity? _selectedGranularity;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alignProvider = context.watch<AlignmentProvider>();
    final audioService = AudioService();
    final isRTL = widget.localeCode == 'ar';

    _selectedGranularity ??= alignProvider.activeGranularity;

    final ayahItems = alignProvider.ayahReviewItems;
    final breathItems = alignProvider.breathReviewItems;
    final wordItems = alignProvider.wordReviewItems;

    final currentItems = switch (_selectedGranularity!) {
      AlignmentGranularity.ayah => ayahItems,
      AlignmentGranularity.breath => breathItems,
      AlignmentGranularity.word => wordItems,
    };

    final currentThreshold = alignProvider.getThresholdForGranularity(_selectedGranularity!);
    final currentThresholdPercent = (currentThreshold * 100).round();

    final activeColor = switch (_selectedGranularity!) {
      AlignmentGranularity.ayah => AppColors.primaryEmerald,
      AlignmentGranularity.breath => AppColors.primaryTeal,
      AlignmentGranularity.word => const Color(0xFF6366F1),
    };

    final filtered = currentItems.where((item) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.trim().toLowerCase();
      return item.text.toLowerCase().contains(q) ||
          item.ayahText.toLowerCase().contains(q) ||
          (item.ayahNumber != null && item.ayahNumber.toString().contains(q)) ||
          (item.breathIndex != null && item.breathIndex.toString().contains(q));
    }).toList();

    return Directionality(
      textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Container(
          width: 740,
          height: 670,
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.scoreLow.withValues(alpha: 0.35), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: AppColors.scoreLow.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 0),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark.withValues(alpha: 0.8),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                  border: Border(
                    bottom: BorderSide(color: AppColors.glassBorder.withValues(alpha: 0.5)),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.scoreLow.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.scoreLow.withValues(alpha: 0.4)),
                      ),
                      child: const Icon(Icons.fact_check_rounded, color: AppColors.scoreLow, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'مواضع المراجعة وتدقيق الدقة',
                                style: GoogleFonts.cairo(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.scoreLow,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${currentItems.length} موضع',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'المواضع ذات الدقة الأقل من $currentThresholdPercent% لمراجعة جودة الصوت أو النطق',
                            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'إغلاق',
                    ),
                  ],
                ),
              ),

              // 2. Granularity Level Tabs (Ayah, Breath, Word)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark.withValues(alpha: 0.4),
                  border: Border(bottom: BorderSide(color: AppColors.glassBorder.withValues(alpha: 0.4))),
                ),
                child: Row(
                  children: [
                    _buildGranularityTab(
                      granularity: AlignmentGranularity.ayah,
                      label: '📜 الآيات',
                      count: ayahItems.length,
                      color: AppColors.primaryEmerald,
                      isSelected: _selectedGranularity == AlignmentGranularity.ayah,
                    ),
                    const SizedBox(width: 8),
                    _buildGranularityTab(
                      granularity: AlignmentGranularity.breath,
                      label: '🌬️ الأنفاس والسكتات',
                      count: breathItems.length,
                      color: AppColors.primaryTeal,
                      isSelected: _selectedGranularity == AlignmentGranularity.breath,
                    ),
                    const SizedBox(width: 8),
                    _buildGranularityTab(
                      granularity: AlignmentGranularity.word,
                      label: '🔤 الكلمات',
                      count: wordItems.length,
                      color: const Color(0xFF6366F1),
                      isSelected: _selectedGranularity == AlignmentGranularity.word,
                    ),
                  ],
                ),
              ),

              // 2.5 Dynamic Threshold Selector Bar
              _buildThresholdControlBar(alignProvider, activeColor, currentThreshold),

              // 3. Search Box
              if (currentItems.length > 2)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'البحث في مواضع المراجعة أو نص الآية...',
                      hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.textMuted),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 16, color: AppColors.textMuted),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: AppColors.surfaceDark.withValues(alpha: 0.5),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.glassBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.glassBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.scoreLow),
                      ),
                    ),
                  ),
                ),

              // 4. Body: Review Items List
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              currentItems.isEmpty ? Icons.verified_rounded : Icons.search_off_rounded,
                              size: 48,
                              color: currentItems.isEmpty ? AppColors.scoreHigh : AppColors.textMuted,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              currentItems.isEmpty
                                  ? 'ممتاز! لا توجد مواضع ذات دقة أقل من $currentThresholdPercent% في هذا المستوى'
                                  : 'لا توجد نتائج مطابقة لبحثك',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          return _buildReviewCard(context, item, audioService, alignProvider);
                        },
                      ),
              ),

              // 5. Footer
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark.withValues(alpha: 0.6),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(15)),
                  border: Border(
                    top: BorderSide(color: AppColors.glassBorder.withValues(alpha: 0.5)),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 14, color: AppColors.textMuted),
                    const SizedBox(width: 6),
                    Text(
                      'المعروض: ${filtered.length} من أصل ${currentItems.length} موضع مراجعة (عتبة $currentThresholdPercent%)',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('إغلاق', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGranularityTab({
    required AlignmentGranularity granularity,
    required String label,
    required int count,
    required Color color,
    required bool isSelected,
  }) {
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedGranularity = granularity;
            _searchQuery = '';
            _searchController.clear();
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? color.withValues(alpha: 0.6) : AppColors.glassBorder.withValues(alpha: 0.3),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? color : AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThresholdControlBar(
    AlignmentProvider alignProvider,
    Color activeColor,
    double currentThreshold,
  ) {
    final thresholdPercent = (currentThreshold * 100).round();
    final presets = [80, 85, 90, 95, 98];

    final levelName = switch (_selectedGranularity!) {
      AlignmentGranularity.ayah => 'الآيات',
      AlignmentGranularity.breath => 'الأنفاس والسكتات',
      AlignmentGranularity.word => 'الكلمات',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark.withValues(alpha: 0.28),
        border: Border(bottom: BorderSide(color: AppColors.glassBorder.withValues(alpha: 0.3))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, size: 16, color: activeColor),
              const SizedBox(width: 8),
              Text(
                'عتبة مراجعة $levelName:',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: activeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: activeColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  'أقل من $thresholdPercent%',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: activeColor,
                  ),
                ),
              ),
              const Spacer(),
              // Quick preset chips
              Wrap(
                spacing: 4,
                children: presets.map((p) {
                  final isSelected = thresholdPercent == p;
                  return InkWell(
                    onTap: () {
                      alignProvider.setThresholdForGranularity(_selectedGranularity!, p / 100.0);
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSelected ? activeColor : AppColors.surfaceDark,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSelected ? activeColor : AppColors.glassBorder,
                        ),
                      ),
                      child: Text(
                        '$p%',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Colors.white : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              const Text('50%', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: activeColor,
                    inactiveTrackColor: AppColors.surfaceDark,
                    thumbColor: activeColor,
                    overlayColor: activeColor.withValues(alpha: 0.2),
                    trackHeight: 3.5,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: currentThreshold,
                    min: 0.50,
                    max: 0.99,
                    divisions: 49,
                    onChanged: (val) {
                      alignProvider.setThresholdForGranularity(_selectedGranularity!, val);
                    },
                  ),
                ),
              ),
              const Text('99%', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard(
    BuildContext context,
    ReviewItemDetail item,
    AudioService audioService,
    AlignmentProvider alignProvider,
  ) {
    final isCriticallyLow = item.score < 0.85;
    final scoreColor = isCriticallyLow ? AppColors.dangerRed : AppColors.warningAmber;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceDark.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scoreColor.withValues(alpha: 0.3), width: 1),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header info row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: scoreColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: scoreColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  '#${item.index}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: scoreColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Score Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: scoreColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: scoreColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 13,
                      color: scoreColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${(item.score * 100).toStringAsFixed(0)}% دقة',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: scoreColor,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Context Badge (Ayah / Breath / Word)
              if (item.granularity == AlignmentGranularity.ayah && item.ayahNumber != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primaryEmerald.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'الآية #${item.ayahNumber}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryEmerald,
                    ),
                  ),
                ),

              if (item.granularity == AlignmentGranularity.breath && item.breathIndex != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primaryTeal.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'سكتة #${item.breathIndex}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryTeal,
                    ),
                  ),
                ),

              if (item.granularity == AlignmentGranularity.word && item.ayahNumber != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'آية #${item.ayahNumber}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF818CF8),
                    ),
                  ),
                ),

              const Spacer(),

              // Timing
              Text(
                '${item.timestamp.toStringAsFixed(2)}s - ${item.endTime.toStringAsFixed(2)}s (${item.duration.toStringAsFixed(2)}s)',
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Target text highlight box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scoreColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scoreColor.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, size: 16, color: scoreColor),
                const SizedBox(width: 8),
                Text(
                  'الموضع المراد تدقيقه:',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item.text,
                    style: GoogleFonts.amiri(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: scoreColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (item.ayahText.isNotEmpty && item.ayahText != item.text) ...[
            const SizedBox(height: 8),
            Text(
              item.ayahText,
              style: GoogleFonts.amiri(
                fontSize: 14,
                height: 1.6,
                color: AppColors.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          const SizedBox(height: 10),

          // Action buttons row
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Snippet Play Button
              OutlinedButton.icon(
                onPressed: () {
                  audioService.playSnippet(item.timestamp, item.endTime);
                },
                icon: Icon(Icons.play_arrow_rounded, size: 16, color: scoreColor),
                label: Text('استماع للمقطع', style: TextStyle(fontSize: 11, color: scoreColor)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: scoreColor.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),

              const SizedBox(width: 8),

              // Navigate Button
              ElevatedButton.icon(
                onPressed: () {
                  if (_selectedGranularity != null) {
                    alignProvider.setGranularity(_selectedGranularity!);
                  }
                  Navigator.of(context).pop();
                  widget.onNavigate?.call(item.timestamp);
                },
                icon: const Icon(Icons.near_me_rounded, size: 15, color: Colors.white),
                label: const Text('انتقال للموضع', style: TextStyle(fontSize: 11, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryEmerald,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

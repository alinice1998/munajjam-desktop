import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/alignment_models.dart';
import '../../providers/alignment_provider.dart';
import '../../services/audio_service.dart';

class RepetitionsModal extends StatefulWidget {
  final String localeCode;
  final Function(double timestamp)? onNavigate;

  const RepetitionsModal({
    super.key,
    this.localeCode = 'ar',
    this.onNavigate,
  });

  @override
  State<RepetitionsModal> createState() => _RepetitionsModalState();
}

class _RepetitionsModalState extends State<RepetitionsModal> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

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
    final allRepetitions = alignProvider.detailedRepetitions;

    final filtered = allRepetitions.where((rep) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.trim().toLowerCase();
      return rep.text.toLowerCase().contains(q) ||
          rep.ayahText.toLowerCase().contains(q) ||
          (rep.ayahNumber != null && rep.ayahNumber.toString().contains(q));
    }).toList();

    return Directionality(
      textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Container(
          width: 680,
          height: 600,
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.warningAmber.withValues(alpha: 0.35), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: AppColors.warningAmber.withValues(alpha: 0.08),
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
                        color: AppColors.warningAmber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.warningAmber.withValues(alpha: 0.4)),
                      ),
                      child: const Icon(Icons.repeat_rounded, color: AppColors.warningAmber, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'قائمة التكرارات المكتشفة',
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
                                  color: AppColors.warningAmber,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${allRepetitions.length} موضع',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'انقر على أي موضع للانتقال إليه مباشرة على الموجة الصوتية وقائمة الآيات',
                            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
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

              // 2. Search Box (if more than 3 repetitions)
              if (allRepetitions.length > 3)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'البحث في كلمات التكرار أو نص الآية...',
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
                        borderSide: const BorderSide(color: AppColors.warningAmber),
                      ),
                    ),
                  ),
                ),

              // 3. Body: Repetition Items List
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              allRepetitions.isEmpty ? Icons.check_circle_outline_rounded : Icons.search_off_rounded,
                              size: 48,
                              color: allRepetitions.isEmpty ? AppColors.scoreHigh : AppColors.textMuted,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              allRepetitions.isEmpty
                                  ? 'لا توجد مواضع تكرار مكتشفة في هذه السورة'
                                  : 'لا توجد نتائج مطابقة لبحثك',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
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
                          return _buildRepetitionCard(context, item, audioService, alignProvider);
                        },
                      ),
              ),

              // 4. Footer
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
                      'المعروض: ${filtered.length} من أصل ${allRepetitions.length} موضع تكرار',
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

  Widget _buildRepetitionCard(
    BuildContext context,
    RepetitionDetail item,
    AudioService audioService,
    AlignmentProvider alignProvider,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceDark.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warningAmber.withValues(alpha: 0.25), width: 1),
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
                  color: AppColors.warningAmber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.warningAmber.withValues(alpha: 0.5)),
                ),
                child: Text(
                  '#${item.index}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.warningAmber,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (item.ayahNumber != null)
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
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.isWord ? 'كلمة مكررة' : 'نَفَس مكرر',
                  style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
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

          // Repeated text highlight box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.warningAmber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.warningAmber.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.repeat_one_rounded, size: 16, color: AppColors.warningAmber),
                const SizedBox(width: 8),
                Text(
                  'النص المكرر:',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item.text,
                    style: GoogleFonts.amiri(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.warningAmber,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (item.ayahText.isNotEmpty) ...[
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
                icon: const Icon(Icons.play_arrow_rounded, size: 16, color: AppColors.warningAmber),
                label: const Text('استماع للمقطع', style: TextStyle(fontSize: 11, color: AppColors.warningAmber)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.warningAmber.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),

              const SizedBox(width: 8),

              // Navigate Button
              ElevatedButton.icon(
                onPressed: () {
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

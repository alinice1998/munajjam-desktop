import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/localization/app_locale.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/alignment_provider.dart';

class SurahInfoCard extends StatelessWidget {
  final String localeCode;

  const SurahInfoCard({super.key, this.localeCode = 'ar'});

  @override
  Widget build(BuildContext context) {
    final alignProvider = context.watch<AlignmentProvider>();
    final surah = alignProvider.currentSurah;
    final isRTL = localeCode == 'ar';
    final avgSim = alignProvider.averageSimilarity;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.glassCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
        children: [
          // Surah Number Badge
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primaryEmerald.withOpacity(0.3),
                  AppColors.primaryTeal.withOpacity(0.1),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primaryEmerald.withOpacity(0.4)),
            ),
            alignment: Alignment.center,
            child: Text(
              '${surah.id}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Surah Name (Arabic & English)
          Column(
            crossAxisAlignment: isRTL ? CrossAxisAlignment.start : CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isRTL ? surah.nameArabic : surah.nameTransliteration,
                style: GoogleFonts.amiri(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                isRTL ? surah.nameTransliteration : surah.nameArabic,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),

          const Spacer(),

          // Stats: Ayahs, Breaths, Avg Similarity
          Row(
            mainAxisSize: MainAxisSize.min,
            textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
            children: [
              Text(
                '${alignProvider.segments.length} ${AppLocale.get(context, 'ayahs', localeCode: localeCode)} • ${alignProvider.breathGroups.length} ${AppLocale.get(context, 'breaths', localeCode: localeCode)}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              if (alignProvider.segments.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: avgSim >= 0.95
                        ? AppColors.scoreHigh.withOpacity(0.15)
                        : AppColors.scoreMed.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: avgSim >= 0.95
                          ? AppColors.scoreHigh.withOpacity(0.4)
                          : AppColors.scoreMed.withOpacity(0.4),
                    ),
                  ),
                  child: Text(
                    '${(avgSim * 100).toStringAsFixed(1)}% ${AppLocale.get(context, 'avg', localeCode: localeCode)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: avgSim >= 0.95 ? AppColors.scoreHigh : AppColors.scoreMed,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

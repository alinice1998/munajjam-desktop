import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/localization/app_locale.dart';
import '../../core/theme/app_theme.dart';
import '../../models/surah_model.dart';
import '../../providers/alignment_provider.dart';

class SurahSelectorModal extends StatefulWidget {
  final String localeCode;

  const SurahSelectorModal({super.key, this.localeCode = 'ar'});

  @override
  State<SurahSelectorModal> createState() => _SurahSelectorModalState();
}

class _SurahSelectorModalState extends State<SurahSelectorModal> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final alignProvider = context.watch<AlignmentProvider>();
    final isRTL = widget.localeCode == 'ar';

    final filtered = allSurahsList.where((s) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase().trim();
      return s.id.toString() == q ||
          s.nameArabic.contains(q) ||
          s.nameEnglish.toLowerCase().contains(q) ||
          s.nameTransliteration.toLowerCase().contains(q);
    }).toList();

    return Dialog(
      backgroundColor: AppColors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.glassBorder),
      ),
      child: Container(
        width: 540,
        height: 580,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Title Bar
            Row(
              textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
              children: [
                const Icon(Icons.menu_book_rounded, color: AppColors.primaryEmerald, size: 20),
                const SizedBox(width: 10),
                Text(
                  'اختيار السورة (${allSurahsList.length} سورة)',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Search Bar
            TextField(
              decoration: InputDecoration(
                hintText: AppLocale.get(context, 'searchSurah', localeCode: widget.localeCode),
                prefixIcon: const Icon(Icons.search, size: 18),
                filled: true,
                fillColor: AppColors.surfaceDark,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.glassBorder),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),

            const SizedBox(height: 12),

            // Surahs Grid / List
            Expanded(
              child: ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final surah = filtered[index];
                  final isSelected = surah.id == alignProvider.selectedSurahId;

                  return InkWell(
                    onTap: () {
                      alignProvider.setSurahId(surah.id);
                      Navigator.pop(context);
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primaryEmerald.withOpacity(0.15) : AppColors.surfaceDark.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? AppColors.primaryEmerald : AppColors.glassBorder,
                        ),
                      ),
                      child: Row(
                        textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppColors.primaryEmerald.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${surah.id}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryEmerald,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: isRTL ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                              children: [
                                Text(
                                  surah.nameArabic,
                                  style: GoogleFonts.amiri(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  '${surah.nameTransliteration} • ${surah.ayahCount} آيات • ${surah.isMeccan ? 'مكية' : 'مدنية'}',
                                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            const Icon(Icons.check_circle_rounded, color: AppColors.primaryEmerald, size: 20),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

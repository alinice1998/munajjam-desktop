import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/localization/app_locale.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/alignment_provider.dart';
import 'batch_alignment_modal.dart';
import 'config_modal.dart';
import 'hybrid_alignment_modal.dart';
import 'surah_selector_modal.dart';
import '../../services/audio_service.dart';

class HeaderBar extends StatelessWidget {
  final VoidCallback? onLanguageToggle;
  final String currentLocale;

  const HeaderBar({
    super.key,
    this.onLanguageToggle,
    this.currentLocale = 'ar',
  });

  @override
  Widget build(BuildContext context) {
    final alignProvider = context.watch<AlignmentProvider>();
    final isRTL = currentLocale == 'ar';
    final audioFileName = alignProvider.localAudioPath?.split(RegExp(r'[\\/]')).last;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark.withOpacity(0.85),
        border: const Border(
          bottom: BorderSide(color: AppColors.glassBorder, width: 1),
        ),
      ),
      child: Row(
        textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
        children: [
          // Left: App Logo, Title, & Active Audio Session Badge
          Row(
            mainAxisSize: MainAxisSize.min,
            textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primaryEmerald.withOpacity(0.25),
                      AppColors.primaryTeal.withOpacity(0.15),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primaryEmerald.withOpacity(0.4)),
                ),
                child: const Icon(Icons.waves_rounded, color: AppColors.primaryEmerald, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                AppLocale.get(context, 'appTitle', localeCode: currentLocale),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  letterSpacing: 0.2,
                ),
              ),

              // Active Audio File Session Indicator
              if (audioFileName != null) ...[
                const SizedBox(width: 12),
                Tooltip(
                  message: alignProvider.localAudioPath ?? '',
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.primaryEmerald.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.primaryEmerald.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.audiotrack_rounded, color: AppColors.primaryEmerald, size: 14),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(
                            audioFileName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryEmerald,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),

          const Spacer(),

          // Right: Action Buttons & Controls (Scrollable to prevent any window overflow)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
              children: [
                // 1. AI Hybrid Alignment Button (Primary CTA)
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF059669), Color(0xFF0D9488), Color(0xFF10B981)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryEmerald.withOpacity(0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => HybridAlignmentModal(localeCode: currentLocale),
                      );
                    },
                    icon: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 16),
                    label: Text(
                      AppLocale.get(context, 'aiAlignment', localeCode: currentLocale),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // 1.5 Batch / Khatmah Alignment Button
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0284C7), Color(0xFF0EA5E9), Color(0xFF06B6D4)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accentCyan.withOpacity(0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => BatchAlignmentModal(localeCode: currentLocale),
                      );
                    },
                    icon: const Icon(Icons.playlist_play_rounded, color: Colors.white, size: 18),
                    label: Text(
                      AppLocale.get(context, 'batchAlignment', localeCode: currentLocale),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // 2. Import JSON Alignment Button
                OutlinedButton.icon(
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      dialogTitle: 'اختر ملف التزمين (JSON)',
                      type: FileType.custom,
                      allowedExtensions: ['json'],
                    );

                    if (result != null && result.files.single.path != null) {
                      final filePath = result.files.single.path!;
                      final file = File(filePath);
                      final jsonString = await file.readAsString();

                      String? audioPath = alignProvider.localAudioPath;
                      if (audioPath == null || !File(audioPath).existsSync()) {
                        final audioResult = await FilePicker.platform.pickFiles(
                          dialogTitle: 'اختر الملف الصوتي للتلاوة المقابل لملف التزمين (اختياري)',
                          type: FileType.custom,
                          allowedExtensions: ['mp3', 'wav', 'm4a', 'aac', 'ogg'],
                        );
                        if (audioResult != null && audioResult.files.single.path != null) {
                          audioPath = audioResult.files.single.path!;
                        }
                      }

                      final success = await alignProvider.importAlignmentFromJson(
                        jsonString: jsonString,
                        audioPath: audioPath,
                      );

                      if (audioPath != null && File(audioPath).existsSync()) {
                        await AudioService().loadAudioSource(audioPath, isLocal: true);
                      }

                      if (context.mounted) {
                        if (success) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('تم استيراد التزمين بنجاح من: ${file.path.split(Platform.pathSeparator).last}'),
                              backgroundColor: AppColors.primaryEmerald,
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تعذر فك ملف التزمين. يرجى التأكد من صحة صيغة الـ JSON'),
                              backgroundColor: AppColors.dangerRed,
                            ),
                          );
                        }
                      }
                    }
                  },
                  icon: const Icon(Icons.file_open_rounded, color: AppColors.primaryEmerald, size: 16),
                  label: Text(
                    AppLocale.get(context, 'importJson', localeCode: currentLocale),
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.glassBorder),
                    backgroundColor: AppColors.glassCard,
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),

                // 3. Export JSON Button (Visible when alignment segments are ready)
                if (alignProvider.segments.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final jsonString = alignProvider.generateExportJson();
                      final audioBase = alignProvider.localAudioPath != null
                          ? alignProvider.localAudioPath!.split(RegExp(r'[\\/]')).last.replaceAll(RegExp(r'\.[^.]+$'), '')
                          : 'surah_${alignProvider.selectedSurahId.toString().padLeft(3, '0')}';
                      final defaultFileName = '${audioBase}_alignment.json';

                      final outputFile = await FilePicker.platform.saveFile(
                        dialogTitle: 'تصدير ملف التوقيتات JSON',
                        fileName: defaultFileName,
                        type: FileType.custom,
                        allowedExtensions: ['json'],
                      );
                      if (outputFile != null) {
                        await File(outputFile).writeAsString(jsonString);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('تم حفظ ملف التوقيتات بنجاح في: $outputFile'),
                              backgroundColor: AppColors.primaryEmerald,
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.file_download_rounded, color: AppColors.primaryTeal, size: 16),
                    label: Text(
                      AppLocale.get(context, 'exportJson', localeCode: currentLocale),
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.glassBorder),
                      backgroundColor: AppColors.glassCard,
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],

                const SizedBox(width: 8),

                // 4. Surah Selector Button
                OutlinedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => SurahSelectorModal(localeCode: currentLocale),
                    );
                  },
                  icon: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primaryEmerald.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${alignProvider.selectedSurahId}',
                      style: const TextStyle(
                        color: AppColors.primaryEmerald,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  label: Text(
                    isRTL ? alignProvider.currentSurah.nameArabic : alignProvider.currentSurah.nameTransliteration,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.glassBorder),
                    backgroundColor: AppColors.glassCard,
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),

                const SizedBox(width: 8),

                // 5. Options / Settings Button (Unified with Icon + Label)
                OutlinedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => ConfigModal(localeCode: currentLocale),
                    );
                  },
                  icon: const Icon(Icons.tune_rounded, color: AppColors.textSecondary, size: 16),
                  label: Text(
                    AppLocale.get(context, 'settings', localeCode: currentLocale),
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 12.5),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.glassBorder),
                    backgroundColor: AppColors.glassCard,
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),

                // 6. Language Toggle Button (Unified with Icon + Label)
                if (onLanguageToggle != null) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: onLanguageToggle,
                    icon: const Icon(Icons.translate_rounded, color: AppColors.primaryTeal, size: 15),
                    label: Text(
                      currentLocale == 'ar' ? 'English' : 'عربي',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.glassBorder),
                      backgroundColor: AppColors.glassCard,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

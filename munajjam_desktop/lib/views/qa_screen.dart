import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/localization/app_locale.dart';
import '../core/theme/app_theme.dart';
import '../providers/alignment_provider.dart';
import 'widgets/ayah_list_view.dart';
import 'widgets/config_modal.dart';
import 'widgets/custom_title_bar.dart';
import 'widgets/header_bar.dart';
import 'widgets/hybrid_alignment_modal.dart';
import 'widgets/karaoke_player.dart';
import 'widgets/surah_info_card.dart';
import 'widgets/waveform_editor.dart';

class QAScreen extends StatefulWidget {
  final VoidCallback? onLanguageToggle;
  final String currentLocale;

  const QAScreen({
    super.key,
    this.onLanguageToggle,
    this.currentLocale = 'ar',
  });

  @override
  State<QAScreen> createState() => _QAScreenState();
}

class _QAScreenState extends State<QAScreen> {
  @override
  Widget build(BuildContext context) {
    final alignProvider = context.watch<AlignmentProvider>();
    final isRTL = widget.currentLocale == 'ar';
    final hasSegments = alignProvider.segments.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Directionality(
        textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
        child: Column(
          children: [
            // 0. Window Custom Title Bar
            CustomTitleBar(localeCode: widget.currentLocale),

            // 1. Top Header Bar
            HeaderBar(
              onLanguageToggle: widget.onLanguageToggle,
              currentLocale: widget.currentLocale,
            ),

            // 2. Main Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1400),
                    child: !hasSegments
                        ? _buildWelcomeState(context)
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Surah Info Header Card
                              SurahInfoCard(localeCode: widget.currentLocale),
                              const SizedBox(height: 16),

                              // Interactive Multi-Level Waveform Editor
                              WaveformEditor(localeCode: widget.currentLocale),
                              const SizedBox(height: 20),

                              // 2-Column Section: Karaoke Quran Player & Ayah List
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  if (constraints.maxWidth > 900) {
                                    return Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: KaraokePlayer(localeCode: widget.currentLocale),
                                        ),
                                        const SizedBox(width: 20),
                                        Expanded(
                                          child: AyahListView(localeCode: widget.currentLocale),
                                        ),
                                      ],
                                    );
                                  } else {
                                    return Column(
                                      children: [
                                        KaraokePlayer(localeCode: widget.currentLocale),
                                        const SizedBox(height: 16),
                                        AyahListView(localeCode: widget.currentLocale),
                                      ],
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeState(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 60),
      padding: const EdgeInsets.all(40),
      constraints: const BoxConstraints(maxWidth: 600),
      decoration: BoxDecoration(
        color: AppColors.glassCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.glassBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primaryEmerald.withOpacity(0.2),
                  AppColors.primaryTeal.withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.primaryEmerald.withOpacity(0.3)),
            ),
            child: const Icon(Icons.auto_awesome, color: AppColors.primaryEmerald, size: 36),
          ),
          const SizedBox(height: 20),
          Text(
            AppLocale.get(context, 'welcomeTitle', localeCode: widget.currentLocale),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            AppLocale.get(context, 'welcomeDesc', localeCode: widget.currentLocale),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => HybridAlignmentModal(localeCode: widget.currentLocale),
                  );
                },
                icon: const Icon(Icons.cloud_upload_outlined, color: Colors.white, size: 18),
                label: Text(
                  AppLocale.get(context, 'uploadAndAlign', localeCode: widget.currentLocale),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryEmerald,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => ConfigModal(localeCode: widget.currentLocale),
                  );
                },
                icon: const Icon(Icons.tune_rounded, color: AppColors.textSecondary, size: 18),
                label: Text(
                  AppLocale.get(context, 'options', localeCode: widget.currentLocale),
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.glassBorder),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

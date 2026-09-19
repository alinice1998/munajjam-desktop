import 'package:flutter/material.dart';
import '../../core/server_manager.dart';
import '../../core/theme/app_theme.dart';

class ConfigModal extends StatelessWidget {
  final String localeCode;

  const ConfigModal({super.key, this.localeCode = 'ar'});

  @override
  Widget build(BuildContext context) {
    final serverManager = ServerManager();
    final isRTL = localeCode == 'ar';

    return Dialog(
      backgroundColor: AppColors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.glassBorder),
      ),
      child: Container(
        width: 540,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title
            Row(
              textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
              children: [
                const Icon(Icons.settings_suggest_rounded, color: AppColors.primaryEmerald, size: 22),
                const SizedBox(width: 10),
                const Text(
                  'إعدادات النظام والعتاد',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Server & Hardware Status
            ValueListenableBuilder<HardwareStatus?>(
              valueListenable: serverManager.hardwareStatusNotifier,
              builder: (context, hw, _) {
                return Column(
                  children: [
                    _buildStatusTile(
                      title: 'خادم التزمين المحلي',
                      subtitle: serverManager.serverUrl,
                      status: serverManager.isOnline ? 'نشط ومتصل' : 'غير متصل',
                      isOk: serverManager.isOnline,
                      icon: Icons.dns_rounded,
                    ),
                    const SizedBox(height: 10),
                    _buildStatusTile(
                      title: 'مسرع العتاد والذكاء الاصطناعي',
                      subtitle: hw?.providerName ?? 'جاري الفحص...',
                      status: (hw?.hasGpu ?? false) ? 'GPU Acceleration' : 'CPU Mode',
                      isOk: hw != null,
                      icon: Icons.memory_rounded,
                    ),
                    const SizedBox(height: 10),
                    _buildStatusTile(
                      title: 'نموذج تقطيع النَّفَس recitation-segmenter-v2 (المرحلة 1)',
                      subtitle: 'Wav2Vec2-BERT ONNX DirectML (تقطيع الأنفاس على GPU)',
                      status: (hw?.segmenterLoaded ?? true) ? 'محمل وجاهز' : 'غير موجود',
                      isOk: hw?.segmenterLoaded ?? true,
                      icon: Icons.air_rounded,
                    ),
                    const SizedBox(height: 10),
                    _buildStatusTile(
                      title: 'نموذج Zipformer v3 (المرحلة 2)',
                      subtitle: 'zipformer_p_arabic_v3.onnx (كشف البسملة والاستعاذة)',
                      status: (hw?.zipformerLoaded ?? true) ? 'محمل وجاهز' : 'غير موجود',
                      isOk: hw?.zipformerLoaded ?? true,
                      icon: Icons.multitrack_audio_rounded,
                    ),
                    const SizedBox(height: 10),
                    _buildStatusTile(
                      title: 'نموذج Wav2Vec2 XLSR-53 (المرحلة 3)',
                      subtitle: 'wav2vec2-large-xlsr-53-arabic (المحاذاة القسرية على GPU)',
                      status: (hw?.wav2vec2Loaded ?? true) ? 'محمل وجاهز' : 'غير موجود',
                      isOk: hw?.wav2vec2Loaded ?? true,
                      icon: Icons.graphic_eq_rounded,
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 20),

            // Info note
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: AppColors.primaryTeal, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'يتم تشغيل خادم التزمين العصبي تلقائياً في الخلفية بدون نوافذ أوامر سوداء، ويتحول تلقائياً إلى المعالج CPU عند عدم وجود كرت شاشة منفصل.',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryEmerald,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('تم', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusTile({
    required String title,
    required String subtitle,
    required String status,
    required bool isOk,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: isOk ? AppColors.primaryEmerald : AppColors.warningAmber, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isOk ? AppColors.scoreHigh.withOpacity(0.15) : AppColors.warningAmber.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isOk ? AppColors.scoreHigh.withOpacity(0.3) : AppColors.warningAmber.withOpacity(0.3),
              ),
            ),
            child: Text(
              status,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isOk ? AppColors.scoreHigh : AppColors.warningAmber,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

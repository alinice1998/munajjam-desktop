import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/alignment_models.dart';
import '../../providers/alignment_provider.dart';
import '../../services/audio_service.dart';

String reviewLevelLabel(AlignmentGranularity level) => switch (level) {
  AlignmentGranularity.ayah => 'الآيات',
  AlignmentGranularity.breath => 'الأنفاس',
  AlignmentGranularity.word => 'الكلمات',
};

class ConfidenceReviewDialog extends StatefulWidget {
  final AlignmentGranularity initialLevel;
  const ConfidenceReviewDialog({super.key, required this.initialLevel});
  @override
  State<ConfidenceReviewDialog> createState() => _ConfidenceReviewDialogState();
}

class _ConfidenceReviewDialogState extends State<ConfidenceReviewDialog> {
  late AlignmentGranularity _level = widget.initialLevel;
  @override
  Widget build(BuildContext context) {
    context.select(
      (AlignmentProvider p) => (
        p.alignmentRevision,
        p.reviewThreshold(AlignmentGranularity.ayah),
        p.reviewThreshold(AlignmentGranularity.breath),
        p.reviewThreshold(AlignmentGranularity.word),
      ),
    );
    final provider = context.read<AlignmentProvider>();
    final items = provider.reviewItems(_level);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: AppColors.surfaceCard,
        title: const Text('مراجعة الموثوقية'),
        content: SizedBox(
          width: 560,
          height: 440,
          child: Column(
            children: [
              const Text(
                'تحتاج المراجعة عندما تكون الموثوقية أقل من الحد المحدد لكل مستوى.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              for (final level in AlignmentGranularity.values)
                Row(
                  children: [
                    SizedBox(
                      width: 60,
                      child: Text(
                        reviewLevelLabel(level),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        key: ValueKey('review_threshold_${level.name}'),
                        value: provider.reviewThreshold(level) * 100,
                        min: 0,
                        max: 100,
                        divisions: 100,
                        label:
                            '${(provider.reviewThreshold(level) * 100).round()}%',
                        onChanged: (value) =>
                            provider.setReviewThreshold(level, value / 100),
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${(provider.reviewThreshold(level) * 100).round()}%',
                      ),
                    ),
                  ],
                ),
              Row(
                children: [
                  Expanded(
                    child: DropdownButton<AlignmentGranularity>(
                      key: const ValueKey('review_level'),
                      value: _level,
                      isExpanded: true,
                      dropdownColor: AppColors.surfaceCard,
                      items: [
                        for (final level in AlignmentGranularity.values)
                          DropdownMenuItem(
                            value: level,
                            child: Text(reviewLevelLabel(level)),
                          ),
                      ],
                      onChanged: (level) {
                        if (level != null) setState(() => _level = level);
                      },
                    ),
                  ),
                  Text(
                    ' ${items.length} موضع',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
              Expanded(
                child: items.isEmpty
                    ? const Center(
                        child: Text('لا توجد مواضع تحتاج للمراجعة بهذا الحد'),
                      )
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, _) =>
                            const Divider(color: AppColors.glassBorder),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final score = item.reliability.isFinite
                              ? '${(item.reliability * 100).toStringAsFixed(1)}%'
                              : 'غير متاحة';
                          return ListTile(
                            key: ValueKey(
                              'review_item_${item.level.name}_$index',
                            ),
                            leading: const Icon(
                              Icons.error_outline,
                              color: AppColors.scoreLow,
                            ),
                            title: Text(
                              item.text.isEmpty
                                  ? 'موضع ${index + 1}'
                                  : item.text,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              'الموثوقية $score • ${item.start.toStringAsFixed(2)}s — ${item.end.toStringAsFixed(2)}s${item.isError ? ' • خطأ معلّم' : ''}',
                            ),
                            onTap: () {
                              provider.selectReviewItem(item);
                              AudioService().seek(item.start);
                              Navigator.of(context).pop();
                            },
                          );
                        },
                      ),
              ),
              const Text(
                'الموثوقية غير المتاحة لا تُعامل كنسبة منخفضة. الأخطاء المعلّمة تبقى للمراجعة.',
                style: TextStyle(fontSize: 10, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
}

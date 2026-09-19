import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/localization/app_locale.dart';
import '../../core/theme/app_theme.dart';
import '../../models/batch_alignment_item.dart';
import '../../models/surah_model.dart';
import '../../providers/alignment_provider.dart';
import '../../services/audio_service.dart';
import '../../services/batch_alignment_service.dart';

class BatchAlignmentModal extends StatefulWidget {
  final String localeCode;

  const BatchAlignmentModal({super.key, this.localeCode = 'ar'});

  @override
  State<BatchAlignmentModal> createState() => _BatchAlignmentModalState();
}

class _BatchAlignmentModalState extends State<BatchAlignmentModal> {
  final BatchAlignmentService _batchService = BatchAlignmentService();

  @override
  void initState() {
    super.initState();
    _batchService.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _batchService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _pickFolder() async {
    final folderPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'اختر مجلد الختمة أو مجلد التلاوات',
    );
    if (folderPath != null && mounted) {
      await _batchService.loadFolder(folderPath);
    }
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'اختر ملفات السور الصوتية',
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac'],
    );
    if (result != null && result.paths.isNotEmpty && mounted) {
      final validPaths = result.paths.whereType<String>().toList();
      _batchService.loadFiles(validPaths);
    }
  }

  Future<void> _previewItemInQa(BatchAlignmentItem item) async {
    if (item.outputJsonPath == null || !File(item.outputJsonPath!).existsSync()) return;

    try {
      final jsonString = await File(item.outputJsonPath!).readAsString();
      if (!mounted) return;
      final alignProvider = context.read<AlignmentProvider>();

      final success = await alignProvider.importAlignmentFromJson(
        jsonString: jsonString,
        audioPath: item.audioPath,
        overrideSurahId: item.surahId,
      );

      if (File(item.audioPath).existsSync()) {
        await AudioService().loadAudioSource(item.audioPath, isLocal: true);
      }

      if (mounted) {
        if (success) {
          Navigator.of(context).pop(); // إغلاق نافذة الدفعة للعودة إلى المحرر
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم فتح تزمين ${item.surahName} في المحرر بنجاح'),
              backgroundColor: AppColors.primaryEmerald,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل تحميل السورة في المحرر: $e'),
            backgroundColor: AppColors.dangerRed,
          ),
        );
      }
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    final hours = d.inHours;
    if (hours > 0) {
      return '$hours ساعة و $minutes دقيقة';
    }
    return '$minutes دقيقة و $seconds ثانية';
  }

  @override
  Widget build(BuildContext context) {
    final isRTL = widget.localeCode == 'ar';
    final hasItems = _batchService.items.isNotEmpty;
    final isRunning = _batchService.isRunning;
    final isPaused = _batchService.isPaused;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
      child: Container(
        width: 1060,
        height: 720,
        decoration: BoxDecoration(
          color: AppColors.surfaceDark.withOpacity(0.96),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.glassBorder, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.7),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
            children: [
              // 1. Modal Top Bar
              _buildHeader(context, isRTL),

              // 2. Action Toolbar & Settings
              _buildControlPanel(isRTL),

              const Divider(color: AppColors.glassBorder, height: 1),

              // 3. Queue List / Table
              Expanded(
                child: hasItems
                    ? _buildQueueTable(isRTL)
                    : _buildEmptyState(context, isRTL),
              ),

              const Divider(color: AppColors.glassBorder, height: 1),

              // 4. Bottom Overall Progress & Action Footer
              _buildFooter(context, isRTL, isRunning, isPaused, hasItems),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isRTL) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard.withOpacity(0.9),
        border: const Border(bottom: BorderSide(color: AppColors.glassBorder)),
      ),
      child: Row(
        textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primaryEmerald, AppColors.primaryTeal],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.playlist_play_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: isRTL ? CrossAxisAlignment.start : CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocale.get(context, 'batchModalTitle', localeCode: widget.localeCode),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'تزمين مجلد تلاوات كامل سورة بسورة وحفظ ملفات الـ JSON تلقائياً في الخلفية مع منع نوم الحاسوب',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 20),
            tooltip: AppLocale.get(context, 'close', localeCode: widget.localeCode),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel(bool isRTL) {
    final isRunning = _batchService.isRunning;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: AppColors.surfaceCard.withOpacity(0.4),
      child: Column(
        children: [
          // Row 1: Source Pickers & Path badge
          Row(
            textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
            children: [
              ElevatedButton.icon(
                onPressed: isRunning ? null : _pickFolder,
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: Text(AppLocale.get(context, 'chooseFolder', localeCode: widget.localeCode)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryEmerald.withOpacity(0.2),
                  foregroundColor: AppColors.primaryEmerald,
                  elevation: 0,
                  side: const BorderSide(color: AppColors.primaryEmerald, width: 0.8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: isRunning ? null : _pickFiles,
                icon: const Icon(Icons.audio_file_rounded, size: 18),
                label: Text(AppLocale.get(context, 'chooseFiles', localeCode: widget.localeCode)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.glassBorder),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(width: 14),
              if (_batchService.currentFolderPath != null) ...[
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceDark.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.folder_rounded, size: 14, color: AppColors.textMuted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _batchService.currentFolderPath!,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primaryEmerald.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${_batchService.items.length} ${AppLocale.get(context, 'filesLoaded', localeCode: widget.localeCode)}',
                            style: const TextStyle(fontSize: 10.5, color: AppColors.primaryEmerald, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else
                const Spacer(),
            ],
          ),

          const SizedBox(height: 10),

          // Row 2: Settings (Riwaya, Engine, Options)
          Row(
            textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
            children: [
              // Riwaya
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _batchService.riwaya,
                    isDense: true,
                    dropdownColor: AppColors.surfaceCard,
                    style: GoogleFonts.tajawal(
                      fontSize: 12,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'hafsh',
                        child: Text(
                          'رواية حفص عن عاصم',
                          style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textPrimary),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'warsh',
                        child: Text(
                          'رواية ورش عن نافع',
                          style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textPrimary),
                        ),
                      ),
                    ],
                    onChanged: isRunning ? null : (val) => val != null ? _batchService.setRiwaya(val) : null,
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // Engine
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _batchService.method,
                    isDense: true,
                    dropdownColor: AppColors.surfaceCard,
                    style: GoogleFonts.tajawal(
                      fontSize: 12,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'hybrid',
                        child: Text(
                          'المحرك الهجين فائق الدقة (مُنجّم v2) - موصى به',
                          style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textPrimary),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'hybrid_fuzzy',
                        child: Text(
                          'المحرك التجريبي الذكي (الضبابي Fuzzy)',
                          style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textPrimary),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'zipformer',
                        child: Text(
                          'محرك Zipformer الكلاسيكي (فائق السرعة)',
                          style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textPrimary),
                        ),
                      ),
                    ],
                    onChanged: isRunning ? null : (val) => val != null ? _batchService.setMethod(val) : null,
                  ),
                ),
              ),

              const Spacer(),

              // Checkbox: Skip Existing
              _buildOptionChip(
                label: AppLocale.get(context, 'skipExisting', localeCode: widget.localeCode),
                value: _batchService.skipExisting,
                enabled: !isRunning,
                onChanged: (v) => _batchService.setSkipExisting(v),
              ),

              const SizedBox(width: 8),

              // Checkbox: Save in alignments/ subfolder
              _buildOptionChip(
                label: 'مجلد alignments/',
                value: _batchService.saveInSubfolder,
                enabled: !isRunning,
                onChanged: (v) => _batchService.setSaveInSubfolder(v),
              ),

              const SizedBox(width: 8),

              // Checkbox: Auto Shutdown
              _buildOptionChip(
                label: 'إطفاء الحاسوب بعد الانتهاء',
                icon: Icons.power_settings_new_rounded,
                value: _batchService.shutdownWhenDone,
                enabled: !isRunning,
                activeColor: AppColors.warningAmber,
                onChanged: (v) => _batchService.setShutdownWhenDone(v),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOptionChip({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
    IconData? icon,
    Color activeColor = AppColors.primaryEmerald,
  }) {
    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: value ? activeColor.withOpacity(0.12) : AppColors.surfaceDark.withOpacity(0.5),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: value ? activeColor.withOpacity(0.6) : AppColors.glassBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: value ? activeColor : AppColors.textSecondary),
              const SizedBox(width: 4),
            ],
            Icon(
              value ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              size: 14,
              color: value ? activeColor : AppColors.textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: value ? AppColors.textPrimary : AppColors.textSecondary,
                fontWeight: value ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isRTL) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surfaceCard.withOpacity(0.6),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: const Icon(Icons.folder_zip_rounded, size: 48, color: AppColors.primaryEmerald),
          ),
          const SizedBox(height: 16),
          const Text(
            'لم يتم اختيار ملفات أو مجلد ختمة بعد',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          const Text(
            'اضغط على "اختيار مجلد الختمة" لقراءة كافة السور تلقائياً ومطابقتها بأسمائها وأرقامها',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _pickFolder,
            icon: const Icon(Icons.folder_open_rounded, size: 18),
            label: const Text('اختيار مجلد الختمة الآن'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryEmerald,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueTable(bool isRTL) {
    final items = _batchService.items;
    final isRunning = _batchService.isRunning;

    return Column(
      children: [
        // Table Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          color: AppColors.surfaceDark.withOpacity(0.8),
          child: Row(
            textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
            children: [
              SizedBox(
                width: 32,
                child: Checkbox(
                  value: _batchService.selectedCount == items.length,
                  tristate: _batchService.selectedCount > 0 && _batchService.selectedCount < items.length,
                  onChanged: isRunning ? null : (v) => _batchService.toggleSelectAll(v ?? false),
                ),
              ),
              const SizedBox(width: 8),
              const SizedBox(
                width: 40,
                child: Text('#', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ),
              const Expanded(
                flex: 3,
                child: Text('الملف الصوتي', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ),
              const Expanded(
                flex: 3,
                child: Text('السورة المطابقة (يمكن تغييرها)', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ),
              const Expanded(
                flex: 3,
                child: Text('حالة التزمين والتقدم', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ),
              const SizedBox(
                width: 110,
                child: Text('إجراء', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ),
            ],
          ),
        ),

        const Divider(color: AppColors.glassBorder, height: 1),

        // Table Rows
        Expanded(
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(color: AppColors.glassBorder, height: 1),
            itemBuilder: (context, index) {
              final item = items[index];
              return _buildItemRow(item, index, isRTL, isRunning);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildItemRow(BatchAlignmentItem item, int index, bool isRTL, bool isRunning) {
    final isProcessing = item.status == BatchItemStatus.processing;

    return Container(
      color: isProcessing ? AppColors.primaryEmerald.withOpacity(0.08) : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
        children: [
          // 1. Checkbox
          SizedBox(
            width: 32,
            child: Checkbox(
              value: item.isSelected,
              onChanged: isRunning ? null : (v) => _batchService.toggleItemSelection(index, v ?? true),
            ),
          ),

          const SizedBox(width: 8),

          // 2. Index
          SizedBox(
            width: 40,
            child: Text(
              '${index + 1}',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),

          // 3. Audio File Name
          Expanded(
            flex: 3,
            child: Row(
              children: [
                const Icon(Icons.audiotrack_rounded, size: 14, color: AppColors.primaryTeal),
                const SizedBox(width: 6),
                Expanded(
                  child: Tooltip(
                    message: item.audioPath,
                    child: Text(
                      item.fileName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 4. Detected Surah (with dropdown to modify if wrong)
          Expanded(
            flex: 3,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryEmerald.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.primaryEmerald.withOpacity(0.3)),
                  ),
                  child: Text(
                    '${item.surahId}',
                    style: const TextStyle(fontSize: 10.5, color: AppColors.primaryEmerald, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceDark.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: item.surahId,
                      isDense: true,
                      icon: const Padding(
                        padding: EdgeInsetsDirectional.only(start: 4),
                        child: Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: AppColors.primaryEmerald),
                      ),
                      dropdownColor: AppColors.surfaceCard,
                      style: GoogleFonts.tajawal(
                        fontSize: 12,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                      items: allSurahsList.map((s) {
                        return DropdownMenuItem<int>(
                          value: s.id,
                          child: Text(
                            '${s.id}. سورة ${s.nameArabic}',
                            style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textPrimary),
                          ),
                        );
                      }).toList(),
                      onChanged: isRunning ? null : (newId) {
                        if (newId != null) _batchService.updateItemSurah(index, newId);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 5. Status & Progress
          Expanded(
            flex: 3,
            child: _buildStatusWidget(item),
          ),

          // 6. Action Button (Open in QA if done)
          SizedBox(
            width: 110,
            child: item.isDone && item.outputJsonPath != null
                ? TextButton.icon(
                    onPressed: () => _previewItemInQa(item),
                    icon: const Icon(Icons.open_in_new_rounded, size: 13, color: AppColors.primaryEmerald),
                    label: const Text(
                      'معاينة بالمحرر',
                      style: TextStyle(fontSize: 11, color: AppColors.primaryEmerald),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusWidget(BatchAlignmentItem item) {
    switch (item.status) {
      case BatchItemStatus.pending:
        return const Row(
          children: [
            Icon(Icons.hourglass_empty_rounded, size: 13, color: AppColors.textMuted),
            SizedBox(width: 6),
            Text('قيد الانتظار', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          ],
        );

      case BatchItemStatus.processing:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryEmerald),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${item.progress}% - ${item.progressMessage}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: AppColors.primaryEmerald, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: item.progress / 100.0,
                minHeight: 3,
                backgroundColor: AppColors.glassBorder,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryEmerald),
              ),
            ),
          ],
        );

      case BatchItemStatus.completed:
        final elapsedStr = item.elapsed != null ? ' (${item.elapsed!.inSeconds}ث)' : '';
        return Row(
          children: [
            const Icon(Icons.check_circle_rounded, size: 14, color: AppColors.scoreHigh),
            const SizedBox(width: 6),
            Text(
              'اكتمل التزمين$elapsedStr',
              style: const TextStyle(fontSize: 11.5, color: AppColors.scoreHigh, fontWeight: FontWeight.w600),
            ),
          ],
        );

      case BatchItemStatus.skipped:
        return const Row(
          children: [
            Icon(Icons.skip_next_rounded, size: 14, color: AppColors.accentCyan),
            SizedBox(width: 6),
            Text(
              'تم التخطي (موجود مسبقاً)',
              style: TextStyle(fontSize: 11.5, color: AppColors.accentCyan),
            ),
          ],
        );

      case BatchItemStatus.error:
        return Tooltip(
          message: item.errorMessage ?? '',
          child: Row(
            children: [
              const Icon(Icons.error_outline_rounded, size: 14, color: AppColors.dangerRed),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  item.errorMessage ?? 'حدث خطأ',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.dangerRed),
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _buildFooter(BuildContext context, bool isRTL, bool isRunning, bool isPaused, bool hasItems) {
    final overallProgress = _batchService.overallProgress;
    final totalSelected = _batchService.selectedCount;
    final completed = _batchService.completedCount + _batchService.skippedCount;
    final percent = (overallProgress * 100).toInt();
    final eta = _batchService.estimatedRemainingTime;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard.withOpacity(0.95),
        border: const Border(top: BorderSide(color: AppColors.glassBorder)),
      ),
      child: Column(
        children: [
          // Progress metrics strip
          Row(
            textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
            children: [
              // Count Badge
              Text(
                'التقدم الإجمالي: $completed من $totalSelected سورة ($percent%)',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),

              const SizedBox(width: 16),

              // Elapsed Time
              if (isRunning || _batchService.totalElapsed > Duration.zero) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer_outlined, size: 14, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Text(
                      'المنقضي: ${_formatDuration(_batchService.totalElapsed)}',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
              ],

              // Estimated Remaining Time
              if (eta != null) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.hourglass_top_rounded, size: 14, color: AppColors.primaryTeal),
                    const SizedBox(width: 4),
                    Text(
                      'الوقت التقديري المتبقي: ${_formatDuration(eta)}',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.primaryTeal, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],

              const Spacer(),

              // Sleep Prevention Indicator
              if (isRunning) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryEmerald.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.primaryEmerald.withOpacity(0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shield_rounded, size: 12, color: AppColors.primaryEmerald),
                      SizedBox(width: 5),
                      Text(
                        'منع سكون الحاسوب مفعّل',
                        style: TextStyle(fontSize: 10.5, color: AppColors.primaryEmerald, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 10),

          // Overall Linear Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: overallProgress,
              minHeight: 6,
              backgroundColor: AppColors.surfaceDark,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryEmerald),
            ),
          ),

          const SizedBox(height: 12),

          // Buttons Row
          Row(
            textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
            children: [
              // Start / Resume Button
              if (!isRunning) ...[
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF059669), Color(0xFF0D9488), Color(0xFF10B981)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryEmerald.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: hasItems ? () => _batchService.startBatch() : null,
                    icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                    label: Text(
                      AppLocale.get(context, 'startBatch', localeCode: widget.localeCode),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ] else if (isPaused) ...[
                ElevatedButton.icon(
                  onPressed: () => _batchService.resumeBatch(),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(AppLocale.get(context, 'resumeBatch', localeCode: widget.localeCode)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryEmerald,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ] else ...[
                ElevatedButton.icon(
                  onPressed: () => _batchService.pauseBatch(),
                  icon: const Icon(Icons.pause_rounded, size: 18),
                  label: Text(AppLocale.get(context, 'pauseBatch', localeCode: widget.localeCode)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.warningAmber,
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],

              const SizedBox(width: 10),

              // Cancel Button (if running)
              if (isRunning) ...[
                OutlinedButton.icon(
                  onPressed: () => _batchService.cancelBatch(),
                  icon: const Icon(Icons.stop_rounded, size: 18, color: AppColors.dangerRed),
                  label: Text(
                    AppLocale.get(context, 'cancelBatch', localeCode: widget.localeCode),
                    style: const TextStyle(color: AppColors.dangerRed),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.dangerRed, width: 0.8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],

              const Spacer(),

              // Close / Done Button
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.glassBorder),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(
                  AppLocale.get(context, 'close', localeCode: widget.localeCode),
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

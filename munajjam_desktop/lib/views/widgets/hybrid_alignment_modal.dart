import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/localization/app_locale.dart';
import '../../core/server_manager.dart';
import '../../core/theme/app_theme.dart';
import '../../models/batch_alignment_item.dart';
import '../../models/surah_model.dart';
import '../../providers/alignment_provider.dart';
import '../../services/aligner_api_service.dart';
import '../../services/audio_service.dart';

class HybridAlignmentModal extends StatefulWidget {
  final String localeCode;

  const HybridAlignmentModal({super.key, this.localeCode = 'ar'});

  @override
  State<HybridAlignmentModal> createState() => _HybridAlignmentModalState();
}

class _HybridAlignmentModalState extends State<HybridAlignmentModal> {
  File? _selectedAudioFile;
  File? _selectedJsonFile;
  int _selectedSurahId = 1;
  String? _autoDetectedSurahName;
  String _selectedRiwaya = 'hafsh';
  String _selectedMethod = 'hybrid'; // hybrid or zipformer
  double _chunkDuration = 2.0; // Customizable streaming chunk duration
  int _minSilenceMs = 200; // 25ms - 1000ms
  int _minSpeechMs = 750; // 200ms - 2000ms
  String _repetitionAttach = 'next'; // 'next' or 'prev'

  bool _isAligning = false;
  int _progress = 0;
  String _progressMessage = '';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final alignProvider = context.read<AlignmentProvider>();
    _selectedSurahId = alignProvider.selectedSurahId;
    _selectedRiwaya = alignProvider.riwaya;

    if (alignProvider.localAudioPath != null && File(alignProvider.localAudioPath!).existsSync()) {
      _selectedAudioFile = File(alignProvider.localAudioPath!);
      final (detectedId, detectedName) = SurahFileNameDetector.detectSurah(alignProvider.localAudioPath!);
      _selectedSurahId = detectedId;
      _autoDetectedSurahName = detectedName;
    }
  }

  Future<void> _pickAudioFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'm4a', 'aac', 'ogg'],
    );

    if (result != null && result.files.single.path != null) {
      final filePath = result.files.single.path!;
      final (detectedId, detectedName) = SurahFileNameDetector.detectSurah(filePath);
      setState(() {
        _selectedAudioFile = File(filePath);
        _selectedSurahId = detectedId;
        _autoDetectedSurahName = detectedName;
        _errorMessage = null;
      });
    }
  }

  Future<void> _pickJsonFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result != null && result.files.single.path != null) {
      final filePath = result.files.single.path!;
      final (detectedId, detectedName) = SurahFileNameDetector.detectSurah(filePath);
      setState(() {
        _selectedJsonFile = File(filePath);
        _selectedSurahId = detectedId;
        _autoDetectedSurahName = detectedName;
        _errorMessage = null;
      });
    }
  }

  Future<void> _startAlignment() async {
    if (_selectedMethod == 'json_file') {
      if (_selectedJsonFile == null) {
        setState(() {
          _errorMessage = 'يرجى اختيار ملف التزمين (JSON) أولاً';
        });
        return;
      }
      final alignProvider = context.read<AlignmentProvider>();
      try {
        final jsonString = await _selectedJsonFile!.readAsString();
        final success = await alignProvider.importAlignmentFromJson(
          jsonString: jsonString,
          audioPath: _selectedAudioFile?.path,
          overrideSurahId: _selectedSurahId,
        );

        if (_selectedAudioFile != null) {
          await AudioService().loadAudioSource(_selectedAudioFile!.path, isLocal: true);
        }

        if (mounted) {
          if (success) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('تم استيراد التزمين بنجاح من: ${_selectedJsonFile!.path.split(Platform.pathSeparator).last}'),
                backgroundColor: AppColors.primaryEmerald,
              ),
            );
          } else {
            setState(() {
              _errorMessage = 'تعذر فك ملف التزمين. يرجى التأكد من صحة صيغة الـ JSON';
            });
          }
        }
      } catch (e) {
        setState(() {
          _errorMessage = 'خطأ أثناء قراءة ملف JSON: $e';
        });
      }
      return;
    }

    if (_selectedAudioFile == null) {
      setState(() {
        _errorMessage = 'يرجى اختيار ملف صوتي للتلاوة أولاً';
      });
      return;
    }

    final serverManager = ServerManager();
    if (!serverManager.isOnline) {
      setState(() {
        _errorMessage = 'الخادم غير متصل. يرجى الانتظار حتى يتم تشغيل الخادم المحلي.';
      });
      return;
    }

    setState(() {
      _isAligning = true;
      _progress = 5;
      _progressMessage = 'جاري رفع الملف وبدء المعالجة العصبية...';
      _errorMessage = null;
    });

    try {
      final apiService = AlignerApiService();
      final jobId = await apiService.startAlignmentJob(
        surahId: _selectedSurahId,
        audioFile: _selectedAudioFile!,
        method: _selectedMethod,
        riwaya: _selectedRiwaya,
        chunkDuration: _chunkDuration,
        minSilenceMs: _minSilenceMs,
        minSpeechMs: _minSpeechMs,
        repetitionAttach: _repetitionAttach,
      );

      // Poll progress until success
      Timer.periodic(const Duration(milliseconds: 700), (timer) async {
        try {
          final status = await apiService.checkJobStatus(jobId);

          if (!mounted) {
            timer.cancel();
            return;
          }

          setState(() {
            _progress = status.progress;
            _progressMessage = status.message;
          });

          if (status.isSuccess) {
            timer.cancel();
            setState(() {
              _progress = 100;
              _isAligning = false;
            });

            final alignProvider = context.read<AlignmentProvider>();
            alignProvider.applyAlignmentResult(
              ayahs: status.data ?? [],
              breaths: status.breathGroups ?? [],
              surahId: _selectedSurahId,
              audioPath: _selectedAudioFile!.path,
            );

            await AudioService().loadAudioSource(_selectedAudioFile!.path, isLocal: true);

            if (mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('اكتمل التزمين الهجين بنجاح!'),
                  backgroundColor: AppColors.primaryEmerald,
                ),
              );
            }
          } else if (status.isError) {
            timer.cancel();
            setState(() {
              _isAligning = false;
              _errorMessage = status.message.isNotEmpty ? status.message : 'حدث خطأ أثناء المعالجة العصبية';
            });
          }
        } catch (e) {
          timer.cancel();
          if (mounted) {
            setState(() {
              _isAligning = false;
              _errorMessage = 'خطأ في الاتصال بالخادم: $e';
            });
          }
        }
      });
    } catch (e) {
      setState(() {
        _isAligning = false;
        _errorMessage = 'فشل بدء التزمين: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRTL = widget.localeCode == 'ar';
    final serverManager = ServerManager();

    return Dialog(
      backgroundColor: AppColors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.glassBorder),
      ),
      child: Container(
        width: 660,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.90,
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryEmerald.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.auto_awesome, color: AppColors.primaryEmerald, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocale.get(context, 'modalTitle', localeCode: widget.localeCode),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Server Status Tag
            ValueListenableBuilder<bool>(
              valueListenable: serverManager.isOnlineNotifier,
              builder: (context, online, _) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: online ? AppColors.scoreHigh.withOpacity(0.1) : AppColors.scoreLow.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: online ? AppColors.scoreHigh.withOpacity(0.3) : AppColors.scoreLow.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
                    children: [
                      Icon(
                        online ? Icons.check_circle_outline : Icons.error_outline,
                        color: online ? AppColors.scoreHigh : AppColors.scoreLow,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        online ? 'الخادم المحلي متصل وجاهز للمعالجة العصبية' : 'الخادم غير متصل',
                        style: TextStyle(
                          fontSize: 12,
                          color: online ? AppColors.scoreHigh : AppColors.scoreLow,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 12),

            // Scrollable Settings Body
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Audio File Picker
                    InkWell(
                      onTap: _isAligning ? null : _pickAudioFile,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceDark,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _selectedAudioFile != null ? AppColors.primaryEmerald : AppColors.glassBorder,
                            style: BorderStyle.solid,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              _selectedAudioFile != null ? Icons.audio_file_rounded : Icons.cloud_upload_outlined,
                              color: _selectedAudioFile != null ? AppColors.primaryEmerald : AppColors.textMuted,
                              size: 34,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _selectedAudioFile != null
                                  ? _selectedAudioFile!.path.split(Platform.pathSeparator).last
                                  : AppLocale.get(context, 'dragOrBrowse', localeCode: widget.localeCode),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: _selectedAudioFile != null ? FontWeight.bold : FontWeight.normal,
                                color: _selectedAudioFile != null ? Colors.white : AppColors.textSecondary,
                              ),
                            ),
                            if (_autoDetectedSurahName != null) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryEmerald.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: AppColors.primaryEmerald.withValues(alpha: 0.35),
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.auto_awesome, size: 12, color: AppColors.primaryEmerald),
                                    const SizedBox(width: 5),
                                    Text(
                                      'تم التعرف على السورة تلقائياً: $_autoDetectedSurahName (رقم $_selectedSurahId)',
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primaryEmerald,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // 2. Surah & Riwaya Selectors
                    Row(
                      children: [
                        // Surah Dropdown
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text('السورة', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                  if (_autoDetectedSurahName != null) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryEmerald.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: AppColors.primaryEmerald.withValues(alpha: 0.3), width: 0.8),
                                      ),
                                      child: const Text(
                                        'تم التعرف تلقائياً',
                                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: AppColors.primaryEmerald),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceDark,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColors.glassBorder),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<int>(
                                    value: _selectedSurahId,
                                    isExpanded: true,
                                    dropdownColor: AppColors.surfaceCard,
                                    style: GoogleFonts.tajawal(
                                      fontSize: 13,
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    items: allSurahsList.map((s) {
                                      return DropdownMenuItem<int>(
                                        value: s.id,
                                        child: Text(
                                          '${s.id}. ${s.nameArabic}',
                                          style: GoogleFonts.tajawal(fontSize: 13, color: AppColors.textPrimary),
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: _isAligning ? null : (val) {
                                      if (val != null) {
                                        setState(() {
                                          _selectedSurahId = val;
                                          _autoDetectedSurahName = null;
                                        });
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Riwaya Dropdown
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('الرواية', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceDark,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColors.glassBorder),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _selectedRiwaya,
                                    isExpanded: true,
                                    dropdownColor: AppColors.surfaceCard,
                                    style: GoogleFonts.tajawal(
                                      fontSize: 13,
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    items: [
                                      DropdownMenuItem(
                                        value: 'hafsh',
                                        child: Text(
                                          'حفص عن عاصم',
                                          style: GoogleFonts.tajawal(fontSize: 13, color: AppColors.textPrimary),
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 'warsh',
                                        child: Text(
                                          'ورش عن نافع',
                                          style: GoogleFonts.tajawal(fontSize: 13, color: AppColors.textPrimary),
                                        ),
                                      ),
                                    ],
                                    onChanged: _isAligning ? null : (val) {
                                      if (val != null) setState(() => _selectedRiwaya = val);
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // 3. Engine Method Choice (Hybrid v2 vs Hybrid Classic v1 vs Zipformer Only)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('محرك التزمين والذكاء الاصطناعي', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        const SizedBox(height: 8),
                        _buildEngineOption(
                          id: 'hybrid',
                          title: 'المحرك الهجين فائق الدقة (مُنجّم v2)',
                          subtitle: 'دمج ثلاثي: تقطيع الأنفاس العصبي recitation-segmenter-v2 + Zipformer v3 + التدقيق المجهري Wav2Vec2',
                          icon: Icons.auto_awesome_rounded,
                          badgeText: 'الافتراضي (موصى به)',
                          badgeColor: AppColors.primaryEmerald,
                        ),
                        const SizedBox(height: 6),
                        _buildEngineOption(
                          id: 'hybrid_fuzzy',
                          title: 'المحرك التجريبي الذكي (الضبابي Fuzzy)',
                          subtitle: 'تقطيع الأنفاس العصبي + تفريغ حر ومطابقة تقريبية مرنة (للتعامل الفائق مع تلاوات التحقيق الصعبة والتكرار)',
                          icon: Icons.psychology_alt_rounded,
                          badgeText: 'تجريبي',
                          badgeColor: AppColors.repetitionPurple,
                        ),
                        const SizedBox(height: 6),
                        _buildEngineOption(
                          id: 'zipformer',
                          title: 'محرك Zipformer الكلاسيكي (فائق السرعة)',
                          subtitle: 'تزمين مباشر وخفيف بنموذج Zipformer v3 فقط، يعمل بكفاءة على أي معالج CPU دون الحاجة لكرت شاشة',
                          icon: Icons.bolt_rounded,
                          badgeText: 'خفيف CPU',
                          badgeColor: AppColors.accentCyan,
                        ),
                        const SizedBox(height: 6),
                        _buildEngineOption(
                          id: 'json_file',
                          title: 'استيراد من ملف JSON جاهز',
                          subtitle: 'تحميل تزمين تم استخراجه مسبقاً ومعاينته مباشرة في المحرر دون تشغيل نماذج الذكاء الاصطناعي',
                          icon: Icons.file_present_rounded,
                          badgeText: 'تزمين سابق',
                          badgeColor: AppColors.accentGold,
                        ),
                      ],
                    ),

                    // JSON File Picker box when json_file is chosen
                    if (_selectedMethod == 'json_file') ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceDark,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.primaryEmerald.withOpacity(0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('ملف التوقيتات الجاهز (JSON):', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: _pickJsonFile,
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceCard,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.glassBorder),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.description_outlined, color: AppColors.primaryEmerald, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _selectedJsonFile != null
                                            ? _selectedJsonFile!.path.split(Platform.pathSeparator).last
                                            : 'اضغط لاختيار ملف JSON (مثل tmpdve8r7_6.json)...',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: _selectedJsonFile != null ? AppColors.textPrimary : AppColors.textSecondary,
                                          fontWeight: _selectedJsonFile != null ? FontWeight.bold : FontWeight.normal,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const Icon(Icons.folder_open_rounded, color: AppColors.textSecondary, size: 18),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 14),

                    // 4. Recitation Segmentation Settings (Min Silence & Min Speech)
                    if (_selectedMethod == 'hybrid' || _selectedMethod == 'hybrid_fuzzy') ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceDark,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.air_rounded, size: 16, color: AppColors.primaryEmerald),
                                    SizedBox(width: 6),
                                    Text(
                                      'إعدادات تقطيع الأنفاس والوقف (recitation-segmenter-v2)',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                    ),
                                  ],
                                ),
                                InkWell(
                                  onTap: _isAligning
                                      ? null
                                      : () {
                                          setState(() {
                                            _minSilenceMs = 200;
                                            _minSpeechMs = 750;
                                          });
                                        },
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Row(
                                      children: [
                                        Icon(Icons.replay_rounded, size: 12, color: AppColors.textMuted),
                                        SizedBox(width: 4),
                                        Text('استعادة الافتراضي', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // A. Min Silence Duration
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'أدنى مدة للسكوت / الوقف (Min Silence Duration)',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryEmerald.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: AppColors.primaryEmerald.withValues(alpha: 0.3)),
                                  ),
                                  child: Text(
                                    '$_minSilenceMs ms',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryEmerald),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'القيم الأقل = تقسيم أكثر. أنقص القيمة للقراء ذوي الوقفات السريعة.',
                              style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                            ),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: AppColors.primaryEmerald,
                                inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                                thumbColor: AppColors.primaryEmerald,
                                overlayColor: AppColors.primaryEmerald.withValues(alpha: 0.2),
                                trackHeight: 3,
                              ),
                              child: Slider(
                                value: _minSilenceMs.toDouble(),
                                min: 25.0,
                                max: 1000.0,
                                divisions: 39,
                                label: '$_minSilenceMs ms',
                                onChanged: _isAligning ? null : (val) => setState(() => _minSilenceMs = val.round()),
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildSilenceChip('50ms', 50),
                                _buildSilenceChip('100ms', 100),
                                _buildSilenceChip('150ms', 150),
                                _buildSilenceChip('200ms (افتراضي)', 200),
                                _buildSilenceChip('300ms', 300),
                                _buildSilenceChip('500ms', 500),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // B. Min Speech Duration
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'أدنى مدة للنَّفَس / الكلام (Min Speech Duration)',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryTeal.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: AppColors.primaryTeal.withValues(alpha: 0.3)),
                                  ),
                                  child: Text(
                                    '$_minSpeechMs ms',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryTeal),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'تُستبعد المقاطع الأقصر لفلترة أصوات الشهيق والتشويش ومنع التحديدات الوهمية.',
                              style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                            ),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: AppColors.primaryTeal,
                                inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                                thumbColor: AppColors.primaryTeal,
                                overlayColor: AppColors.primaryTeal.withValues(alpha: 0.2),
                                trackHeight: 3,
                              ),
                              child: Slider(
                                value: _minSpeechMs.toDouble(),
                                min: 200.0,
                                max: 2000.0,
                                divisions: 36,
                                label: '$_minSpeechMs ms',
                                onChanged: _isAligning ? null : (val) => setState(() => _minSpeechMs = val.round()),
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildSpeechChip('400ms', 400),
                                _buildSpeechChip('500ms', 500),
                                _buildSpeechChip('750ms (افتراضي)', 750),
                                _buildSpeechChip('1000ms', 1000),
                                _buildSpeechChip('1500ms', 1500),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // 5. Customizable Chunk Duration Setting
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceDark,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.glassBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.tune_rounded, size: 16, color: AppColors.primaryTeal),
                                  SizedBox(width: 6),
                                  Text(
                                    'طول نافذة المعالجة العصبية (Chunk Duration)',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryEmerald.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppColors.primaryEmerald.withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  '${_chunkDuration.toStringAsFixed(1)} ثانية',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryEmerald),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: AppColors.primaryEmerald,
                              inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                              thumbColor: AppColors.primaryEmerald,
                              overlayColor: AppColors.primaryEmerald.withValues(alpha: 0.2),
                              trackHeight: 3,
                            ),
                            child: Slider(
                              value: _chunkDuration,
                              min: 0.5,
                              max: 10.0,
                              divisions: 19,
                              label: '${_chunkDuration.toStringAsFixed(1)}s',
                              onChanged: _isAligning ? null : (val) => setState(() => _chunkDuration = val),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildPresetChip('0.5s', 0.5),
                              _buildPresetChip('1.0s', 1.0),
                              _buildPresetChip('2.0s (افتراضي)', 2.0),
                              _buildPresetChip('5.0s', 5.0),
                              _buildPresetChip('10.0s', 10.0),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // 6. Repetition Placement Settings
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceDark,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.glassBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.repeat_rounded, size: 16, color: AppColors.repetitionPurple),
                              SizedBox(width: 6),
                              Text(
                                'توزيع تكرار الوقف والابتداء بين مقاطع الأنفاس',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: _isAligning ? null : () => setState(() => _repetitionAttach = 'next'),
                                  borderRadius: BorderRadius.circular(8),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: _repetitionAttach == 'next'
                                          ? AppColors.repetitionPurple.withValues(alpha: 0.18)
                                          : Colors.white.withValues(alpha: 0.04),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: _repetitionAttach == 'next'
                                            ? AppColors.repetitionPurple
                                            : Colors.transparent,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              _repetitionAttach == 'next'
                                                  ? Icons.radio_button_checked_rounded
                                                  : Icons.radio_button_unchecked_rounded,
                                              size: 14,
                                              color: _repetitionAttach == 'next'
                                                  ? AppColors.repetitionPurple
                                                  : AppColors.textMuted,
                                            ),
                                            const SizedBox(width: 6),
                                            const Flexible(
                                              child: Text(
                                                'ضم الإعادة للتالي (موصى به)',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.textPrimary,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        const Text(
                                          'التكرار الأول في السابق، والثاني في التالي كاملاً دون قطش',
                                          style: TextStyle(fontSize: 9.5, color: AppColors.textMuted),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: InkWell(
                                  onTap: _isAligning ? null : () => setState(() => _repetitionAttach = 'prev'),
                                  borderRadius: BorderRadius.circular(8),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: _repetitionAttach == 'prev'
                                          ? AppColors.repetitionPurple.withValues(alpha: 0.18)
                                          : Colors.white.withValues(alpha: 0.04),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: _repetitionAttach == 'prev'
                                            ? AppColors.repetitionPurple
                                            : Colors.transparent,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              _repetitionAttach == 'prev'
                                                  ? Icons.radio_button_checked_rounded
                                                  : Icons.radio_button_unchecked_rounded,
                                              size: 14,
                                              color: _repetitionAttach == 'prev'
                                                  ? AppColors.repetitionPurple
                                                  : AppColors.textMuted,
                                            ),
                                            const SizedBox(width: 6),
                                            const Flexible(
                                              child: Text(
                                                'ضم الإعادة للسابق',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.textPrimary,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        const Text(
                                          'المقطع السابق يمتد للإعادة، والتالي يبدأ بعدها في وادي الطاقة',
                                          style: TextStyle(fontSize: 9.5, color: AppColors.textMuted),
                                        ),
                                      ],
                                    ),
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

            const SizedBox(height: 14),

            // Progress Bar or Error Display
            if (_isAligning) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_progressMessage, style: const TextStyle(fontSize: 12, color: AppColors.primaryEmerald)),
                      Text('$_progress%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryEmerald)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: _progress / 100.0,
                      backgroundColor: Colors.white.withOpacity(0.1),
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryEmerald),
                      minHeight: 8,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.dangerRed.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.dangerRed.withOpacity(0.3)),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(fontSize: 12, color: AppColors.dangerRed),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Action Button
            ElevatedButton.icon(
              onPressed: _isAligning ? null : _startAlignment,
              icon: _isAligning
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.play_arrow_rounded, color: Colors.white),
              label: Text(
                _isAligning ? 'جاري المعالجة العصبية...' : AppLocale.get(context, 'startAlignment', localeCode: widget.localeCode),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryEmerald,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEngineOption({
    required String id,
    required String title,
    required String subtitle,
    required IconData icon,
    String? badgeText,
    Color? badgeColor,
  }) {
    final isSelected = _selectedMethod == id;
    final effectiveBadgeColor = badgeColor ?? AppColors.primaryEmerald;

    return InkWell(
      onTap: _isAligning ? null : () => setState(() => _selectedMethod = id),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryEmerald.withValues(alpha: 0.12)
              : AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryEmerald
                : AppColors.glassBorder,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primaryEmerald.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: isSelected ? AppColors.primaryEmerald : AppColors.textMuted,
                size: 19,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                      if (badgeText != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: effectiveBadgeColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: effectiveBadgeColor.withValues(alpha: 0.4),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            badgeText,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: effectiveBadgeColor,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected ? AppColors.textSecondary : AppColors.textMuted,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isSelected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 18,
              color: isSelected ? AppColors.primaryEmerald : AppColors.textMuted.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetChip(String label, double val) {
    final isSelected = (_chunkDuration - val).abs() < 0.05;
    return InkWell(
      onTap: _isAligning ? null : () => setState(() => _chunkDuration = val),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryEmerald.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? AppColors.primaryEmerald : AppColors.glassBorder,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isSelected ? AppColors.primaryEmerald : AppColors.textMuted,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildSilenceChip(String label, int val) {
    final isSelected = _minSilenceMs == val;
    return InkWell(
      onTap: _isAligning ? null : () => setState(() => _minSilenceMs = val),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryEmerald.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? AppColors.primaryEmerald : AppColors.glassBorder,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isSelected ? AppColors.primaryEmerald : AppColors.textMuted,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildSpeechChip(String label, int val) {
    final isSelected = _minSpeechMs == val;
    return InkWell(
      onTap: _isAligning ? null : () => setState(() => _minSpeechMs = val),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryTeal.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? AppColors.primaryTeal : AppColors.glassBorder,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isSelected ? AppColors.primaryTeal : AppColors.textMuted,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

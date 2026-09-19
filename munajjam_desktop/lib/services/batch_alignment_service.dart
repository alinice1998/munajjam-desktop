import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/batch_alignment_item.dart';
import '../models/surah_model.dart';
import 'aligner_api_service.dart';
import 'quran_data_service.dart';
import 'windows_power_service.dart';

class BatchAlignmentService extends ChangeNotifier {
  static final BatchAlignmentService _instance = BatchAlignmentService._internal();
  factory BatchAlignmentService() => _instance;
  BatchAlignmentService._internal();

  List<BatchAlignmentItem> _items = [];
  String? _currentFolderPath;
  bool _isRunning = false;
  bool _isPaused = false;
  int _currentIndex = -1;

  String _riwaya = 'hafsh';
  String _method = 'hybrid';
  bool _skipExisting = true;
  bool _saveInSubfolder = true;
  bool _shutdownWhenDone = false;

  DateTime? _batchStartTime;
  DateTime? _currentItemStartTime;
  Timer? _tickerTimer;
  Duration _totalElapsed = Duration.zero;

  // Getters
  List<BatchAlignmentItem> get items => _items;
  String? get currentFolderPath => _currentFolderPath;
  bool get isRunning => _isRunning;
  bool get isPaused => _isPaused;
  int get currentIndex => _currentIndex;
  String get riwaya => _riwaya;
  String get method => _method;
  bool get skipExisting => _skipExisting;
  bool get saveInSubfolder => _saveInSubfolder;
  bool get shutdownWhenDone => _shutdownWhenDone;
  Duration get totalElapsed => _totalElapsed;

  int get selectedCount => _items.where((i) => i.isSelected).length;
  int get completedCount => _items.where((i) => i.status == BatchItemStatus.completed).length;
  int get skippedCount => _items.where((i) => i.status == BatchItemStatus.skipped).length;
  int get errorCount => _items.where((i) => i.status == BatchItemStatus.error).length;

  double get overallProgress {
    if (_items.isEmpty) return 0.0;
    final selected = _items.where((i) => i.isSelected).toList();
    if (selected.isEmpty) return 0.0;

    double sum = 0.0;
    for (final item in selected) {
      if (item.status == BatchItemStatus.completed || item.status == BatchItemStatus.skipped) {
        sum += 100.0;
      } else if (item.status == BatchItemStatus.processing) {
        sum += item.progress;
      }
    }
    return (sum / (selected.length * 100.0)).clamp(0.0, 1.0);
  }

  /// الوقت التقديري المتبقي بناءً على متوسط وقت معالجة السور السابقة
  Duration? get estimatedRemainingTime {
    if (!_isRunning) return null;
    final completedItems = _items.where((i) => i.status == BatchItemStatus.completed && i.elapsed != null).toList();
    if (completedItems.isEmpty) return null;

    final totalCompletedMs = completedItems.fold<int>(0, (sum, i) => sum + i.elapsed!.inMilliseconds);
    final avgMsPerSurah = totalCompletedMs / completedItems.length;

    final remainingItemsCount = _items.where((i) => i.isSelected && i.status == BatchItemStatus.pending).length;
    return Duration(milliseconds: (avgMsPerSurah * remainingItemsCount).round());
  }

  void setRiwaya(String val) {
    _riwaya = val;
    notifyListeners();
  }

  void setMethod(String val) {
    _method = val;
    notifyListeners();
  }

  void setSkipExisting(bool val) {
    _skipExisting = val;
    notifyListeners();
  }

  void setSaveInSubfolder(bool val) {
    _saveInSubfolder = val;
    notifyListeners();
  }

  void setShutdownWhenDone(bool val) {
    _shutdownWhenDone = val;
    notifyListeners();
  }

  void toggleSelectAll(bool select) {
    for (final item in _items) {
      item.isSelected = select;
    }
    notifyListeners();
  }

  void toggleItemSelection(int index, bool select) {
    if (index >= 0 && index < _items.length) {
      _items[index].isSelected = select;
      notifyListeners();
    }
  }

  void updateItemSurah(int index, int newSurahId) {
    if (index >= 0 && index < _items.length) {
      final surah = getSurahById(newSurahId);
      _items[index].surahId = surah.id;
      _items[index].surahName = surah.nameArabic;
      notifyListeners();
    }
  }

  /// تحميل كل الملفات الصوتية الموجودة في مجلد الختمة
  Future<void> loadFolder(String folderPath) async {
    _currentFolderPath = folderPath;
    final dir = Directory(folderPath);
    if (!dir.existsSync()) return;

    final audioExts = {'.mp3', '.wav', '.m4a', '.aac', '.ogg', '.flac'};
    final files = dir
        .listSync(recursive: false)
        .whereType<File>()
        .where((f) => audioExts.contains(p.extension(f.path).toLowerCase()))
        .toList();

    _loadFilesInternal(files.map((f) => f.path).toList());
  }

  /// تحميل قائمة ملفات محددة يدوياً
  void loadFiles(List<String> filePaths) {
    if (filePaths.isNotEmpty) {
      _currentFolderPath = p.dirname(filePaths.first);
    }
    _loadFilesInternal(filePaths);
  }

  void _loadFilesInternal(List<String> filePaths) {
    _items = [];
    for (final filePath in filePaths) {
      final (surahId, surahName) = SurahFileNameDetector.detectSurah(filePath);
      _items.add(BatchAlignmentItem(
        audioPath: filePath,
        fileName: p.basename(filePath),
        surahId: surahId,
        surahName: surahName,
      ));
    }

    // فرز الملفات حسب رقم السورة ثم اسم الملف
    _items.sort((a, b) {
      final cmp = a.surahId.compareTo(b.surahId);
      return cmp != 0 ? cmp : a.fileName.compareTo(b.fileName);
    });

    _currentIndex = -1;
    notifyListeners();
  }

  void clear() {
    if (_isRunning) return;
    _items.clear();
    _currentFolderPath = null;
    _currentIndex = -1;
    notifyListeners();
  }

  /// المسار المعتمد لحفظ ملف الـ JSON لسورة معينة
  String getTargetJsonPath(BatchAlignmentItem item) {
    final audioDir = p.dirname(item.audioPath);
    final targetDir = _saveInSubfolder ? p.join(audioDir, 'alignments') : audioDir;
    final surahPad = item.surahId.toString().padLeft(3, '0');
    final safeName = item.surahName.replaceAll(' ', '_');
    return p.join(targetDir, '${surahPad}_$safeName.json');
  }

  /// بدء تنفيذ التزمين الجماعي
  Future<void> startBatch() async {
    if (_isRunning || _items.isEmpty) return;

    _isRunning = true;
    _isPaused = false;
    _batchStartTime = DateTime.now();

    // منع ويندوز من النوم أثناء الليل
    WindowsPowerService.preventSleep();

    _tickerTimer?.cancel();
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_batchStartTime != null) {
        _totalElapsed = DateTime.now().difference(_batchStartTime!);
        notifyListeners();
      }
    });

    notifyListeners();
    await _processQueue();
  }

  void pauseBatch() {
    if (!_isRunning || _isPaused) return;
    _isPaused = true;
    notifyListeners();
  }

  void resumeBatch() {
    if (!_isRunning || !_isPaused) return;
    _isPaused = false;
    notifyListeners();
    _processQueue();
  }

  void cancelBatch() {
    _isRunning = false;
    _isPaused = false;
    _tickerTimer?.cancel();
    WindowsPowerService.allowSleep();
    notifyListeners();
  }

  /// المعالجة المتسلسلة لجميع السور في الطابور
  Future<void> _processQueue() async {
    while (_isRunning && !_isPaused) {
      // البحث عن أول عنصر محدد وما زال معلقاً
      final nextIdx = _items.indexWhere((i) => i.isSelected && i.status == BatchItemStatus.pending);
      if (nextIdx == -1) {
        // اكتملت كافة السور في الطابور!
        await _finishBatch();
        return;
      }

      _currentIndex = nextIdx;
      final currentItem = _items[nextIdx];
      final targetJsonPath = getTargetJsonPath(currentItem);

      // 1. فحص إمكانية التخطي إذا كان الملف موجوداً مسبقاً
      if (_skipExisting && File(targetJsonPath).existsSync()) {
        currentItem.status = BatchItemStatus.skipped;
        currentItem.progress = 100;
        currentItem.progressMessage = 'تم التخطي (الملف موجود مسبقاً)';
        currentItem.outputJsonPath = targetJsonPath;
        notifyListeners();
        continue;
      }

      // 2. بدء تزمين السورة الحالية
      currentItem.status = BatchItemStatus.processing;
      currentItem.progress = 5;
      currentItem.progressMessage = 'جاري إرسال الملف للخادم العصبي...';
      _currentItemStartTime = DateTime.now();
      notifyListeners();

      try {
        await _alignSingleItem(currentItem, targetJsonPath);
        currentItem.status = BatchItemStatus.completed;
        currentItem.progress = 100;
        currentItem.progressMessage = 'اكتمل بنجاح';
        currentItem.outputJsonPath = targetJsonPath;
        if (_currentItemStartTime != null) {
          currentItem.elapsed = DateTime.now().difference(_currentItemStartTime!);
        }
      } catch (e) {
        currentItem.status = BatchItemStatus.error;
        currentItem.errorMessage = e.toString();
        currentItem.progressMessage = 'فشل: $e';
      }

      notifyListeners();
    }
  }

  /// تزمين سورة واحدة عبر AlignerApiService وحفظ الناتج
  Future<void> _alignSingleItem(BatchAlignmentItem item, String targetJsonPath) async {
    final apiService = AlignerApiService();
    final audioFile = File(item.audioPath);

    final jobId = await apiService.startAlignmentJob(
      surahId: item.surahId,
      audioFile: audioFile,
      method: _method,
      riwaya: _riwaya,
    );

    // متابعة تقدم المهمة حتى الاكتمال
    final completer = Completer<AlignmentJobStatus>();
    Timer.periodic(const Duration(milliseconds: 750), (timer) async {
      if (!_isRunning) {
        timer.cancel();
        if (!completer.isCompleted) completer.completeError('تم إلغاء المهمة');
        return;
      }

      try {
        final status = await apiService.checkJobStatus(jobId);
        item.progress = status.progress;
        item.progressMessage = status.message;
        notifyListeners();

        if (status.isSuccess) {
          timer.cancel();
          if (!completer.isCompleted) completer.complete(status);
        } else if (status.isError) {
          timer.cancel();
          if (!completer.isCompleted) completer.completeError(status.message);
        }
      } catch (e) {
        timer.cancel();
        if (!completer.isCompleted) completer.completeError('خطأ في الاتصال: $e');
      }
    });

    final finalStatus = await completer.future;

    // دمج نصوص الآيات وحفظ ملف الـ JSON
    final quranText = await QuranDataService().getSurahAyahs(item.surahId, riwaya: _riwaya);
    final mergedAyahs = QuranDataService().mergeQuranTextIntoSegments(finalStatus.data ?? [], quranText);
    final breaths = finalStatus.breathGroups ?? [];

    // إنشاء المجلد إذا لم يكن موجوداً
    final targetDir = Directory(p.dirname(targetJsonPath));
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }

    final exportData = {
      'surah_id': item.surahId,
      'surah_name': item.surahName,
      'audio_file': item.fileName,
      'riwaya': _riwaya,
      'method': _method,
      'total_ayahs': mergedAyahs.length,
      'total_breath_groups': breaths.length,
      'ayahs': mergedAyahs.map((s) => s.toJson()).toList(),
      'breath_groups': breaths.map((b) => b.toJson()).toList(),
    };

    final jsonContent = const JsonEncoder.withIndent('  ').convert(exportData);
    await File(targetJsonPath).writeAsString(jsonContent, encoding: utf8);
  }

  /// إنهاء الدفعة وحفظ الفهرس الشامل
  Future<void> _finishBatch() async {
    _isRunning = false;
    _isPaused = false;
    _tickerTimer?.cancel();
    WindowsPowerService.allowSleep();

    // حفظ تقرير الفهرس الشامل khatmah_manifest.json
    if (_currentFolderPath != null && Directory(_currentFolderPath!).existsSync()) {
      final manifestDir = _saveInSubfolder
          ? p.join(_currentFolderPath!, 'alignments')
          : _currentFolderPath!;
      if (!Directory(manifestDir).existsSync()) {
        Directory(manifestDir).createSync(recursive: true);
      }

      final manifestPath = p.join(manifestDir, 'khatmah_manifest.json');
      final manifestData = {
        'title': 'Munajjam Khatmah Alignment Manifest',
        'generated_at': DateTime.now().toIso8601String(),
        'riwaya': _riwaya,
        'method': _method,
        'total_files': _items.length,
        'completed': completedCount,
        'skipped': skippedCount,
        'errors': errorCount,
        'total_elapsed_seconds': _totalElapsed.inSeconds,
        'items': _items.map((i) => {
              'surah_id': i.surahId,
              'surah_name': i.surahName,
              'file_name': i.fileName,
              'status': i.status.name,
              'json_file': i.outputJsonPath != null ? p.basename(i.outputJsonPath!) : null,
              'elapsed_seconds': i.elapsed?.inSeconds,
              'error': i.errorMessage,
            }).toList(),
      };

      try {
        await File(manifestPath).writeAsString(
          const JsonEncoder.withIndent('  ').convert(manifestData),
          encoding: utf8,
        );
      } catch (_) {}
    }

    notifyListeners();

    // إيقاف تشغيل الكمبيوتر إذا تم تحديد هذا الخيار
    if (_shutdownWhenDone) {
      await WindowsPowerService.shutdownComputer(delaySeconds: 60);
    }
  }
}

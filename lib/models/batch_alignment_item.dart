import 'package:path/path.dart' as p;
import 'surah_model.dart';

enum BatchItemStatus {
  pending,    // بانتظار بدء التزمين
  processing, // جاري التزمين العصبي
  completed,  // تم التزمين بنجاح
  skipped,    // تم التخطي لوجود ملف JSON مسبقاً
  error,      // حدث خطأ أثناء التزمين
}

class BatchAlignmentItem {
  final String audioPath;
  final String fileName;
  int surahId;
  String surahName;
  BatchItemStatus status;
  int progress;
  String progressMessage;
  String? outputJsonPath;
  String? errorMessage;
  Duration? elapsed;
  bool isSelected;

  BatchAlignmentItem({
    required this.audioPath,
    required this.fileName,
    required this.surahId,
    required this.surahName,
    this.status = BatchItemStatus.pending,
    this.progress = 0,
    this.progressMessage = 'قيد الانتظار',
    this.outputJsonPath,
    this.errorMessage,
    this.elapsed,
    this.isSelected = true,
  });

  bool get isDone => status == BatchItemStatus.completed || status == BatchItemStatus.skipped;
}

class SurahFileNameDetector {
  /// تنظيف النص العربي للمقارنة (إزالة التشكيل والهمزات)
  static String normalizeArabic(String text) {
    var result = text;
    result = result.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), ''); // تشكيل
    result = result.replaceAll(RegExp(r'[إأآا]'), 'ا');
    result = result.replaceAll('ة', 'ه');
    result = result.replaceAll('ى', 'ي');
    result = result.replaceAll(RegExp(r'[\s_\-\.\(\)]+'), '');
    return result.toLowerCase();
  }

  static final Map<String, int> _arabicSurahAliases = {
    'الفاتحه': 1, 'فاتحه': 1, 'الحمد': 1,
    'البقره': 2, 'بقره': 2,
    'ال عمران': 3, 'عمران': 3,
    'النساء': 4, 'نساء': 4,
    'المائده': 5, 'مائده': 5,
    'الانعام': 6, 'انعام': 6,
    'الاعراف': 7, 'اعراف': 7,
    'الانفال': 8, 'انفال': 8,
    'التوبه': 9, 'توبه': 9, 'براءه': 9,
    'يونس': 10,
    'هود': 11,
    'يوسف': 12,
    'الرعد': 13, 'رعد': 13,
    'ابراهيم': 14,
    'الحجر': 15, 'حجر': 15,
    'النحل': 16, 'نحل': 16,
    'الاسراء': 17, 'اسراء': 17, 'بني اسرائيل': 17,
    'الكهف': 18, 'كهف': 18,
    'مريم': 19,
    'طه': 20,
    'الانبياء': 21, 'انبياء': 21,
    'الحج': 22, 'حج': 22,
    'المؤمنون': 23, 'المؤمنين': 23, 'مؤمنون': 23, 'مؤمنين': 23,
    'النور': 24, 'نور': 24,
    'الفرقان': 25, 'فرقان': 25,
    'الشعراء': 26, 'شعراء': 26,
    'النمل': 27, 'نمل': 27,
    'القصص': 28, 'قصص': 28,
    'العنكبوت': 29, 'عنكبوت': 29,
    'الروم': 30, 'روم': 30,
    'لقمان': 31,
    'السجده': 32, 'سجده': 32,
    'الاحزاب': 33, 'احزاب': 33,
    'سبا': 34,
    'فاطر': 35,
    'يس': 36, 'ياسين': 36,
    'الصافات': 37, 'صافات': 37,
    'ص': 38, 'صاد': 38,
    'الزمر': 39, 'زمر': 39,
    'غافر': 40, 'المؤمن': 40,
    'فصلت': 41, 'حم السجده': 41,
    'الشوري': 42, 'شوري': 42,
    'الزخرف': 43, 'زخرف': 43,
    'الدخان': 44, 'دخان': 44,
    'الجاثيه': 45, 'جاثيه': 45,
    'الاحقاف': 46, 'احقاف': 46,
    'محمد': 47, 'القتال': 47,
    'الفتح': 48, 'فتح': 48,
    'الحجرات': 49, 'حجرات': 49,
    'ق': 50, 'قاف': 50,
    'الذاريات': 51, 'ذاريات': 51,
    'الطور': 52, 'طور': 52,
    'النجم': 53, 'نجم': 53,
    'القمر': 54, 'قمر': 54,
    'الرحمن': 55, 'رحمن': 55,
    'الواقعه': 56, 'واقعه': 56,
    'الحديد': 57, 'حديد': 57,
    'المجادله': 58, 'مجادله': 58,
    'الحشر': 59, 'حشر': 59,
    'الممتحنه': 60, 'ممتحنه': 60,
    'الصف': 61, 'صف': 61,
    'الجمعه': 62, 'جمعه': 62,
    'المنافقون': 63, 'منافقون': 63,
    'التغابن': 64, 'تغابن': 64,
    'الطلاق': 65, 'طلاق': 65,
    'التحريم': 66, 'تحريم': 66,
    'الملك': 67, 'ملك': 67, 'تبارك': 67,
    'القلم': 68, 'قلم': 68, 'نون': 68,
    'الحاقه': 69, 'حاقه': 69,
    'المعارج': 70, 'معارج': 70,
    'نوح': 71,
    'الجن': 72, 'جن': 72,
    'المزمل': 73, 'مزمل': 73,
    'المدثر': 74, 'مدثر': 74,
    'القيامه': 75, 'قيامه': 75,
    'الانسان': 76, 'انسان': 76, 'الدهر': 76, 'دهر': 76,
    'المرسلات': 77, 'مرسلات': 77,
    'النبا': 78, 'نبا': 78, 'عم': 78,
    'النازعات': 79, 'نازعات': 79,
    'عبس': 80,
    'التكوير': 81, 'تكوير': 81,
    'الانفطار': 82, 'انفطار': 82,
    'المطففين': 83, 'مطففين': 83,
    'الانشقاق': 84, 'انشقاق': 84,
    'البروج': 85, 'بروج': 85,
    'الطارق': 86, 'طارق': 86,
    'الاعلي': 87, 'اعلي': 87,
    'الغاشيه': 88, 'غاشيه': 88,
    'الفجر': 89, 'فجر': 89,
    'البلد': 90, 'بلد': 90,
    'الشمس': 91, 'شمس': 91,
    'الليل': 92, 'ليل': 92,
    'الضحي': 93, 'ضحي': 93,
    'الشرح': 94, 'شرح': 94, 'الانشراح': 94, 'انشراح': 94,
    'التين': 95, 'تين': 95,
    'العلق': 96, 'علق': 96, 'اقرا': 96,
    'القدر': 97, 'قدر': 97,
    'البينه': 98, 'بينه': 98, 'لم يكن': 98,
    'الزلزله': 99, 'زلزله': 99,
    'العاديات': 100, 'عاديات': 100,
    'القارعه': 101, 'قارعه': 101,
    'التكاثر': 102, 'تكاثر': 102,
    'العصر': 103, 'عصر': 103,
    'الهمزه': 104, 'همزه': 104,
    'الفيل': 105, 'فيل': 105,
    'قريش': 106, 'لايلاف': 106,
    'الماعون': 107, 'ماعون': 107,
    'الكوثر': 108, 'كوثر': 108,
    'الكافرون': 109, 'كافرون': 109,
    'النصر': 110, 'نصر': 110,
    'المسد': 111, 'مسد': 111, 'تبت': 111,
    'الاخلاص': 112, 'اخلاص': 112, 'التوحيد': 112,
    'الفلق': 113, 'فلق': 113,
    'الناس': 114, 'ناس': 114,
  };

  /// تنظيف النص اللاتيني للمقارنة
  static String normalizeLatin(String text) {
    return text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// كشف رقم واسم السورة من اسم الملف الصوتي بدقة متناهية
  static (int, String) detectSurah(String filePath) {
    final fileName = p.basenameWithoutExtension(filePath);
    final cleanName = fileName.trim();

    // 1. فحص وجود "سورة" صريحة متبوعة برقم (مثل: "Surah_018", "surah-1", "سورة 112")
    final explicitSurahNumMatch = RegExp(
      r'(?:surah|sura|سورة|سوره)[\s_\-]*0*([1-9]\d{0,2})\b',
      caseSensitive: false,
    ).firstMatch(cleanName);
    if (explicitSurahNumMatch != null) {
      final id = int.tryParse(explicitSurahNumMatch.group(1)!);
      if (id != null && id >= 1 && id <= 114) {
        final surah = getSurahById(id);
        return (surah.id, surah.nameArabic);
      }
    }

    // 2. فحص وجود "سورة" أو "سوره" متبوعة باسم السورة (مثل: "سورة يس", "سورة طه", "سورة ص", "سورة ق", "سورة البقرة")
    final surahNameAfterWordMatch = RegExp(
      r'(?:سورة|سوره)[\s_\-]+([^\s_\-\.\(\)\[\]]+)',
    ).firstMatch(cleanName);
    if (surahNameAfterWordMatch != null) {
      final rawWord = surahNameAfterWordMatch.group(1)!;
      final normWord = normalizeArabic(rawWord);
      // فحص الكلمة المباشرة
      if (_arabicSurahAliases.containsKey(normWord)) {
        final surah = getSurahById(_arabicSurahAliases[normWord]!);
        return (surah.id, surah.nameArabic);
      }
      // فحص إذا كانت السورة مركبة مثل "آل عمران"
      final twoWordsMatch = RegExp(
        r'(?:سورة|سوره)[\s_\-]+([^\s_\-\.\(\)\[\]]+)[\s_\-]+([^\s_\-\.\(\)\[\]]+)',
      ).firstMatch(cleanName);
      if (twoWordsMatch != null) {
        final compound = '${normalizeArabic(twoWordsMatch.group(1)!)} ${normalizeArabic(twoWordsMatch.group(2)!)}';
        if (_arabicSurahAliases.containsKey(compound)) {
          final surah = getSurahById(_arabicSurahAliases[compound]!);
          return (surah.id, surah.nameArabic);
        }
      }
    }

    // 3. فحص وجود رقم السورة في نهاية اسم الملف (شائع جداً في ختمات القراء: "QR_SC1447_Bdr-Atturki_001")
    final trailingNumMatch = RegExp(r'[\s_\-]0*([1-9]\d{0,2})$').firstMatch(cleanName);
    if (trailingNumMatch != null) {
      final id = int.tryParse(trailingNumMatch.group(1)!);
      if (id != null && id >= 1 && id <= 114) {
        final surah = getSurahById(id);
        return (surah.id, surah.nameArabic);
      }
    }

    // 4. فحص وجود أرقام صريحة في بداية اسم الملف (مثل: "001", "002 - البقرة", "4.mp3", "18.mp3")
    final leadNumMatch = RegExp(r'^0*([1-9]\d{0,2})(?:[\s_\-\.]|$)').firstMatch(cleanName);
    if (leadNumMatch != null) {
      final id = int.tryParse(leadNumMatch.group(1)!);
      if (id != null && id >= 1 && id <= 114) {
        final surah = getSurahById(id);
        return (surah.id, surah.nameArabic);
      }
    }

    // 5. مطابقة ككلمة مستقلة (Tokens) لحل أسماء السور القصيرة مثل: "طه", "يس", "ص", "ق"
    final tokens = cleanName
        .split(RegExp(r'[\s_\-\.\(\)\[\]/\\#@!]+'))
        .map((t) => normalizeArabic(t))
        .where((t) => t.isNotEmpty)
        .toList();

    // فحص كل كلمة مفردة
    for (final token in tokens) {
      if (_arabicSurahAliases.containsKey(token)) {
        final surah = getSurahById(_arabicSurahAliases[token]!);
        return (surah.id, surah.nameArabic);
      }
    }

    // فحص الكلمات المركبة (مثل: آل عمران)
    for (var i = 0; i < tokens.length - 1; i++) {
      final pair = '${tokens[i]} ${tokens[i + 1]}';
      if (_arabicSurahAliases.containsKey(pair)) {
        final surah = getSurahById(_arabicSurahAliases[pair]!);
        return (surah.id, surah.nameArabic);
      }
    }

    // 6. مطابقة السور كأجزاء نصية (للأسماء التي طولها 3 أحرف فأكثر تجنباً للتضارب)
    final normalizedInput = normalizeArabic(cleanName);
    final sortedAliases = _arabicSurahAliases.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final alias in sortedAliases) {
      if (alias.length >= 3 && normalizedInput.contains(alias.replaceAll(' ', ''))) {
        final surah = getSurahById(_arabicSurahAliases[alias]!);
        return (surah.id, surah.nameArabic);
      }
    }

    // 7. مطابقة الاسم الإنجليزي أو اللاتيني (مثل: Ya-Sin, Ta-Ha, Sad, Qaf, Al-Baqarah)
    final normLatinInput = normalizeLatin(cleanName);
    for (final surah in allSurahsList) {
      final normEng = normalizeLatin(surah.nameEnglish);
      final normTrans = normalizeLatin(surah.nameTransliteration);
      if (normEng.length >= 3 && normLatinInput.contains(normEng)) {
        return (surah.id, surah.nameArabic);
      }
      if (normTrans.length >= 3 && normLatinInput.contains(normTrans)) {
        return (surah.id, surah.nameArabic);
      }
    }

    // 8. فحص خاص للأسماء اللاتينية القصيرة ككلمات منفصلة: taha, yasin, yaseen, sad, qaf
    final latinTokens = cleanName
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    for (final lt in latinTokens) {
      if (lt == 'taha' || lt == 'ta-ha') return (20, getSurahById(20).nameArabic);
      if (lt == 'yasin' || lt == 'yaseen' || lt == 'ya-sin') return (36, getSurahById(36).nameArabic);
      if (lt == 'sad') return (38, getSurahById(38).nameArabic);
      if (lt == 'qaf') return (50, getSurahById(50).nameArabic);
    }

    // 9. البحث عن أي أرقام معزولة بفواصل (تجنب السنين مثل 1447 و 2024 ومعدل البت 128 و 320)
    final isolatedNumMatches = RegExp(r'(?:^|[^\d])0*([1-9]\d{0,2})(?:[^\d]|$)').allMatches(cleanName);
    for (final match in isolatedNumMatches.toList().reversed) {
      final numStr = match.group(1);
      if (numStr != null) {
        final id = int.tryParse(numStr);
        if (id != null && id >= 1 && id <= 114) {
          final surah = getSurahById(id);
          return (surah.id, surah.nameArabic);
        }
      }
    }

    // افتراضياً سورة الفاتحة إذا لم يتم التعرف
    return (1, allSurahsList.first.nameArabic);
  }
}

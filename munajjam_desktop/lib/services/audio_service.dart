import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'waveform_extractor.dart';

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal() {
    _initListeners();
  }

  final AudioPlayer _player = AudioPlayer();
  Timer? _snippetTimer;

  final ValueNotifier<Duration> positionNotifier = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration> durationNotifier = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<PlayerState> playerStateNotifier = ValueNotifier<PlayerState>(PlayerState.stopped);
  final ValueNotifier<double> playbackRateNotifier = ValueNotifier<double>(1.0);
  final ValueNotifier<List<double>> peaksNotifier = ValueNotifier<List<double>>([]);
  final ValueNotifier<bool> isExtractingNotifier = ValueNotifier<bool>(false);

  AudioPlayer get player => _player;
  bool get isPlaying => playerStateNotifier.value == PlayerState.playing;
  double get currentSeconds => positionNotifier.value.inMilliseconds / 1000.0;
  double get totalSeconds => durationNotifier.value.inMilliseconds / 1000.0;

  bool _isSeeking = false;
  bool get isSeeking => _isSeeking;

  int _seekSessionId = 0;

  void _initListeners() {
    _player.onPositionChanged.listen((pos) {
      if (_isSeeking) return;
      // منع برامج تشغيل الصوت في ويندوز من إرجاع المؤشر إلى الصفر أو مواضع قديمة أثناء الإيقاف المؤقت
      if (!isPlaying) return;
      positionNotifier.value = pos;
    });

    _player.onDurationChanged.listen((dur) {
      if (dur > Duration.zero) {
        durationNotifier.value = dur;
      }
    });

    _player.onPlayerStateChanged.listen((state) {
      playerStateNotifier.value = state;
    });
  }

  int _loadAudioSessionId = 0;

  /// تجهيز نسخة WAV معيارية موحدة للتشغيل المحلي لضمان التطابق الزمني المطلق ومنع أي ترحيل
  Future<String> _ensurePlaybackWav(String source) async {
    if (source.toLowerCase().endsWith('.wav')) {
      return source;
    }

    try {
      final file = File(source);
      if (!await file.exists()) {
        return source;
      }

      final ffmpegPath = await WaveformExtractor().findFfmpegPath();
      if (ffmpegPath == null) {
        return source;
      }

      final tempDir = Directory(p.join(Directory.systemTemp.path, 'munajjam_cache'));
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }

      final stat = await file.stat();
      final baseName = p.basenameWithoutExtension(source).replaceAll(RegExp(r'[^\w\.-]'), '_');
      final cacheKey = 'norm_${baseName}_${stat.size}_${stat.modified.millisecondsSinceEpoch}.wav';
      final cachedWav = File(p.join(tempDir.path, cacheKey));

      if (await cachedWav.exists() && await cachedWav.length() > 1000) {
        return cachedWav.path;
      }

      // تحويل فائق السرعة عبر FFmpeg إلى تدفق PCM 16-bit قياسي بدون ترحيل وبدون ضغط
      final tempTargetPath = '${cachedWav.path}.tmp.wav';
      final res = await Process.run(ffmpegPath, [
        '-v', 'error',
        '-y',
        '-i', source,
        '-vn',
        '-c:a', 'pcm_s16le',
        tempTargetPath,
      ]);

      if (res.exitCode == 0 && await File(tempTargetPath).exists()) {
        final tmpFile = File(tempTargetPath);
        if (await cachedWav.exists()) {
          await cachedWav.delete();
        }
        await tmpFile.rename(cachedWav.path);
        _cleanupOldCache(tempDir, keepPath: cachedWav.path);
        return cachedWav.path;
      } else {
        if (await File(tempTargetPath).exists()) {
          await File(tempTargetPath).delete();
        }
      }
    } catch (e) {
      debugPrint('Error preparing playback WAV: $e');
    }

    return source;
  }

  /// تنظيف تلقائي للملفات المؤقتة القديمة للإبقاء على مساحة التخزين نظيفة
  void _cleanupOldCache(Directory tempDir, {required String keepPath}) {
    Future.microtask(() async {
      try {
        final now = DateTime.now();
        await for (final entity in tempDir.list()) {
          if (entity is File && entity.path != keepPath && entity.path.endsWith('.wav')) {
            final stat = await entity.stat();
            if (now.difference(stat.modified).inHours > 24) {
              await entity.delete();
            }
          }
        }
      } catch (_) {}
    });
  }

  Future<void> loadAudioSource(String source, {bool isLocal = false}) async {
    _snippetTimer?.cancel();
    peaksNotifier.value = [];
    isExtractingNotifier.value = true;
    final currentSession = ++_loadAudioSessionId;

    try {
      String effectiveSource = source;
      if (isLocal) {
        effectiveSource = await _ensurePlaybackWav(source);
        if (currentSession != _loadAudioSessionId) return;
        await _player.setSource(DeviceFileSource(effectiveSource));
      } else {
        await _player.setSource(UrlSource(source));
      }

      // استخراج حقيقي ودقيق للتموجات الصوتية من الإشارة الفيزيائية الموحدة
      final realPeaks = await WaveformExtractor().extractPeaks(effectiveSource, isLocal: isLocal);
      if (currentSession == _loadAudioSessionId) {
        if (realPeaks != null && realPeaks.isNotEmpty) {
          peaksNotifier.value = realPeaks;
          if (durationNotifier.value == Duration.zero) {
            durationNotifier.value = Duration(milliseconds: (realPeaks.length * 10));
          }
        }
        isExtractingNotifier.value = false;
      }
    } catch (e) {
      debugPrint('Error loading audio source: $e');
      if (currentSession == _loadAudioSessionId) {
        isExtractingNotifier.value = false;
      }
    }
  }

  Future<void> play() async {
    _snippetTimer?.cancel();
    await _player.resume();
  }

  Future<void> pause() async {
    _snippetTimer?.cancel();
    await _player.pause();
  }

  Future<void> togglePlay() async {
    if (isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seek(double seconds) async {
    _snippetTimer?.cancel();
    final currentSession = ++_seekSessionId;
    final millis = (seconds * 1000).toInt();
    final targetDuration = Duration(milliseconds: millis);
    // تحديث فوري لحظي للمؤشر بدون أي تأخير (Zero-Latency Instant Playhead Snap)
    positionNotifier.value = targetDuration;
    _isSeeking = true;
    try {
      await _player.seek(targetDuration);
    } catch (_) {} finally {
      Future.delayed(const Duration(milliseconds: 250), () {
        if (_seekSessionId == currentSession) {
          _isSeeking = false;
        }
      });
    }
  }

  Future<void> setPlaybackRate(double rate) async {
    playbackRateNotifier.value = rate;
    await _player.setPlaybackRate(rate);
  }

  int _snippetId = 0;

  Future<void> playSnippet(double startSeconds, double endSeconds) async {
    _snippetTimer?.cancel();
    final currentId = ++_snippetId;

    try {
      // 1. تحديث الموضع اللحظي فوراً لمنع أي وميض أو ظهور لموضع سابق
      final targetMs = (startSeconds * 1000).round();
      final targetDuration = Duration(milliseconds: targetMs);
      positionNotifier.value = targetDuration;
      _isSeeking = true;

      // 2. إيقاف التشغيل فوراً لمنع تسرب الصوت من الموضع السابق أثناء القفز
      await _player.pause();
      if (currentId != _snippetId) return;

      // 3. انتظار اكتمال الانتقال الفعلي في محرك الصوت بويندوز عبر Completer آمن
      final completer = Completer<void>();
      StreamSubscription? seekSub;
      seekSub = _player.onSeekComplete.listen((_) {
        if (!completer.isCompleted) completer.complete();
      });
      final fallbackTimer = Timer(const Duration(milliseconds: 180), () {
        if (!completer.isCompleted) completer.complete();
      });

      await _player.seek(targetDuration);
      await completer.future;
      await seekSub.cancel();
      fallbackTimer.cancel();
      _isSeeking = false;

      if (currentId != _snippetId) return;

      // 4. بدء التشغيل الآن فقط بعد استقرار الرأس الصوتي في الهاردوير
      await _player.resume();
      if (currentId != _snippetId) return;

      // 5. حساب مدة المقطع بدقة متناهية مع تعويض زمن استجابة ويندوز (Platform IPC Latency)
      final durationMs = ((endSeconds - startSeconds) * 1000 / playbackRateNotifier.value).round();
      // إرسال أمر الإيقاف قبل نهاية المقطع بـ 20ms لتعويض تأخر وصول أمر Pause إلى محرك الصوت بويندوز
      // مما يجعل الصوت يتوقف فيزيائياً من السماعات عند لحظة endSeconds بدقة تامة دون أي نزف للكلمة التالية
      final stopDelayMs = max(20, durationMs - 20);

      StreamSubscription? posSub;
      posSub = _player.onPositionChanged.listen((pos) {
        if (pos.inMilliseconds >= (endSeconds * 1000) - 15) {
          if (currentId == _snippetId) {
            _player.pause();
            posSub?.cancel();
          }
        }
      });

      _snippetTimer = Timer(Duration(milliseconds: stopDelayMs), () async {
        posSub?.cancel();
        if (currentId == _snippetId) {
          await pause();
        }
      });
    } catch (e) {
      debugPrint('Error playing snippet: $e');
    }
  }



  void dispose() {
    _snippetTimer?.cancel();
    _player.dispose();
  }
}

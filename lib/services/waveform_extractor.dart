import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// خدمة استخراج التموجات الصوتية الحقيقية بدقة متناهية (Real Audio Waveform Extractor)
/// تدعم جميع صيغ الصوت الشائعة (MP3, WAV, M4A, AAC, OGG, FLAC) بسرعة فائقة
class WaveformExtractor {
  static final WaveformExtractor _instance = WaveformExtractor._internal();
  factory WaveformExtractor() => _instance;
  WaveformExtractor._internal();

  String? _cachedFfmpegPath;

  /// البحث الذكي عن مسار FFmpeg
  Future<String?> findFfmpegPath() async {
    if (_cachedFfmpegPath != null) return _cachedFfmpegPath;

    final candidates = <String>[];

    try {
      // 1. المجلد الذي يوجد به ملف تشغيل التطبيق (في النسخة المجمعة الموزعة)
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      candidates.add(p.join(exeDir, 'ffmpeg.exe'));
      candidates.add(p.join(exeDir, 'ffmpeg'));

      // 2. المجلدات الأبوية (أثناء بيئة التطوير في Flutter)
      var parentDir = Directory(exeDir);
      for (int i = 0; i < 5; i++) {
        candidates.add(p.join(parentDir.path, 'ffmpeg.exe'));
        candidates.add(p.join(parentDir.path, 'ffmpeg'));
        parentDir = parentDir.parent;
      }

      // 3. مجلد العمل الحالي
      final cwd = Directory.current.path;
      candidates.add(p.join(cwd, 'ffmpeg.exe'));
      candidates.add(p.join(cwd, '..', 'ffmpeg.exe'));
    } catch (_) {}

    for (final path in candidates) {
      if (File(path).existsSync()) {
        _cachedFfmpegPath = p.normalize(File(path).absolute.path);
        return _cachedFfmpegPath;
      }
    }

    // 4. فحص مسار النظام العام (System PATH)
    try {
      final res = await Process.run('ffmpeg', ['-version']);
      if (res.exitCode == 0) {
        _cachedFfmpegPath = 'ffmpeg';
        return _cachedFfmpegPath;
      }
    } catch (_) {}

    return null;
  }

  /// استخراج مصفوفة التموجات الصوتية الحقيقية (بمعدل 100 نقطة لكل ثانية = دقة 10ms)
  Future<List<double>?> extractPeaks(String source, {bool isLocal = true}) async {
    try {
      if (isLocal && !File(source).existsSync()) {
        return null;
      }

      final ffmpegPath = await findFfmpegPath();
      if (ffmpegPath != null) {
        final peaks = await _extractWithFfmpeg(source, ffmpegPath);
        if (peaks != null && peaks.isNotEmpty) {
          return peaks;
        }
      }

      // في حال تعذر FFmpeg وكان الملف محلياً بصيغة WAV نستخدم المحرك الداخلي
      if (isLocal && source.toLowerCase().endsWith('.wav')) {
        return await _extractWavNative(source);
      }

      return null;
    } catch (e) {
      debugPrint('WaveformExtractor error: $e');
      return null;
    }
  }

  /// استخراج حقيقي فائق السرعة عبر تدفق PCM أحادي القناة بتردد 1000Hz
  Future<List<double>?> _extractWithFfmpeg(String source, String ffmpegPath) async {
    try {
      // نطلب من FFmpeg تحويل أي ملف صوتي إلى تدفق PCM 16-bit أحادي بتردد 1000Hz عبر stdout
      final process = await Process.start(ffmpegPath, [
        '-v', 'error',
        '-i', source,
        '-ac', '1',
        '-ar', '1000',
        '-f', 's16le',
        '-',
      ]);

      final bytesBuilder = BytesBuilder(copy: false);
      await for (final chunk in process.stdout) {
        bytesBuilder.add(chunk);
      }

      final exitCode = await process.exitCode;
      if (exitCode != 0) {
        debugPrint('FFmpeg process exited with code $exitCode');
        return null;
      }

      final rawBytes = bytesBuilder.takeBytes();
      if (rawBytes.isEmpty) return null;

      // حساب القمم في خيط خلفي لمنع أي تأخير لواجهة المستخدم
      return await compute(_processRawPcmBytes, rawBytes);
    } catch (e) {
      debugPrint('_extractWithFfmpeg error: $e');
      return null;
    }
  }

  /// معالجة عينات الـ PCM واستخراج مصفوفة القمم الموحدة (100 peak/sec)
  static List<double> _processRawPcmBytes(Uint8List rawBytes) {
    final byteData = ByteData.sublistView(rawBytes);
    final totalSamples = rawBytes.lengthInBytes ~/ 2;
    if (totalSamples == 0) return [];

    // كل نافذة 10ms تحتوي على 10 عينات (1000Hz / 100 = 10 samples)
    const samplesPerBin = 10;
    final numBins = totalSamples ~/ samplesPerBin;
    final rawPeaks = <double>[];
    double globalMax = 0.0;

    for (int b = 0; b < numBins; b++) {
      int maxVal = 0;
      final start = b * samplesPerBin;
      for (int s = 0; s < samplesPerBin; s++) {
        final sample = byteData.getInt16((start + s) * 2, Endian.little).abs();
        if (sample > maxVal) maxVal = sample;
      }
      final norm = maxVal / 32768.0;
      if (norm > globalMax) globalMax = norm;
      rawPeaks.add(norm);
    }

    final remainder = totalSamples % samplesPerBin;
    if (remainder > 0) {
      int maxVal = 0;
      final start = numBins * samplesPerBin;
      for (int s = 0; s < remainder; s++) {
        final sample = byteData.getInt16((start + s) * 2, Endian.little).abs();
        if (sample > maxVal) maxVal = sample;
      }
      final norm = maxVal / 32768.0;
      if (norm > globalMax) globalMax = norm;
      rawPeaks.add(norm);
    }

    if (globalMax < 0.001) return List.filled(rawPeaks.length, 0.0);

    // معايرة احترافية: رفع مستوى الصوت ليصل أعلى صوت إلى 0.94
    // مع تطبيق دالة رفع هادئة (0.85) لإبراز أصوات التجويد والهمسات دون المساس بالصمت التام
    final scale = 0.94 / globalMax;
    final finalPeaks = List<double>.generate(rawPeaks.length, (i) {
      final scaled = (rawPeaks[i] * scale).clamp(0.0, 1.0);
      return pow(scaled, 0.85).toDouble();
    });

    return finalPeaks;
  }

  /// محرك مدمج احتياطي لقراءة ملفات الـ WAV القياسية بدون أي برامج خارجية
  Future<List<double>?> _extractWavNative(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.length < 44) return null;

      return await compute(_processWavBytes, bytes);
    } catch (e) {
      debugPrint('_extractWavNative error: $e');
      return null;
    }
  }

  /// فك ترويسة ملفات WAV واستخراج القمم بدقة
  static List<double>? _processWavBytes(Uint8List bytes) {
    try {
      final bd = bytes.buffer.asByteData();
      if (bd.getUint32(0, Endian.big) != 0x52494646) return null; // 'RIFF'
      if (bd.getUint32(8, Endian.big) != 0x57415645) return null; // 'WAVE'

      int offset = 12;
      int audioFormat = 1;
      int numChannels = 1;
      int sampleRate = 16000;
      int bitsPerSample = 16;
      int dataOffset = -1;
      int dataLength = 0;

      while (offset + 8 <= bytes.length) {
        final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
        final chunkSize = bd.getUint32(offset + 4, Endian.little);
        if (chunkId == 'fmt ') {
          audioFormat = bd.getUint16(offset + 8, Endian.little);
          numChannels = bd.getUint16(offset + 10, Endian.little);
          sampleRate = bd.getUint32(offset + 12, Endian.little);
          bitsPerSample = bd.getUint16(offset + 22, Endian.little);
        } else if (chunkId == 'data') {
          dataOffset = offset + 8;
          dataLength = min(chunkSize, bytes.length - dataOffset);
          break;
        }
        offset += 8 + chunkSize + (chunkSize % 2);
      }

      if (dataOffset < 0 || dataLength <= 0 || sampleRate <= 0 || numChannels <= 0) return null;

      final bytesPerSample = bitsPerSample ~/ 8;
      final bytesPerFrame = bytesPerSample * numChannels;
      final totalFrames = dataLength ~/ bytesPerFrame;
      if (totalFrames <= 0) return null;

      final durationSec = totalFrames / sampleRate;
      final targetPeaks = max(100, (durationSec * 100).round());
      final framesPerPeak = totalFrames / targetPeaks;

      final rawPeaks = <double>[];
      double globalMax = 0.0;

      for (int p = 0; p < targetPeaks; p++) {
        final startFrame = (p * framesPerPeak).floor();
        final endFrame = min(((p + 1) * framesPerPeak).floor(), totalFrames);
        double peakVal = 0.0;
        final stride = max(1, (endFrame - startFrame) ~/ 16);

        for (int f = startFrame; f < endFrame; f += stride) {
          final frameOffset = dataOffset + (f * bytesPerFrame);
          for (int ch = 0; ch < numChannels; ch++) {
            final sampleOffset = frameOffset + (ch * bytesPerSample);
            double s = 0.0;
            if (bitsPerSample == 16) {
              s = bd.getInt16(sampleOffset, Endian.little).abs() / 32768.0;
            } else if (bitsPerSample == 24) {
              final b0 = bytes[sampleOffset];
              final b1 = bytes[sampleOffset + 1];
              final b2 = bytes[sampleOffset + 2];
              int val = (b2 << 24) | (b1 << 16) | (b0 << 8);
              s = (val >> 8).abs() / 8388608.0;
            } else if (bitsPerSample == 32) {
              if (audioFormat == 3) {
                s = bd.getFloat32(sampleOffset, Endian.little).abs();
              } else {
                s = bd.getInt32(sampleOffset, Endian.little).abs() / 2147483648.0;
              }
            } else if (bitsPerSample == 8) {
              s = (bytes[sampleOffset] - 128).abs() / 128.0;
            }
            if (s > peakVal) peakVal = s;
          }
        }
        if (peakVal > globalMax) globalMax = peakVal;
        rawPeaks.add(peakVal);
      }

      if (globalMax < 0.001) return List.filled(rawPeaks.length, 0.0);
      final scale = 0.94 / globalMax;
      return rawPeaks.map((v) => pow((v * scale).clamp(0.0, 1.0), 0.85).toDouble()).toList();
    } catch (e) {
      return null;
    }
  }
}

// ignore_for_file: constant_identifier_names

import 'dart:ffi';
import 'dart:io';

/// خدمة للتحكم في طاقة النظام ومنع الدخول في وضع السكون أثناء تزمين الختمات الطويلة
class WindowsPowerService {
  static const int ES_SYSTEM_REQUIRED = 0x00000001;
  static const int ES_CONTINUOUS = 0x80000000;
  static const int ES_AWAYMODE_REQUIRED = 0x00000040;

  static DynamicLibrary? _kernel32;
  static int Function(int)? _setThreadExecutionState;
  static bool _isPreventingSleep = false;

  static void _init() {
    if (!Platform.isWindows) return;
    if (_kernel32 != null) return;
    try {
      _kernel32 = DynamicLibrary.open('kernel32.dll');
      _setThreadExecutionState = _kernel32!
          .lookupFunction<Uint32 Function(Uint32), int Function(int)>('SetThreadExecutionState');
    } catch (e) {
      // Ignored if not available
    }
  }

  /// منع الكمبيوتر من الدخول في وضع السكون أثناء عمل الطابور
  static void preventSleep() {
    if (!Platform.isWindows) return;
    _init();
    try {
      _setThreadExecutionState?.call(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_AWAYMODE_REQUIRED);
      _isPreventingSleep = true;
    } catch (_) {}
  }

  /// إعادة تمكين وضع السكون الطبيعي للنظام
  static void allowSleep() {
    if (!Platform.isWindows || !_isPreventingSleep) return;
    _init();
    try {
      _setThreadExecutionState?.call(ES_CONTINUOUS);
      _isPreventingSleep = false;
    } catch (_) {}
  }

  /// إيقاف تشغيل الكمبيوتر بأمان مع إعطاء مهلة بالثواني
  static Future<void> shutdownComputer({int delaySeconds = 60}) async {
    if (!Platform.isWindows) return;
    try {
      await Process.run('shutdown', ['/s', '/t', delaySeconds.toString()]);
    } catch (_) {}
  }

  /// إلغاء أمر إيقاف التشغيل
  static Future<void> cancelShutdown() async {
    if (!Platform.isWindows) return;
    try {
      await Process.run('shutdown', ['/a']);
    } catch (_) {}
  }
}

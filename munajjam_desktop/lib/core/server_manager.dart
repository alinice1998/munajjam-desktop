import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class HardwareStatus {
  final bool hasGpu;
  final String providerName;
  final bool segmenterLoaded;
  final bool zipformerLoaded;
  final bool wav2vec2Loaded;
  final bool pythonFound;
  final String message;

  HardwareStatus({
    required this.hasGpu,
    required this.providerName,
    required this.segmenterLoaded,
    required this.zipformerLoaded,
    required this.wav2vec2Loaded,
    required this.pythonFound,
    required this.message,
  });
}

class ServerManager {
  static final ServerManager _instance = ServerManager._internal();
  factory ServerManager() => _instance;
  ServerManager._internal();

  Process? _serverProcess;
  bool _isStarting = false;
  bool _isOnline = false;
  final String _serverUrl = 'http://localhost:8000';
  Timer? _healthCheckTimer;

  final ValueNotifier<bool> isOnlineNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String> statusMessageNotifier = ValueNotifier<String>('جاري التهيئة...');
  final ValueNotifier<HardwareStatus?> hardwareStatusNotifier = ValueNotifier<HardwareStatus?>(null);

  String get serverUrl => _serverUrl;
  bool get isOnline => _isOnline;

  String _resolveAppRootDir() {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      if (File('$exeDir\\munajjam_server.py').existsSync() ||
          File('$exeDir\\munajjam_server.exe').existsSync() ||
          File('$exeDir\\backend\\munajjam_server.exe').existsSync()) {
        return exeDir;
      }
    } catch (_) {}

    String currentDir = Directory.current.path;
    if (currentDir.endsWith('munajjam_desktop')) {
      return Directory(currentDir).parent.path;
    }
    return currentDir;
  }

  Future<void> initAndStartServer({String? serverScriptPath}) async {
    if (_isStarting || _isOnline) return;
    _isStarting = true;

    // Check if server is already running
    final currentlyOnline = await checkHealth();
    if (currentlyOnline) {
      _isOnline = true;
      _isStarting = false;
      isOnlineNotifier.value = true;
      statusMessageNotifier.value = 'الخادم متصل ونشط';
      _startPeriodicHealthCheck();
      await detectHardwareAndModels();
      return;
    }

    statusMessageNotifier.value = 'جاري إطلاق خادم التزمين الهجين في الخلفية...';

    try {
      final rootDir = _resolveAppRootDir();

      // Check if standalone executable or embedded python or python script
      final backendExe = File('$rootDir\\backend\\munajjam_server.exe');
      final standaloneExe = File('$rootDir\\munajjam_server.exe');
      final embeddedPythonw = File('$rootDir\\python_runtime\\pythonw.exe');
      final scriptFile = File('$rootDir\\munajjam_server.py');

      if (await backendExe.exists()) {
        _serverProcess = await Process.start(
          backendExe.path,
          ['--parent-pid', pid.toString()],
          workingDirectory: rootDir,
          mode: ProcessStartMode.detached,
          runInShell: false,
        );
      } else if (await standaloneExe.exists()) {
        _serverProcess = await Process.start(
          standaloneExe.path,
          ['--parent-pid', pid.toString()],
          workingDirectory: rootDir,
          mode: ProcessStartMode.detached,
          runInShell: false,
        );
      } else if (await embeddedPythonw.exists() && await scriptFile.exists()) {
        _serverProcess = await Process.start(
          embeddedPythonw.path,
          ['munajjam_server.py', '--parent-pid', pid.toString()],
          workingDirectory: rootDir,
          mode: ProcessStartMode.detached,
          runInShell: false,
        );
      } else if (await scriptFile.exists()) {
        final serverArgs = ['munajjam_server.py', '--parent-pid', pid.toString()];
        try {
          _serverProcess = await Process.start(
            'pythonw',
            serverArgs,
            workingDirectory: rootDir,
            mode: ProcessStartMode.detached,
            runInShell: false,
          );
        } catch (_) {
          _serverProcess = await Process.start(
            'python',
            serverArgs,
            workingDirectory: rootDir,
            mode: ProcessStartMode.detached,
            runInShell: false,
          );
        }
      } else {
        statusMessageNotifier.value = 'ملف السيرفر غير موجود في المسار: $rootDir';
        _isStarting = false;
        return;
      }

      debugPrint('Launched background server process pid: ${_serverProcess?.pid}');

      // Poll until online (up to 35 seconds)
      for (int i = 0; i < 40; i++) {
        await Future.delayed(const Duration(milliseconds: 800));
        if (await checkHealth()) {
          _isOnline = true;
          isOnlineNotifier.value = true;
          statusMessageNotifier.value = 'تم تشغيل الخادم والتحميل بنجاح';
          break;
        }
      }

      if (!_isOnline) {
        statusMessageNotifier.value = 'تعذر الاتصال بالخادم، يرجى التأكد من اكتمال ملفات التثبيت.';
      }
    } catch (e) {
      debugPrint('Error starting server: $e');
      statusMessageNotifier.value = 'خطأ في تشغيل الخادم: $e';
    } finally {
      _isStarting = false;
      _startPeriodicHealthCheck();
      await detectHardwareAndModels();
    }
  }

  Future<bool> checkHealth() async {
    try {
      final response = await http.get(
        Uri.parse('$_serverUrl/health'),
      ).timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _isOnline = (data['status'] == 'online' && data['model_loaded'] == true);
        isOnlineNotifier.value = _isOnline;
        return _isOnline;
      }
    } catch (_) {
      _isOnline = false;
      isOnlineNotifier.value = false;
    }
    return false;
  }

  void _startPeriodicHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await checkHealth();
    });
  }

  Future<void> detectHardwareAndModels() async {
    bool hasGpu = false;
    String provider = 'CPU Execution Provider';
    bool segmenterOk = false;
    bool zipformerOk = false;
    bool wav2vec2Ok = false;
    bool pythonOk = true;

    try {
      final rootDir = _resolveAppRootDir();

      final segmenterModel = File('$rootDir\\model_segmenter\\model.onnx');
      final segmenterConfig = File('$rootDir\\model_segmenter\\config.json');
      final zipformerModel = File('$rootDir\\model_zipformer\\zipformer_p_arabic_v3.onnx');
      final wav2vec2Model = File('$rootDir\\model_wav2vec2\\model.onnx');

      segmenterOk = await segmenterModel.exists() || await segmenterConfig.exists();
      zipformerOk = await zipformerModel.exists();
      wav2vec2Ok = await wav2vec2Model.exists();

      if (_isOnline) {
        try {
          final res = await http.get(Uri.parse('$_serverUrl/health')).timeout(const Duration(seconds: 2));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            if (data['has_gpu'] == true) {
              hasGpu = true;
              provider = data['provider_name'] ?? 'DirectML Hardware Acceleration (GPU)';
            }
          }
        } catch (_) {}
      }
    } catch (_) {
      // Fallback
    }

    hardwareStatusNotifier.value = HardwareStatus(
      hasGpu: hasGpu,
      providerName: provider,
      segmenterLoaded: segmenterOk,
      zipformerLoaded: zipformerOk,
      wav2vec2Loaded: wav2vec2Ok,
      pythonFound: pythonOk,
      message: hasGpu
          ? 'المسرع الرسومي $provider نشط ويعمل بأعلى كفاءة'
          : 'يعمل التطبيق بنمط المعالج المركزي CPU بأداء فائق وخفيف',
    );
  }

  Future<void> stopServer() async {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;

    final pidToKill = _serverProcess?.pid;

    try {
      await http.post(
        Uri.parse('$_serverUrl/shutdown'),
      ).timeout(const Duration(seconds: 2));
    } catch (_) {}

    try {
      _serverProcess?.kill(ProcessSignal.sigterm);
      _serverProcess?.kill(ProcessSignal.sigkill);
      _serverProcess = null;
    } catch (_) {}

    if (Platform.isWindows && pidToKill != null) {
      try {
        await Process.run('taskkill', ['/F', '/PID', pidToKill.toString()]);
      } catch (_) {}
    }

    _isOnline = false;
    _isStarting = false;
    isOnlineNotifier.value = false;
    statusMessageNotifier.value = 'تم إيقاف الخادم';
  }

  void dispose() {
    stopServer();
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'core/server_manager.dart';
import 'core/theme/app_theme.dart';
import 'providers/alignment_provider.dart';
import 'services/audio_service.dart';
import 'services/quran_data_service.dart';
import 'views/qa_screen.dart';
import 'views/widgets/exit_loading_dialog.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop Window Configuration
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    try {
      await windowManager.ensureInitialized();
      const windowOptions = WindowOptions(
        size: Size(1240, 720),
        minimumSize: Size(960, 580),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        title: 'منجم - محرر التزمين القرآني الذكي',
        titleBarStyle: TitleBarStyle.hidden,
      );
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.center();
        final pos = await windowManager.getPosition();
        // ضمان ألا تكون النافذة مقطوعة أو خارج حدود الشاشة من الأعلى
        if (pos.dy < 30) {
          await windowManager.setPosition(Offset(pos.dx, 30));
        }
        await windowManager.show();
        await windowManager.focus();
        await windowManager.setPreventClose(true);
      });
    } catch (_) {}
  }

  // Pre-load local Quran data
  try {
    await QuranDataService().loadData();
  } catch (_) {}

  // Automatically start silent background server
  ServerManager().initAndStartServer();

  runApp(const MunajjamApp());
}

class MunajjamApp extends StatefulWidget {
  const MunajjamApp({super.key});

  @override
  State<MunajjamApp> createState() => _MunajjamAppState();
}

class _MunajjamAppState extends State<MunajjamApp> with WindowListener {
  String _localeCode = 'ar';

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.addListener(this);
    }
  }

  @override
  void onWindowClose() async {
    final ctx = appNavigatorKey.currentContext;
    if (ctx != null) {
      ExitLoadingDialog.show(ctx, localeCode: _localeCode);
    } else {
      await ServerManager().stopServer();
      await windowManager.destroy();
    }
  }

  void _toggleLocale() {
    setState(() {
      _localeCode = _localeCode == 'ar' ? 'en' : 'ar';
    });
  }

  @override
  void dispose() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.removeListener(this);
    }
    ServerManager().stopServer();
    AudioService().dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AlignmentProvider()),
      ],
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        title: 'منجم - التزمين القرآني الذكي',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        locale: Locale(_localeCode),
        supportedLocales: const [
          Locale('ar', 'SA'),
          Locale('en', 'US'),
        ],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: QAScreen(
          currentLocale: _localeCode,
          onLanguageToggle: _toggleLocale,
        ),
      ),
    );
  }
}

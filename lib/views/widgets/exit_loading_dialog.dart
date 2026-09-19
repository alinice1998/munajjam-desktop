import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/server_manager.dart';
import '../../core/theme/app_theme.dart';

class ExitLoadingDialog extends StatefulWidget {
  final String localeCode;
  const ExitLoadingDialog({super.key, this.localeCode = 'ar'});

  static Future<void> show(BuildContext context, {String localeCode = 'ar'}) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (ctx) => ExitLoadingDialog(localeCode: localeCode),
    );
  }

  @override
  State<ExitLoadingDialog> createState() => _ExitLoadingDialogState();
}

class _ExitLoadingDialogState extends State<ExitLoadingDialog> {
  @override
  void initState() {
    super.initState();
    _performShutdown();
  }

  Future<void> _performShutdown() async {
    try {
      await ServerManager().stopServer().timeout(const Duration(seconds: 3));
    } catch (_) {}

    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        await windowManager.destroy();
      } else {
        exit(0);
      }
    } catch (_) {
      exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = widget.localeCode == 'ar';

    return PopScope(
      canPop: false,
      child: Center(
        child: Container(
          width: 430,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.primaryEmerald.withValues(alpha: 0.35),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryEmerald.withValues(alpha: 0.12),
                blurRadius: 30,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.7),
                blurRadius: 40,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Glowing Spinner Icon
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryEmerald.withValues(alpha: 0.12),
                  border: Border.all(
                    color: AppColors.primaryEmerald.withValues(alpha: 0.4),
                  ),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.8,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryEmerald),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Title
              Text(
                isAr ? 'جاري تفريغ الذاكرة وإغلاق الخادم' : 'Freeing Memory & Shutting Down',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 8),

              // Subtitle
              Text(
                isAr
                    ? 'يرجى الانتظار لحظات، جاري تحرير موارد كرت الشاشة (VRAM) والذاكرة العشوائية...'
                    : 'Please wait a moment while GPU VRAM & system RAM are released...',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.white.withValues(alpha: 0.75),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

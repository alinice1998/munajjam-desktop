import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/server_manager.dart';
import '../../core/theme/app_theme.dart';
import 'exit_loading_dialog.dart';

class CustomTitleBar extends StatefulWidget {
  final String localeCode;

  const CustomTitleBar({super.key, this.localeCode = 'ar'});

  @override
  State<CustomTitleBar> createState() => _CustomTitleBarState();
}

class _CustomTitleBarState extends State<CustomTitleBar> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.addListener(this);
      _checkMaximizedState();
    }
  }

  Future<void> _checkMaximizedState() async {
    try {
      final isMax = await windowManager.isMaximized();
      if (mounted) {
        setState(() {
          _isMaximized = isMax;
        });
      }
    } catch (_) {}
  }

  @override
  void onWindowMaximize() {
    setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    setState(() => _isMaximized = false);
  }

  @override
  void onWindowRestore() {
    setState(() => _isMaximized = false);
  }

  @override
  void dispose() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  void _handleMaximizeRestore() async {
    if (_isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return const SizedBox.shrink();
    }

    final isRTL = widget.localeCode == 'ar';
    final serverManager = ServerManager();

    // Standard Windows Window Control Buttons
    final windowControls = Row(
      mainAxisSize: MainAxisSize.min,
      textDirection: TextDirection.ltr,
      children: [
        _WindowControlButton(
          icon: Icons.close_rounded,
          isClose: true,
          tooltip: 'إغلاق',
          onPressed: () {
            ExitLoadingDialog.show(context, localeCode: widget.localeCode);
          },
        ),
        _WindowControlButton(
          icon: _isMaximized ? Icons.filter_none_rounded : Icons.crop_square_rounded,
          iconSize: _isMaximized ? 12 : 14,
          tooltip: _isMaximized ? 'استعادة' : 'تكبير',
          onPressed: _handleMaximizeRestore,
        ),
        _WindowControlButton(
          icon: Icons.remove_rounded,
          tooltip: 'تصغير',
          onPressed: () => windowManager.minimize(),
        ),
      ],
    );

    // App Branding & Title Area
    final brandingArea = Row(
      textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
      children: [
        // App Icon Badge
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primaryEmerald, AppColors.primaryTeal],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryEmerald.withValues(alpha: 0.3),
                blurRadius: 6,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.auto_awesome,
            color: Colors.white,
            size: 13,
          ),
        ),
        const SizedBox(width: 8),

        // Title
        Text(
          isRTL ? 'منجم - محرر التزمين القرآني الذكي' : 'Munajjam - Neural Quran Aligner',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(width: 8),

        // Version Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: const Text(
            'v1.0.0',
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              color: AppColors.textMuted,
            ),
          ),
        ),

        const SizedBox(width: 8),

        // Hardware Acceleration Indicator Pill
        ValueListenableBuilder<bool>(
          valueListenable: serverManager.isOnlineNotifier,
          builder: (context, isOnline, _) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isOnline
                    ? AppColors.primaryEmerald.withValues(alpha: 0.12)
                    : AppColors.warningAmber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isOnline
                      ? AppColors.primaryEmerald.withValues(alpha: 0.3)
                      : AppColors.warningAmber.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.bolt_rounded,
                    size: 11,
                    color: isOnline ? AppColors.primaryEmerald : AppColors.warningAmber,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    isOnline ? 'RTX DirectML' : 'جاري التشغيل...',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isOnline ? AppColors.primaryEmerald : AppColors.warningAmber,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );

    return Container(
      height: 38,
      decoration: const BoxDecoration(
        color: Color(0xFF0C1017),
        border: Border(
          bottom: BorderSide(color: AppColors.glassBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Drag Window Header
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (details) {
                windowManager.startDragging();
              },
              onDoubleTap: _handleMaximizeRestore,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: isRTL ? Alignment.centerRight : Alignment.centerLeft,
                child: brandingArea,
              ),
            ),
          ),

          // Window Controls
          windowControls,
        ],
      ),
    );
  }
}

class _WindowControlButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final bool isClose;
  final double iconSize;

  const _WindowControlButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.isClose = false,
    this.iconSize = 14,
  });

  @override
  State<_WindowControlButton> createState() => _WindowControlButtonState();
}

class _WindowControlButtonState extends State<_WindowControlButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 44,
            height: 38,
            decoration: BoxDecoration(
              color: _isHovered
                  ? (widget.isClose ? const Color(0xFFE11D48) : Colors.white.withValues(alpha: 0.1))
                  : Colors.transparent,
            ),
            alignment: Alignment.center,
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: _isHovered && widget.isClose ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

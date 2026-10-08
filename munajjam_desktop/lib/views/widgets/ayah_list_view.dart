import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/alignment_models.dart';
import '../../providers/alignment_provider.dart';
import '../../services/audio_service.dart';

enum WordScopeFilter {
  allSurah,
  currentAyah,
  currentBreath,
}

class AyahListView extends StatefulWidget {
  final String localeCode;

  const AyahListView({super.key, this.localeCode = 'ar'});

  @override
  State<AyahListView> createState() => _AyahListViewState();
}

class _AyahListViewState extends State<AyahListView> {
  int? _expandedAyahIndex;
  bool _pinToTop = true;
  final Map<int, GlobalKey> _ayahKeys = {};
  final Map<int, GlobalKey> _breathKeys = {};
  final ScrollController _ayahScrollController = ScrollController();
  final ScrollController _breathScrollController = ScrollController();
  int? _lastPinnedAyahIndex;
  int? _lastPinnedBreathIndex;
  AlignmentGranularity? _lastGranularity;
  WordScopeFilter _wordScopeFilter = WordScopeFilter.allSurah;

  @override
  void initState() {
    super.initState();
    AudioService().positionNotifier.addListener(_onPositionChanged);
  }

  @override
  void dispose() {
    AudioService().positionNotifier.removeListener(_onPositionChanged);
    _ayahScrollController.dispose();
    _breathScrollController.dispose();
    super.dispose();
  }

  void _onPositionChanged() {
    if (!mounted || !_pinToTop) return;
    if (!AudioService().isPlaying) return; // Only auto-scroll when audio is actively playing!
    final alignProvider = context.read<AlignmentProvider>();
    final activeGranularity = alignProvider.activeGranularity;

    if (activeGranularity == AlignmentGranularity.ayah) {
      final currentIdx = alignProvider.currentSegmentIndex;
      if (currentIdx != null && currentIdx != _lastPinnedAyahIndex) {
        _lastPinnedAyahIndex = currentIdx;
        _scrollToAyah(currentIdx);
      }
    } else if (activeGranularity == AlignmentGranularity.breath) {
      final currentIdx = alignProvider.currentBreathIndex;
      if (currentIdx != null && currentIdx != _lastPinnedBreathIndex) {
        _lastPinnedBreathIndex = currentIdx;
        _scrollToBreath(currentIdx);
      }
    }
  }

  double _estimateAyahOffset(AlignmentProvider provider, int targetIndex) {
    final segments = provider.segments;
    if (segments.isEmpty || targetIndex <= 0) return 0.0;

    double offset = 0.0;
    final limit = targetIndex.clamp(0, segments.length);
    for (int i = 0; i < limit; i++) {
      final text = segments[i].text;
      final lines = (text.length / 55.0).ceil().clamp(1, 15);
      final itemHeight = 110.0 + (lines * 26.0);
      offset += itemHeight;
    }
    return offset;
  }

  double _estimateBreathOffset(AlignmentProvider provider, int targetIndex) {
    final breaths = provider.breathGroups;
    if (breaths.isEmpty || targetIndex <= 0) return 0.0;

    double offset = 0.0;
    final limit = targetIndex.clamp(0, breaths.length);
    for (int i = 0; i < limit; i++) {
      final b = breaths[i];
      final text = b.text;
      final lines = (text.length / 60.0).ceil().clamp(1, 10);
      final hasWords = b.words.isNotEmpty;
      final itemHeight = 68.0 + (lines * 24.0) + (hasWords ? 32.0 : 0.0);
      offset += itemHeight;
    }
    return offset;
  }

  void _scrollToAyah(int index, {bool force = false}) {
    if (!_pinToTop && !force) return;
    _lastPinnedAyahIndex = index;
    void doScroll([int attempts = 0]) {
      if (!mounted) return;
      final alignProvider = context.read<AlignmentProvider>();
      final key = _ayahKeys[index];
      if (key?.currentContext != null) {
        final ctx = key!.currentContext!;
        final renderObj = ctx.findRenderObject();
        final scrollable = Scrollable.maybeOf(ctx);
        if (scrollable != null && renderObj != null) {
          scrollable.position.ensureVisible(
            renderObj,
            alignment: 0.0,
            alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
          );
          return;
        }
      }

      // تمرير تراكمي ذكي نحو الآية المستهدفة إذا لم تكن في الواجهة بعد
      if (_ayahScrollController.hasClients) {
        final maxScroll = _ayahScrollController.position.maxScrollExtent;
        if (attempts == 0) {
          final targetOffset = _estimateAyahOffset(alignProvider, index);
          _ayahScrollController.jumpTo(targetOffset.clamp(0.0, maxScroll));
        } else {
          int? visibleMin;
          int? visibleMax;
          for (final e in _ayahKeys.entries) {
            if (e.value.currentContext != null) {
              if (visibleMin == null || e.key < visibleMin) visibleMin = e.key;
              if (visibleMax == null || e.key > visibleMax) visibleMax = e.key;
            }
          }
          if (visibleMin != null && visibleMax != null) {
            final cur = _ayahScrollController.offset;
            if (index < visibleMin) {
              _ayahScrollController.jumpTo((cur - 350.0).clamp(0.0, maxScroll));
            } else if (index > visibleMax) {
              _ayahScrollController.jumpTo((cur + 350.0).clamp(0.0, maxScroll));
            }
          }
        }
      }

      if (attempts < 5) {
        WidgetsBinding.instance.addPostFrameCallback((_) => doScroll(attempts + 1));
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => doScroll());
  }

  void _scrollToBreath(int index, {bool force = false}) {
    if (!_pinToTop && !force) return;
    _lastPinnedBreathIndex = index;
    void doScroll([int attempts = 0]) {
      if (!mounted) return;
      final alignProvider = context.read<AlignmentProvider>();
      final key = _breathKeys[index];
      if (key?.currentContext != null) {
        final ctx = key!.currentContext!;
        final renderObj = ctx.findRenderObject();
        final scrollable = Scrollable.maybeOf(ctx);
        if (scrollable != null && renderObj != null) {
          scrollable.position.ensureVisible(
            renderObj,
            alignment: 0.0,
            alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
          );
          return;
        }
      }

      // تمرير تراكمي ذكي نحو السكتة المستهدفة إذا لم تكن في الواجهة بعد
      if (_breathScrollController.hasClients) {
        final maxScroll = _breathScrollController.position.maxScrollExtent;
        if (attempts == 0) {
          final targetOffset = _estimateBreathOffset(alignProvider, index);
          _breathScrollController.jumpTo(targetOffset.clamp(0.0, maxScroll));
        } else {
          int? visibleMin;
          int? visibleMax;
          for (final e in _breathKeys.entries) {
            if (e.value.currentContext != null) {
              if (visibleMin == null || e.key < visibleMin) visibleMin = e.key;
              if (visibleMax == null || e.key > visibleMax) visibleMax = e.key;
            }
          }
          if (visibleMin != null && visibleMax != null) {
            final cur = _breathScrollController.offset;
            if (index < visibleMin) {
              _breathScrollController.jumpTo((cur - 350.0).clamp(0.0, maxScroll));
            } else if (index > visibleMax) {
              _breathScrollController.jumpTo((cur + 350.0).clamp(0.0, maxScroll));
            }
          }
        }
      }

      if (attempts < 5) {
        WidgetsBinding.instance.addPostFrameCallback((_) => doScroll(attempts + 1));
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => doScroll());
  }

  void _handleNavigatePrevious(AlignmentProvider alignProvider, AudioService audioService) {
    alignProvider.navigatePrevious();
    if (alignProvider.activeGranularity == AlignmentGranularity.ayah && alignProvider.currentSegmentIndex != null) {
      _scrollToAyah(alignProvider.currentSegmentIndex!);
    } else if (alignProvider.activeGranularity == AlignmentGranularity.breath && alignProvider.currentBreathIndex != null) {
      _scrollToBreath(alignProvider.currentBreathIndex!);
    }
  }

  void _handleNavigateNext(AlignmentProvider alignProvider, AudioService audioService) {
    alignProvider.navigateNext();
    if (alignProvider.activeGranularity == AlignmentGranularity.ayah && alignProvider.currentSegmentIndex != null) {
      _scrollToAyah(alignProvider.currentSegmentIndex!);
    } else if (alignProvider.activeGranularity == AlignmentGranularity.breath && alignProvider.currentBreathIndex != null) {
      _scrollToBreath(alignProvider.currentBreathIndex!);
    }
  }

  void _jumpToCurrentPlayingItem(AlignmentProvider alignProvider) {
    if (alignProvider.activeGranularity == AlignmentGranularity.ayah) {
      if (alignProvider.currentSegmentIndex != null) {
        _scrollToAyah(alignProvider.currentSegmentIndex!, force: true);
      }
    } else if (alignProvider.activeGranularity == AlignmentGranularity.breath) {
      if (alignProvider.currentBreathIndex != null) {
        _scrollToBreath(alignProvider.currentBreathIndex!, force: true);
      }
    } else {
      if (alignProvider.currentSegmentIndex != null) {
        _scrollToAyah(alignProvider.currentSegmentIndex!, force: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final alignProvider = context.watch<AlignmentProvider>();
    final isRTL = widget.localeCode == 'ar';
    final audioService = AudioService();

    final activeGranularity = alignProvider.activeGranularity;

    // مزامنة التبديل بين التبويبات (تثبيت فوري للآية أو النَّفَس الحالي في الأعلى)
    if (_lastGranularity != activeGranularity) {
      _lastGranularity = activeGranularity;
      _lastPinnedAyahIndex = null;
      _lastPinnedBreathIndex = null;
      _ayahKeys.clear();
      _breathKeys.clear();
      if (_pinToTop) {
        if (activeGranularity == AlignmentGranularity.ayah && alignProvider.currentSegmentIndex != null) {
          _scrollToAyah(alignProvider.currentSegmentIndex!);
        } else if (activeGranularity == AlignmentGranularity.breath && alignProvider.currentBreathIndex != null) {
          _scrollToBreath(alignProvider.currentBreathIndex!);
        }
      }
    }

    // مزامنة التمرير والتثبيت بالأعلى أثناء التشغيل المستمر
    if (_pinToTop && audioService.isPlaying) {
      final curSeg = alignProvider.currentSegmentIndex;
      final curBreath = alignProvider.currentBreathIndex;
      if (activeGranularity == AlignmentGranularity.ayah &&
          curSeg != null &&
          curSeg != _lastPinnedAyahIndex) {
        _lastPinnedAyahIndex = curSeg;
        _scrollToAyah(curSeg);
      } else if (activeGranularity == AlignmentGranularity.breath &&
          curBreath != null &&
          curBreath != _lastPinnedBreathIndex) {
        _lastPinnedBreathIndex = curBreath;
        _scrollToBreath(curBreath);
      }
    }

    return Focus(
      autofocus: false,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _handleNavigatePrevious(alignProvider, audioService);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _handleNavigateNext(alignProvider, audioService);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        height: 380,
        decoration: BoxDecoration(
          color: AppColors.glassCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Header with 3-Tab Granularity Switcher & Pin-to-top Toggle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceDark,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildTab(
                          AlignmentGranularity.ayah,
                          '📜 الآيات (${alignProvider.segments.length})',
                          alignProvider,
                        ),
                        _buildTab(
                          AlignmentGranularity.breath,
                          '🌬️ السكتات (${alignProvider.breathGroups.length})',
                          alignProvider,
                        ),
                        _buildTab(
                          AlignmentGranularity.word,
                          '🔤 الكلمات',
                          alignProvider,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Pin to top toggle button (Icon only)
                  Tooltip(
                    message: _pinToTop
                        ? 'تثبيت الآية المتلوة دائمًا في الأعلى: مفعّل (انقر للتعطيل)'
                        : 'تثبيت الآية المتلوة دائمًا في الأعلى: معطّل (انقر للتفعيل)',
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _pinToTop = !_pinToTop;
                        });
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: _pinToTop ? AppColors.primaryEmerald.withValues(alpha: 0.2) : AppColors.surfaceDark,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _pinToTop ? AppColors.primaryEmerald : AppColors.glassBorder,
                            width: 1.2,
                          ),
                        ),
                        child: Icon(
                          _pinToTop ? Icons.vertical_align_top_rounded : Icons.vertical_align_center_rounded,
                          size: 16,
                          color: _pinToTop ? AppColors.primaryEmerald : AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Jump to currently playing item button
                  Tooltip(
                    message: 'الانتقال إلى موضع التلاوة الحالي في القائمة',
                    child: InkWell(
                      onTap: () => _jumpToCurrentPlayingItem(alignProvider),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceDark,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.glassBorder, width: 1),
                        ),
                        child: const Icon(
                          Icons.my_location_rounded,
                          size: 16,
                          color: AppColors.primaryEmerald,
                        ),
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Arrow Navigation Hint
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.unfold_more_rounded, size: 13, color: AppColors.textMuted),
                        SizedBox(width: 4),
                        Text(
                          '▲ / ▼ للتنقل',
                          style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: AppColors.glassBorder),

            // 2. Tab Content List (Lazy rendering: only active tab is evaluated)
            Expanded(
              child: activeGranularity == AlignmentGranularity.ayah
                  ? _buildAyahTab(alignProvider, audioService, isRTL)
                  : (activeGranularity == AlignmentGranularity.breath
                      ? _buildBreathTab(alignProvider, audioService, isRTL)
                      : _buildWordTab(alignProvider, audioService, isRTL)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(AlignmentGranularity g, String label, AlignmentProvider provider) {
    final isSelected = provider.activeGranularity == g;
    return InkWell(
      onTap: () {
        provider.setGranularity(g);
        _lastPinnedAyahIndex = null;
        _lastPinnedBreathIndex = null;
        _ayahKeys.clear();
        _breathKeys.clear();
        if (_pinToTop) {
          if (g == AlignmentGranularity.ayah && provider.currentSegmentIndex != null) {
            _scrollToAyah(provider.currentSegmentIndex!);
          } else if (g == AlignmentGranularity.breath && provider.currentBreathIndex != null) {
            _scrollToBreath(provider.currentBreathIndex!);
          }
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (g == AlignmentGranularity.ayah
                  ? AppColors.primaryEmerald
                  : (g == AlignmentGranularity.breath ? AppColors.primaryTeal : const Color(0xFF6366F1)))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  // 1. AYAH TAB
  Widget _buildAyahTab(AlignmentProvider alignProvider, AudioService audioService, bool isRTL) {
    final segments = alignProvider.segments;
    if (segments.isEmpty) {
      return const Center(child: Text('لا توجد آيات محملة', style: TextStyle(color: AppColors.textMuted)));
    }

    return ListView.separated(
      controller: _ayahScrollController,
      cacheExtent: 1200,
      padding: const EdgeInsets.all(10),
      itemCount: segments.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final ayah = segments[index];
        final isSelected = index == alignProvider.currentSegmentIndex;
        final isExpanded = _expandedAyahIndex == index;

        return Container(
          key: _ayahKeys.putIfAbsent(index, () => GlobalKey()),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryEmerald.withValues(alpha: 0.12) : AppColors.surfaceDark.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.primaryEmerald.withValues(alpha: 0.5) : AppColors.glassBorder,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Main Row
              InkWell(
                onTap: () {
                  audioService.seek(ayah.start);
                  alignProvider.selectAyah(index);
                  _scrollToAyah(index);
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
                    children: [
                      // Ayah badge
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primaryEmerald : AppColors.primaryEmerald.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${ayah.ayahNumber}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : AppColors.primaryEmerald,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Text and Timings
                      Expanded(
                        child: Column(
                          crossAxisAlignment: isRTL ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                          children: [
                            Text(
                              ayah.text,
                              textDirection: TextDirection.rtl,
                              style: GoogleFonts.amiri(
                                fontSize: 16,
                                height: 1.6,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? Colors.white : AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
                              children: [
                                Text(
                                  '${ayah.start.toStringAsFixed(2)}s - ${ayah.end.toStringAsFixed(2)}s (${ayah.duration.toStringAsFixed(2)}s)',
                                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.textMuted),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: ayah.similarity >= 0.95
                                        ? AppColors.scoreHigh.withValues(alpha: 0.15)
                                        : AppColors.scoreMed.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${(ayah.similarity * 100).toStringAsFixed(0)}% دقة',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: ayah.similarity >= 0.95 ? AppColors.scoreHigh : AppColors.scoreMed,
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

              // Action Toolbar for this Ayah
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                  border: const Border(top: BorderSide(color: AppColors.glassBorder)),
                ),
                child: Row(
                  textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
                  children: [
                    // Play Ayah Only Button
                    ElevatedButton.icon(
                      onPressed: () {
                        alignProvider.selectAyah(index);
                        audioService.playSnippet(ayah.start, ayah.end);
                      },
                      icon: const Icon(Icons.play_arrow_rounded, size: 14, color: Colors.white),
                      label: const Text('الآية فقط', style: TextStyle(fontSize: 11, color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryEmerald.withValues(alpha: 0.4),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),

                    const SizedBox(width: 6),

                    // Continuous Play Button
                    OutlinedButton.icon(
                      onPressed: () {
                        audioService.seek(ayah.start);
                        alignProvider.selectAyah(index);
                        audioService.play();
                      },
                      icon: const Icon(Icons.fast_forward_rounded, size: 14, color: Colors.white),
                      label: const Text('مستمر', style: TextStyle(fontSize: 11, color: Colors.white)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        side: const BorderSide(color: AppColors.glassBorder),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),

                    const Spacer(),

                    // Expand Words Toggle
                    if (ayah.words.isNotEmpty)
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _expandedAyahIndex = isExpanded ? null : index;
                          });
                        },
                        icon: Icon(
                          isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.auto_awesome,
                          size: 14,
                          color: AppColors.primaryTeal,
                        ),
                        label: Text(
                          isExpanded ? 'إخفاء' : '${ayah.words.length} كلمات',
                          style: const TextStyle(fontSize: 11, color: AppColors.primaryTeal),
                        ),
                      ),
                  ],
                ),
              ),

              // Expanded Words Breakdown
              if (isExpanded && ayah.words.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(10),
                  color: Colors.black.withValues(alpha: 0.4),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    textDirection: TextDirection.rtl,
                    children: ayah.words.map((w) {
                      return InkWell(
                        onTap: () => audioService.playSnippet(w.start, w.end),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceDark,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.glassBorder),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.play_circle_outline, size: 12, color: AppColors.primaryEmerald),
                              const SizedBox(width: 4),
                              Text(
                                w.word,
                                style: GoogleFonts.amiri(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${(w.end - w.start).toStringAsFixed(2)}s',
                                style: const TextStyle(fontSize: 9, fontFamily: 'monospace', color: AppColors.textMuted),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // 2. BREATH TAB
  Widget _buildBreathTab(AlignmentProvider alignProvider, AudioService audioService, bool isRTL) {
    final breaths = alignProvider.breathGroups;
    if (breaths.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد بيانات سكتات (قم بإجراء التزمين الهجين لاستخراجها تلقائيًا)',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }

    return ListView.separated(
      controller: _breathScrollController,
      cacheExtent: 1200,
      padding: const EdgeInsets.all(10),
      itemCount: breaths.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final breath = breaths[index];
        final isSelected = index == alignProvider.currentBreathIndex;

        return Container(
          key: _breathKeys.putIfAbsent(index, () => GlobalKey()),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryTeal.withValues(alpha: 0.15) : AppColors.surfaceDark.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.primaryTeal.withValues(alpha: 0.5) : AppColors.glassBorder,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: InkWell(
            onTap: () {
              audioService.seek(breath.startTime);
              alignProvider.selectBreath(index);
              _scrollToBreath(index);
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top info & actions
                  Row(
                    textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primaryTeal.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'سكتة #${breath.groupIndex}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryTeal),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${breath.startTime.toStringAsFixed(2)}s - ${breath.endTime.toStringAsFixed(2)}s (${breath.duration.toStringAsFixed(2)}s)',
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.textMuted),
                      ),
                      const Spacer(),

                      // Play Breath Only
                      IconButton(
                        onPressed: () {
                          audioService.playSnippet(breath.startTime, breath.endTime);
                          alignProvider.selectBreath(index);
                        },
                        icon: const Icon(Icons.play_circle_fill_rounded, color: AppColors.primaryTeal, size: 22),
                        tooltip: 'استماع لهذا النَّفَس فقط',
                      ),

                      // Continuous play
                      IconButton(
                        onPressed: () {
                          audioService.seek(breath.startTime);
                          alignProvider.selectBreath(index);
                          audioService.play();
                        },
                        icon: const Icon(Icons.fast_forward_rounded, color: Colors.white, size: 18),
                        tooltip: 'تشغيل مستمر من هذا النَّفَس',
                      ),

                      // Split Breath
                      IconButton(
                        onPressed: () {
                          final mid = (breath.startTime + breath.endTime) / 2;
                          alignProvider.splitBreath(index, mid);
                        },
                        icon: const Icon(Icons.content_cut_rounded, color: AppColors.warningAmber, size: 16),
                        tooltip: 'تقسيم النَّفَس من المنتصف',
                      ),

                      // Merge with next
                      if (index < breaths.length - 1)
                        IconButton(
                          onPressed: () => alignProvider.mergeBreathWithNext(index),
                          icon: const Icon(Icons.merge_type_rounded, color: AppColors.primaryEmerald, size: 18),
                          tooltip: 'دمج مع النَّفَس التالي',
                        ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  // Breath Text
                  Text(
                    breath.text.isNotEmpty ? breath.text : 'مقطع نَفَس',
                    textDirection: TextDirection.rtl,
                    style: GoogleFonts.amiri(
                      fontSize: 15,
                      height: 1.6,
                      color: isSelected ? Colors.white : AppColors.textPrimary,
                    ),
                  ),

                  // Breath Words
                  if (breath.words.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      textDirection: TextDirection.rtl,
                      children: breath.words.map((w) {
                        return InkWell(
                          onTap: () => audioService.playSnippet(w.start, w.end),
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceDark,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppColors.glassBorder),
                            ),
                            child: Text(
                              w.word,
                              style: GoogleFonts.amiri(fontSize: 13, color: AppColors.textSecondary),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // 3. WORD TAB
  Widget _buildWordTab(AlignmentProvider alignProvider, AudioService audioService, bool isRTL) {
    final segments = alignProvider.segments;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Sub-header Scope Selector Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: const BoxDecoration(
            color: Color(0x18000000),
            border: Border(bottom: BorderSide(color: AppColors.glassBorder)),
          ),
          child: Row(
            textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildWordFilterBtn(
                      filter: WordScopeFilter.allSurah,
                      label: '📖 كلمات السورة كاملة',
                    ),
                    const SizedBox(width: 4),
                    _buildWordFilterBtn(
                      filter: WordScopeFilter.currentAyah,
                      label: '📜 كلمات الآية الحالية فقط',
                    ),
                    const SizedBox(width: 4),
                    _buildWordFilterBtn(
                      filter: WordScopeFilter.currentBreath,
                      label: '🌬️ كلمات النَّفَس الحالي فقط',
                    ),
                  ],
                ),
              ),
              const Spacer(),
              const Text(
                'انقر على أي كلمة للاستماع لنطقها منفردة',
                style: TextStyle(fontSize: 10, color: AppColors.textMuted),
              ),
            ],
          ),
        ),

        // Filter Content
        Expanded(
          child: _wordScopeFilter == WordScopeFilter.allSurah
              ? _buildAllSurahWords(segments, audioService, isRTL)
              : (_wordScopeFilter == WordScopeFilter.currentAyah
                  ? _buildCurrentAyahWords(alignProvider, audioService, isRTL)
                  : _buildCurrentBreathWords(alignProvider, audioService, isRTL)),
        ),
      ],
    );
  }

  Widget _buildWordFilterBtn({
    required WordScopeFilter filter,
    required String label,
  }) {
    final isSelected = _wordScopeFilter == filter;
    return InkWell(
      onTap: () {
        setState(() {
          _wordScopeFilter = filter;
        });
      },
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6366F1) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildAllSurahWords(List<AyahSegment> segments, AudioService audioService, bool isRTL) {
    if (segments.isEmpty || segments.every((s) => s.words.isEmpty)) {
      return const Center(
        child: Text('لا توجد كلمات محاذاة', style: TextStyle(color: AppColors.textMuted)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: segments.length,
      itemBuilder: (context, index) {
        final ayah = segments[index];
        if (ayah.words.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primaryEmerald.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'آية #${ayah.ayahNumber}',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primaryEmerald),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${ayah.start.toStringAsFixed(2)}s - ${ayah.end.toStringAsFixed(2)}s',
                    style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppColors.textMuted),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.play_circle_outline, size: 16, color: AppColors.primaryEmerald),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'استماع للآية كاملة',
                    onPressed: () => audioService.playSnippet(ayah.start, ayah.end),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                textDirection: TextDirection.rtl,
                children: ayah.words.map((w) => _buildWordBadge(w, audioService)).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCurrentAyahWords(AlignmentProvider alignProvider, AudioService audioService, bool isRTL) {
    final segments = alignProvider.segments;
    if (segments.isEmpty) {
      return const Center(child: Text('لا توجد آيات محملة', style: TextStyle(color: AppColors.textMuted)));
    }

    final curIdx = (alignProvider.currentSegmentIndex ?? 0).clamp(0, segments.length - 1);
    final ayah = segments[curIdx];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Current Ayah Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primaryEmerald.withValues(alpha: 0.15),
                  AppColors.surfaceDark.withValues(alpha: 0.7),
                ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primaryEmerald.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryEmerald,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'الآية الحالية: #${ayah.ayahNumber}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${ayah.start.toStringAsFixed(2)}s - ${ayah.end.toStringAsFixed(2)}s (${ayah.duration.toStringAsFixed(2)}s)',
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.textMuted),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded, size: 20, color: AppColors.textSecondary),
                      tooltip: 'الآية السابقة',
                      onPressed: curIdx > 0
                          ? () {
                              alignProvider.selectAyah(curIdx - 1);
                              audioService.seek(segments[curIdx - 1].start);
                            }
                          : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textSecondary),
                      tooltip: 'الآية التالية',
                      onPressed: curIdx < segments.length - 1
                          ? () {
                              alignProvider.selectAyah(curIdx + 1);
                              audioService.seek(segments[curIdx + 1].start);
                            }
                          : null,
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton.icon(
                      onPressed: () {
                        alignProvider.selectAyah(curIdx);
                        audioService.playSnippet(ayah.start, ayah.end);
                      },
                      icon: const Icon(Icons.play_arrow_rounded, size: 14, color: Colors.white),
                      label: const Text('استماع للآية', style: TextStyle(fontSize: 11, color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryEmerald,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  ayah.text,
                  textDirection: TextDirection.rtl,
                  style: GoogleFonts.amiri(
                    fontSize: 18,
                    height: 1.7,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Words list header
          Row(
            textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
            children: [
              Text(
                'كلمات الآية (${ayah.words.length} كلمة):',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
              ),
              const Spacer(),
              Text(
                'دقة المطابقة: ${(ayah.similarity * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 11, color: AppColors.primaryEmerald),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (ayah.words.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('لا توجد كلمات محاذاة لهذه الآية', style: TextStyle(color: AppColors.textMuted)),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              textDirection: TextDirection.rtl,
              children: ayah.words.map((w) => _buildWordBadge(w, audioService, large: true)).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildCurrentBreathWords(AlignmentProvider alignProvider, AudioService audioService, bool isRTL) {
    final breaths = alignProvider.breathGroups;
    if (breaths.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد بيانات سكتات (قم بإجراء التزمين الهجين لاستخراجها تلقائيًا)',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }

    final curIdx = (alignProvider.currentBreathIndex ?? 0).clamp(0, breaths.length - 1);
    final breath = breaths[curIdx];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Current Breath Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primaryTeal.withValues(alpha: 0.18),
                  AppColors.surfaceDark.withValues(alpha: 0.7),
                ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primaryTeal.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryTeal,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'النَّفَس الحالي: سكتة #${breath.groupIndex}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${breath.startTime.toStringAsFixed(2)}s - ${breath.endTime.toStringAsFixed(2)}s (${breath.duration.toStringAsFixed(2)}s)',
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.textMuted),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded, size: 20, color: AppColors.textSecondary),
                      tooltip: 'النَّفَس السابق',
                      onPressed: curIdx > 0
                          ? () {
                              alignProvider.selectBreath(curIdx - 1);
                              audioService.seek(breaths[curIdx - 1].startTime);
                            }
                          : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textSecondary),
                      tooltip: 'النَّفَس التالي',
                      onPressed: curIdx < breaths.length - 1
                          ? () {
                              alignProvider.selectBreath(curIdx + 1);
                              audioService.seek(breaths[curIdx + 1].startTime);
                            }
                          : null,
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton.icon(
                      onPressed: () {
                        alignProvider.selectBreath(curIdx);
                        audioService.playSnippet(breath.startTime, breath.endTime);
                      },
                      icon: const Icon(Icons.play_arrow_rounded, size: 14, color: Colors.white),
                      label: const Text('استماع للنَّفَس', style: TextStyle(fontSize: 11, color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryTeal,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  breath.text.isNotEmpty ? breath.text : 'مقطع نَفَس',
                  textDirection: TextDirection.rtl,
                  style: GoogleFonts.amiri(
                    fontSize: 18,
                    height: 1.7,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Words list header
          Row(
            textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
            children: [
              Text(
                'كلمات هذا النَّفَس (${breath.words.length} كلمة):',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
              ),
              if (breath.ayahNumbers.isNotEmpty) ...[
                const Spacer(),
                Text(
                  'الآيات المرتبطة: ${breath.ayahNumbers.join(', ')}',
                  style: const TextStyle(fontSize: 11, color: AppColors.primaryTeal),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),

          if (breath.words.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('لا توجد كلمات مسجلة لهذا النَّفَس', style: TextStyle(color: AppColors.textMuted)),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              textDirection: TextDirection.rtl,
              children: breath.words.map((w) => _buildWordBadge(w, audioService, large: true)).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildWordBadge(WordSegment w, AudioService audioService, {bool large = false}) {
    return InkWell(
      onTap: () => audioService.playSnippet(w.start, w.end),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: large ? 12 : 8, vertical: large ? 8 : 5),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.play_circle_outline, size: 12, color: AppColors.primaryEmerald),
                const SizedBox(width: 4),
                Text(
                  w.word,
                  style: GoogleFonts.amiri(
                    fontSize: large ? 16 : 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${w.start.toStringAsFixed(2)}s - ${w.end.toStringAsFixed(2)}s',
              style: TextStyle(
                fontSize: large ? 10 : 9,
                fontFamily: 'monospace',
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

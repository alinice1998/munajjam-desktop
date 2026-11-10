import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/alignment_models.dart';
import '../../providers/alignment_provider.dart';
import '../../services/audio_service.dart';

class AyahListView extends StatefulWidget {
  final String localeCode;

  const AyahListView({super.key, this.localeCode = 'ar'});

  @override
  State<AyahListView> createState() => _AyahListViewState();
}

class _AyahListViewState extends State<AyahListView> {
  int? _expandedAyahIndex;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _listController = ScrollController();
  int _anchorIndex = 0;
  String? _anchorGroup;
  String? _lastFollowed;
  bool _followPlayback = true;

  @override
  void dispose() {
    _focusNode.dispose();
    _listController.dispose();
    super.dispose();
  }

  void _locateCurrent() {
    final provider = context.read<AlignmentProvider>();
    final level = provider.activeGranularity;
    int? index = level == AlignmentGranularity.ayah
        ? provider.currentSegmentIndex
        : level == AlignmentGranularity.breath
        ? provider.currentBreathIndex
        : provider.visibleWordEntries.indexWhere(
            (e) => e.segment.start == provider.currentWordStart,
          );
    if (index == null || index < 0 || !_listController.hasClients) return;
    if (level == AlignmentGranularity.word) {
      _listController.jumpTo(
        (index * 96.0).clamp(0.0, _listController.position.maxScrollExtent),
      );
    } else {
      setState(() => _anchorIndex = index);
      _listController.jumpTo(0);
    }
  }

  Widget _trackedList({
    required int itemCount,
    required int? activeIndex,
    required Widget Function(BuildContext, int) itemBuilder,
  }) {
    final provider = context.read<AlignmentProvider>();
    final prefix = provider.activeGranularity.name;
    final followKey =
        '$prefix:${provider.alignmentRevision}:${provider.wordListScope.name}:${provider.currentSegmentIndex}:${provider.currentBreathIndex}:$activeIndex';
    if (_anchorGroup != prefix) {
      _anchorGroup = prefix;
      _anchorIndex = activeIndex ?? 0;
    }
    _anchorIndex = itemCount == 0 ? 0 : _anchorIndex.clamp(0, itemCount - 1);
    if (activeIndex != null &&
        followKey != _lastFollowed &&
        (!AudioService().isPlaying || _followPlayback)) {
      _lastFollowed = followKey;
      if (prefix != 'word') _anchorIndex = activeIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !_listController.hasClients ||
            _lastFollowed != followKey ||
            (AudioService().isPlaying && !_followPlayback)) {
          return;
        }
        if (prefix == 'word') {
          _listController.jumpTo(
            (activeIndex * 96.0).clamp(
              0.0,
              _listController.position.maxScrollExtent,
            ),
          );
          return;
        }
        _listController.jumpTo(0);
      });
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (prefix == 'word') {
          return ListView.builder(
            controller: _listController,
            itemExtent: 96,
            padding: EdgeInsets.fromLTRB(10, 10, 10, constraints.maxHeight),
            itemCount: itemCount,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: itemBuilder(context, index),
            ),
          );
        }
        const centerKey = ValueKey('alignment_list_center');
        Widget row(int index) => Padding(
          key: ValueKey('alignment_row_${prefix}_$index'),
          padding: const EdgeInsets.only(bottom: 8),
          child: itemBuilder(context, index),
        );
        // Anchor directly at the selected index; both sides are lazy slivers.
        // Reaching a distant verse never lays out all preceding verses.
        return CustomScrollView(
          controller: _listController,
          center: centerKey,
          cacheExtent: 180,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => row(_anchorIndex - index - 1),
                  childCount: _anchorIndex,
                ),
              ),
            ),
            SliverPadding(
              key: centerKey,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => index == itemCount - _anchorIndex
                      ? SizedBox(height: constraints.maxHeight)
                      : row(_anchorIndex + index),
                  childCount: itemCount - _anchorIndex + 1,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final alignProvider = context.watch<AlignmentProvider>();
    final isRTL = widget.localeCode == 'ar';
    final audioService = AudioService();

    final activeGranularity = alignProvider.activeGranularity;

    return Focus(
      focusNode: _focusNode,
      child: Listener(
        onPointerDown: (_) => _focusNode.requestFocus(),
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
              // 1. Header with 3-Tab Granularity Switcher
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    textDirection: isRTL
                        ? TextDirection.rtl
                        : TextDirection.ltr,
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
                      IconButton(
                        key: const ValueKey('follow_current_ayah'),
                        tooltip: _followPlayback
                            ? 'إيقاف تثبيت الآية أعلى القائمة'
                            : 'تفعيل تثبيت الآية أعلى القائمة',
                        onPressed: () => setState(() {
                          _followPlayback = !_followPlayback;
                          if (_followPlayback) _lastFollowed = null;
                        }),
                        icon: Icon(
                          Icons.vertical_align_top,
                          color: _followPlayback
                              ? AppColors.primaryEmerald
                              : AppColors.textMuted,
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('locate_current_item'),
                        tooltip: 'الانتقال إلى الموضع الحالي',
                        icon: const Icon(
                          Icons.my_location,
                          color: AppColors.accentCyan,
                        ),
                        onPressed: _locateCurrent,
                      ),
                      Text(
                        'انقر للتشغيل والمزامنة',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const Divider(height: 1, color: AppColors.glassBorder),

              // 2. Tab Content List
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
      ),
    );
  }

  Widget _buildTab(
    AlignmentGranularity g,
    String label,
    AlignmentProvider provider,
  ) {
    final isSelected = provider.activeGranularity == g;
    return InkWell(
      onTap: () => provider.setGranularity(g),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (g == AlignmentGranularity.ayah
                    ? AppColors.primaryEmerald
                    : (g == AlignmentGranularity.breath
                          ? AppColors.primaryTeal
                          : const Color(0xFF6366F1)))
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
  Widget _buildAyahTab(
    AlignmentProvider alignProvider,
    AudioService audioService,
    bool isRTL,
  ) {
    final segments = alignProvider.segments;
    if (segments.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد آيات محملة',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }

    return _trackedList(
      itemCount: segments.length,
      activeIndex: alignProvider.currentSegmentIndex,
      itemBuilder: (context, index) {
        final ayah = segments[index];
        final isSelected = index == alignProvider.currentSegmentIndex;
        final isExpanded = _expandedAyahIndex == index;

        return Container(
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primaryEmerald.withValues(alpha: 0.12)
                : AppColors.surfaceDark.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? AppColors.primaryEmerald.withValues(alpha: 0.5)
                  : AppColors.glassBorder,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Main Row
              InkWell(
                onTap: () {
                  alignProvider.selectAyah(index);
                  audioService.seek(ayah.start);
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    textDirection: isRTL
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    children: [
                      // Ayah badge
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primaryEmerald
                              : AppColors.primaryEmerald.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${ayah.ayahNumber}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? Colors.white
                                : AppColors.primaryEmerald,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Text and Timings
                      Expanded(
                        child: Column(
                          crossAxisAlignment: isRTL
                              ? CrossAxisAlignment.start
                              : CrossAxisAlignment.end,
                          children: [
                            Text(
                              ayah.text,
                              textDirection: TextDirection.rtl,
                              style: GoogleFonts.amiri(
                                fontSize: 16,
                                height: 1.6,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isSelected
                                    ? Colors.white
                                    : AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              textDirection: isRTL
                                  ? TextDirection.rtl
                                  : TextDirection.ltr,
                              children: [
                                Text(
                                  '${ayah.start.toStringAsFixed(2)}s - ${ayah.end.toStringAsFixed(2)}s (${ayah.duration.toStringAsFixed(2)}s)',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                    color: AppColors.textMuted,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: ayah.reliability >= 0.95
                                        ? AppColors.scoreHigh.withValues(
                                            alpha: 0.15,
                                          )
                                        : AppColors.scoreMed.withValues(
                                            alpha: 0.15,
                                          ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    ayah.reliability.isFinite
                                        ? '${(ayah.reliability * 100).toStringAsFixed(0)}% موثوقية'
                                        : 'الموثوقية غير متاحة',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: ayah.reliability >= 0.95
                                          ? AppColors.scoreHigh
                                          : AppColors.scoreMed,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(12),
                  ),
                  border: const Border(
                    top: BorderSide(color: AppColors.glassBorder),
                  ),
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
                      icon: const Icon(
                        Icons.play_arrow_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'الآية فقط',
                        style: TextStyle(fontSize: 11, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryEmerald.withValues(
                          alpha: 0.4,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        minimumSize: Size.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),

                    const SizedBox(width: 6),

                    // Continuous Play Button
                    OutlinedButton.icon(
                      onPressed: () {
                        alignProvider.selectAyah(index);
                        audioService.seek(ayah.start);
                        audioService.play();
                      },
                      icon: const Icon(
                        Icons.fast_forward_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'مستمر',
                        style: TextStyle(fontSize: 11, color: Colors.white),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        minimumSize: Size.zero,
                        side: const BorderSide(color: AppColors.glassBorder),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
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
                          isExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.auto_awesome,
                          size: 14,
                          color: AppColors.primaryTeal,
                        ),
                        label: Text(
                          isExpanded ? 'إخفاء' : '${ayah.words.length} كلمات',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.primaryTeal,
                          ),
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceDark,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.glassBorder),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.play_circle_outline,
                                size: 12,
                                color: AppColors.primaryEmerald,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                w.word,
                                style: GoogleFonts.amiri(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${(w.end - w.start).toStringAsFixed(2)}s',
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontFamily: 'monospace',
                                  color: AppColors.textMuted,
                                ),
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
  Widget _buildBreathTab(
    AlignmentProvider alignProvider,
    AudioService audioService,
    bool isRTL,
  ) {
    final breaths = alignProvider.breathGroups;
    if (breaths.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد بيانات سكتات (قم بإجراء التزمين الهجين لاستخراجها تلقائياً)',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }

    return _trackedList(
      itemCount: breaths.length,
      activeIndex: alignProvider.currentBreathIndex,
      itemBuilder: (context, index) {
        final breath = breaths[index];
        final isSelected = index == alignProvider.currentBreathIndex;

        return GestureDetector(
          key: ValueKey('breath_row_$index'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            alignProvider.selectBreath(index);
            audioService.seek(breath.startTime);
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primaryTeal.withValues(alpha: 0.15)
                  : AppColors.surfaceDark.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? AppColors.primaryTeal.withValues(alpha: 0.5)
                    : AppColors.glassBorder,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top info & actions
                Row(
                  textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryTeal.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'سكتة #${breath.groupIndex}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryTeal,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${breath.startTime.toStringAsFixed(2)}s - ${breath.endTime.toStringAsFixed(2)}s (${breath.duration.toStringAsFixed(2)}s)',
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: AppColors.textMuted,
                      ),
                    ),
                    const Spacer(),

                    // Play Breath Only
                    IconButton(
                      onPressed: () {
                        alignProvider.selectBreath(index);
                        audioService.playSnippet(
                          breath.startTime,
                          breath.endTime,
                        );
                      },
                      icon: const Icon(
                        Icons.play_circle_fill_rounded,
                        color: AppColors.primaryTeal,
                        size: 22,
                      ),
                      tooltip: 'استماع لهذا النَّفَس فقط',
                    ),

                    // Continuous play
                    IconButton(
                      onPressed: () {
                        alignProvider.selectBreath(index);
                        audioService.seek(breath.startTime);
                        audioService.play();
                      },
                      icon: const Icon(
                        Icons.fast_forward_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      tooltip: 'تشغيل مستمر من هذا النَّفَس',
                    ),

                    // Split Breath
                    IconButton(
                      onPressed: () {
                        final mid = (breath.startTime + breath.endTime) / 2;
                        alignProvider.splitBreath(index, mid);
                      },
                      icon: const Icon(
                        Icons.content_cut_rounded,
                        color: AppColors.warningAmber,
                        size: 16,
                      ),
                      tooltip: 'تقسيم النَّفَس من المنتصف',
                    ),

                    // Merge with next
                    if (index < breaths.length - 1)
                      IconButton(
                        onPressed: () =>
                            alignProvider.mergeBreathWithNext(index),
                        icon: const Icon(
                          Icons.merge_type_rounded,
                          color: AppColors.primaryEmerald,
                          size: 18,
                        ),
                        tooltip: 'دمج مع النَّفَس التالي',
                      ),
                  ],
                ),

                const SizedBox(height: 6),

                Text(
                  breath.reliability.isFinite
                      ? 'الموثوقية ${(breath.reliability * 100).toStringAsFixed(0)}%'
                      : 'الموثوقية غير متاحة',
                  style: TextStyle(
                    fontSize: 11,
                    color:
                        alignProvider.needsReview(
                          AlignmentGranularity.breath,
                          breath.reliability,
                          isError:
                              breath.isError ||
                              breath.words.any((w) => w.isError),
                        )
                        ? AppColors.scoreLow
                        : AppColors.textSecondary,
                  ),
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceDark,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppColors.glassBorder),
                          ),
                          child: Text(
                            w.word,
                            style: GoogleFonts.amiri(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _wordScopeTab(WordListScope scope, AlignmentProvider provider) {
    final selected = scope == provider.wordListScope;
    final label = switch (scope) {
      WordListScope.surah => 'السورة كاملة',
      WordListScope.ayah => 'الآية الحالية',
      WordListScope.breath => 'النَّفَس الحالي',
    };
    return Semantics(
      selected: selected,
      button: true,
      child: Tooltip(
        message: label,
        child: Material(
          color: selected ? AppColors.primaryTeal : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            key: ValueKey('word_scope_${scope.name}'),
            borderRadius: BorderRadius.circular(6),
            onTap: () => provider.setWordListScope(scope),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: selected ? Colors.white : AppColors.textSecondary,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _wordScopeContext(AlignmentProvider provider) {
    String title;
    String text;
    if (provider.wordListScope == WordListScope.ayah) {
      final index = provider.currentSegmentIndex;
      title = index == null
          ? 'لا توجد آية حالية'
          : 'الآية ${provider.segments[index].ayahNumber}';
      text = index == null ? '' : provider.segments[index].text;
    } else {
      final index = provider.currentBreathIndex;
      title = index == null
          ? 'لا يوجد نَفَس حالي'
          : 'النَّفَس ${provider.breathGroups[index].groupIndex}';
      text = index == null ? '' : provider.breathGroups[index].text;
    }
    return Container(
      key: const ValueKey('word_scope_context'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      padding: const EdgeInsets.all(10),
      constraints: const BoxConstraints(maxHeight: 118),
      decoration: BoxDecoration(
        color: AppColors.primaryTeal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.primaryTeal.withValues(alpha: 0.25),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.primaryTeal,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (text.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                text,
                textDirection: TextDirection.rtl,
                style: GoogleFonts.amiri(
                  fontSize: 16,
                  height: 1.5,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 3. WORD TAB
  Widget _buildWordTab(
    AlignmentProvider alignProvider,
    AudioService audioService,
    bool isRTL,
  ) {
    final words = alignProvider.visibleWordEntries;
    final active = words.indexWhere(
      (e) => e.segment.start == alignProvider.currentWordStart,
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Container(
            key: const ValueKey('word_list_scope'),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Row(
              children: [
                for (final scope in [
                  WordListScope.surah,
                  WordListScope.ayah,
                  WordListScope.breath,
                ])
                  Expanded(child: _wordScopeTab(scope, alignProvider)),
              ],
            ),
          ),
        ),
        if (alignProvider.wordListScope != WordListScope.surah)
          _wordScopeContext(alignProvider),
        Expanded(
          child: words.isEmpty
              ? const Center(
                  child: Text(
                    'لا توجد كلمات في الموضع الحالي',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                )
              : _trackedList(
                  itemCount: words.length,
                  activeIndex: active < 0 ? null : active,
                  itemBuilder: (context, index) {
                    final entry = words[index];
                    final word = entry.segment;
                    final selected = index == active;
                    final review = alignProvider.needsReview(
                      AlignmentGranularity.word,
                      word.reliability,
                      isError: word.isError,
                    );
                    final score = word.reliability.isFinite
                        ? '${(word.reliability * 100).toStringAsFixed(0)}%'
                        : 'غير متاحة';
                    return Material(
                      color: Colors.transparent,
                      child: ListTile(
                        key: ValueKey('word_row_${word.start}'),
                        selected: selected,
                        selectedTileColor: AppColors.primaryEmerald.withValues(
                          alpha: 0.15,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        leading: Text(
                          entry.ayahIndex == null
                              ? '${index + 1}'
                              : '${alignProvider.segments[entry.ayahIndex!].ayahNumber}:${entry.wordIndex! + 1}',
                        ),
                        title: Text(
                          word.word,
                          textDirection: TextDirection.rtl,
                          style: GoogleFonts.amiri(
                            fontSize: 20,
                            color: review
                                ? AppColors.scoreLow
                                : selected
                                ? AppColors.primaryEmerald
                                : Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          '${word.start.toStringAsFixed(2)}s – ${word.end.toStringAsFixed(2)}s • الموثوقية $score',
                        ),
                        trailing: Icon(
                          review
                              ? Icons.error_outline
                              : word.isRepetition
                              ? Icons.repeat
                              : Icons.play_arrow_rounded,
                          color: review ? AppColors.scoreLow : null,
                        ),
                        onTap: () {
                          if (entry.ayahIndex != null &&
                              entry.wordIndex != null) {
                            alignProvider.selectWord(
                              entry.ayahIndex!,
                              entry.wordIndex!,
                            );
                          } else {
                            alignProvider.updateCurrentTime(word.start);
                          }
                          audioService.playSnippet(word.start, word.end);
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/localization/app_locale.dart';
import '../../core/theme/app_theme.dart';
import '../../models/alignment_models.dart';
import '../../providers/alignment_provider.dart';
import '../../services/audio_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'waveform_painter.dart';
import 'repetitions_modal.dart';

enum MarkerActionMode {
  moveNearest,
  addNew,
}

class WaveformEditor extends StatefulWidget {
  final String localeCode;

  const WaveformEditor({super.key, this.localeCode = 'ar'});

  @override
  State<WaveformEditor> createState() => _WaveformEditorState();
}

class _WaveformEditorState extends State<WaveformEditor> {
  final ScrollController _scrollController = ScrollController();
  MarkerActionMode _markerMode = MarkerActionMode.moveNearest;
  double _pixelsPerSecond = 60.0;
  final double _minPps = 20.0;
  final double _maxPps = 250.0;
  double _waveformHeight = 180.0;
  final double _minWaveformHeight = 120.0;
  final double _maxWaveformHeight = 500.0;

  int? _draggingIndex;
  int? _draggingWordAyahIndex;
  int? _draggingWordIndex;
  bool _isDraggingStart = false;
  double? _dragCurrentTime;

  int? _hoveredIndex;
  bool? _hoveredIsStart;
  MouseCursor _currentCursor = SystemMouseCursors.basic;

  bool _autoScrollEnabled = true;

  @override
  void initState() {
    super.initState();
    AudioService().positionNotifier.addListener(_onPositionChanged);
  }

  @override
  void dispose() {
    AudioService().positionNotifier.removeListener(_onPositionChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onPositionChanged() {
    if (!_autoScrollEnabled || !AudioService().isPlaying || !_scrollController.hasClients) return;

    final currentSec = AudioService().currentSeconds;
    if (currentSec.isNaN || currentSec < 0) return;

    final position = _scrollController.position;
    if (!position.hasViewportDimension || position.viewportDimension <= 0) return;

    final playheadX = currentSec * _pixelsPerSecond;
    final viewportWidth = position.viewportDimension;
    final currentScroll = _scrollController.offset;
    if (currentScroll.isNaN) return;

    final maxScroll = position.maxScrollExtent;
    if (maxScroll.isNaN || maxScroll < 0) return;

    // Keep playhead within the center 50% of the visible viewport
    if (playheadX < currentScroll + 50 || playheadX > currentScroll + viewportWidth - 50) {
      final targetScroll = (playheadX - viewportWidth / 2).clamp(0.0, maxScroll);
      if (!targetScroll.isNaN && (targetScroll - currentScroll).abs() > 1.0) {
        _scrollController.jumpTo(targetScroll);
      }
    }
  }

  void _executeMarkerAction(AlignmentProvider alignProvider) {
    final currentSec = AudioService().currentSeconds;
    if (_markerMode == MarkerActionMode.moveNearest) {
      alignProvider.moveNearestMarkerTo(currentSec);
    } else {
      alignProvider.addNewMarkerAt(currentSec);
    }
  }

  double _getDynamicMinPps(double totalDuration, double viewportWidth) {
    if (totalDuration <= 0 || viewportWidth <= 0) return 1.0;
    final fitPps = viewportWidth / totalDuration;
    return (fitPps * 0.98).clamp(0.01, 30.0);
  }

  void _fitEntireSurah(double totalDuration, double viewportWidth) {
    if (totalDuration <= 0 || viewportWidth <= 0) return;
    final fitPps = (viewportWidth / totalDuration).clamp(0.01, _maxPps);
    setState(() {
      _pixelsPerSecond = fitPps;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
    });
  }

  void _handleWheelZoom(PointerScrollEvent event, double mouseViewportX, {double totalDuration = 0, double viewportWidth = 0}) {
    final scrollDelta = event.scrollDelta.dy;
    final zoomFactor = scrollDelta > 0 ? 0.85 : 1.15;
    final oldPps = _pixelsPerSecond;
    final minLimit = (totalDuration > 0 && viewportWidth > 0)
        ? _getDynamicMinPps(totalDuration, viewportWidth)
        : _minPps;
    final newPps = (oldPps * zoomFactor).clamp(minLimit, _maxPps);

    if ((newPps - oldPps).abs() > 0.05) {
      final currentScroll = _scrollController.hasClients ? _scrollController.offset : 0.0;
      final mouseAbsoluteX = currentScroll + mouseViewportX;
      final mouseTimeSec = mouseAbsoluteX / oldPps;

      setState(() {
        _pixelsPerSecond = newPps;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          final newScroll = (mouseTimeSec * newPps - mouseViewportX).clamp(
            0.0,
            _scrollController.position.maxScrollExtent,
          );
          _scrollController.jumpTo(newScroll);
        }
      });
    }
  }

  void _scrollBy(double delta) {
    if (!_scrollController.hasClients) return;
    final target = (_scrollController.offset + delta).clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(target, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
  }

  void _ensureTimeVisible(double timeSec) {
    if (!_scrollController.hasClients) return;
    final targetX = timeSec * _pixelsPerSecond;
    final currentOffset = _scrollController.offset;
    final viewWidth = _scrollController.position.viewportDimension;
    if (targetX < currentOffset + 50 || targetX > currentOffset + viewWidth - 50) {
      final targetScroll = (targetX - viewWidth / 2).clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.animateTo(targetScroll, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  void _centerOnCurrentPosition() {
    if (!_scrollController.hasClients) return;
    final currentSec = AudioService().currentSeconds;
    final targetX = currentSec * _pixelsPerSecond;
    final viewWidth = _scrollController.position.viewportDimension;
    final targetScroll = (targetX - viewWidth / 2).clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(targetScroll, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  void _openRepetitionsModal(BuildContext context, AlignmentProvider alignProvider) {
    showDialog(
      context: context,
      builder: (ctx) => RepetitionsModal(
        localeCode: widget.localeCode,
        onNavigate: (timestamp) {
          AudioService().seek(timestamp);
          _ensureTimeVisible(timestamp);
          alignProvider.updateCurrentTime(timestamp);
        },
      ),
    );
  }

  void _handleStepBackward(AlignmentProvider alignProvider) {
    alignProvider.stepBackward();
    _ensureTimeVisible(AudioService().currentSeconds);
  }

  void _handleStepForward(AlignmentProvider alignProvider) {
    alignProvider.stepForward();
    _ensureTimeVisible(AudioService().currentSeconds);
  }

  void _jumpToNextRepetition(AlignmentProvider alignProvider) {
    final next = alignProvider.getNextRepetition(AudioService().currentSeconds);
    if (next != null) {
      AudioService().seek(next);
      _ensureTimeVisible(next);
    }
  }

  void _jumpToPrevRepetition(AlignmentProvider alignProvider) {
    final prev = alignProvider.getPrevRepetition(AudioService().currentSeconds);
    if (prev != null) {
      AudioService().seek(prev);
      _ensureTimeVisible(prev);
    }
  }

  void _jumpToNextError(AlignmentProvider alignProvider) {
    final next = alignProvider.getNextError(AudioService().currentSeconds);
    if (next != null) {
      AudioService().seek(next);
      _ensureTimeVisible(next);
    }
  }

  void _jumpToPrevError(AlignmentProvider alignProvider) {
    final prev = alignProvider.getPrevError(AudioService().currentSeconds);
    if (prev != null) {
      AudioService().seek(prev);
      _ensureTimeVisible(prev);
    }
  }

  void _handleSeekTap(TapDownDetails details, double totalDuration, AlignmentProvider alignProvider) {
    final x = details.localPosition.dx;
    final targetSec = (x / _pixelsPerSecond).clamp(0.0, totalDuration);
    AudioService().seek(targetSec);

    // Update active selection
    if (alignProvider.activeGranularity == AlignmentGranularity.ayah) {
      for (int i = 0; i < alignProvider.segments.length; i++) {
        final seg = alignProvider.segments[i];
        if (targetSec >= seg.start && targetSec <= seg.end) {
          alignProvider.selectAyah(i);
          break;
        }
      }
    } else if (alignProvider.activeGranularity == AlignmentGranularity.breath) {
      for (int i = 0; i < alignProvider.breathGroups.length; i++) {
        final bg = alignProvider.breathGroups[i];
        if (targetSec >= bg.startTime && targetSec <= bg.endTime) {
          alignProvider.selectBreath(i);
          break;
        }
      }
    }
  }

  void _handleSecondaryTap(TapDownDetails details, AlignmentProvider alignProvider) {
    final x = details.localPosition.dx;
    final clickSec = x / _pixelsPerSecond;
    _showContextMenu(details.globalPosition, clickSec, alignProvider);
  }

  void _showContextMenu(Offset globalPos, double clickSec, AlignmentProvider alignProvider) {
    int? foundAyahIdx;
    AyahSegment? foundAyah;
    for (int i = 0; i < alignProvider.segments.length; i++) {
      if (clickSec >= alignProvider.segments[i].start && clickSec <= alignProvider.segments[i].end) {
        foundAyahIdx = i;
        foundAyah = alignProvider.segments[i];
        break;
      }
    }

    int? foundBreathIdx;
    BreathGroup? foundBreath;
    for (int i = 0; i < alignProvider.breathGroups.length; i++) {
      if (clickSec >= alignProvider.breathGroups[i].startTime && clickSec <= alignProvider.breathGroups[i].endTime) {
        foundBreathIdx = i;
        foundBreath = alignProvider.breathGroups[i];
        break;
      }
    }

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(globalPos.dx, globalPos.dy, globalPos.dx + 1, globalPos.dy + 1),
      color: AppColors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.glassBorder),
      ),
      items: [
        if (foundAyah != null) ...[
          PopupMenuItem(
            value: 'play_ayah',
            child: Row(
              children: [
                const Icon(Icons.play_circle_fill_rounded, color: AppColors.primaryEmerald, size: 18),
                const SizedBox(width: 8),
                Text('تشغيل آية ${foundAyah.ayahNumber} فقط'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'edit_ayah',
            child: const Row(
              children: [
                Icon(Icons.edit_calendar_rounded, color: AppColors.accentCyan, size: 18),
                SizedBox(width: 8),
                Text('تعديل توقيت الآية'),
              ],
            ),
          ),
        ],
        if (foundBreath != null) ...[
          PopupMenuItem(
            value: 'play_breath',
            child: Row(
              children: [
                const Icon(Icons.air_rounded, color: AppColors.primaryTeal, size: 18),
                const SizedBox(width: 8),
                Text('تشغيل سكتة ${foundBreath.groupIndex} فقط'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'split_breath',
            child: Row(
              children: [
                const Icon(Icons.content_cut_rounded, color: AppColors.warningAmber, size: 18),
                const SizedBox(width: 8),
                Text('تقسيم السكتة هنا (${clickSec.toStringAsFixed(2)}s)'),
              ],
            ),
          ),
          if (foundBreathIdx != null && foundBreathIdx < alignProvider.breathGroups.length - 1)
            PopupMenuItem(
              value: 'merge_breath',
              child: const Row(
                children: [
                  Icon(Icons.merge_type_rounded, color: AppColors.primaryEmerald, size: 18),
                  SizedBox(width: 8),
                  Text('دمج مع السكتة التالية'),
                ],
              ),
            ),
        ],
        PopupMenuItem(
          value: 'play_continuous',
          child: const Row(
            children: [
              Icon(Icons.fast_forward_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('تشغيل مستمر من هذا الموضع'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'zoom_region',
          child: const Row(
            children: [
              Icon(Icons.center_focus_strong_rounded, color: AppColors.accentGold, size: 18),
              SizedBox(width: 8),
              Text('تكبير وتوسيط المقطع'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      final audioService = AudioService();

      if (value == 'play_ayah' && foundAyah != null) {
        alignProvider.selectAyah(foundAyahIdx!);
        audioService.playSnippet(foundAyah.start, foundAyah.end);
      } else if (value == 'play_breath' && foundBreath != null) {
        alignProvider.selectBreath(foundBreathIdx!);
        audioService.playSnippet(foundBreath.startTime, foundBreath.endTime);
      } else if (value == 'edit_ayah' && foundAyah != null) {
        _showEditDialog(
          title: 'تعديل توقيت آية ${foundAyah.ayahNumber}',
          initialStart: foundAyah.start,
          initialEnd: foundAyah.end,
          onSave: (s, e) => alignProvider.updateAyahSegment(foundAyahIdx!, start: s, end: e),
        );
      } else if (value == 'split_breath' && foundBreathIdx != null) {
        alignProvider.splitBreath(foundBreathIdx, clickSec);
      } else if (value == 'merge_breath' && foundBreathIdx != null) {
        alignProvider.mergeBreathWithNext(foundBreathIdx);
      } else if (value == 'play_continuous') {
        audioService.seek(clickSec);
        audioService.play();
      } else if (value == 'zoom_region') {
        final start = foundAyah?.start ?? foundBreath?.startTime ?? clickSec;
        setState(() {
          _pixelsPerSecond = 120.0;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              (start * _pixelsPerSecond - 100).clamp(0.0, _scrollController.position.maxScrollExtent),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }
        });
      }
    });
  }

  void _handleDoubleTapEdit(TapDownDetails details, AlignmentProvider alignProvider) {
    final x = details.localPosition.dx;
    final clickSec = x / _pixelsPerSecond;

    if (alignProvider.activeGranularity == AlignmentGranularity.ayah) {
      for (int i = 0; i < alignProvider.segments.length; i++) {
        final seg = alignProvider.segments[i];
        if (clickSec >= seg.start && clickSec <= seg.end) {
          _showEditDialog(
            title: 'تعديل توقيت آية ${seg.ayahNumber}',
            initialStart: seg.start,
            initialEnd: seg.end,
            onSave: (s, e) => alignProvider.updateAyahSegment(i, start: s, end: e),
          );
          break;
        }
      }
    } else if (alignProvider.activeGranularity == AlignmentGranularity.breath) {
      for (int i = 0; i < alignProvider.breathGroups.length; i++) {
        final bg = alignProvider.breathGroups[i];
        if (clickSec >= bg.startTime && clickSec <= bg.endTime) {
          _showEditDialog(
            title: 'تعديل توقيت سكتة ${bg.groupIndex}',
            initialStart: bg.startTime,
            initialEnd: bg.endTime,
            onSave: (s, e) => alignProvider.updateBreathGroup(i, start: s, end: e),
          );
          break;
        }
      }
    }
  }

  void _showEditDialog({
    required String title,
    required double initialStart,
    required double initialEnd,
    required Function(double, double) onSave,
  }) {
    final startCtrl = TextEditingController(text: initialStart.toStringAsFixed(3));
    final endCtrl = TextEditingController(text: initialEnd.toStringAsFixed(3));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceCard,
        title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: startCtrl,
              decoration: const InputDecoration(
                labelText: 'بداية المقطع (ثانية)',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: endCtrl,
              decoration: const InputDecoration(
                labelText: 'نهاية المقطع (ثانية)',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              final s = double.tryParse(startCtrl.text) ?? initialStart;
              final e = double.tryParse(endCtrl.text) ?? initialEnd;
              if (e > s) {
                onSave(s, e);
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryEmerald),
            child: const Text('حفظ التعديل', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// كشف حواف المقاطع وتغيير شكل مؤشر الفأرة إلى مؤشر السحب بسهولة
  void _handleHover(PointerHoverEvent event, AlignmentProvider alignProvider) {
    if (_draggingIndex != null || _draggingWordIndex != null) return;
    final x = event.localPosition.dx;
    final hoverSec = x / _pixelsPerSecond;
    final thresholdSec = 14.0 / _pixelsPerSecond;

    int? hitIdx;
    bool? hitIsStart;

    if (alignProvider.activeGranularity == AlignmentGranularity.ayah) {
      for (int i = 0; i < alignProvider.segments.length; i++) {
        final seg = alignProvider.segments[i];
        if ((hoverSec - seg.start).abs() <= thresholdSec) {
          hitIdx = i;
          hitIsStart = true;
          break;
        } else if ((hoverSec - seg.end).abs() <= thresholdSec) {
          hitIdx = i;
          hitIsStart = false;
          break;
        }
      }
    } else if (alignProvider.activeGranularity == AlignmentGranularity.breath) {
      for (int i = 0; i < alignProvider.breathGroups.length; i++) {
        final bg = alignProvider.breathGroups[i];
        if ((hoverSec - bg.startTime).abs() <= thresholdSec) {
          hitIdx = i;
          hitIsStart = true;
          break;
        } else if ((hoverSec - bg.endTime).abs() <= thresholdSec) {
          hitIdx = i;
          hitIsStart = false;
          break;
        }
      }
    } else {
      for (int a = 0; a < alignProvider.segments.length; a++) {
        final seg = alignProvider.segments[a];
        for (int w = 0; w < seg.words.length; w++) {
          final word = seg.words[w];
          if ((hoverSec - word.start).abs() <= thresholdSec) {
            hitIdx = a * 1000 + w;
            hitIsStart = true;
            break;
          } else if ((hoverSec - word.end).abs() <= thresholdSec) {
            hitIdx = a * 1000 + w;
            hitIsStart = false;
            break;
          }
        }
        if (hitIdx != null) break;
      }
    }

    final newCursor = hitIdx != null ? SystemMouseCursors.resizeLeftRight : SystemMouseCursors.basic;
    if (_hoveredIndex != hitIdx || _hoveredIsStart != hitIsStart || _currentCursor != newCursor) {
      setState(() {
        _hoveredIndex = hitIdx;
        _hoveredIsStart = hitIsStart;
        _currentCursor = newCursor;
      });
    }
  }

  void _handlePanStart(DragStartDetails details, AlignmentProvider alignProvider) {
    final x = details.localPosition.dx;
    final clickSec = x / _pixelsPerSecond;
    final thresholdSec = 16.0 / _pixelsPerSecond;

    if (alignProvider.activeGranularity == AlignmentGranularity.ayah) {
      for (int i = 0; i < alignProvider.segments.length; i++) {
        final seg = alignProvider.segments[i];
        if ((clickSec - seg.start).abs() <= thresholdSec) {
          setState(() {
            _draggingIndex = i;
            _isDraggingStart = true;
            _dragCurrentTime = seg.start;
            _currentCursor = SystemMouseCursors.resizeLeftRight;
          });
          return;
        } else if ((clickSec - seg.end).abs() <= thresholdSec) {
          setState(() {
            _draggingIndex = i;
            _isDraggingStart = false;
            _dragCurrentTime = seg.end;
            _currentCursor = SystemMouseCursors.resizeLeftRight;
          });
          return;
        }
      }
    } else if (alignProvider.activeGranularity == AlignmentGranularity.breath) {
      for (int i = 0; i < alignProvider.breathGroups.length; i++) {
        final bg = alignProvider.breathGroups[i];
        if ((clickSec - bg.startTime).abs() <= thresholdSec) {
          setState(() {
            _draggingIndex = i;
            _isDraggingStart = true;
            _dragCurrentTime = bg.startTime;
            _currentCursor = SystemMouseCursors.resizeLeftRight;
          });
          return;
        } else if ((clickSec - bg.endTime).abs() <= thresholdSec) {
          setState(() {
            _draggingIndex = i;
            _isDraggingStart = false;
            _dragCurrentTime = bg.endTime;
            _currentCursor = SystemMouseCursors.resizeLeftRight;
          });
          return;
        }
      }
    } else {
      for (int a = 0; a < alignProvider.segments.length; a++) {
        final seg = alignProvider.segments[a];
        for (int w = 0; w < seg.words.length; w++) {
          final word = seg.words[w];
          if ((clickSec - word.start).abs() <= thresholdSec) {
            setState(() {
              _draggingWordAyahIndex = a;
              _draggingWordIndex = w;
              _isDraggingStart = true;
              _dragCurrentTime = word.start;
              _currentCursor = SystemMouseCursors.resizeLeftRight;
            });
            return;
          } else if ((clickSec - word.end).abs() <= thresholdSec) {
            setState(() {
              _draggingWordAyahIndex = a;
              _draggingWordIndex = w;
              _isDraggingStart = false;
              _dragCurrentTime = word.end;
              _currentCursor = SystemMouseCursors.resizeLeftRight;
            });
            return;
          }
        }
      }
    }

    // If not dragging an edge handle, instantly move playhead and allow scrubbing
    if (_draggingIndex == null && _draggingWordIndex == null) {
      AudioService().seek(clickSec);
    }
  }

  void _handlePanUpdate(DragUpdateDetails details, AlignmentProvider alignProvider) {
    final x = details.localPosition.dx;
    final newSec = (x / _pixelsPerSecond).clamp(0.0, AudioService().totalSeconds);

    // If not dragging an edge handle, scrub playhead smoothly
    if (_draggingIndex == null && _draggingWordIndex == null) {
      AudioService().seek(newSec);
      return;
    }

    final isShift = HardwareKeyboard.instance.isShiftPressed;
    // التعديل المتزامن مع المقطع المجاور هو الوضع الافتراضي، والضغط على Shift يفصل التزامن للتعديل المنفرد
    final syncAdjacent = !isShift;

    setState(() {
      _dragCurrentTime = newSec;
    });

    // 1. Ayah Dragging
    if (alignProvider.activeGranularity == AlignmentGranularity.ayah && _draggingIndex != null) {
      final idx = _draggingIndex!;
      if (_isDraggingStart) {
        alignProvider.updateAyahSegment(idx, start: newSec);
        if (syncAdjacent && idx > 0) {
          alignProvider.updateAyahSegment(idx - 1, end: newSec);
        }
      } else {
        alignProvider.updateAyahSegment(idx, end: newSec);
        if (syncAdjacent && idx < alignProvider.segments.length - 1) {
          alignProvider.updateAyahSegment(idx + 1, start: newSec);
        }
      }
    }
    // 2. Breath Dragging
    else if (alignProvider.activeGranularity == AlignmentGranularity.breath && _draggingIndex != null) {
      final idx = _draggingIndex!;
      if (_isDraggingStart) {
        alignProvider.updateBreathGroup(idx, start: newSec);
        if (syncAdjacent && idx > 0) {
          alignProvider.updateBreathGroup(idx - 1, end: newSec);
        }
      } else {
        alignProvider.updateBreathGroup(idx, end: newSec);
        if (syncAdjacent && idx < alignProvider.breathGroups.length - 1) {
          alignProvider.updateBreathGroup(idx + 1, start: newSec);
        }
      }
    }
    // 3. Word Dragging
    else if (alignProvider.activeGranularity == AlignmentGranularity.word &&
        _draggingWordAyahIndex != null &&
        _draggingWordIndex != null) {
      final aIdx = _draggingWordAyahIndex!;
      final wIdx = _draggingWordIndex!;
      final ayah = alignProvider.segments[aIdx];

      if (_isDraggingStart) {
        alignProvider.updateWordSegment(aIdx, wIdx, start: newSec);
        if (syncAdjacent && wIdx > 0) {
          alignProvider.updateWordSegment(aIdx, wIdx - 1, end: newSec);
        }
      } else {
        alignProvider.updateWordSegment(aIdx, wIdx, end: newSec);
        if (syncAdjacent && wIdx < ayah.words.length - 1) {
          alignProvider.updateWordSegment(aIdx, wIdx + 1, start: newSec);
        }
      }
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    setState(() {
      _draggingIndex = null;
      _draggingWordAyahIndex = null;
      _draggingWordIndex = null;
      _dragCurrentTime = null;
      _currentCursor = SystemMouseCursors.basic;
    });
  }

  String _formatTime(double seconds) {
    if (seconds.isNaN || seconds < 0) return '00:00.000';
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    final ms = ((seconds % 1) * 1000).floor();
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}.${ms.toString().padLeft(3, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final alignProvider = context.watch<AlignmentProvider>();
    final audioService = AudioService();
    final isRTL = widget.localeCode == 'ar';

    return Focus(
      autofocus: false,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.space) {
            audioService.togglePlay();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.keyM) {
            _executeMarkerAction(alignProvider);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _handleStepBackward(alignProvider);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _handleStepForward(alignProvider);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.glassCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Top Controls Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
                children: [
                  // 1. Play / Pause Circular Button
                  ValueListenableBuilder<PlayerState>(
                    valueListenable: audioService.playerStateNotifier,
                    builder: (context, playerState, _) {
                      final isPlaying = playerState == PlayerState.playing;
                      return Tooltip(
                        message: isPlaying
                            ? '${AppLocale.get(context, 'pause', localeCode: widget.localeCode)} (Space)'
                            : '${AppLocale.get(context, 'play', localeCode: widget.localeCode)} (Space)',
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => audioService.togglePlay(),
                            borderRadius: BorderRadius.circular(20),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isPlaying ? AppColors.warningAmber : AppColors.primaryEmerald,
                                boxShadow: [
                                  BoxShadow(
                                    color: (isPlaying ? AppColors.warningAmber : AppColors.primaryEmerald).withOpacity(0.35),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Icon(
                                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                size: 20,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(width: 10),

                  // Divider
                  Container(
                    height: 18,
                    width: 1,
                    color: AppColors.glassBorder,
                  ),

                  const SizedBox(width: 10),

                  // 2. Granularity Tabs (Ayahs, Breaths, Words)
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
                        _buildGranularityTab(
                          AlignmentGranularity.ayah,
                          AppLocale.get(context, 'granularityAyah', localeCode: widget.localeCode),
                          alignProvider,
                        ),
                        _buildGranularityTab(
                          AlignmentGranularity.breath,
                          AppLocale.get(context, 'granularityBreath', localeCode: widget.localeCode),
                          alignProvider,
                        ),
                        _buildGranularityTab(
                          AlignmentGranularity.word,
                          AppLocale.get(context, 'granularityWord', localeCode: widget.localeCode),
                          alignProvider,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 10),

                  // Divider
                  Container(
                    height: 18,
                    width: 1,
                    color: AppColors.glassBorder,
                  ),

                  const SizedBox(width: 10),

                  // 3. Single Seamless Segmented Capsule for Markers (Move / Add)
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
                        _buildMarkerSegmentTab(
                          mode: MarkerActionMode.moveNearest,
                          icon: Icons.near_me_rounded,
                          label: isRTL ? 'نقل أقرب علامة' : 'Move Nearest',
                          tooltip: AppLocale.get(context, 'moveNearestMarkerTooltip', localeCode: widget.localeCode),
                          activeColor: AppColors.accentCyan,
                          alignProvider: alignProvider,
                        ),
                        const SizedBox(width: 2),
                        _buildMarkerSegmentTab(
                          mode: MarkerActionMode.addNew,
                          icon: Icons.add_location_alt_rounded,
                          label: isRTL ? 'إضافة علامة' : 'Add Marker',
                          tooltip: AppLocale.get(context, 'addNewMarkerTooltip', localeCode: widget.localeCode),
                          activeColor: AppColors.warningAmber,
                          alignProvider: alignProvider,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 10),

                // Breath Tools: Split, Merge, Bridge, Reset
                if (alignProvider.activeGranularity == AlignmentGranularity.breath) ...[
                  IconButton(
                    onPressed: () {
                      final currentBreathIdx = alignProvider.currentBreathIndex;
                      if (currentBreathIdx != null) {
                        alignProvider.splitBreath(currentBreathIdx, audioService.currentSeconds);
                      }
                    },
                    icon: const Icon(Icons.content_cut_outlined, size: 16, color: AppColors.primaryTeal),
                    tooltip: AppLocale.get(context, 'splitBreath', localeCode: widget.localeCode),
                  ),
                  IconButton(
                    onPressed: () {
                      final currentBreathIdx = alignProvider.currentBreathIndex;
                      if (currentBreathIdx != null) {
                        alignProvider.mergeBreathWithNext(currentBreathIdx);
                      }
                    },
                    icon: const Icon(Icons.merge_type_rounded, size: 16, color: AppColors.primaryTeal),
                    tooltip: AppLocale.get(context, 'mergeBreath', localeCode: widget.localeCode),
                  ),
                ],

                IconButton(
                  onPressed: () => alignProvider.bridgeSilenceGaps(),
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 16, color: AppColors.accentGold),
                  tooltip: AppLocale.get(context, 'bridgeGaps', localeCode: widget.localeCode),
                ),

                IconButton(
                  onPressed: () => alignProvider.resetToOriginal(),
                  icon: const Icon(Icons.restart_alt_rounded, size: 16, color: AppColors.textMuted),
                  tooltip: AppLocale.get(context, 'resetOriginal', localeCode: widget.localeCode),
                ),

                const SizedBox(width: 8),

                // Helper Pill: Shift Drag linking hint
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.link_rounded, size: 13, color: AppColors.primaryEmerald),
                      const SizedBox(width: 4),
                      Text(
                        isRTL ? 'سحب = تعديل متزامن | Shift + سحب = تعديل منفرد' : 'Drag = Linked Move | Shift + Drag = Single Move',
                        style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: audioService.isExtractingNotifier,
                  builder: (context, isExtracting, _) {
                    if (!isExtracting) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryEmerald.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.primaryEmerald.withOpacity(0.35)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryEmerald),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isRTL ? 'تحليل التموجات الصوتية الحقيقية...' : 'Analyzing real audio waveforms...',
                            style: const TextStyle(fontSize: 11, color: AppColors.primaryEmerald, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                // Repetition Navigation Capsule
                if (alignProvider.repetitionTimestamps.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.warningAmber.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.warningAmber.withOpacity(0.35)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                          icon: const Icon(Icons.chevron_left_rounded, size: 16, color: AppColors.warningAmber),
                          tooltip: 'التكرار السابق',
                          onPressed: () => _jumpToPrevRepetition(alignProvider),
                        ),
                        InkWell(
                          onTap: () => _openRepetitionsModal(context, alignProvider),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.repeat_rounded, size: 13, color: AppColors.warningAmber),
                                const SizedBox(width: 3),
                                Text(
                                  'تكرار (${alignProvider.repetitionTimestamps.length})',
                                  style: const TextStyle(fontSize: 10.5, color: AppColors.warningAmber, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                          icon: const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.warningAmber),
                          tooltip: 'التكرار التالي',
                          onPressed: () => _jumpToNextRepetition(alignProvider),
                        ),
                      ],
                    ),
                  ),
                ],

                // Error / Low Confidence Navigation Capsule
                if (alignProvider.errorTimestamps.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.scoreLow.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.scoreLow.withOpacity(0.35)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                          icon: const Icon(Icons.chevron_left_rounded, size: 16, color: AppColors.scoreLow),
                          tooltip: 'الموضع السابق ذو الدقة المنخفضة',
                          onPressed: () => _jumpToPrevError(alignProvider),
                        ),
                        const Icon(Icons.priority_high_rounded, size: 13, color: AppColors.scoreLow),
                        const SizedBox(width: 3),
                        Text(
                          'مراجعة (${alignProvider.errorTimestamps.length})',
                          style: const TextStyle(fontSize: 10.5, color: AppColors.scoreLow, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                          icon: const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.scoreLow),
                          tooltip: 'الموضع التالي ذو الدقة المنخفضة',
                          onPressed: () => _jumpToNextError(alignProvider),
                        ),
                      ],
                    ),
                  ),
                ],

                const Spacer(),

                // Save Status Indicator
                if (alignProvider.saveStatus == 'saved') ...[
                  const Icon(Icons.check_circle_rounded, color: AppColors.scoreHigh, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    AppLocale.get(context, 'saved', localeCode: widget.localeCode),
                    style: const TextStyle(color: AppColors.scoreHigh, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 12),
                ],

                // Auto Scroll Follow Playhead Toggle
                IconButton(
                  onPressed: () {
                    setState(() {
                      _autoScrollEnabled = !_autoScrollEnabled;
                    });
                  },
                  icon: Icon(
                    _autoScrollEnabled ? Icons.my_location_rounded : Icons.location_disabled_rounded,
                    size: 16,
                    color: _autoScrollEnabled ? AppColors.primaryEmerald : AppColors.textMuted,
                  ),
                  tooltip: _autoScrollEnabled ? 'تتبع موضع القراءة نشط' : 'تتبع موضع القراءة معطل',
                ),

                // Center waveform on current playhead
                IconButton(
                  onPressed: _centerOnCurrentPosition,
                  icon: const Icon(Icons.center_focus_strong_rounded, size: 17, color: AppColors.primaryEmerald),
                  tooltip: 'الانتقال بموجات الصوت إلى موضع القراءة الحالي',
                ),

                const SizedBox(width: 4),

                // Fit entire Surah button
                IconButton(
                  onPressed: () {
                    double totalSec = audioService.totalSeconds;
                    if (totalSec <= 0 && alignProvider.segments.isNotEmpty) {
                      totalSec = alignProvider.segments.last.end;
                    }
                    final viewWidth = _scrollController.hasClients && _scrollController.position.hasViewportDimension
                        ? _scrollController.position.viewportDimension
                        : 900.0;
                    _fitEntireSurah(totalSec, viewWidth);
                  },
                  icon: const Icon(Icons.fit_screen_rounded, size: 17, color: AppColors.primaryTeal),
                  tooltip: 'ملاءمة كامل السورة للشاشة عند أقصى حد',
                ),

                // Zoom Controls & Wheel hint
                IconButton(
                  onPressed: () {
                    double totalSec = audioService.totalSeconds;
                    if (totalSec <= 0 && alignProvider.segments.isNotEmpty) {
                      totalSec = alignProvider.segments.last.end;
                    }
                    final viewWidth = _scrollController.hasClients && _scrollController.position.hasViewportDimension
                        ? _scrollController.position.viewportDimension
                        : 900.0;
                    final dynamicMin = _getDynamicMinPps(totalSec, viewWidth);
                    setState(() {
                      _pixelsPerSecond = (_pixelsPerSecond - 15).clamp(dynamicMin, _maxPps);
                    });
                  },
                  icon: const Icon(Icons.zoom_out, size: 18),
                  tooltip: AppLocale.get(context, 'zoomOut', localeCode: widget.localeCode),
                ),
                SizedBox(
                  width: 90,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                      activeTrackColor: AppColors.primaryEmerald,
                      inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                    ),
                    child: Builder(builder: (context) {
                      double totalSec = audioService.totalSeconds;
                      if (totalSec <= 0 && alignProvider.segments.isNotEmpty) {
                        totalSec = alignProvider.segments.last.end;
                      }
                      final viewWidth = _scrollController.hasClients && _scrollController.position.hasViewportDimension
                          ? _scrollController.position.viewportDimension
                          : 900.0;
                      final dynamicMin = _getDynamicMinPps(totalSec, viewWidth);
                      return Slider(
                        value: _pixelsPerSecond.clamp(dynamicMin, _maxPps),
                        min: dynamicMin,
                        max: _maxPps,
                        onChanged: (val) {
                          setState(() {
                            _pixelsPerSecond = val;
                          });
                        },
                      );
                    }),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    double totalSec = audioService.totalSeconds;
                    if (totalSec <= 0 && alignProvider.segments.isNotEmpty) {
                      totalSec = alignProvider.segments.last.end;
                    }
                    final viewWidth = _scrollController.hasClients && _scrollController.position.hasViewportDimension
                        ? _scrollController.position.viewportDimension
                        : 900.0;
                    final dynamicMin = _getDynamicMinPps(totalSec, viewWidth);
                    setState(() {
                      _pixelsPerSecond = (_pixelsPerSecond + 15).clamp(dynamicMin, _maxPps);
                    });
                  },
                  icon: const Icon(Icons.zoom_in, size: 18),
                  tooltip: AppLocale.get(context, 'zoomIn', localeCode: widget.localeCode),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: AppColors.glassBorder),

          // 2. Interactive Waveform Viewport with Mouse Wheel Zoom & Dragging (Strictly LTR Timeline)
          Directionality(
            textDirection: TextDirection.ltr,
            child: ValueListenableBuilder<Duration>(
              valueListenable: audioService.durationNotifier,
              builder: (context, dur, _) {
                double totalSec = dur.inMilliseconds / 1000.0;
                if ((totalSec <= 0 || totalSec.isNaN) && alignProvider.segments.isNotEmpty) {
                  totalSec = alignProvider.segments.last.end;
                } else if ((totalSec <= 0 || totalSec.isNaN) && alignProvider.breathGroups.isNotEmpty) {
                  totalSec = alignProvider.breathGroups.last.endTime;
                }
                final canvasWidth = max(MediaQuery.of(context).size.width, (totalSec > 0 ? totalSec : 1.0) * _pixelsPerSecond);

                return SizedBox(
                  height: _waveformHeight,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Listener(
                        onPointerSignal: (pointerSignal) {
                          if (pointerSignal is PointerScrollEvent) {
                            GestureBinding.instance.pointerSignalResolver.register(
                              pointerSignal,
                              (event) {
                                final scrollEvent = event as PointerScrollEvent;
                                final mouseViewportX = scrollEvent.localPosition.dx;
                                _handleWheelZoom(
                                  scrollEvent,
                                  mouseViewportX,
                                  totalDuration: totalSec,
                                  viewportWidth: constraints.maxWidth,
                                );
                              },
                            );
                          }
                        },
                        child: Scrollbar(
                          controller: _scrollController,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            scrollDirection: Axis.horizontal,
                            physics: const ClampingScrollPhysics(),
                            child: ValueListenableBuilder<Duration>(
                              valueListenable: audioService.positionNotifier,
                              builder: (context, pos, _) {
                                final currentSec = pos.inMilliseconds / 1000.0;
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (context.mounted && audioService.isPlaying) {
                                    alignProvider.updateCurrentTime(currentSec);
                                  }
                                });

                                return ValueListenableBuilder<List<double>>(
                                  valueListenable: audioService.peaksNotifier,
                                  builder: (context, peaks, _) {
                                    return MouseRegion(
                                      cursor: _currentCursor,
                                      onHover: (event) => _handleHover(event, alignProvider),
                                      onExit: (_) {
                                        if (_draggingIndex == null && _draggingWordIndex == null) {
                                          setState(() {
                                            _hoveredIndex = null;
                                            _hoveredIsStart = null;
                                            _currentCursor = SystemMouseCursors.basic;
                                          });
                                        }
                                      },
                                      child: GestureDetector(
                                        onTapDown: (details) => _handleSeekTap(details, totalSec, alignProvider),
                                        onSecondaryTapDown: (details) => _handleSecondaryTap(details, alignProvider),
                                        onDoubleTapDown: (details) => _handleDoubleTapEdit(details, alignProvider),
                                        onPanStart: (details) => _handlePanStart(details, alignProvider),
                                        onPanUpdate: (details) => _handlePanUpdate(details, alignProvider),
                                        onPanEnd: _handlePanEnd,
                                        child: AnimatedBuilder(
                                          animation: _scrollController,
                                          builder: (context, child) {
                                            double offset = 0;
                                            double viewWidth = constraints.maxWidth;
                                            if (_scrollController.hasClients && _scrollController.position.hasViewportDimension) {
                                              offset = _scrollController.offset;
                                              if (offset.isNaN || offset < 0) offset = 0;
                                              viewWidth = _scrollController.position.viewportDimension;
                                              if (viewWidth.isNaN || viewWidth <= 0) viewWidth = constraints.maxWidth;
                                            }
                                            return Stack(
                                              children: [
                                                CustomPaint(
                                                  size: Size(canvasWidth, _waveformHeight),
                                                  painter: WaveformPainter(
                                                    peaks: peaks,
                                                    totalDuration: totalSec,
                                                    currentPosition: currentSec,
                                                    pixelsPerSecond: _pixelsPerSecond,
                                                    granularity: alignProvider.activeGranularity,
                                                    ayahs: alignProvider.segments,
                                                    breaths: alignProvider.breathGroups,
                                                    activeIndex: alignProvider.activeGranularity == AlignmentGranularity.ayah
                                                        ? alignProvider.currentSegmentIndex
                                                        : alignProvider.currentBreathIndex,
                                                    hoveredIndex: _hoveredIndex,
                                                    hoveredIsStart: _hoveredIsStart,
                                                    draggingIndex: _draggingIndex,
                                                    isDraggingStart: _isDraggingStart,
                                                    isShiftPressed: HardwareKeyboard.instance.isShiftPressed,
                                                    dragTimeSec: _dragCurrentTime,
                                                    visibleStartX: offset,
                                                    visibleWidth: viewWidth,
                                                  ),
                                                ),
                                                ValueListenableBuilder<bool>(
                                                  valueListenable: audioService.isExtractingNotifier,
                                                  builder: (context, isExtracting, _) {
                                                    if (!isExtracting || peaks.isNotEmpty) return const SizedBox.shrink();
                                                    return Positioned(
                                                      left: offset,
                                                      width: viewWidth,
                                                      top: 0,
                                                      bottom: 0,
                                                      child: Center(
                                                        child: Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                                          decoration: BoxDecoration(
                                                            color: AppColors.surfaceDark.withOpacity(0.90),
                                                            borderRadius: BorderRadius.circular(12),
                                                            border: Border.all(color: AppColors.primaryEmerald.withOpacity(0.4)),
                                                          ),
                                                          child: Row(
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: [
                                                              const SizedBox(
                                                                width: 16,
                                                                height: 16,
                                                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryEmerald),
                                                              ),
                                                              const SizedBox(width: 12),
                                                              Text(
                                                                isRTL ? 'جاري تحليل واستخراج التموجات الصوتية الحقيقية...' : 'Extracting real physical audio waveforms...',
                                                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),

          // Divider
          const Divider(height: 1, color: AppColors.glassBorder),

          // 3. Bottom Status Bar: Scroll Buttons, Time, Info, Speed & Height Presets
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
              children: [
                // Waveform Channel Horizontal Scroll Buttons
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_left_rounded, size: 20, color: Colors.white),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                        tooltip: 'تمرير قناة الموجات لليسار',
                        onPressed: () => _scrollBy(-120),
                      ),
                      Container(width: 1, height: 14, color: AppColors.glassBorder),
                      IconButton(
                        icon: const Icon(Icons.arrow_right_rounded, size: 20, color: Colors.white),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                        tooltip: 'تمرير قناة الموجات لليمين',
                        onPressed: () => _scrollBy(120),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 10),

                // Current Time & Duration Badge
                ValueListenableBuilder<Duration>(
                  valueListenable: audioService.positionNotifier,
                  builder: (context, pos, _) {
                    final current = pos.inMilliseconds / 1000.0;
                    final total = audioService.totalSeconds;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.glassBorder),
                      ),
                      child: Text(
                        '${_formatTime(current)} / ${_formatTime(total)}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryEmerald,
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(width: 10),

                // Selected Granularity Item Quick Info
                if (alignProvider.activeGranularity == AlignmentGranularity.ayah &&
                    alignProvider.currentSegmentIndex != null &&
                    alignProvider.currentSegmentIndex! < alignProvider.segments.length) ...[
                  Builder(builder: (context) {
                    final ayah = alignProvider.segments[alignProvider.currentSegmentIndex!];
                    return Text(
                      'الآية الحالية: ${ayah.ayahNumber} (${ayah.start.toStringAsFixed(2)}s - ${ayah.end.toStringAsFixed(2)}s)',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    );
                  }),
                ] else if (alignProvider.activeGranularity == AlignmentGranularity.breath &&
                    alignProvider.currentBreathIndex != null &&
                    alignProvider.currentBreathIndex! < alignProvider.breathGroups.length) ...[
                  Builder(builder: (context) {
                    final breath = alignProvider.breathGroups[alignProvider.currentBreathIndex!];
                    return Text(
                      'النَّفَس الحالي: ${breath.groupIndex} (${breath.startTime.toStringAsFixed(2)}s - ${breath.endTime.toStringAsFixed(2)}s)',
                      style: const TextStyle(fontSize: 11, color: AppColors.primaryTeal),
                    );
                  }),
                ],

                const Spacer(),

                // Playback Speed Selector
                ValueListenableBuilder<double>(
                  valueListenable: audioService.playbackRateNotifier,
                  builder: (context, rate, _) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [0.75, 1.0, 1.25, 1.5].map((r) {
                        final isSel = (rate - r).abs() < 0.05;
                        return GestureDetector(
                          onTap: () => audioService.setPlaybackRate(r),
                          child: Container(
                            margin: const EdgeInsets.only(left: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isSel ? AppColors.primaryEmerald.withOpacity(0.2) : Colors.transparent,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isSel ? AppColors.primaryEmerald : Colors.transparent,
                              ),
                            ),
                            child: Text(
                              '${r}x',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                color: isSel ? AppColors.primaryEmerald : AppColors.textMuted,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),

                const SizedBox(width: 8),

                // Height Presets Quick Toggle
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildHeightPresetBtn(180, 'عادي'),
                      _buildHeightPresetBtn(260, 'متوسط'),
                      _buildHeightPresetBtn(360, 'عريض'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Sleek Draggable Height Resize Handle (مقبض مط قسم موجات الصوت للأسفل بأسلوب نحيف وأنيق)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (details) {
              setState(() {
                _waveformHeight = (_waveformHeight + details.delta.dy).clamp(_minWaveformHeight, _maxWaveformHeight);
              });
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeUpDown,
              child: Container(
                height: 8,
                width: double.infinity,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                ),
                child: Tooltip(
                  message: 'اسحب للأسفل لتوسيع ارتفاع الموجات عموديًا',
                  child: Container(
                    width: 36,
                    height: 3,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildGranularityTab(
    AlignmentGranularity granularity,
    String label,
    AlignmentProvider provider,
  ) {
    final isSelected = provider.activeGranularity == granularity;
    return GestureDetector(
      onTap: () => provider.setGranularity(granularity),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryEmerald : Colors.transparent,
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

  Widget _buildMarkerSegmentTab({
    required MarkerActionMode mode,
    required IconData icon,
    required String label,
    required String tooltip,
    required Color activeColor,
    required AlignmentProvider alignProvider,
  }) {
    final isSelected = _markerMode == mode;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _markerMode = mode;
          });
          _executeMarkerAction(alignProvider);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected ? activeColor.withOpacity(0.20) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? activeColor.withOpacity(0.55) : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? activeColor : AppColors.textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeightPresetBtn(double h, String label) {
    final isSelected = (_waveformHeight - h).abs() < 15;
    return GestureDetector(
      onTap: () {
        setState(() {
          _waveformHeight = h;
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryEmerald.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? AppColors.primaryEmerald : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

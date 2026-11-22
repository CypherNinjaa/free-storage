import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/constants.dart';
import 'package:immich_mobile/domain/models/timeline.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/datetime_extensions.dart';
import 'package:immich_mobile/presentation/widgets/timeline/constants.dart';
import 'package:immich_mobile/presentation/widgets/timeline/segment.model.dart';
import 'package:immich_mobile/presentation/widgets/timeline/timeline.state.dart';
import 'package:immich_mobile/providers/haptic_feedback.provider.dart';
import 'package:intl/intl.dart' hide TextDirection;

part 'scrubber.widget.freezed.dart';

/// A widget that will display a BoxScrollView with a ScrollThumb that can be dragged
/// for quick navigation of the BoxScrollView.
class Scrubber extends ConsumerStatefulWidget {
  /// The view that will be scrolled with the scroll thumb
  final CustomScrollView child;

  /// The segments of the timeline
  final List<Segment> layoutSegments;

  final double timelineHeight;

  final double topPadding;

  final double bottomPadding;

  final double? monthSegmentSnappingOffset;

  final bool snapToMonth;

  /// Whether an app bar is present, affects coordinate calculations
  final bool hasAppBar;

  Scrubber({
    super.key,
    required this.layoutSegments,
    required this.timelineHeight,
    this.topPadding = 0,
    this.bottomPadding = 0,
    this.monthSegmentSnappingOffset,
    this.snapToMonth = true,
    this.hasAppBar = true,
    required this.child,
  }) : assert(child.scrollDirection == Axis.vertical);

  @override
  ConsumerState createState() => ScrubberState();
}

List<_Segment> _buildSegments({required List<Segment> layoutSegments, required double timelineHeight}) {
  const double offsetThreshold = 40.0;

  final segments = <_Segment>[];
  if (layoutSegments.isEmpty || layoutSegments.first.bucket is! TimeBucket) {
    return [];
  }

  final formatter = DateFormat.yMMM(resolvedDateTimeLocale());
  DateTime? lastDate;
  double lastOffset = -offsetThreshold;
  for (final layoutSegment in layoutSegments) {
    final scrollPercentage = layoutSegment.startOffset / layoutSegments.last.endOffset;
    final startOffset = scrollPercentage * timelineHeight;

    final date = (layoutSegment.bucket as TimeBucket).date;
    final label = formatter.format(date);

    final showSegment = lastOffset + offsetThreshold <= startOffset && (lastDate == null || date.year != lastDate.year);

    segments.add(_Segment(date: date, startOffset: startOffset, scrollLabel: label, showSegment: showSegment));
    lastDate = date;
    if (showSegment) {
      lastOffset = startOffset;
    }
  }

  return segments;
}

class ScrubberState extends ConsumerState<Scrubber> with TickerProviderStateMixin {
  String? _lastLabel;
  final ValueNotifier<double> _thumbTopOffsetNotifier = ValueNotifier<double>(0.0);
  bool _isDragging = false;
  List<_Segment> _segments = [];
  int _monthCount = 0;

  late AnimationController _thumbAnimationController;
  Timer? _fadeOutTimer;
  late Animation<double> _thumbAnimation;

  late AnimationController _labelAnimationController;
  late Animation<double> _labelAnimation;

  double get _scrubberHeight => widget.timelineHeight - widget.topPadding - widget.bottomPadding;

  late ScrollController _scrollController;

  double get _currentOffset {
    if (_scrollController.hasClients != true) {
      return 0.0;
    }
    final maxExtent = _scrollController.position.maxScrollExtent;
    if (maxExtent <= 0) {
      return 0.0;
    }
    return (_scrollController.offset * _scrubberHeight / maxExtent).clamp(0.0, _scrubberHeight.clamp(0.0, double.infinity));
  }

  @override
  void initState() {
    super.initState();
    _isDragging = false;
    _segments = _buildSegments(layoutSegments: widget.layoutSegments, timelineHeight: _scrubberHeight);
    _thumbAnimationController = AnimationController(vsync: this, duration: kTimelineScrubberFadeInDuration);
    _thumbAnimation = CurvedAnimation(parent: _thumbAnimationController, curve: Curves.fastEaseInToSlowEaseOut);
    _labelAnimationController = AnimationController(vsync: this, duration: kTimelineScrubberFadeInDuration);
    _monthCount = getMonthCount();

    _labelAnimation = CurvedAnimation(parent: _labelAnimationController, curve: Curves.fastOutSlowIn);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scrollController = PrimaryScrollController.of(context);
  }

  @override
  void didUpdateWidget(covariant Scrubber oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.layoutSegments.lastOrNull?.endOffset != widget.layoutSegments.lastOrNull?.endOffset) {
      _segments = _buildSegments(layoutSegments: widget.layoutSegments, timelineHeight: _scrubberHeight);
      _monthCount = getMonthCount();
    }
  }

  @override
  void dispose() {
    _thumbTopOffsetNotifier.dispose();
    _thumbAnimationController.dispose();
    _labelAnimationController.dispose();
    _fadeOutTimer?.cancel();
    super.dispose();
  }

  void _resetThumbTimer() {
    _fadeOutTimer?.cancel();
    _fadeOutTimer = Timer(kTimelineScrubberFadeOutDuration, () {
      unawaited(_thumbAnimationController.reverse());
      _fadeOutTimer = null;
    });
  }

  int getMonthCount() {
    return _segments.map((e) => "${e.date.month}_${e.date.year}").toSet().length;
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (_isDragging) {
      // If the user is dragging the thumb, we don't want to update the position
      return false;
    }

    switch (notification) {
      case ScrollStartNotification():
        ref.read(timelineStateProvider.notifier).setScrolling(true);
        _fadeOutTimer?.cancel();
      case ScrollUpdateNotification():
        ref.read(timelineStateProvider.notifier).setScrolling(true);
        _fadeOutTimer?.cancel();
        if (_labelAnimationController.status.isForwardOrCompleted) {
          unawaited(_labelAnimationController.reverse());
        }
        if (!_thumbAnimationController.status.isForwardOrCompleted) {
          unawaited(_thumbAnimationController.forward());
        }
        _thumbTopOffsetNotifier.value = _currentOffset;
      case ScrollEndNotification():
        ref.read(timelineStateProvider.notifier).setScrolling(false);
        _resetThumbTimer();
    }

    return false;
  }

  void _onDragStart(DragStartDetails _) {
    setState(() {
      _isDragging = true;
      unawaited(_labelAnimationController.forward());
      _fadeOutTimer?.cancel();
      _lastLabel = null;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) {
      return;
    }

    if (_scrubberHeight <= 0) {
      return;
    }

    if (_thumbAnimationController.status != AnimationStatus.forward) {
      unawaited(_thumbAnimationController.forward());
    }

    final dragPosition = _calculateDragPosition(details);
    final nearestMonthSegment = _findNearestMonthSegment(dragPosition);

    if (nearestMonthSegment != null) {
      final label = nearestMonthSegment.scrollLabel;
      if (_lastLabel != label) {
        ref.read(hapticFeedbackProvider.notifier).selectionClick();
        _lastLabel = label;
      }
    }

    if (_monthCount < kMinMonthsToEnableScrubberSnap || !widget.snapToMonth) {
      _thumbTopOffsetNotifier.value = dragPosition;
      _scrollController.jumpTo((dragPosition / _scrubberHeight) * _scrollController.position.maxScrollExtent);
    } else if (nearestMonthSegment != null) {
      _snapToSegment(nearestMonthSegment);
    }
  }

  double _calculateDragPosition(DragUpdateDetails details) {
    if (widget.hasAppBar) {
      final dragAreaTop = widget.topPadding;
      final dragAreaBottom = widget.timelineHeight - widget.bottomPadding;
      final dragAreaHeight = dragAreaBottom - dragAreaTop;

      final relativePosition = details.globalPosition.dy - dragAreaTop;

      return relativePosition.clamp(0.0, dragAreaHeight);
    }

    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final localPosition = renderBox.globalToLocal(details.globalPosition);
      return localPosition.dy.clamp(0.0, _scrubberHeight);
    }

    final dragAreaTop = widget.topPadding;
    final relativePosition = details.globalPosition.dy - dragAreaTop;
    return relativePosition.clamp(0.0, _scrubberHeight);
  }

  _Segment? _findNearestMonthSegment(double position) {
    _Segment? nearestSegment;
    double minDistance = double.infinity;

    for (final segment in _segments) {
      final distance = (segment.startOffset - position).abs();
      if (distance < minDistance) {
        minDistance = distance;
        nearestSegment = segment;
      }
    }

    return nearestSegment;
  }

  void _snapToSegment(_Segment segment) {
    _thumbTopOffsetNotifier.value = segment.startOffset;

    final layoutSegmentIndex = _findLayoutSegmentIndex(segment);

    if (layoutSegmentIndex >= 0) {
      _scrollToLayoutSegment(layoutSegmentIndex);
    }
  }

  int _findLayoutSegmentIndex(_Segment segment) {
    return widget.layoutSegments.indexWhere((layoutSegment) {
      final bucket = layoutSegment.bucket as TimeBucket;
      return bucket.date.year == segment.date.year && bucket.date.month == segment.date.month;
    });
  }

  void _scrollToLayoutSegment(int layoutSegmentIndex) {
    final layoutSegment = widget.layoutSegments[layoutSegmentIndex];
    final maxScrollExtent = _scrollController.position.maxScrollExtent;
    final viewportHeight = _scrollController.position.viewportDimension;

    final targetScrollOffset = layoutSegment.startOffset;
    final centeredOffset = targetScrollOffset - (viewportHeight / 4) + 100 + (widget.monthSegmentSnappingOffset ?? 0.0);

    _scrollController.jumpTo(centeredOffset.clamp(0.0, maxScrollExtent));
  }

  void _onDragEnd(DragEndDetails _) {
    unawaited(_labelAnimationController.reverse());
    setState(() {
      _isDragging = false;
    });

    _resetThumbTimer();
  }

  @override
  Widget build(BuildContext ctx) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: Stack(
        children: [
          RepaintBoundary(child: widget.child),
          // Scroll Segments - wrapped in RepaintBoundary for better performance
          RepaintBoundary(
            child: _SegmentsLayer(
              key: ValueKey('segments_${_isDragging}_${_segments.length}'),
              segments: _segments,
              topPadding: widget.topPadding,
              isDragging: _isDragging,
            ),
          ),
          ValueListenableBuilder<double>(
            valueListenable: _thumbTopOffsetNotifier,
            builder: (context, thumbTopOffset, _) {
              if (!_scrollController.hasClients || _scrollController.position.maxScrollExtent <= 0) {
                return const SizedBox.shrink();
              }
              final labelText =
                  _segments.lastWhereOrNull((segment) => segment.startOffset <= thumbTopOffset)?.scrollLabel ??
                  _segments.firstOrNull?.scrollLabel;
              final label = labelText != null
                  ? Text(
                      labelText,
                      style: ctx.textTheme.labelLarge?.copyWith(
                        color: ctx.colorScheme.onInverseSurface,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    )
                  : null;

              return PositionedDirectional(
                top: thumbTopOffset + widget.topPadding,
                end: 0,
                child: RepaintBoundary(
                  child: GestureDetector(
                    onVerticalDragStart: _onDragStart,
                    onVerticalDragUpdate: _onDragUpdate,
                    onVerticalDragEnd: _onDragEnd,
                    child: _Scrubber(thumbAnimation: _thumbAnimation, labelAnimation: _labelAnimation, label: label),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SegmentsLayer extends StatelessWidget {
  final List<_Segment> segments;
  final double topPadding;
  final bool isDragging;

  const _SegmentsLayer({super.key, required this.segments, required this.topPadding, required this.isDragging});

  @override
  Widget build(BuildContext context) {
    return Visibility(
      visible: isDragging,
      child: Stack(
        children: segments
            .where((segment) => segment.showSegment)
            .map(
              (segment) => PositionedDirectional(
                key: ValueKey('segment_${segment.date.millisecondsSinceEpoch}'),
                top: topPadding + segment.startOffset,
                end: 100,
                child: RepaintBoundary(child: _SegmentWidget(segment)),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _SegmentWidget extends StatelessWidget {
  final _Segment _segment;

  const _SegmentWidget(this._segment);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        margin: const EdgeInsets.only(right: 36.0),
        child: Material(
          color: context.colorScheme.surfaceContainerHighest,
          shape: StadiumBorder(side: BorderSide(color: context.colorScheme.outlineVariant)),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 28),
            padding: const EdgeInsets.symmetric(horizontal: 10.0),
            alignment: Alignment.center,
            child: Text(
              _segment.date.year.toString(),
              style: context.textTheme.labelMedium?.copyWith(
                fontFamily: "GoogleSansCode",
                fontWeight: FontWeight.w600,
                color: context.colorScheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScrollLabel extends StatelessWidget {
  final Text label;
  final Color backgroundColor;
  final Animation<double> animation;

  const _ScrollLabel({required this.label, required this.backgroundColor, required this.animation});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: FadeTransition(
        opacity: animation,
        child: Container(
          margin: const EdgeInsets.only(right: 12.0),
          child: Material(
            elevation: 2.0,
            color: backgroundColor,
            shape: const StadiumBorder(),
            child: Container(
              constraints: const BoxConstraints(minHeight: 30, maxHeight: 32),
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              alignment: Alignment.center,
              child: label,
            ),
          ),
        ),
      ),
    );
  }
}

class _Scrubber extends StatelessWidget {
  final Text? label;
  final Animation<double> thumbAnimation;
  final Animation<double> labelAnimation;

  const _Scrubber({this.label, required this.thumbAnimation, required this.labelAnimation});

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;

    return _SlideFadeTransition(
      animation: thumbAnimation,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (label != null) _ScrollLabel(label: label!, backgroundColor: scheme.inverseSurface, animation: labelAnimation),
          _CircularThumb(
            backgroundColor: scheme.surfaceContainerHighest,
            borderColor: scheme.outlineVariant,
            iconColor: scheme.onSurface,
          ),
        ],
      ),
    );
  }
}

class _CircularThumb extends StatelessWidget {
  final Color backgroundColor;
  final Color borderColor;
  final Color iconColor;

  const _CircularThumb({
    required this.backgroundColor,
    required this.borderColor,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _ArrowPainter(iconColor),
      child: Material(
        elevation: 2.0,
        color: backgroundColor,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: borderColor),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(kScrubberThumbHeight),
            bottomLeft: Radius.circular(kScrubberThumbHeight),
            topRight: Radius.circular(4.0),
            bottomRight: Radius.circular(4.0),
          ),
        ),
        child: Container(
          constraints: BoxConstraints.tight(const Size(kScrubberThumbHeight * 0.68, kScrubberThumbHeight)),
        ),
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  final Color color;

  const _ArrowPainter(this.color);

  @override
  bool shouldRepaint(covariant _ArrowPainter oldDelegate) => oldDelegate.color != color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const width = 10.0;
    const height = 6.0;
    final left = (size.width - width) / 2 + 1.0;
    final centerY = size.height / 2;

    canvas.drawPath(_trianglePath(Offset(left, centerY - 2.5), width, height, true), paint);
    canvas.drawPath(_trianglePath(Offset(left, centerY + 2.5), width, height, false), paint);
  }

  static Path _trianglePath(Offset o, double width, double height, bool isUp) {
    return Path()
      ..moveTo(o.dx, o.dy)
      ..lineTo(o.dx + width, o.dy)
      ..lineTo(o.dx + (width / 2), isUp ? o.dy - height : o.dy + height)
      ..close();
  }
}

class _SlideFadeTransition extends StatelessWidget {
  final Animation<double> _animation;
  final Widget _child;

  const _SlideFadeTransition({required this._animation, required this._child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => _animation.value == 0.0 ? const SizedBox() : child!,
      child: SlideTransition(
        position: Tween(begin: const Offset(0.3, 0.0), end: Offset.zero).animate(_animation),
        child: FadeTransition(opacity: _animation, child: _child),
      ),
    );
  }
}

@freezed
abstract class _Segment with _$Segment {
  const factory _Segment({
    required DateTime date,
    required double startOffset,
    required String scrollLabel,
    @Default(false) bool showSegment,
  }) = __Segment;
}

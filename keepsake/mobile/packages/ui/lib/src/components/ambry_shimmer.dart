import 'package:flutter/material.dart';
import 'package:immich_ui/src/motion.dart';

/// Shares a single 1200ms shimmer AnimationController across an entire timeline or grid
/// so 10,000+ tiles incur zero per-tile Ticker overhead (05_motion_spec.md §2 #12).
/// Automatically falls back to static surface fill when reduced motion is enabled.
class AmbryShimmerScope extends StatefulWidget {
  final Widget child;

  const AmbryShimmerScope({super.key, required this.child});

  static Animation<double>? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_AmbryShimmerInherited>()?.notifier;
  }

  @override
  State<AmbryShimmerScope> createState() => _AmbryShimmerScopeState();
}

class _AmbryShimmerScopeState extends State<AmbryShimmerScope> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AmbryMotion.dShimmer,
  );

  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = AmbryMotion.isReduced(context);
    if (reduced != _reduced) {
      _reduced = reduced;
      if (_reduced) {
        _controller.stop();
        _controller.value = 0.0;
      } else if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else if (!_reduced && !_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AmbryShimmerInherited(notifier: _controller, child: widget.child);
  }
}

class _AmbryShimmerInherited extends InheritedNotifier<AnimationController> {
  const _AmbryShimmerInherited({required super.notifier, required super.child});
}

/// Lightweight skeleton box that reads the nearest [AmbryShimmerScope] animation.
class AmbrySkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final BorderRadiusGeometry borderRadius;

  const AmbrySkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = BorderRadius.zero,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduced = AmbryMotion.isReduced(context);
    final anim = reduced ? null : AmbryShimmerScope.maybeOf(context);

    final base = scheme.surfaceContainerLow;
    final highlight = scheme.surfaceContainerHigh;

    if (anim == null) {
      return ExcludeSemantics(
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(color: scheme.surfaceContainer, borderRadius: borderRadius),
        ),
      );
    }

    final t = anim.value;
    final slide = -1.2 + (t * 2.4);
    return ExcludeSemantics(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            begin: Alignment(slide - 0.6, -0.2),
            end: Alignment(slide + 0.6, 0.2),
            colors: [base, highlight, base],
            stops: const [0.1, 0.5, 0.9],
          ),
        ),
      ),
    );
  }
}

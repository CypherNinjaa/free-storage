import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/presentation/widgets/timeline/timeline.state.dart';
import 'package:immich_ui/immich_ui.dart';

class BaseBottomSheet extends ConsumerStatefulWidget {
  final List<Widget> actions;
  final DraggableScrollableController? controller;
  final List<Widget>? slivers;
  final Widget? footer;
  final double initialChildSize;
  final double minChildSize;
  final double maxChildSize;
  final bool expand;
  final bool shouldCloseOnMinExtent;
  final bool resizeOnScroll;
  final Color? backgroundColor;

  const BaseBottomSheet({
    super.key,
    required this.actions,
    this.slivers,
    this.footer,
    this.controller,
    this.initialChildSize = 0.35,
    double? minChildSize,
    this.maxChildSize = 0.65,
    this.expand = true,
    this.shouldCloseOnMinExtent = true,
    this.resizeOnScroll = true,
    this.backgroundColor,
  }) : minChildSize = minChildSize ?? 0.15;

  @override
  ConsumerState<BaseBottomSheet> createState() => _BaseDraggableScrollableSheetState();
}

class _BaseDraggableScrollableSheetState extends ConsumerState<BaseBottomSheet> {
  late DraggableScrollableController _controller;
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = DraggableScrollableController();
      _ownsController = true;
    }
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(timelineStateProvider, (previous, next) {
      if (!widget.resizeOnScroll) {
        return;
      }

      if (previous?.isInteracting != true && next.isInteracting) {
        unawaited(
          _controller.animateTo(
            widget.minChildSize,
            duration: AmbryMotion.durationOf(context, AmbryMotion.dStandard),
            curve: AmbryMotion.easeSpatial,
          ),
        );
      }
    });

    final midSnap = widget.initialChildSize.clamp(widget.minChildSize, widget.maxChildSize);
    final snapSizes = <double>[
      if (midSnap > widget.minChildSize + 0.02 && midSnap < widget.maxChildSize - 0.02) midSnap,
    ];

    return DraggableScrollableSheet(
      controller: _controller,
      initialChildSize: widget.initialChildSize,
      minChildSize: widget.minChildSize,
      maxChildSize: widget.maxChildSize,
      snap: true,
      snapSizes: snapSizes.isEmpty ? null : snapSizes,
      expand: widget.expand,
      shouldCloseOnMinExtent: widget.shouldCloseOnMinExtent,
      builder: (BuildContext context, ScrollController scrollController) {
        return Material(
          color: widget.backgroundColor ?? context.colorScheme.surfaceContainerLow,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(ImmichRadius.xl)),
            side: BorderSide(color: context.colorScheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Expanded(
                  child: CustomScrollView(
                    controller: scrollController,
                    slivers: [
                      const SliverToBoxAdapter(child: _DragHandle()),
                      if (widget.actions.isNotEmpty)
                        SliverToBoxAdapter(
                          child: Column(
                            children: [
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: widget.actions),
                              ),
                              const Divider(indent: 16, endIndent: 16),
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      if (widget.slivers != null) ...widget.slivers!,
                    ],
                  ),
                ),
                if (widget.footer != null) widget.footer!,
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: Center(
        child: SizedBox(
          width: 36,
          height: 4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.pill)),
              color: context.colorScheme.outlineVariant,
            ),
          ),
        ),
      ),
    );
  }
}

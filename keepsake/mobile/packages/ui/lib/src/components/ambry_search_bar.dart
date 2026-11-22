import 'package:flutter/material.dart';
import 'package:immich_ui/src/constants.dart';

/// Unified pill search bar replacing the duplicated primary-gradient search fields
/// across SearchPage, AlbumSelector, and LanguageSettings (04_design_system.md §4.6).
class AmbrySearchBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final IconData prefixIcon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final Widget? trailing;
  final bool autofocus;
  final TapRegionCallback? onTapOutside;

  const AmbrySearchBar({
    super.key,
    required this.controller,
    required this.hintText,
    this.focusNode,
    this.prefixIcon = Icons.search_rounded,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.trailing,
    this.autofocus = false,
    this.onTapOutside,
  });

  @override
  State<AmbrySearchBar> createState() => _AmbrySearchBarState();
}

class _AmbrySearchBarState extends State<AmbrySearchBar> {
  late bool _hasText;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_onTextChange);
    widget.focusNode?.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant AmbrySearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChange);
      widget.controller.addListener(_onTextChange);
      _hasText = widget.controller.text.isNotEmpty;
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocusChange);
      widget.focusNode?.addListener(_onFocusChange);
      _focused = widget.focusNode?.hasFocus ?? false;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChange);
    widget.focusNode?.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onTextChange() {
    final next = widget.controller.text.isNotEmpty;
    if (next != _hasText && mounted) {
      setState(() => _hasText = next);
    }
  }

  void _onFocusChange() {
    final next = widget.focusNode?.hasFocus ?? false;
    if (next != _focused && mounted) {
      setState(() => _focused = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Focus(
      onFocusChange: (focused) {
        if (focused != _focused) {
          setState(() => _focused = focused);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        constraints: const BoxConstraints(minHeight: 48),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: const BorderRadius.all(Radius.circular(999)),
          border: Border.all(
            color: _focused ? colorScheme.outline : colorScheme.outlineVariant,
            width: _focused ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: ImmichSpacing.lg),
            Icon(widget.prefixIcon, size: ImmichIconSize.sm, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: ImmichSpacing.md),
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                autofocus: widget.autofocus,
                textInputAction: TextInputAction.search,
                onChanged: widget.onChanged,
                onSubmitted: widget.onSubmitted,
                onTapOutside: widget.onTapOutside,
                style: textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            if (_hasText)
              IconButton(
                tooltip: 'Clear search',
                icon: Icon(Icons.close_rounded, size: ImmichIconSize.sm, color: colorScheme.onSurfaceVariant),
                onPressed: () {
                  widget.controller.clear();
                  widget.onClear?.call();
                  widget.onChanged?.call('');
                },
              ),
            if (widget.trailing != null) widget.trailing!,
            if (!_hasText && widget.trailing == null) const SizedBox(width: ImmichSpacing.md),
          ],
        ),
      ),
    );
  }
}

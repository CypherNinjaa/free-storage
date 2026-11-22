import 'dart:async';

import 'package:flutter/material.dart';
import 'package:immich_ui/src/constants.dart';

/// Unified M3 confirmation dialog with calm neutral Cancel and standard or destructive Confirm
/// supporting async inline loading state (04_design_system.md §4.4).
class AmbryConfirmDialog extends StatefulWidget {
  final String title;
  final String content;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;
  final FutureOr<void> Function() onConfirm;

  const AmbryConfirmDialog({
    super.key,
    required this.title,
    required this.content,
    required this.confirmLabel,
    required this.onConfirm,
    this.cancelLabel = 'Cancel',
    this.destructive = false,
  });

  @override
  State<AmbryConfirmDialog> createState() => _AmbryConfirmDialogState();
}

class _AmbryConfirmDialogState extends State<AmbryConfirmDialog> {
  bool _busy = false;

  Future<void> _handleConfirm() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onConfirm();
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        backgroundColor: scheme.surfaceContainer,
        elevation: ImmichElevation.none,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(ImmichRadius.xl))),
        title: Text(widget.title, style: textTheme.titleMedium?.copyWith(color: scheme.onSurface)),
        content: Text(widget.content, style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
            child: Text(widget.cancelLabel),
          ),
          FilledButton(
            onPressed: _busy ? null : _handleConfirm,
            style: FilledButton.styleFrom(
              backgroundColor: widget.destructive ? scheme.error : scheme.primary,
              foregroundColor: widget.destructive ? scheme.onError : scheme.onPrimary,
              shape: const StadiumBorder(),
            ),
            child: _busy
                ? SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: widget.destructive ? scheme.onError : scheme.onPrimary,
                    ),
                  )
                : Text(widget.confirmLabel),
          ),
        ],
      ),
    );
  }
}

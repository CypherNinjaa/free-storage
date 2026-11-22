import 'package:flutter/material.dart';
import 'package:immich_ui/src/constants.dart';

/// Unified, calm, Dynamic-Type-safe empty state (04_design_system.md §4.14).
class AmbryEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isError;

  const AmbryEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final circleColor = isError ? colorScheme.errorContainer : colorScheme.surfaceContainerHigh;
    final iconColor = isError ? colorScheme.onErrorContainer : colorScheme.onSurfaceVariant;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(ImmichSpacing.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: circleColor, shape: BoxShape.circle),
                child: Icon(icon, size: ImmichIconSize.lg, color: iconColor),
              ),
              const SizedBox(height: ImmichSpacing.lg),
              Text(
                title,
                textAlign: TextAlign.center,
                style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurface),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: ImmichSpacing.sm),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: ImmichSpacing.xl),
                FilledButton(
                  onPressed: onAction,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(140, 48),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

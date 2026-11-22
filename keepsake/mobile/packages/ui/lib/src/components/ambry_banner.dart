import 'package:flutter/material.dart';
import 'package:immich_ui/src/constants.dart';
import 'package:immich_ui/src/theme.dart';

enum AmbryBannerVariant { info, warning, error, success }

/// Tonal, WCAG AA-verified alert & disclosure banner (04_design_system.md §4.15).
class AmbryBanner extends StatelessWidget {
  final AmbryBannerVariant variant;
  final IconData? icon;
  final String title;
  final String? body;
  final List<Widget> actions;
  final EdgeInsetsGeometry? margin;

  const AmbryBanner({
    super.key,
    required this.variant,
    required this.title,
    this.icon,
    this.body,
    this.actions = const [],
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = Theme.of(context).extension<ImmichColors>() ?? ImmichColors.sunlitAlcove(scheme.brightness);
    final textTheme = Theme.of(context).textTheme;

    final (bg, fg, defaultIcon) = switch (variant) {
      AmbryBannerVariant.info => (colors.infoContainer, colors.onInfoContainer, Icons.info_outline_rounded),
      AmbryBannerVariant.warning => (colors.warningContainer, colors.onWarningContainer, Icons.warning_amber_rounded),
      AmbryBannerVariant.error => (scheme.errorContainer, scheme.onErrorContainer, Icons.error_outline_rounded),
      AmbryBannerVariant.success => (colors.successContainer, colors.onSuccessContainer, Icons.check_circle_outline_rounded),
    };

    return Container(
      margin: margin,
      padding: EdgeInsets.fromLTRB(
        ImmichSpacing.lg,
        ImmichSpacing.md + 2,
        ImmichSpacing.lg,
        actions.isEmpty ? ImmichSpacing.md + 2 : ImmichSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.lg)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon ?? defaultIcon, size: 22, color: fg),
              const SizedBox(width: ImmichSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleSmall?.copyWith(color: fg, fontWeight: FontWeight.w600),
                    ),
                    if (body != null && body!.isNotEmpty) ...[
                      const SizedBox(height: ImmichSpacing.xs),
                      Text(
                        body!,
                        style: textTheme.bodySmall?.copyWith(color: fg.withValues(alpha: 0.9)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: ImmichSpacing.xs),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(spacing: ImmichSpacing.sm, children: actions),
            ),
          ],
        ],
      ),
    );
  }
}

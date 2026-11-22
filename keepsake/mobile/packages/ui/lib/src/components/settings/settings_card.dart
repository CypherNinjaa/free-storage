import 'package:flutter/material.dart';
import 'package:immich_ui/src/constants.dart';

/// Calm tonal SettingsCard (04_design_system.md §1.4 & §4):
/// neutral `onSurface` title, tonal 40dp icon badge, subtle trailing chevron.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final Function() onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ImmichSpacing.lg),
      child: Card(
        elevation: ImmichElevation.none,
        clipBehavior: Clip.antiAlias,
        color: scheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(ImmichRadius.lg))),
        margin: const EdgeInsets.symmetric(vertical: ImmichSpacing.xs),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: ImmichSpacing.lg, vertical: ImmichSpacing.xs),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.surfaceContainerHigh,
            ),
            child: Icon(icon, size: ImmichIconSize.sm, color: scheme.primary),
          ),
          title: Text(
            title,
            style: textTheme.titleMedium?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            subtitle,
            style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          trailing: Icon(Icons.chevron_right_rounded, size: ImmichIconSize.sm, color: scheme.onSurfaceVariant),
          onTap: onTap,
        ),
      ),
    );
  }
}

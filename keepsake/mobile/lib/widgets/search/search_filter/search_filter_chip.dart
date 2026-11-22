import 'package:flutter/material.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';

class SearchFilterChip extends StatelessWidget {
  final String label;
  final Function() onTap;
  final Widget? currentFilter;
  final IconData icon;

  const SearchFilterChip({super.key, required this.label, required this.onTap, required this.icon, this.currentFilter});

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final isActive = currentFilter != null;

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: Material(
        color: isActive ? scheme.primaryContainer : scheme.surfaceContainerLow,
        shape: StadiumBorder(
          side: BorderSide(color: isActive ? Colors.transparent : scheme.outlineVariant),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 14.0),
            child: IconTheme(
              data: IconThemeData(
                size: 18,
                color: isActive ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
              ),
              child: DefaultTextStyle.merge(
                style: context.textTheme.labelLarge?.copyWith(
                  color: isActive ? scheme.onPrimaryContainer : scheme.onSurface,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon),
                    const SizedBox(width: 6.0),
                    currentFilter ?? Text(label),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:immich_ui/src/constants.dart';

/// Ambry arched-alcove sunrise mark + clean wordmark (04_design_system.md §4.1).
class AmbryBrandMark extends StatelessWidget {
  final double iconSize;
  final double? fontSize;
  final bool showWordmark;

  const AmbryBrandMark({
    super.key,
    this.iconSize = 26.0,
    this.fontSize,
    this.showWordmark = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.all(Radius.circular(iconSize >= 40 ? ImmichRadius.md : ImmichRadius.sm)),
          child: Image.asset(
            'assets/ambry-logo.png',
            width: iconSize,
            height: iconSize,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, _, _) => Icon(Icons.photo_library_rounded, size: iconSize, color: colorScheme.primary),
          ),
        ),
        if (showWordmark) ...[
          const SizedBox(width: 10),
          Text(
            'Ambry',
            style: (textTheme.titleLarge ?? const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)).copyWith(
              fontSize: fontSize ?? textTheme.titleLarge?.fontSize ?? 20,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.25,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ],
    );
  }
}

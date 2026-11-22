import 'package:flutter/material.dart';
import 'package:immich_ui/immich_ui.dart';

class ThumbnailPlaceholder extends StatelessWidget {
  final EdgeInsets margin;
  final double width;
  final double height;

  const ThumbnailPlaceholder({super.key, this.margin = EdgeInsets.zero, this.width = 250, this.height = 250});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: AmbrySkeletonBox(width: width, height: height, borderRadius: BorderRadius.zero),
    );
  }
}

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/presentation/widgets/map/map.widget.dart';
import 'package:immich_mobile/presentation/widgets/map/map_settings_sheet.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

@RoutePage()
class MapPage extends StatelessWidget {
  final LatLng? initialLocation;

  const MapPage({super.key, this.initialLocation});

  Future<void> onSettingsPressed(BuildContext context) {
    return showModalBottomSheet(
      elevation: 0.0,
      showDragHandle: true,
      isScrollControlled: true,
      context: context,
      builder: (_) => const MapSettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final buttonStyle = IconButton.styleFrom(
      padding: const EdgeInsets.all(10),
      backgroundColor: scheme.surfaceContainerHigh,
      foregroundColor: scheme.onSurface,
      elevation: 2,
      shadowColor: Colors.black26,
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          MapView(initialLocation: initialLocation),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton.filledTonal(
                    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                    onPressed: () => ContextHelper(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    style: buttonStyle,
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Map settings',
                    onPressed: () => onSettingsPressed(context),
                    icon: const Icon(Icons.tune_rounded),
                    style: buttonStyle,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

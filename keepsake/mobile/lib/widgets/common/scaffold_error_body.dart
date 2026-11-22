import 'package:flutter/material.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_ui/immich_ui.dart';

// Error widget to be used in Scaffold when an AsyncError is received
class ScaffoldErrorBody extends StatelessWidget {
  final bool withIcon;
  final String? errorMsg;

  const ScaffoldErrorBody({super.key, this.withIcon = true, this.errorMsg});

  @override
  Widget build(BuildContext context) {
    return AmbryEmptyState(
      icon: withIcon ? Icons.error_outline_rounded : Icons.info_outline_rounded,
      title: context.t.scaffold_body_error_occurred,
      subtitle: withIcon ? errorMsg : null,
      isError: true,
    );
  }
}

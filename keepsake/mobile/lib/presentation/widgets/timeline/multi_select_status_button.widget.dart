import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/timeline/multiselect.provider.dart';

class MultiSelectStatusButton extends ConsumerWidget {
  const MultiSelectStatusButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectCount = ref.watch(multiSelectProvider.select((s) => s.selectedAssets.length));
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        elevation: 2,
      ),
      onPressed: () => ref.read(multiSelectProvider.notifier).reset(),
      icon: Icon(Icons.close_rounded, size: 20, color: context.colorScheme.onPrimary),
      label: Text(
        selectCount.toString(),
        style: context.textTheme.titleMedium?.copyWith(
          color: context.colorScheme.onPrimary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

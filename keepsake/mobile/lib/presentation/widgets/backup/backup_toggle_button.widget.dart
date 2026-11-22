import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/providers/backup/backup.provider.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';
import 'package:immich_ui/immich_ui.dart';

class BackupToggleButton extends ConsumerWidget {
  final VoidCallback onStart;
  final VoidCallback onStop;

  const BackupToggleButton({super.key, required this.onStart, required this.onStop});

  Future<void> _onToggle(WidgetRef ref, bool value) async {
    await ref.read(settingsProvider).write(.backupEnabled, value);

    if (value) {
      onStart.call();
    } else {
      onStop.call();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEnabled = ref.watch(appConfigProvider.select((c) => c.backup.enabled));
    final uploadTasks = ref.watch(backupProvider.select((state) => state.uploadItems));
    final isSyncing = ref.watch(backupProvider.select((state) => state.isSyncing));
    final iCloudProgress = ref.watch(backupProvider.select((state) => state.iCloudDownloadProgress));
    final errorCount = ref.watch(backupProvider.select((state) => state.errorCount));

    final isProcessing = uploadTasks.isNotEmpty || isSyncing || iCloudProgress.isNotEmpty;
    final scheme = context.colorScheme;

    return AnimatedContainer(
      duration: AmbryMotion.durationOf(context, AmbryMotion.dModerate),
      curve: AmbryMotion.easeEffects,
      decoration: BoxDecoration(
        color: isEnabled ? scheme.primaryContainer.withValues(alpha: 0.45) : scheme.surfaceContainerLow,
        borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.lg)),
        border: Border.all(
          color: isEnabled ? scheme.primary.withValues(alpha: 0.35) : scheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isEnabled ? scheme.primaryContainer : scheme.surfaceContainerHigh,
              ),
              child: Center(
                child: isProcessing
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
                      )
                    : Icon(
                        isEnabled ? Icons.cloud_upload_rounded : Icons.cloud_upload_outlined,
                        color: isEnabled ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                        size: 20,
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Back up to Telegram',
                    style: context.textTheme.titleMedium?.copyWith(color: scheme.onSurface),
                  ),
                  if (errorCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        context.t.upload_error_with_count(count: errorCount),
                        style: context.textTheme.labelMedium?.copyWith(color: scheme.error),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        isEnabled ? 'Automatic backup is on' : 'Paused until you turn it on',
                        style: context.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
            ),
            Switch.adaptive(value: isEnabled, onChanged: (value) => _onToggle(ref, value)),
          ],
        ),
      ),
    );
  }
}

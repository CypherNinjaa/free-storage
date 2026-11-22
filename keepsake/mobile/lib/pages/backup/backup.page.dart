import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/local_album.model.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/platform_extensions.dart';
import 'package:immich_mobile/extensions/theme_extensions.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/presentation/widgets/backup/backup_toggle_button.widget.dart';
import 'package:immich_mobile/presentation/widgets/backup/encrypt_uploads_tile.widget.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/providers/backup/backup.provider.dart';
import 'package:immich_mobile/providers/backup/backup_album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';
import 'package:immich_mobile/providers/permission.provider.dart';
import 'package:immich_mobile/providers/sync_status.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_ui/immich_ui.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

@RoutePage()
class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool? syncSuccess;

  @override
  void initState() {
    super.initState();

    unawaited(WakelockPlus.enable());

    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final backupNotifier = ref.read(backupProvider.notifier);
      final syncManager = ref.read(backgroundSyncProvider);

      await backupNotifier.getBackupStatus(currentUser.id);

      backupNotifier.updateSyncing(true);
      syncSuccess = await syncManager.syncRemote();
      backupNotifier.updateSyncing(false);

      if (mounted) {
        await backupNotifier.getBackupStatus(currentUser.id);
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
    unawaited(WakelockPlus.disable());
  }

  @override
  Widget build(BuildContext context) {
    final selectedAlbum = ref
        .watch(backupAlbumProvider)
        .where((album) => album.backupSelection == BackupSelection.selected)
        .toList();

    final error = ref.watch(backupProvider.select((p) => p.error));

    final backupNotifier = ref.watch(backupProvider.notifier);
    final backupSyncManager = ref.watch(backgroundSyncProvider);

    Future<void> startBackup() async {
      final currentUser = Store.tryGet(StoreKey.currentUser);
      if (currentUser == null) {
        return;
      }

      if (syncSuccess == null) {
        backupNotifier.updateSyncing(true);
        syncSuccess = await backupSyncManager.syncRemote();
        backupNotifier.updateSyncing(false);
      }

      await backupNotifier.getBackupStatus(currentUser.id);

      if (syncSuccess == false) {
        Logger("BackupPage").warning("Remote sync did not complete successfully, skipping backup");
        return;
      }
      await backupNotifier.startForegroundBackup(currentUser.id);
    }

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text(context.t.backup_controller_page_backup),
        leading: IconButton(
          onPressed: () {
            unawaited(context.maybePop(true));
          },
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          IconButton(
            onPressed: () {
              unawaited(context.pushRoute(const BackupOptionsRoute()));
            },
            icon: const Icon(Icons.settings_outlined),
            tooltip: context.t.backup_options,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        children: [
          if (selectedAlbum.isNotEmpty) ...[
            const _VaultSummaryCard(),
            const SizedBox(height: 12),
            BackupToggleButton(
              onStart: () async => await startBackup(),
              onStop: () {
                syncSuccess = null;
                backupNotifier.stopForegroundBackup(reason: "backup button toggled off");
              },
            ),
            const EncryptUploadsTile(),
            const SizedBox(height: 12),
          ],
          const _BackupAlbumSelectionCard(),
          if (selectedAlbum.isEmpty) ...[
            const EncryptUploadsTile(),
          ],
          if (selectedAlbum.isNotEmpty) ...[
            switch (error) {
              BackupError.none => const SizedBox.shrink(),
              BackupError.syncFailed => AmbryBanner(
                margin: const EdgeInsets.only(top: 12),
                variant: AmbryBannerVariant.error,
                title: 'Sync interrupted',
                body: context.t.backup_error_sync_failed,
              ),
            },
            const _BackupFooter(),
          ],
        ],
      ),
    );
  }
}

class _BackupFooter extends ConsumerStatefulWidget {
  const _BackupFooter();

  @override
  ConsumerState<_BackupFooter> createState() => _BackupFooterState();
}

class _BackupFooterState extends ConsumerState<_BackupFooter> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (CurrentPlatform.isAndroid && state == AppLifecycleState.resumed && mounted) {
      unawaited(ref.read(notificationPermissionProvider.notifier).getNotificationPermission());
      unawaited(ref.read(batteryOptimizationProvider.notifier).getBatteryOptimizationPermission());
    }
  }

  Future<void> showPermissionsDialog() {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(context.t.notification_permission_dialog_content),
        actions: [
          ImmichTextButton(
            labelText: context.t.cancel,
            variant: .ghost,
            expanded: false,
            onPressed: () => ContextHelper(ctx).pop(),
          ),
          ImmichTextButton(
            labelText: context.t.settings,
            variant: .ghost,
            expanded: false,
            onPressed: () {
              ContextHelper(ctx).pop();
              unawaited(openAppSettings());
            },
          ),
        ],
      ),
    );
  }

  Future<void> showBatteryOptimizationInfo() {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text(context.t.backup_controller_page_background_battery_info_title),
          content: SingleChildScrollView(child: Text(context.t.backup_controller_page_background_battery_info_message)),
          actions: [
            ImmichTextButton(
              labelText: context.t.backup_controller_page_background_battery_info_link,
              variant: .ghost,
              expanded: false,
              onPressed: () =>
                  unawaited(launchUrl(Uri.parse('https://dontkillmyapp.com'), mode: LaunchMode.externalApplication)),
            ),
            ImmichTextButton(
              labelText: context.t.backup_controller_page_background_battery_info_ok,
              variant: .ghost,
              expanded: false,
              onPressed: () => ContextHelper(ctx).pop(),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBackupEnabled = ref.watch(appConfigProvider.select((config) => config.backup.enabled));
    final notificationStatus = ref.watch(notificationPermissionProvider);
    final batteryOptimizationStatus = ref.watch(batteryOptimizationProvider).valueOrNull;

    return Column(
      children: [
        if (CurrentPlatform.isAndroid && isBackupEnabled) ...[
          if (notificationStatus != PermissionStatus.granted)
            TextButton.icon(
              iconAlignment: .end,
              icon: Icon(Icons.open_in_new_outlined, color: context.colorScheme.onSurfaceSecondary),
              label: Text(
                context.t.notification_backup_reliability,
                textAlign: TextAlign.left,
                style: context.textTheme.bodySmall?.copyWith(color: context.colorScheme.onSurfaceSecondary),
              ),
              onPressed: () {
                unawaited(
                  ref.read(notificationPermissionProvider.notifier).requestNotificationPermission().then((p) {
                    if (p == PermissionStatus.permanentlyDenied) {
                      unawaited(showPermissionsDialog());
                    }
                  }),
                );
              },
            ),
          if (notificationStatus != PermissionStatus.granted && batteryOptimizationStatus != PermissionStatus.granted)
            const Divider(indent: 32, endIndent: 32),
          // Phones such as Realme/Oppo/OnePlus (ColorOS), Xiaomi and Vivo freeze apps in the background a few
          // seconds after they close, so background backup never gets to run until the user allows it.
          if (batteryOptimizationStatus != null && batteryOptimizationStatus != PermissionStatus.granted)
            AmbryBanner(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              variant: AmbryBannerVariant.error,
              icon: Icons.battery_alert_rounded,
              title: 'Background backup is paused by your phone',
              body:
                  'Your phone stops Ambry soon after you close it, so new photos are backed up only when you '
                  'open the app. To back up in the background, open app settings, then Battery, and allow '
                  'background activity (or choose "Unrestricted").',
              actions: [
                TextButton(
                  onPressed: () => unawaited(showBatteryOptimizationInfo()),
                  child: const Text('Learn more'),
                ),
                FilledButton.tonal(
                  onPressed: () => unawaited(openAppSettings()),
                  child: const Text('Open app settings'),
                ),
              ],
            ),
        ],
        const SizedBox(height: 8),
        TextButton.icon(
          icon: const Icon(Icons.info_outline_rounded, size: 18),
          onPressed: () => context.pushRoute(const UploadDetailRoute()),
          label: Text(context.t.view_details),
        ),
      ],
    );
  }
}

class _BackupAlbumSelectionCard extends ConsumerWidget {
  const _BackupAlbumSelectionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backupAlbums = ref.watch(backupAlbumProvider);
    final scheme = context.colorScheme;

    Widget buildSelectedAlbumName() {
      String text = context.t.backup_controller_page_backup_selected;
      final albums = backupAlbums.where((album) => album.backupSelection == BackupSelection.selected).toList();

      if (albums.isNotEmpty) {
        for (var album in albums) {
          if (album.name == "Recent" || album.name == "Recents") {
            text += "${album.name} (${context.t.all}), ";
          } else {
            text += "${album.name}, ";
          }
        }

        return Padding(
          padding: const EdgeInsets.only(top: 6.0),
          child: Text(
            text.trim().substring(0, text.length - 2),
            style: context.textTheme.labelMedium?.copyWith(color: scheme.onSurface),
          ),
        );
      } else {
        return Padding(
          padding: const EdgeInsets.only(top: 6.0),
          child: Text(
            context.t.backup_controller_page_none_selected,
            style: context.textTheme.labelMedium?.copyWith(color: scheme.primary),
          ),
        );
      }
    }

    Widget buildExcludedAlbumName() {
      String text = context.t.backup_controller_page_excluded;
      final albums = backupAlbums.where((album) => album.backupSelection == BackupSelection.excluded).toList();

      if (albums.isNotEmpty) {
        for (var album in albums) {
          text += "${album.name}, ";
        }

        return Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            text.trim().substring(0, text.length - 2),
            style: context.textTheme.labelMedium?.copyWith(color: scheme.error),
          ),
        );
      } else {
        return const SizedBox.shrink();
      }
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.lg)),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: scheme.surfaceContainerHigh, shape: BoxShape.circle),
              child: Icon(Icons.folder_copy_outlined, size: 20, color: scheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t.backup_controller_page_albums,
                    style: context.textTheme.titleMedium?.copyWith(color: scheme.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.t.backup_controller_page_to_backup,
                    style: context.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  buildSelectedAlbumName(),
                  buildExcludedAlbumName(),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onPressed: () async {
                await context.pushRoute(const BackupAlbumSelectionRoute());
                if (!context.mounted) {
                  return;
                }

                final currentUser = ref.read(currentUserProvider);
                if (currentUser == null) {
                  return;
                }
                unawaited(ref.read(backupProvider.notifier).getBackupStatus(currentUser.id));
              },
              child: Text(context.t.select),
            ),
          ],
        ),
      ),
    );
  }
}

class _VaultSummaryCard extends ConsumerWidget {
  const _VaultSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalCount = ref.watch(backupProvider.select((p) => p.totalCount));
    final backupCount = ref.watch(backupProvider.select((p) => p.backupCount));
    final remainderCount = ref.watch(backupProvider.select((p) => p.remainderCount));
    final isRemoteSyncing = ref.watch(syncStatusProvider.select((s) => s.isRemoteSyncing));
    final scheme = context.colorScheme;
    final colors = context.immichColors;

    final progress = totalCount > 0 ? (backupCount / totalCount).clamp(0.0, 1.0) : 0.0;
    final isAllBackedUp = remainderCount == 0 && backupCount > 0 && !isRemoteSyncing;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.xl)),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      'Vault backup',
                      style: context.textTheme.titleMedium?.copyWith(color: scheme.onSurface),
                    ),
                    const Spacer(),
                    if (isRemoteSyncing)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Syncing…',
                            style: context.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      )
                    else if (isAllBackedUp)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: colors.successContainer,
                          borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.pill)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_rounded, size: 14, color: colors.onSuccessContainer),
                            const SizedBox(width: 5),
                            Text(
                              'All backed up',
                              style: context.textTheme.labelMedium?.copyWith(
                                color: colors.onSuccessContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Text(
                        '${(progress * 100).round()}%',
                        style: context.textTheme.titleSmall?.copyWith(
                          color: scheme.onSurface,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.pill)),
                  child: LinearProgressIndicator(
                    value: isRemoteSyncing ? null : progress,
                    minHeight: 5,
                    backgroundColor: scheme.surfaceContainerHighest,
                    color: isAllBackedUp ? colors.success : scheme.primary,
                  ),
                ),
                const SizedBox(height: 16),
                IntrinsicHeight(
                  child: Row(
                    children: [
                      _MetricColumn(label: context.t.total, value: totalCount),
                      VerticalDivider(width: 1, thickness: 1, color: scheme.outlineVariant),
                      _MetricColumn(label: context.t.backup_controller_page_backup, value: backupCount),
                      VerticalDivider(width: 1, thickness: 1, color: scheme.outlineVariant),
                      _MetricColumn(
                        label: context.t.backup_controller_page_remainder,
                        value: remainderCount,
                        highlight: remainderCount > 0,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const _PreparingStatus(),
          Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
          InkWell(
            onTap: () => context.pushRoute(const BackupAssetDetailRoute()),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                children: [
                  Text(
                    context.t.view_details,
                    style: context.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right_rounded, size: 20, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricColumn extends StatelessWidget {
  final String label;
  final int value;
  final bool highlight;

  const _MetricColumn({required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;

    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value.toString(),
            style: context.textTheme.headlineSmall?.copyWith(
              color: highlight ? scheme.primary : scheme.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _PreparingStatus extends ConsumerStatefulWidget {
  const _PreparingStatus();

  @override
  _PreparingStatusState createState() => _PreparingStatusState();
}

class _PreparingStatusState extends ConsumerState {
  Timer? _pollingTimer;

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  void _startPollingIfNeeded() {
    if (_pollingTimer != null) {
      return;
    }

    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      final currentUser = ref.read(currentUserProvider);
      if (currentUser != null && mounted) {
        await ref.read(backupProvider.notifier).getBackupStatus(currentUser.id);
        if (!context.mounted) {
          timer.cancel();
          _pollingTimer = null;
          return;
        }

        // Stop polling if processing count reaches 0
        final updatedProcessingCount = ref.read(backupProvider.select((p) => p.processingCount));
        if (updatedProcessingCount == 0) {
          timer.cancel();
          _pollingTimer = null;
        }
      } else {
        timer.cancel();
        _pollingTimer = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final syncStatus = ref.watch(syncStatusProvider);
    final remainderCount = ref.watch(backupProvider.select((p) => p.remainderCount));
    final processingCount = ref.watch(backupProvider.select((p) => p.processingCount));
    final readyForUploadCount = remainderCount - processingCount;

    ref.listen<int>(backupProvider.select((p) => p.processingCount), (previous, next) {
      if (next > 0 && _pollingTimer == null) {
        _startPollingIfNeeded();
      } else if (next == 0 && _pollingTimer != null) {
        _pollingTimer?.cancel();
        _pollingTimer = null;
      }
    });

    if (!syncStatus.isHashing) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 1.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
              decoration: BoxDecoration(
                color: context.colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
                shape: BoxShape.rectangle,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        context.t.preparing,
                        style: context.textTheme.labelLarge?.copyWith(
                          color: context.colorScheme.onSurface.withAlpha(200),
                        ),
                      ),
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 1.5)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    processingCount.toString(),
                    style: context.textTheme.titleMedium?.copyWith(
                      color: context.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [const FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            decoration: BoxDecoration(color: context.colorScheme.primary.withValues(alpha: 0.1)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  context.t.ready_for_upload,
                  style: context.textTheme.labelLarge?.copyWith(color: context.colorScheme.onSurface.withAlpha(200)),
                ),
                const SizedBox(height: 2),
                Text(
                  readyForUploadCount.toString(),
                  style: context.textTheme.titleMedium?.copyWith(
                    color: context.primaryColor,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [const FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

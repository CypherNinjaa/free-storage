import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart' hide Store;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/pages/common/settings.page.dart';
import 'package:immich_mobile/platform/keepsake_api.g.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/providers/infrastructure/platform.provider.dart';
import 'package:immich_mobile/providers/infrastructure/readonly_mode.provider.dart';
import 'package:immich_mobile/providers/locale_provider.dart';
import 'package:immich_mobile/providers/websocket.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/widgets/common/app_bar_dialog/app_bar_profile_info.dart';
import 'package:immich_ui/immich_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Where Ambry's source code is published, as the AGPL requires for the Immich code it is built on.
const _sourceCodeUrl = 'https://github.com/CypherNinjaa/free-storage';
const _privacyPolicyUrl = 'https://ambry.vikashin.tech/privacy/';

String _ago(int epochMs) {
  final elapsed = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(epochMs));
  if (elapsed.inMinutes < 1) {
    return 'just now';
  }
  if (elapsed.inHours < 1) {
    return '${elapsed.inMinutes} min ago';
  }
  if (elapsed.inDays < 1) {
    return '${elapsed.inHours} h ago';
  }
  return elapsed.inDays == 1 ? 'yesterday' : '${elapsed.inDays} days ago';
}

class ImmichAppBarDialog extends HookConsumerWidget {
  const ImmichAppBarDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(localeProvider);
    final scheme = context.colorScheme;
    final colors = context.immichColors;
    final isLoggingOut = useState(false);
    final isSelfTesting = useState(false);
    final isSnapshotting = useState(false);
    final vaultCount = useFuture(useMemoized(() => ref.read(keepsakeLibraryApiProvider).assetCount()));
    final statusRefresh = useState(0);
    final backupStatus = useFuture(
      useMemoized(() => ref.read(keepsakeLibraryApiProvider).getIndexBackupStatus(), [statusRefresh.value]),
    );
    final activeDevice = useFuture(
      useMemoized(
        () => ref
            .read(keepsakeLibraryApiProvider)
            .getActiveDevice()
            .then<ActiveDeviceStatus?>((s) => s, onError: (_) => null),
        [statusRefresh.value],
      ),
    );
    final isClaiming = useState(false);
    final isReadonlyModeEnabled = ref.watch(readonlyModeProvider);

    Widget buildActionTile(
      IconData icon,
      String text,
      VoidCallback onTap, {
      Widget? trailing,
      Color? iconColor,
      Color? textColor,
    }) {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Icon(icon, color: iconColor ?? scheme.onSurfaceVariant, size: 22),
        title: Text(
          text,
          style: context.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w500,
            color: textColor ?? scheme.onSurface,
          ),
        ),
        trailing: trailing ?? Icon(Icons.chevron_right_rounded, size: 20, color: scheme.onSurfaceVariant),
        onTap: onTap,
      );
    }

    Future<void> runSelfTest() async {
      if (isSelfTesting.value) {
        return;
      }
      isSelfTesting.value = true;
      try {
        final report = await ref.read(keepsakeTelegramApiProvider).runSelfTest();
        if (!context.mounted) {
          return;
        }
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(report.success ? 'Vault self-test passed' : 'Vault self-test failed'),
            content: SingleChildScrollView(child: Text(report.steps.join('\n'))),
            actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(context.t.ok))],
          ),
        );
      } on PlatformException catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message ?? error.code)));
        }
      } finally {
        isSelfTesting.value = false;
      }
    }

    Future<void> runSnapshot() async {
      if (isSnapshotting.value) {
        return;
      }
      isSnapshotting.value = true;
      try {
        final count = await ref.read(keepsakeLibraryApiProvider).snapshotIndex(true);
        statusRefresh.value++;
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Library index backed up to Telegram ($count items)')));
        }
      } on PlatformException catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message ?? error.code)));
        }
      } finally {
        isSnapshotting.value = false;
      }
    }

    Future<void> handleSignOut() async {
      if (isLoggingOut.value) {
        return;
      }
      await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) {
          return AmbryConfirmDialog(
            title: context.t.app_bar_signout_dialog_title,
            content: context.t.app_bar_signout_dialog_content,
            confirmLabel: context.t.sign_out,
            cancelLabel: context.t.cancel,
            destructive: true,
            onConfirm: () async {
              isLoggingOut.value = true;
              try {
                await ref.read(authProvider.notifier).logout();
                if (!context.mounted) {
                  return;
                }
                ref.read(websocketProvider.notifier).disconnect();
                if (!context.mounted) {
                  return;
                }
                unawaited(context.replaceRoute(const LoginRoute()));
              } finally {
                isLoggingOut.value = false;
              }
            },
          );
        },
      );
    }

    Widget buildActiveDeviceWarning() {
      final status = activeDevice.data;
      if (status == null || status.isThisDevice) {
        return const SizedBox.shrink();
      }
      return AmbryBanner(
        margin: const EdgeInsets.only(bottom: 12),
        variant: AmbryBannerVariant.error,
        title: 'Backups paused on this phone',
        body:
            'Your vault is active on ${status.deviceName ?? 'another phone'}'
            '${status.claimedAtMs == null ? '' : ' (since ${_ago(status.claimedAtMs!)})'}. '
            'Only one phone writes to a vault at a time.',
        actions: [
          FilledButton.tonal(
            onPressed: isClaiming.value
                ? null
                : () async {
                    isClaiming.value = true;
                    try {
                      await ref.read(keepsakeLibraryApiProvider).claimVault();
                      statusRefresh.value++;
                    } on PlatformException catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message ?? error.code)));
                      }
                    } finally {
                      isClaiming.value = false;
                    }
                  },
            child: isClaiming.value
                ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Use this phone'),
          ),
        ],
      );
    }

    Widget buildStorageInformation() {
      final indexStatus = backupStatus.data;
      final isUpToDate = indexStatus != null && indexStatus.lastSnapshotAtMs != null && indexStatus.pendingChanges == 0;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isUpToDate ? colors.successContainer : scheme.surfaceContainerHigh,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.verified_user_outlined,
                size: 18,
                color: isUpToDate ? colors.onSuccessContainer : scheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Private Telegram vault', style: context.textTheme.titleSmall?.copyWith(color: scheme.onSurface)),
                  const SizedBox(height: 2),
                  Text(
                    vaultCount.hasData
                        ? '${vaultCount.data} items in your private Telegram channel'
                        : 'Storage: your private Telegram channel · no server',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (indexStatus != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      indexStatus.lastSnapshotAtMs == null
                          ? 'Library index not backed up yet'
                          : 'Library index backed up ${_ago(indexStatus.lastSnapshotAtMs!)}'
                                '${indexStatus.pendingChanges == 0 ? ' · up to date' : ' · changes back up daily'}',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: isUpToDate ? colors.success : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget buildFooter() {
      return Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
              onPressed: () async {
                ContextHelper(context).pop();
                final packageInfo = await PackageInfo.fromPlatform();
                if (!context.mounted) {
                  return;
                }
                showLicensePage(
                  context: context,
                  applicationName: 'Ambry',
                  applicationVersion: packageInfo.version,
                  applicationLegalese:
                      'Ambry is free software under the GNU Affero General Public License v3. It is a modified '
                      'version of the Immich mobile app (© Immich contributors, AGPL-3.0) and uses TDLib '
                      '(Boost Software License). Source code: $_sourceCodeUrl',
                );
              },
              child: Text(context.t.licenses, style: context.textTheme.labelMedium),
            ),
            Text('·', style: TextStyle(color: scheme.onSurfaceVariant)),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
              onPressed: () => unawaited(launchUrl(Uri.parse(_sourceCodeUrl), mode: LaunchMode.externalApplication)),
              child: Text('Source code', style: context.textTheme.labelMedium),
            ),
            Text('·', style: TextStyle(color: scheme.onSurfaceVariant)),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
              onPressed: () => unawaited(launchUrl(Uri.parse(_privacyPolicyUrl), mode: LaunchMode.externalApplication)),
              child: Text('Privacy', style: context.textTheme.labelMedium),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.pill)),
                ),
              ),
            ),
            Row(
              children: [
                const SizedBox(width: 4),
                const AmbryBrandMark(iconSize: 24),
                const Spacer(),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => ContextHelper(context).pop(),
                  icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainer,
                borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.lg)),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  const AppBarProfileInfoBox(),
                  Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
                  buildStorageInformation(),
                ],
              ),
            ),
            const SizedBox(height: 12),
            buildActiveDeviceWarning(),
            if (isReadonlyModeEnabled)
              AmbryBanner(
                margin: const EdgeInsets.only(bottom: 12),
                variant: AmbryBannerVariant.info,
                title: context.t.profile_drawer_readonly_mode,
              ),
            Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainer,
                borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.lg)),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  buildActionTile(
                    Icons.cleaning_services_outlined,
                    context.t.free_up_space,
                    () {
                      ContextHelper(context).pop();
                      unawaited(context.pushRoute(SettingsSubRoute(section: SettingSection.freeUpSpace)));
                    },
                  ),
                  Divider(height: 1, thickness: 1, indent: 54, color: scheme.outlineVariant),
                  buildActionTile(
                    Icons.settings_outlined,
                    context.t.settings,
                    () {
                      ContextHelper(context).pop();
                      unawaited(context.pushRoute(const SettingsRoute()));
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainer,
                borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.lg)),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Theme(
                data: context.themeData.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: Icon(Icons.build_outlined, size: 22, color: scheme.onSurfaceVariant),
                  title: Text(
                    'Vault maintenance',
                    style: context.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500, color: scheme.onSurface),
                  ),
                  children: [
                    Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
                    buildActionTile(
                      Icons.cloud_sync_outlined,
                      'Back up library index now',
                      runSnapshot,
                      trailing: isSnapshotting.value
                          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const SizedBox.shrink(),
                    ),
                    Divider(height: 1, thickness: 1, indent: 54, color: scheme.outlineVariant),
                    buildActionTile(
                      Icons.health_and_safety_outlined,
                      'Run vault self-test',
                      runSelfTest,
                      trailing: isSelfTesting.value
                          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const SizedBox.shrink(),
                    ),
                    Divider(height: 1, thickness: 1, indent: 54, color: scheme.outlineVariant),
                    buildActionTile(
                      Icons.assignment_outlined,
                      context.t.profile_drawer_app_logs,
                      () {
                        ContextHelper(context).pop();
                        unawaited(context.pushRoute(const AppLogRoute()));
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainer,
                borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.lg)),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
              ),
              clipBehavior: Clip.antiAlias,
              child: buildActionTile(
                Icons.logout_rounded,
                context.t.sign_out,
                handleSignOut,
                iconColor: scheme.error,
                textColor: scheme.error,
                trailing: isLoggingOut.value
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const SizedBox.shrink(),
              ),
            ),
            buildFooter(),
          ],
        ),
      ),
    );
  }
}

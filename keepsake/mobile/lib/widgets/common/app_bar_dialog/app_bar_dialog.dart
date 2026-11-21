import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart' hide Store;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/pages/common/settings.page.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/providers/infrastructure/platform.provider.dart';
import 'package:immich_mobile/providers/infrastructure/readonly_mode.provider.dart';
import 'package:immich_mobile/providers/locale_provider.dart';
import 'package:immich_mobile/providers/websocket.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/widgets/common/app_bar_dialog/app_bar_profile_info.dart';
import 'package:immich_mobile/widgets/common/confirm_dialog.dart';
import 'package:package_info_plus/package_info_plus.dart';

class ImmichAppBarDialog extends HookConsumerWidget {
  const ImmichAppBarDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(localeProvider);
    final theme = context.themeData;
    final bool isHorizontal = !context.isMobile;
    final horizontalPadding = isHorizontal ? 100.0 : 20.0;
    final isLoggingOut = useState(false);
    final isSelfTesting = useState(false);
    final isReadonlyModeEnabled = ref.watch(readonlyModeProvider);

    useEffect(() {
      // Serverless mode: no remote server disk/user refresh calls.
      return null;
    }, []);

    SizedBox buildTopRow() {
      return SizedBox(
        height: 56,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            IconButton(
              onPressed: () => ContextHelper(context).pop(),
              icon: Icon(Icons.close, size: 20, color: context.colorScheme.onSurfaceVariant),
            ),
            Align(
              alignment: Alignment.center,
              child: Text(
                'Keepsake',
                style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }

    ListTile buildActionButton(IconData icon, String text, Function() onTap, {Widget? trailing}) {
      return ListTile(
        dense: true,
        visualDensity: VisualDensity.standard,
        contentPadding: const EdgeInsets.only(left: 30, right: 30),
        minLeadingWidth: 40,
        leading: SizedBox(child: Icon(icon, color: theme.textTheme.labelLarge?.color?.withAlpha(250), size: 20)),
        title: Text(
          text,
          style: theme.textTheme.labelLarge?.copyWith(color: theme.textTheme.labelLarge?.color?.withAlpha(250)),
        ),
        onTap: onTap,
        trailing: trailing,
      );
    }

    ListTile buildSettingButton() {
      return buildActionButton(
        Icons.settings_outlined,
        context.t.settings,
        () => context.pushRoute(const SettingsRoute()),
      );
    }

    ListTile buildFreeUpSpaceButton() {
      return buildActionButton(
        Icons.cleaning_services_outlined,
        context.t.free_up_space,
        () => context.pushRoute(SettingsSubRoute(section: SettingSection.freeUpSpace)),
      );
    }

    ListTile buildSelfTestButton() {
      return buildActionButton(
        Icons.health_and_safety_outlined,
        'Run vault self-test',
        () async {
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
        },
        trailing: isSelfTesting.value
            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : null,
      );
    }

    ListTile buildAppLogButton() {
      return buildActionButton(
        Icons.assignment_outlined,
        context.t.profile_drawer_app_logs,
        () => context.pushRoute(const AppLogRoute()),
      );
    }

    ListTile buildSignOutButton() {
      return buildActionButton(
        Icons.logout_rounded,
        context.t.sign_out,
        () async {
          if (isLoggingOut.value) {
            return;
          }

          unawaited(
            showDialog(
              context: context,
              builder: (BuildContext ctx) {
                return ConfirmDialog(
                  title: context.t.app_bar_signout_dialog_title,
                  content: context.t.app_bar_signout_dialog_content,
                  ok: context.t.yes,
                  onOk: () async {
                    isLoggingOut.value = true;
                    await ref.read(authProvider.notifier).logout().whenComplete(() => isLoggingOut.value = false);
                    if (!context.mounted) {
                      return;
                    }

                    ref.read(websocketProvider.notifier).disconnect();
                    if (!context.mounted) {
                      return;
                    }

                    unawaited(context.replaceRoute(const LoginRoute()));
                  },
                );
              },
            ),
          );
        },
        trailing: isLoggingOut.value
            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : null,
      );
    }

    Widget buildStorageInformation() {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.verified_user_outlined, size: 20, color: context.primaryColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Serverless Encrypted Vault', style: context.textTheme.labelLarge),
                  Text(
                    'Storage: Private Telegram Channel (TDLib) • Zero Server',
                    style: context.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Padding buildFooter() {
      return Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Powered by the Telegram API', style: context.textTheme.bodySmall),
            const SizedBox(width: 14, child: Text("•", textAlign: TextAlign.center)),
            InkWell(
              onTap: () async {
                ContextHelper(context).pop();
                final packageInfo = await PackageInfo.fromPlatform();
                if (!context.mounted) {
                  return;
                }

                showLicensePage(
                  context: context,
                  applicationName: 'Keepsake',
                  applicationVersion: packageInfo.version,
                );
              },
              child: Text(context.t.licenses, style: context.textTheme.bodySmall),
            ),
          ],
        ),
      );
    }

    Padding buildReadonlyMessage() {
      return Padding(
        padding: const EdgeInsets.only(left: 10.0, right: 10.0),
        child: ListTile(
          dense: true,
          visualDensity: VisualDensity.standard,
          contentPadding: const EdgeInsets.only(left: 20, right: 20),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
          minLeadingWidth: 20,
          tileColor: theme.primaryColor.withAlpha(80),
          title: Text(
            context.t.profile_drawer_readonly_mode,
            style: theme.textTheme.labelLarge?.copyWith(color: theme.textTheme.labelLarge?.color?.withAlpha(250)),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Dismissible(
      behavior: HitTestBehavior.translucent,
      direction: DismissDirection.down,
      onDismissed: (_) => ContextHelper(context).pop(),
      key: const Key('app_bar_dialog'),
      child: Dialog(
        clipBehavior: Clip.hardEdge,
        alignment: Alignment.topCenter,
        insetPadding: EdgeInsets.only(
          top: isHorizontal ? 20 : 40,
          left: horizontalPadding,
          right: horizontalPadding,
          bottom: isHorizontal ? 20 : 100,
        ),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
        child: SizedBox(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 8), child: buildTopRow()),
                Container(
                  decoration: BoxDecoration(
                    color: context.colorScheme.surface,
                    borderRadius: const BorderRadius.all(Radius.circular(10)),
                  ),
                  margin: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
                  child: Column(
                    children: [
                      const AppBarProfileInfoBox(),
                      Divider(thickness: 4, color: context.colorScheme.surfaceContainer),
                      buildStorageInformation(),
                    ],
                  ),
                ),
                if (isReadonlyModeEnabled) buildReadonlyMessage(),
                buildSelfTestButton(),
                buildAppLogButton(),
                buildFreeUpSpaceButton(),
                buildSettingButton(),
                buildSignOutButton(),
                buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

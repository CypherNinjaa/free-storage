import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/utils/recovery_kit.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/platform/keepsake_api.g.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/providers/gallery_permission.provider.dart';
import 'package:immich_mobile/providers/infrastructure/platform.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:package_info_plus/package_info_plus.dart';

@RoutePage()
class LoginPage extends HookConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final telegramApi = ref.watch(keepsakeTelegramApiProvider);
    final vaultApi = ref.watch(keepsakeVaultApiProvider);
    final libraryApi = ref.watch(keepsakeLibraryApiProvider);

    final step = useState(0);
    final vaultNameController = useTextEditingController(text: 'My Vault');
    final phoneController = useTextEditingController();
    final codeController = useTextEditingController();
    final telegramPasswordController = useTextEditingController();
    final passphraseController = useTextEditingController();
    final confirmPassphraseController = useTextEditingController();
    final obscurePassphrase = useState(true);
    final recoveryWords = useMemoized(RecoveryKit.generate24Words);
    final savedRecoveryChecked = useState(false);
    final authStatus = useState<TelegramAuthStatus?>(null);
    final existingVault = useState(false);
    final discoveredVault = useState<DiscoveredVault?>(null);
    final discoveryFailed = useState(false);
    final useRecoveryWords = useState(false);
    final recoveryWordsController = useTextEditingController();
    final isBusy = useState(false);
    final progressText = useState<String?>(null);
    final errorText = useState<String?>(null);
    final appVersion = useState('0.1.0');

    Future<void> runTelegramAction(Future<TelegramAuthStatus> Function() action) async {
      if (isBusy.value) {
        return;
      }
      isBusy.value = true;
      errorText.value = null;
      try {
        authStatus.value = await action();
      } on PlatformException catch (e) {
        errorText.value = e.message ?? e.code;
      } catch (e) {
        errorText.value = '$e';
      } finally {
        isBusy.value = false;
      }
    }

    useEffect(() {
      unawaited(PackageInfo.fromPlatform().then((info) => appVersion.value = info.version));
      unawaited(runTelegramAction(telegramApi.getAuthStatus));
      unawaited(vaultApi.getStatus().then((status) => existingVault.value = status.exists));
      return null;
    }, const []);

    /// Before creating a vault, look for one this Telegram account already holds (new phone or reinstall).
    /// A found vault's descriptor and channels are adopted, so the unlock step can open it.
    Future<void> continueToEncryption({bool skipDiscovery = false}) async {
      if (isBusy.value) {
        return;
      }
      errorText.value = null;
      if (existingVault.value || skipDiscovery) {
        step.value = 1;
        return;
      }
      isBusy.value = true;
      progressText.value = 'Looking for an existing vault in this Telegram account…';
      try {
        final found = await libraryApi.discoverAndAdoptVault();
        if (found != null) {
          discoveredVault.value = found;
          vaultNameController.text = found.vaultName;
          existingVault.value = true;
        }
        discoveryFailed.value = false;
        step.value = 1;
      } on PlatformException catch (e) {
        discoveryFailed.value = true;
        errorText.value = 'Could not check Telegram for an existing vault: ${e.message ?? e.code}';
      } catch (e) {
        discoveryFailed.value = true;
        errorText.value = 'Could not check Telegram for an existing vault: $e';
      } finally {
        progressText.value = null;
        isBusy.value = false;
      }
    }

    Future<void> completeSetup() async {
      progressText.value = 'Preparing your private Telegram channels…';
      await telegramApi.ensureVaultChannels(vaultNameController.text.trim());

      if (await libraryApi.assetCount() == 0) {
        // New phone or reinstall: rebuild the on-device index from the newest snapshot plus channel history.
        progressText.value = discoveredVault.value != null
            ? 'Restoring your library from Telegram. Large libraries take a few minutes…'
            : 'Checking your vault…';
        await libraryApi.restoreIndex();
      }

      progressText.value = 'Opening your timeline…';
      await ref
          .read(authProvider.notifier)
          .completeServerlessOnboarding(
            displayName: vaultNameController.text.trim(),
            telegramAccountName: authStatus.value?.accountName ?? '',
          );

      // Like Immich's login: photos, videos and media location (original EXIF/GPS bytes) are needed to back up.
      progressText.value = 'Allow access to your photos and videos…';
      await ref.read(galleryPermissionNotifier.notifier).requestGalleryPermission();

      final backgroundManager = ref.read(backgroundSyncProvider);
      unawaited(backgroundManager.syncRemote());
      unawaited(backgroundManager.syncLocal(full: true).then((_) => backgroundManager.hashAssets()));

      if (!context.mounted) {
        return;
      }
      await context.router.replaceAll([const TabShellRoute()]);
    }

    Future<void> runSetup(String progress, Future<void> Function() unlockOrCreate) async {
      if (isBusy.value) {
        return;
      }
      isBusy.value = true;
      errorText.value = null;
      try {
        progressText.value = progress;
        await unlockOrCreate();
        await completeSetup();
      } on PlatformException catch (e) {
        errorText.value = e.code == 'WRONG_SECRET'
            ? 'That passphrase or recovery phrase does not unlock this vault.'
            : 'Setup failed: ${e.message ?? e.code}';
      } catch (e) {
        errorText.value = 'Setup failed: $e';
      } finally {
        progressText.value = null;
        isBusy.value = false;
      }
    }

    Future<void> createVaultAndFinish() => runSetup(
      'Creating your encrypted vault…',
      () => vaultApi.createVault(passphraseController.text, RecoveryKit.toEntropy(recoveryWords)),
    );

    Future<void> unlockVaultAndFinish() async {
      if (!useRecoveryWords.value) {
        return runSetup('Unlocking your vault…', () => vaultApi.unlockWithPassphrase(passphraseController.text));
      }
      final words = recoveryWordsController.text.trim().toLowerCase().split(RegExp(r'[\s,]+'));
      if (words.length != RecoveryKit.wordCount || !words.every(RecoveryKit.isWord)) {
        errorText.value = 'Enter all ${RecoveryKit.wordCount} recovery words in order, separated by spaces.';
        return;
      }
      return runSetup(
        'Unlocking your vault with the recovery kit…',
        () => vaultApi.unlockWithRecoveryEntropy(RecoveryKit.toEntropy(words)),
      );
    }

    final telegramStep = authStatus.value?.step;

    Widget buildTelegramLogin() {
      switch (telegramStep) {
        case null:
        case TelegramAuthStep.starting:
        case TelegramAuthStep.loggingOut:
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        case TelegramAuthStep.closed:
          return FilledButton(
            onPressed: isBusy.value ? null : () => runTelegramAction(telegramApi.getAuthStatus),
            child: const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('Reconnect to Telegram')),
          );
        case TelegramAuthStep.waitPhoneNumber:
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Dedicated Telegram phone number',
                  helperText: 'International format, e.g. +91 98765 43210',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: isBusy.value
                    ? null
                    : () => runTelegramAction(() => telegramApi.submitPhoneNumber(phoneController.text)),
                child: const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('Send login code')),
              ),
            ],
          );
        case TelegramAuthStep.waitCode:
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Telegram sent a login code to the dedicated account (check the Telegram app where that account is signed in).',
                style: context.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: codeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Login code',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.sms_outlined),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: isBusy.value ? null : () => runTelegramAction(() => telegramApi.submitCode(codeController.text)),
                child: const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('Verify code')),
              ),
            ],
          );
        case TelegramAuthStep.waitPassword:
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: telegramPasswordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Telegram two-step verification password',
                  helperText: authStatus.value?.passwordHint == null ? null : 'Hint: ${authStatus.value!.passwordHint}',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.password_rounded),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: isBusy.value
                    ? null
                    : () => runTelegramAction(() => telegramApi.submitPassword(telegramPasswordController.text)),
                child: const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('Verify password')),
              ),
            ],
          );
        case TelegramAuthStep.ready:
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: context.colorScheme.primaryContainer.withAlpha(120),
                child: ListTile(
                  leading: Icon(Icons.check_circle_rounded, color: context.colorScheme.primary),
                  title: const Text('Telegram connected'),
                  subtitle: Text(authStatus.value?.accountName ?? 'Dedicated account'),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: isBusy.value ? null : continueToEncryption,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: isBusy.value
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Continue to Encryption Setup'),
                ),
              ),
              if (progressText.value != null) ...[
                const SizedBox(height: 12),
                Text(progressText.value!, style: context.textTheme.bodySmall),
              ],
              if (discoveryFailed.value && !isBusy.value) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => continueToEncryption(skipDiscovery: true),
                  child: const Text('Create a new vault instead'),
                ),
              ],
            ],
          );
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ambry Setup'),
        centerTitle: false,
        actions: [TextButton(onPressed: () => context.pushRoute(const AppLogRoute()), child: const Text('Logs'))],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _StepPill(index: 1, label: 'Telegram', active: step.value == 0, done: step.value > 0),
                  const SizedBox(width: 8),
                  _StepPill(index: 2, label: 'Passphrase', active: step.value == 1, done: step.value > 1),
                  const SizedBox(width: 8),
                  _StepPill(index: 3, label: 'Recovery Kit', active: step.value == 2, done: false),
                ],
              ),
              const SizedBox(height: 24),

              if (step.value == 0) ...[
                Text(
                  'Welcome to Ambry',
                  style: context.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Serverless, client-encrypted photo & video vault stored in your own private Telegram channel.',
                  style: context.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Card(
                  color: context.colorScheme.secondaryContainer.withAlpha(110),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline_rounded, size: 18, color: context.colorScheme.onSecondaryContainer),
                            const SizedBox(width: 8),
                            Text(
                              'Telegram API Disclosure',
                              style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Ambry is an independent app that uses the Telegram API (TDLib) and is not affiliated with Telegram. '
                          'Always use a dedicated Telegram account rather than your personal account.',
                          style: context.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: vaultNameController,
                  decoration: const InputDecoration(
                    labelText: 'Vault Name',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.photo_library_outlined),
                  ),
                ),
                const SizedBox(height: 20),
                buildTelegramLogin(),
              ],

              if (step.value == 1 && existingVault.value) ...[
                Text(
                  'Unlock Your Vault',
                  style: context.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  discoveredVault.value != null
                      ? 'Found the vault “${discoveredVault.value!.vaultName}” in this Telegram account. '
                            'Unlock it to restore your library on this phone.'
                      : 'This phone already holds an encrypted Ambry vault. Unlock it to continue.',
                  style: context.textTheme.bodyMedium,
                ),
                const SizedBox(height: 18),
                if (!useRecoveryWords.value)
                  TextField(
                    controller: passphraseController,
                    obscureText: obscurePassphrase.value,
                    decoration: InputDecoration(
                      labelText: 'Vault passphrase',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(obscurePassphrase.value ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => obscurePassphrase.value = !obscurePassphrase.value,
                      ),
                    ),
                  )
                else
                  TextField(
                    controller: recoveryWordsController,
                    minLines: 3,
                    maxLines: 5,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: '24 recovery words',
                      helperText: 'In order, separated by spaces',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.key_rounded),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: isBusy.value
                        ? null
                        : () {
                            errorText.value = null;
                            useRecoveryWords.value = !useRecoveryWords.value;
                          },
                    child: Text(useRecoveryWords.value ? 'Use the passphrase instead' : 'Use the recovery kit instead'),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: isBusy.value ? null : () => step.value = 0,
                      child: const Text('Back'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: isBusy.value ? null : unlockVaultAndFinish,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: isBusy.value
                              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Unlock & Open Timeline'),
                        ),
                      ),
                    ),
                  ],
                ),
                if (progressText.value != null) ...[
                  const SizedBox(height: 12),
                  Text(progressText.value!, style: context.textTheme.bodySmall),
                ],
              ],

              if (step.value == 1 && !existingVault.value) ...[
                Text(
                  'Create Vault Passphrase',
                  style: context.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Every photo, video, thumbnail, and index backup is encrypted on this phone before leaving your device.',
                  style: context.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Card(
                  color: context.colorScheme.errorContainer.withAlpha(140),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded, color: context.colorScheme.error),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Lose your passphrase and recovery kit = lose your library. There is no server to reset it.',
                            style: context.textTheme.bodySmall?.copyWith(
                              color: context.colorScheme.onErrorContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: passphraseController,
                  obscureText: obscurePassphrase.value,
                  decoration: InputDecoration(
                    labelText: 'Passphrase (min 8 characters)',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(obscurePassphrase.value ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => obscurePassphrase.value = !obscurePassphrase.value,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: confirmPassphraseController,
                  obscureText: obscurePassphrase.value,
                  decoration: const InputDecoration(
                    labelText: 'Confirm Passphrase',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_reset_rounded),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: () {
                        errorText.value = null;
                        step.value = 0;
                      },
                      child: const Text('Back'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          final p1 = passphraseController.text;
                          final p2 = confirmPassphraseController.text;
                          if (p1.length < 8) {
                            errorText.value = 'Passphrase must be at least 8 characters.';
                            return;
                          }
                          if (p1 != p2) {
                            errorText.value = 'Passphrases do not match.';
                            return;
                          }
                          errorText.value = null;
                          step.value = 2;
                        },
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Text('Generate 24-Word Recovery Kit'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              if (step.value == 2) ...[
                Text(
                  'Save Your 24-Word Recovery Kit',
                  style: context.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Write down or print these 24 words together with your dedicated Telegram account phone number. '
                  'Either your passphrase or these words unlock your encrypted library on a new phone.',
                  style: context.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (int i = 0; i < recoveryWords.length; i++)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: context.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${i + 1}. ${recoveryWords[i]}',
                              style: const TextStyle(fontFamily: 'GoogleSansCode', fontSize: 13),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final text = recoveryWords.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n');
                      unawaited(Clipboard.setData(ClipboardData(text: text)));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('24-word recovery kit copied to clipboard')),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copy 24 Words'),
                  ),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: savedRecoveryChecked.value,
                  onChanged: (v) => savedRecoveryChecked.value = v ?? false,
                  title: const Text(
                    'I have saved my passphrase and 24-word recovery kit safely.',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: isBusy.value ? null : () => step.value = 1,
                      child: const Text('Back'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: savedRecoveryChecked.value && !isBusy.value ? createVaultAndFinish : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: isBusy.value
                              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Create Vault & Open Timeline'),
                        ),
                      ),
                    ),
                  ],
                ),
                if (progressText.value != null) ...[
                  const SizedBox(height: 12),
                  Text(progressText.value!, style: context.textTheme.bodySmall),
                ],
              ],

              if (errorText.value != null) ...[
                const SizedBox(height: 14),
                Text(
                  errorText.value!,
                  style: TextStyle(color: context.colorScheme.error, fontWeight: FontWeight.w500),
                ),
              ],

              const SizedBox(height: 28),
              Center(
                child: Text(
                  'Ambry v${appVersion.value}',
                  style: context.textTheme.bodySmall?.copyWith(fontFamily: 'GoogleSansCode'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepPill extends StatelessWidget {
  final int index;
  final String label;
  final bool active;
  final bool done;

  const _StepPill({required this.index, required this.label, required this.active, required this.done});

  @override
  Widget build(BuildContext context) {
    final color = active || done ? context.colorScheme.primary : context.colorScheme.surfaceContainerHighest;
    final fg = active || done ? context.colorScheme.onPrimary : context.colorScheme.onSurfaceVariant;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(done ? Icons.check_circle_rounded : Icons.circle, size: 12, color: fg),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                '$index. $label',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

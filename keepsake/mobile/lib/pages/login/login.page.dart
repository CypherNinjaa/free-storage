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
import 'package:immich_ui/immich_ui.dart';
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
    final passphraseText = useValueListenable(passphraseController).text;
    final obscurePassphrase = useState(true);
    final obscureConfirmPassphrase = useState(true);
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
      final words = RecoveryKit.parseWords(recoveryWordsController.text);
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
          final colors = context.immichColors;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.successContainer,
                  borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.lg)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: colors.onSuccessContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Telegram connected',
                            style: context.textTheme.titleSmall?.copyWith(color: colors.onSuccessContainer),
                          ),
                          Text(
                            authStatus.value?.accountName ?? 'Dedicated account',
                            style: context.textTheme.bodySmall?.copyWith(
                              color: colors.onSuccessContainer.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: isBusy.value ? null : continueToEncryption,
                child: isBusy.value
                    ? SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: context.colorScheme.onPrimary),
                      )
                    : const Text('Continue to Encryption Setup'),
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

    final totalSteps = existingVault.value ? 2 : 3;
    final currentStepNumber = (step.value + 1).clamp(1, totalSteps);
    final stepTitle = switch (step.value) {
      0 => 'Telegram',
      1 => existingVault.value ? 'Unlock Vault' : 'Passphrase',
      _ => 'Recovery Kit',
    };

    Widget buildStepBody() {
      if (step.value == 0) {
        return Column(
          key: const ValueKey('step_0'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Welcome to Ambry',
              style: context.textTheme.headlineMedium?.copyWith(color: context.colorScheme.onSurface),
            ),
            const SizedBox(height: 6),
            Text(
              'Your private photos & videos, encrypted on this phone and stored in your own Telegram channel.',
              style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            const AmbryBanner(
              variant: AmbryBannerVariant.info,
              title: 'Dedicated account recommended',
              body:
                  'Ambry is an independent app using the official Telegram API (TDLib) and is not affiliated with Telegram. '
                  'Use a dedicated Telegram account rather than your personal account.',
            ),
            const SizedBox(height: 20),
            TextField(
              controller: vaultNameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Vault Name',
                prefixIcon: Icon(Icons.photo_library_outlined),
              ),
            ),
            const SizedBox(height: 16),
            buildTelegramLogin(),
          ],
        );
      }

      if (step.value == 1 && existingVault.value) {
        return Column(
          key: const ValueKey('step_1_unlock'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Unlock Your Vault',
              style: context.textTheme.headlineMedium?.copyWith(color: context.colorScheme.onSurface),
            ),
            const SizedBox(height: 6),
            Text(
              discoveredVault.value != null
                  ? 'Found the vault “${discoveredVault.value!.vaultName}” in this Telegram account. '
                        'Unlock it to restore your library on this phone.'
                  : 'This phone already holds an encrypted Ambry vault. Unlock it to continue.',
              style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            if (!useRecoveryWords.value)
              TextField(
                controller: passphraseController,
                obscureText: obscurePassphrase.value,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Vault passphrase',
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
                    child: isBusy.value
                        ? SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: context.colorScheme.onPrimary),
                          )
                        : const Text('Unlock & Open Timeline'),
                  ),
                ),
              ],
            ),
            if (progressText.value != null) ...[
              const SizedBox(height: 12),
              Text(progressText.value!, style: context.textTheme.bodySmall),
            ],
          ],
        );
      }

      if (step.value == 1 && !existingVault.value) {
        return Column(
          key: const ValueKey('step_1_create'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Create Vault Passphrase',
              style: context.textTheme.headlineMedium?.copyWith(color: context.colorScheme.onSurface),
            ),
            const SizedBox(height: 6),
            Text(
              'Every photo, video, thumbnail, and index backup is encrypted on this phone before leaving your device.',
              style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            const AmbryBanner(
              variant: AmbryBannerVariant.error,
              icon: Icons.warning_amber_rounded,
              title: 'Zero-knowledge vault',
              body: 'Lose your passphrase and recovery kit = lose your library. There is no server to reset it.',
            ),
            const SizedBox(height: 18),
            TextField(
              controller: passphraseController,
              obscureText: obscurePassphrase.value,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Passphrase (min 8 characters)',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(obscurePassphrase.value ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => obscurePassphrase.value = !obscurePassphrase.value,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _PassphraseStrengthBar(passphrase: passphraseText),
            const SizedBox(height: 14),
            TextField(
              controller: confirmPassphraseController,
              obscureText: obscureConfirmPassphrase.value,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Confirm Passphrase',
                prefixIcon: const Icon(Icons.lock_reset_rounded),
                suffixIcon: IconButton(
                  icon: Icon(
                    obscureConfirmPassphrase.value ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => obscureConfirmPassphrase.value = !obscureConfirmPassphrase.value,
                ),
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
                    child: const Text('Generate 24-Word Recovery Kit'),
                  ),
                ),
              ],
            ),
          ],
        );
      }

      return Column(
        key: const ValueKey('step_2_recovery'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Save Your 24-Word Recovery Kit',
            style: context.textTheme.headlineMedium?.copyWith(color: context.colorScheme.onSurface),
          ),
          const SizedBox(height: 6),
          Text(
            'Write down or print these 24 words together with your dedicated Telegram account phone number. '
            'Either your passphrase or these words unlock your encrypted library on a new phone.',
            style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          _RecoveryKitGrid(words: recoveryWords),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () {
                final text = recoveryWords.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n');
                unawaited(Clipboard.setData(ClipboardData(text: text)));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('24-word recovery kit copied to clipboard — clear clipboard after saving')),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy 24 Words'),
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: savedRecoveryChecked.value,
            onChanged: (v) => savedRecoveryChecked.value = v ?? false,
            title: Text(
              'I have saved my passphrase and 24-word recovery kit safely.',
              style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.onSurface),
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
                  child: isBusy.value
                      ? SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: context.colorScheme.onPrimary),
                        )
                      : const Text('Create Vault & Open Timeline'),
                ),
              ),
            ],
          ),
          if (progressText.value != null) ...[
            const SizedBox(height: 12),
            Text(progressText.value!, style: context.textTheme.bodySmall),
          ],
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const AmbryBrandMark(iconSize: 24),
        centerTitle: false,
        actions: [
          TextButton(onPressed: () => context.pushRoute(const AppLogRoute()), child: const Text('Logs')),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StepProgressHeader(
                currentStep: currentStepNumber,
                totalSteps: totalSteps,
                stepLabel: stepTitle,
              ),
              const SizedBox(height: 20),
              if (errorText.value != null)
                AmbryBanner(
                  margin: const EdgeInsets.only(bottom: 16),
                  variant: AmbryBannerVariant.error,
                  title: 'Unable to continue',
                  body: errorText.value,
                ),
              AnimatedSwitcher(
                duration: AmbryMotion.durationOf(context, AmbryMotion.dModerate),
                switchInCurve: AmbryMotion.easeSpatial,
                switchOutCurve: AmbryMotion.easeEffects,
                child: buildStepBody(),
              ),
              const SizedBox(height: 28),
              Center(
                child: Text(
                  'Ambry v${appVersion.value}',
                  style: context.textTheme.bodySmall?.copyWith(
                    fontFamily: 'GoogleSansCode',
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepProgressHeader extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final String stepLabel;

  const _StepProgressHeader({
    required this.currentStep,
    required this.totalSteps,
    required this.stepLabel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Step $currentStep of $totalSteps',
              style: context.textTheme.labelMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text('  ·  $stepLabel', style: context.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.pill)),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: currentStep / totalSteps),
            duration: AmbryMotion.durationOf(context, AmbryMotion.dModerate),
            curve: AmbryMotion.easeSpatial,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 4,
              backgroundColor: scheme.surfaceContainerHighest,
              color: scheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}

class _PassphraseStrengthBar extends StatelessWidget {
  final String passphrase;

  const _PassphraseStrengthBar({required this.passphrase});

  int _score() {
    if (passphrase.isEmpty) {
      return 0;
    }
    var score = 0;
    if (passphrase.length >= 8) {
      score++;
    }
    if (passphrase.length >= 12) {
      score++;
    }
    if (RegExp(r'[A-Z]').hasMatch(passphrase) && RegExp(r'[a-z]').hasMatch(passphrase)) {
      score++;
    }
    if (RegExp(r'[0-9]|[^A-Za-z0-9]').hasMatch(passphrase)) {
      score++;
    }
    return score.clamp(1, 4);
  }

  @override
  Widget build(BuildContext context) {
    final score = _score();
    if (score == 0) {
      return const SizedBox.shrink();
    }

    final scheme = context.colorScheme;
    final colors = context.immichColors;
    final (label, color) = switch (score) {
      1 => ('Weak', scheme.error),
      2 => ('Fair', colors.warning),
      3 => ('Good', scheme.primary),
      _ => ('Strong', colors.success),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          spacing: 6,
          children: List.generate(4, (index) {
            final active = index < score;
            return Expanded(
              child: AnimatedContainer(
                duration: AmbryMotion.durationOf(context, AmbryMotion.dFast),
                height: 4,
                decoration: BoxDecoration(
                  color: active ? color : scheme.surfaceContainerHighest,
                  borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.pill)),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 4),
        Text(
          'Strength: $label',
          style: context.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _RecoveryKitGrid extends StatelessWidget {
  final List<String> words;

  const _RecoveryKitGrid({required this.words});

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final half = (words.length / 2).ceil();

    Widget wordCell(int index) {
      final numStr = (index + 1).toString().padLeft(2, '0');
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
        child: Row(
          children: [
            Text(
              numStr,
              style: context.textTheme.labelMedium?.copyWith(
                fontFamily: 'GoogleSansCode',
                color: scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                words[index],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'GoogleSansCode',
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.lg)),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (int i = 0; i < half; i++) wordCell(i)],
              ),
            ),
            VerticalDivider(width: 1, thickness: 1, color: scheme.outlineVariant),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (int i = half; i < words.length; i++) wordCell(i)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

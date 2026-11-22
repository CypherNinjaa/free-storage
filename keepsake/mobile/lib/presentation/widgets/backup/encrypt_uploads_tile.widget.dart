import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/infrastructure/platform.provider.dart';
import 'package:immich_ui/immich_ui.dart';
import 'package:logging/logging.dart';

/// Turns encryption of new uploads on or off. The setting lives in the vault index on the phone, so the
/// foreground backup and the background worker both follow it, and a restored phone gets it back.
class EncryptUploadsTile extends ConsumerStatefulWidget {
  const EncryptUploadsTile({super.key});

  @override
  ConsumerState<EncryptUploadsTile> createState() => _EncryptUploadsTileState();
}

class _EncryptUploadsTileState extends ConsumerState<EncryptUploadsTile> {
  static final _log = Logger('EncryptUploadsTile');

  bool? _encrypt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    var value = true;
    try {
      value = await ref.read(keepsakeLibraryApiProvider).getEncryptUploads();
    } catch (error) {
      _log.warning('Could not read the encryption setting', error);
    }
    if (mounted) {
      setState(() => _encrypt = value);
    }
  }

  Future<void> _change(bool encrypt) async {
    if (!encrypt && !await _confirmPlainUploads()) {
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(keepsakeLibraryApiProvider).setEncryptUploads(encrypt);
      if (mounted) {
        setState(() => _encrypt = encrypt);
      }
    } catch (error) {
      _log.warning('Could not save the encryption setting', error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not change the setting. Try again.')));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<bool> _confirmPlainUploads() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AmbryConfirmDialog(
        title: 'Upload without encryption?',
        content:
            'New photos and videos will be stored in your Telegram channel as ordinary files. You can open them in '
            'Telegram, but so can anyone who gets into your Telegram account, and Telegram can see them too.\n\n'
            'Photos already backed up stay as they are. Your library index stays encrypted.',
        confirmLabel: 'Turn off',
        cancelLabel: 'Keep encryption',
        destructive: true,
        onConfirm: () {},
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final encrypt = _encrypt;
    final enabled = encrypt != null && !_saving;
    final isPlain = encrypt == false;
    final scheme = context.colorScheme;
    final colors = context.immichColors;

    return AnimatedContainer(
      duration: AmbryMotion.durationOf(context, AmbryMotion.dModerate),
      curve: AmbryMotion.easeEffects,
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: isPlain ? colors.warningContainer : scheme.surfaceContainerLow,
        borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.lg)),
        border: Border.all(
          color: isPlain ? colors.warning.withValues(alpha: 0.4) : scheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: SwitchListTile.adaptive(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        secondary: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isPlain ? colors.warning.withValues(alpha: 0.16) : scheme.surfaceContainerHigh,
          ),
          child: Icon(
            isPlain ? Icons.lock_open_rounded : Icons.lock_rounded,
            size: 20,
            color: isPlain ? colors.onWarningContainer : scheme.primary,
          ),
        ),
        title: Text(
          'Encrypt before upload',
          style: context.textTheme.titleMedium?.copyWith(
            color: isPlain ? colors.onWarningContainer : scheme.onSurface,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            isPlain
                ? 'Off: new uploads are ordinary files you can open in Telegram.'
                : 'On: only this app, with your passphrase or recovery words, can open your uploads.',
            style: context.textTheme.bodySmall?.copyWith(
              color: isPlain ? colors.onWarningContainer.withValues(alpha: 0.85) : scheme.onSurfaceVariant,
            ),
          ),
        ),
        value: encrypt ?? true,
        onChanged: enabled ? _change : null,
      ),
    );
  }
}

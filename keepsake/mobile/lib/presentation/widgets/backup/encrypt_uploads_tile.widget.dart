import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/infrastructure/platform.provider.dart';
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
      builder: (context) => AlertDialog(
        title: const Text('Upload without encryption?'),
        content: const Text(
          'New photos and videos will be stored in your Telegram channel as ordinary files. You can open them in '
          'Telegram, but so can anyone who gets into your Telegram account, and Telegram can see them too.\n\n'
          'Photos already backed up stay as they are. Your library index stays encrypted.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep encryption')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Turn off')),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final encrypt = _encrypt;
    final enabled = encrypt != null && !_saving;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(top: 12),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        side: BorderSide(color: context.colorScheme.outlineVariant, width: 1),
      ),
      child: SwitchListTile.adaptive(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        secondary: Icon(encrypt == false ? Icons.lock_open_rounded : Icons.lock_rounded, color: context.primaryColor),
        title: Text(
          'Encrypt before upload',
          style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          encrypt == false
              ? 'Off: new uploads are ordinary files you can open in Telegram.'
              : 'On: only this app, with your passphrase or recovery words, can open your uploads.',
          style: context.textTheme.bodySmall,
        ),
        value: encrypt ?? true,
        onChanged: enabled ? _change : null,
      ),
    );
  }
}

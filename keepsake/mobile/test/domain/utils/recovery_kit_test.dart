import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/domain/utils/recovery_kit.dart';

void main() {
  group('RecoveryKit', () {
    test('generates 24 words from the kit word list', () {
      final words = RecoveryKit.generate24Words();

      expect(words, hasLength(RecoveryKit.wordCount));
      expect(words.every(RecoveryKit.isWord), isTrue);
    });

    test('maps words to 24 bytes of entropy and back', () {
      final words = RecoveryKit.generate24Words();
      final entropy = RecoveryKit.toEntropy(words);

      expect(entropy, hasLength(24));
      expect(RecoveryKit.fromEntropy(entropy), words);
    });

    test('accepts words with different case and surrounding spaces', () {
      final words = RecoveryKit.generate24Words();
      final noisy = [for (final word in words) '  ${word.toUpperCase()} '];

      expect(RecoveryKit.toEntropy(noisy), RecoveryKit.toEntropy(words));
    });

    test('covers every byte value exactly once', () {
      final everyByte = Uint8List.fromList(List<int>.generate(256, (i) => i));
      final words = <String>[];
      for (var offset = 0; offset < 256; offset += 24) {
        final chunk = Uint8List(24);
        for (var i = 0; i < 24; i++) {
          chunk[i] = everyByte[(offset + i) % 256];
        }
        words.addAll(RecoveryKit.fromEntropy(chunk));
      }

      expect(words.toSet(), hasLength(256));
    });

    test('rejects unknown words and wrong lengths', () {
      final words = RecoveryKit.generate24Words();

      expect(() => RecoveryKit.toEntropy([...words.take(23), 'notaword']), throwsArgumentError);
      expect(() => RecoveryKit.toEntropy(words.take(12).toList()), throwsArgumentError);
      expect(() => RecoveryKit.fromEntropy(Uint8List(16)), throwsArgumentError);
    });
  });
}

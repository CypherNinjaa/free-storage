import 'dart:math';
import 'dart:typed_data';

/// Generates a 24-word recovery key using a cryptographically secure RNG
/// (Architecture §6: passphrase + printed 24-word recovery kit).
class RecoveryKit {
  // 256 short, distinct, unambiguous English words (8 bits per word -> 192 bits across 24 words)
  static const List<String> _words = [
    'acorn', 'alder', 'amber', 'anchor', 'anvil', 'apple', 'apron', 'arbor',
    'arch', 'arrow', 'aspen', 'atlas', 'attic', 'audio', 'autumn', 'badge',
    'baker', 'bamboo', 'banjo', 'banner', 'barge', 'barley', 'barrel', 'basil',
    'basin', 'basket', 'beacon', 'beaver', 'beech', 'beetle', 'belfry', 'berry',
    'birch', 'bison', 'blade', 'blanket', 'blaze', 'bloom', 'bluff', 'board',
    'boat', 'bobcat', 'bolt', 'bonfire', 'bonnet', 'boulder', 'branch', 'brass',
    'breeze', 'brick', 'bridge', 'bridle', 'brook', 'broom', 'brush', 'bucket',
    'buckle', 'budget', 'buffalo', 'bugle', 'bundle', 'bunker', 'cabin', 'cable',
    'cactus', 'cairn', 'camel', 'camera', 'camp', 'canal', 'candle', 'cannon',
    'canoe', 'canopy', 'canyon', 'cape', 'carbon', 'cargo', 'carpet', 'carrot',
    'castle', 'cedar', 'cellar', 'cement', 'chain', 'chalk', 'chapel', 'chart',
    'chisel', 'cider', 'cinder', 'circle', 'citadel', 'citrus', 'clamp', 'clasp',
    'cliff', 'cloak', 'clock', 'cloud', 'clover', 'coach', 'coast', 'cobalt',
    'cobra', 'coffee', 'coil', 'collar', 'column', 'comet', 'compass', 'condor',
    'copper', 'coral', 'cord', 'cork', 'corner', 'corral', 'cotton', 'cougar',
    'cradle', 'craft', 'crane', 'crater', 'creek', 'crest', 'cricket', 'crocus',
    'crown', 'crystal', 'cupola', 'curtain', 'custom', 'cypress', 'dagger', 'daisy',
    'damask', 'dancer', 'dawn', 'delta', 'denim', 'depot', 'desert', 'dial',
    'diamond', 'dipper', 'dock', 'dolphin', 'dome', 'donkey', 'dragon', 'drift',
    'drum', 'dune', 'eagle', 'earth', 'easel', 'echo', 'edge', 'elder',
    'elm', 'ember', 'emerald', 'engine', 'epoch', 'ermine', 'estuary', 'fable',
    'falcon', 'fennel', 'fern', 'ferry', 'fiddle', 'field', 'fig', 'finch',
    'fjord', 'flagon', 'flame', 'flannel', 'flask', 'flint', 'flora', 'flute',
    'forest', 'forge', 'fossil', 'fountain', 'fox', 'frame', 'frost', 'funnel',
    'gable', 'galaxy', 'galley', 'garden', 'garnet', 'gate', 'gazelle', 'geyser',
    'ginger', 'glacier', 'glade', 'glass', 'globe', 'glory', 'glove', 'gold',
    'gopher', 'gorge', 'grain', 'granite', 'grape', 'gravel', 'griffin', 'grove',
    'guitar', 'gull', 'hammer', 'hammock', 'harbor', 'harp', 'harvest', 'haven',
    'hawk', 'hazel', 'hearth', 'heather', 'helmet', 'hemlock', 'heron', 'hickory',
    'hill', 'hollow', 'honey', 'horizon', 'hornet', 'hound', 'humble', 'husk',
    'ibex', 'icicle', 'igloo', 'indigo', 'inlet', 'iris', 'iron', 'island',
    'ivory', 'ivy', 'jacket', 'jade', 'jaguar', 'jasper', 'javelin', 'juniper',
  ];

  static const int wordCount = 24;

  static final RegExp _separatorPattern = RegExp(r'[\s,]+');
  static final RegExp _numberingPrefixPattern = RegExp(r'^\d+[.):]');
  static final RegExp _pureNumberingPattern = RegExp(r'^\d+$');

  /// Parses pasted or typed recovery kit text into lower-case word tokens,
  /// stripping numbering prefixes ("1. ", "1) ", "1: ") and ignoring empty or
  /// pure numbering tokens.
  static List<String> parseWords(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return const [];
    }
    final words = <String>[];
    for (final raw in trimmed.toLowerCase().split(_separatorPattern)) {
      final token = raw.replaceFirst(_numberingPrefixPattern, '');
      if (token.isEmpty || _pureNumberingPattern.hasMatch(token)) {
        continue;
      }
      words.add(token);
    }
    return words;
  }

  static List<String> generate24Words() {
    final rng = Random.secure();
    return List<String>.generate(wordCount, (_) => _words[rng.nextInt(_words.length)]);
  }

  static bool isWord(String word) => _words.contains(word.trim().toLowerCase());

  static Uint8List toEntropy(List<String> words) {
    if (words.length != wordCount) {
      throw ArgumentError.value(words.length, 'words', 'A recovery kit has exactly $wordCount words');
    }
    return Uint8List.fromList([for (final word in words) _indexOf(word)]);
  }

  static List<String> fromEntropy(Uint8List entropy) {
    if (entropy.length != wordCount) {
      throw ArgumentError.value(entropy.length, 'entropy', 'Recovery entropy is exactly $wordCount bytes');
    }
    return [for (final value in entropy) _words[value]];
  }

  static int _indexOf(String word) {
    final index = _words.indexOf(word.trim().toLowerCase());
    if (index < 0) {
      throw ArgumentError.value(word, 'words', 'Not a recovery kit word');
    }
    return index;
  }
}

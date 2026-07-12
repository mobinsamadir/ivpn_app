import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';

// Since _processConfigsInIsolate is a top-level private function,
// we'll duplicate its core loop logic for a pure benchmark,
// or test the logic equivalently. We will measure the time
// taken to process a large number of configs with the current logic.

// Original logic
void _originalLogic(
  List<String> configStrings,
  bool checkBlacklist,
  Set<String> blockedHashes,
) {
  final List<String> hashesToRemoveFromBlacklist = [];
  final Set<String> batchConfigs = {};

  for (final raw in configStrings) {
    final trimmedRaw = raw.trim();
    if (trimmedRaw.isEmpty) continue;

    // HASH Check for Blacklist
    final hash = md5.convert(utf8.encode(trimmedRaw)).toString();

    if (checkBlacklist && blockedHashes.contains(hash)) {
      // Silently skip blacklisted config
      continue;
    }

    // Manual Overwrite: If adding with checkBlacklist=false, we mark hash for removal
    if (!checkBlacklist && blockedHashes.contains(hash)) {
      hashesToRemoveFromBlacklist.add(hash);
    }

    // Simulate some work
    if (batchConfigs.contains(trimmedRaw)) {
      continue;
    }
    batchConfigs.add(trimmedRaw);
  }
}

// Optimized logic (will be implemented in actual code later)
void _optimizedLogic(
  List<String> configStrings,
  bool checkBlacklist,
  Set<String> blockedHashes,
) {
  final List<String> hashesToRemoveFromBlacklist = [];
  final Set<String> batchConfigs = {};

  for (final raw in configStrings) {
    final trimmedRaw = raw.trim();
    if (trimmedRaw.isEmpty) continue;

    if (checkBlacklist) {
      final hash = md5.convert(utf8.encode(trimmedRaw)).toString();
      if (blockedHashes.contains(hash)) {
        continue;
      }
    } else if (blockedHashes.isNotEmpty) {
      // In original, if checkBlacklist is false and hash in blocked, remove
      final hash = md5.convert(utf8.encode(trimmedRaw)).toString();
      if (blockedHashes.contains(hash)) {
        hashesToRemoveFromBlacklist.add(hash);
      }
    }

    if (batchConfigs.contains(trimmedRaw)) {
      continue;
    }
    batchConfigs.add(trimmedRaw);
  }
}

void main() {
  test('Benchmark Config Hashing', () {
    const int numConfigs = 20000;
    final List<String> configs = List.generate(
      numConfigs,
      (i) =>
          'vless://uuid-uuid-uuid-uuid-uuid@server$i.com:443?encryption=none&security=tls&sni=server$i.com&type=tcp#Server-$i',
    );

    // For the test, we'll run with checkBlacklist = false, and no blocked hashes
    // This is the common case (e.g. adding initial configs, or sync)
    final Set<String> blockedHashes = {};
    final bool checkBlacklist = false;

    // Warmup
    _originalLogic(configs.take(100).toList(), checkBlacklist, blockedHashes);
    _optimizedLogic(configs.take(100).toList(), checkBlacklist, blockedHashes);

    final stopwatchOriginal = Stopwatch()..start();
    _originalLogic(configs, checkBlacklist, blockedHashes);
    stopwatchOriginal.stop();

    final stopwatchOptimized = Stopwatch()..start();
    _optimizedLogic(configs, checkBlacklist, blockedHashes);
    stopwatchOptimized.stop();

    print(
      'Original (checkBlacklist=false): ${stopwatchOriginal.elapsedMilliseconds} ms',
    );
    print(
      'Optimized (checkBlacklist=false): ${stopwatchOptimized.elapsedMilliseconds} ms',
    );

    // The optimized logic should be significantly faster because it skips hashing entirely
    // when checkBlacklist=false and blockedHashes is empty.
  });
}

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md §9 guardrail 1 + §7 definition of done.
///
/// The plan is blunt about why the previous attempts failed: "on discipline,
/// not knowledge — fixes landed on one path and not its duplicate." These are
/// the mechanical half of the fix. Each rule is a **ratchet**, not a
/// pass/fail: the files that violate it today are listed explicitly, and the
/// test fails in *both* directions —
///
/// * a file not on the list violates → a new violation was introduced;
/// * a file on the list no longer violates → the list is stale, delete the
///   entry.
///
/// The second direction is the point. An allowlist that is only ever appended
/// to becomes a rug; one that must shrink as the work lands is a countdown
/// with a number you can read off `flutter test`.
///
/// The plan names `custom_lint` for this. A test buys the same enforcement
/// with no new dependency and no analyzer-version coupling, and runs wherever
/// the suite runs. What it does not buy is red squiggles while you type — if
/// that turns out to matter, the rules here port to `custom_lint` unchanged.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source with comments removed, so a rule never fires on prose. Several of
/// these terms appear in doc comments precisely *because* the plan discusses
/// them; `FutureBuilder` alone is mentioned in four files that contain none.
String _stripComments(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    if (source.startsWith('/*', i)) {
      final end = source.indexOf('*/', i + 2);
      i = end == -1 ? source.length : end + 2;
      continue;
    }
    if (source.startsWith('//', i)) {
      final end = source.indexOf('\n', i);
      i = end == -1 ? source.length : end;
      continue;
    }
    out.write(source[i]);
    i++;
  }
  return out.toString();
}

List<File> _dartFilesUnder(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

/// Repo-relative, forward-slashed.
String _rel(File f) => f.path.replaceAll(r'\', '/').replaceFirst('./', '');

/// Every import in [source], resolved to a repo-relative `lib/...` path.
///
/// Resolving matters, and this rule learned it the hard way: a regex over the
/// literal import string sees `package:mary_ai_pos/core/database/...` and
/// misses `../database/...` from a sibling directory — the *same file*, under
/// a spelling the rule never matched. `lib/core/sync/sync_engine.dart` sat on
/// the wrong side of the Hive ratchet for exactly that reason, invisible while
/// the allowlist claimed two entries and meant three.
///
/// [path] is the importing file, so relative imports resolve against its own
/// directory. Package imports of this package map onto `lib/`; imports of
/// other packages (`package:flutter/...`, `dart:async`) are not repo files and
/// drop out.
Set<String> _resolvedImports(String path, String source) {
  const selfPackage = 'package:mary_ai_pos/';
  final dir = path.substring(0, path.lastIndexOf('/'));
  final out = <String>{};
  for (final m in RegExp(r"^\s*(?:import|export)\s+'([^']+)'", multiLine: true)
      .allMatches(_stripComments(source))) {
    final raw = m.group(1)!;
    if (raw.startsWith(selfPackage)) {
      out.add('lib/${raw.substring(selfPackage.length)}');
    } else if (!raw.contains(':')) {
      out.add(_normalize('$dir/$raw'));
    }
  }
  return out;
}

/// Collapses `.`/`..` segments so a relative import lands on the same string
/// the package form would produce.
String _normalize(String path) {
  final parts = <String>[];
  for (final segment in path.split('/')) {
    if (segment == '.' || segment.isEmpty) continue;
    if (segment == '..') {
      if (parts.isNotEmpty) parts.removeLast();
      continue;
    }
    parts.add(segment);
  }
  return parts.join('/');
}

/// Runs [violates] over every Dart file under [roots] and asserts the set of
/// offenders is exactly [known].
void _ratchet({
  required String rule,
  required List<String> roots,
  required Set<String> known,
  required bool Function(String path, String source) violates,
  required String remedy,
}) {
  final found = <String>{};
  for (final root in roots) {
    if (!Directory(root).existsSync()) continue;
    for (final file in _dartFilesUnder(root)) {
      final path = _rel(file);
      if (violates(path, file.readAsStringSync())) found.add(path);
    }
  }

  final introduced = found.difference(known).toList()..sort();
  final fixed = known.difference(found).toList()..sort();

  expect(
    introduced,
    isEmpty,
    reason: '$rule\n\n'
        'New violation(s):\n${introduced.map((f) => '  - $f').join('\n')}\n\n'
        '$remedy',
  );
  expect(
    fixed,
    isEmpty,
    reason: '$rule\n\n'
        'These no longer violate the rule — remove them from the allowlist in '
        'test/architecture_guard_test.dart so the ratchet keeps its teeth:\n'
        '${fixed.map((f) => '  - $f').join('\n')}',
  );
}

void main() {
  group('§9.1 — networking stays in the transport layer', () {
    // Nothing outside these may import a networking package. Note what the
    // list does *not* contain: anything under `lib/features/`, except the one
    // entry below that Phase 4 deletes outright.
    const allowed = {
      'lib/core/api/api_error_overlay.dart',
      'lib/core/api/dio_client.dart',
      'lib/core/api/dio_exception_handler.dart',
      'lib/core/service/minio/minio_service.dart',
      'lib/core/services/connectivity/connectivity_cubit.dart',
      'lib/core/services/lan_hub/lan_hub_service.dart',
      'lib/core/services/offline_queue/offline_queue_service.dart',
      // The order aggregate's write transport (§B1). It carries the 409
      // table-open merge and the 404-tolerant per-line cancel — order logic
      // with no home in a CRUD repository — so it speaks Dio directly, the
      // way `main_datasources.dart` does for reads. This does not *grow* the
      // allowlist: it takes over the order replay from
      // `offline_queue_service.dart`, which Phase C deletes.
      'lib/core/outbox/orders_outbox.dart',
      // Timer + shift replay, taken over from `offline_queue_service.dart`
      // (Phase C deletes that, so this list does not grow). Timers speak Dio
      // for the same reason orders do: `MainRepository` has pause/resume but
      // no start, so splitting one aggregate's three verbs across two
      // mechanisms would have been the worse trade.
      'lib/core/outbox/timer_shift_outbox.dart',
      'lib/di.dart',
      // The last feature-layer file that speaks HTTP. Phase 4 deletes it;
      // when it goes, this entry goes and the rule becomes absolute.
      'lib/features/view/main/data/data_source/main_datasources.dart',
    };

    final networkImport = RegExp(
      r"^\s*import\s+'package:(dio|http|minio|connectivity)",
      multiLine: true,
    );

    test('no new file reaches for the network', () {
      _ratchet(
        rule: 'Networking imports (dio, http, minio, connectivity) are '
            'confined to the transport layer.',
        roots: const ['lib'],
        known: allowed,
        violates: (_, source) => networkImport.hasMatch(source),
        remedy: 'Reads belong in a repository over LocalDatabase; writes '
            'belong in the outbox. If this file genuinely is transport, add '
            'it to the allowlist with a note saying why.',
      );
    });

    test('no feature-layer file speaks HTTP except the one on its way out', () {
      final offenders = _dartFilesUnder('lib/features')
          .where((f) => networkImport.hasMatch(f.readAsStringSync()))
          .map(_rel)
          .toList()
        ..sort();
      expect(offenders, [
        'lib/features/view/main/data/data_source/main_datasources.dart',
      ]);
    });
  });

  group('§7 — screens do not reach into the data layer', () {
    // The definition of done wanted this empty, and now it is: every screen
    // resolves its data through a bloc / cubit / controller, never a repository
    // pulled from the widget. The rule is absolute from here — any new
    // inject<...Repository>() under presentation/pages/ fails the build.
    const pending = <String>{};

    final repoInject = RegExp(r'inject<[A-Za-z_]*Repository>\(\)');

    test('no new widget injects a repository directly', () {
      _ratchet(
        rule: 'Widgets under presentation/pages must not resolve repositories '
            'themselves — a bloc or cubit owns that.',
        roots: const ['lib/features'],
        known: pending,
        violates: (path, source) =>
            path.contains('/presentation/pages/') &&
            repoInject.hasMatch(_stripComments(source)),
        remedy: 'Move the read behind a bloc subscribing to a LocalDatabase '
            'query, per the Phase 4 table.',
      );
    });
  });

  group('§7 — no build-time fetching', () {
    // Empty, and staying that way. Both former entries were image loading,
    // now a StreamBuilder over the repository's local image store.
    const pending = <String>{};

    test('no new FutureBuilder', () {
      _ratchet(
        rule: 'A FutureBuilder re-fetches on every rebuild and renders a '
            'spinner the local-first design has no reason to show.',
        roots: const ['lib'],
        known: pending,
        violates: (_, source) => _stripComments(source).contains(
          'FutureBuilder',
        ),
        remedy: 'Use a StreamBuilder over a LocalDatabase query instead.',
      );
    });
  });

  group('§7 — one database', () {
    // Definition of done #4, closed. Two engines used to run in parallel (§6b):
    // the SQLite replica at lib/core/db/, where the change feed lands, and the
    // Hive store at lib/core/database/ with its CacheService blob box beside
    // it. The countdown that used to live here — a shrinking allowlist of files
    // still bound to the old store — reached zero, and both are deleted.
    //
    // The rule inverts accordingly. There is nothing left to allow, so instead
    // of naming who may still import the old store, this asserts it cannot come
    // back: no such directory, no such class, and no import of either.
    const pending = <String>{};

    test('the retiring Hive store is gone and nothing resurrects it', () {
      expect(
        Directory('lib/core/database').existsSync(),
        isFalse,
        reason: 'lib/core/database/ (Hive) was deleted when the last reader '
            'moved to the replica. Reads go through a repository over a '
            'core/db query; writes go through LocalWriter.',
      );
      expect(
        File('lib/core/services/cache/cache_service.dart').existsSync(),
        isFalse,
        reason: 'CacheService was the blob cache beside the Hive store. Its '
            'one genuinely device-scoped value, the USB printer name, lives '
            'in PrinterConfigStorage (SharedPreferences) now.',
      );

      _ratchet(
        rule: 'lib/core/db/ is the single database. Nothing may import a '
            'second store.',
        roots: const ['lib'],
        known: pending,
        violates: (path, source) => _resolvedImports(path, source).any(
          (i) =>
              i.startsWith('lib/core/database/') ||
              i == 'lib/core/services/cache/cache_service.dart',
        ),
        remedy: 'Both stores are deleted. Use lib/core/db/ — a query for '
            'reads, LocalWriter for writes — or SharedPreferences if the '
            'value is genuinely device-scoped and holds no replicated entity '
            '(§2 names the whole list: USB printer name, terminal id, LAN '
            'role, locale).',
      );
    });

    test('only the one-shot migration still opens the retired Hive box', () {
      // It reads a single key so an upgrading terminal keeps the Windows
      // printer its USB entries point at — the one value in that box that
      // exists nowhere else. Delete it once every terminal has run a build
      // containing it.
      final offenders = _dartFilesUnder('lib')
          .where((f) => f.readAsStringSync().contains("'pos_cache'"))
          .map(_rel)
          .toList()
        ..sort();
      expect(offenders, ['lib/core/service/printer/legacy_usb_printer_names.dart']);
    });
  });

  group('the guard itself', () {
    test('strips comments before matching, so prose never trips a rule', () {
      const source = '''
/// Mentions FutureBuilder in a doc comment.
// and inject<MainRepository>() in a line comment
/* and a block comment with import 'package:dio/dio.dart'; */
final x = 1;
''';
      final stripped = _stripComments(source);
      expect(stripped, isNot(contains('FutureBuilder')));
      expect(stripped, isNot(contains('inject<MainRepository>')));
      expect(stripped, isNot(contains('package:dio')));
      expect(stripped, contains('final x = 1;'));
    });

    test('resolves a relative import to the same path as the package form',
        () {
      // The hole this rule shipped with: `sync_engine.dart` reached the Hive
      // store as `'../database/local_database.dart'`, which no amount of
      // matching on `core/database/` in the literal string will ever see.
      const source = '''
import 'package:mary_ai_pos/core/db/local_database.dart';
import '../database/local_database.dart';
import '../../core/services/cache/cache_service.dart';
import 'replication_service.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
''';
      expect(_resolvedImports('lib/core/sync/sync_engine.dart', source), {
        'lib/core/db/local_database.dart',
        'lib/core/database/local_database.dart',
        'lib/core/services/cache/cache_service.dart',
        'lib/core/sync/replication_service.dart',
      });
    });

    test('a commented-out import of the Hive store does not count', () {
      const source = "// import '../database/local_database.dart';";
      expect(_resolvedImports('lib/core/sync/sync_engine.dart', source),
          isEmpty);
    });

    test('sees code that follows a comment on the same line', () {
      final stripped = _stripComments("var a = 1; // note\nvar b = 2;");
      expect(stripped, contains('var a = 1;'));
      expect(stripped, contains('var b = 2;'));
    });
  });
}

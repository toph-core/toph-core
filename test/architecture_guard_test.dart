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

  group('§7 — one database: the Hive store is walled off, shrinking to zero', () {
    // Definition of done #4: "Exactly one database class; CacheService and the
    // Hive LocalDatabase deleted." Two engines still run in parallel (§6b): the
    // SQLite replica at lib/core/db/ — where the change feed lands and every
    // migrated screen reads — and the retiring Hive store at
    // lib/core/database/. Each entry below is a file still bound to the old
    // store: the order / waiter / menu / timer / transactions repositories the
    // sync work exists to serve, plus the two services and the injector that
    // wire them. It is the remaining two-engine consolidation as a number that
    // only goes down. When this set is empty nothing imports lib/core/database/
    // and the directory can be deleted — which is what actually closes DoD #4.
    const stillOnHive = {
      'lib/core/services/auth/login_data_scope_service.dart',
      'lib/di.dart',
      'lib/features/view/main/data/repository/orders_repository_impl.dart',
      'lib/features/view/main/data/repository/table_timer_local_repository_impl.dart',
      'lib/features/view/main/data/repository/waiter_local_repository_impl.dart',
    };

    // Any import of the Hive store, package-form or relative. The `^\s*import`
    // anchor is what keeps prose and commented-out lines from matching — a
    // `// import '.../core/database/...'` line starts with `//`, not `import`.
    final hiveStoreImport = RegExp(
      r"^\s*import\s+'[^']*core/database/",
      multiLine: true,
    );

    test('no new file binds to the retiring Hive store', () {
      _ratchet(
        rule: 'lib/core/database/ (Hive) is being retired in favour of the '
            'single SQLite replica at lib/core/db/. Reads go through a '
            'repository over a core/db query; writes go through LocalWriter. '
            'Nothing new may import the Hive store.',
        roots: const ['lib'],
        known: stillOnHive,
        violates: (path, source) =>
            !path.startsWith('lib/core/database/') &&
            hiveStoreImport.hasMatch(source),
        remedy: 'Move this file onto the SQLite replica — core/db queries for '
            'reads, LocalWriter for writes — and drop the core/database '
            'import. This is the Phase 4 / §6b consolidation; when the last '
            'entry goes, delete lib/core/database/ and close DoD #4.',
      );
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

    test('sees code that follows a comment on the same line', () {
      final stripped = _stripComments("var a = 1; // note\nvar b = 2;");
      expect(stripped, contains('var a = 1;'));
      expect(stripped, contains('var b = 2;'));
    });
  });
}

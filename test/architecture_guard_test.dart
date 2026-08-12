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
    // The definition of done wants this empty. Each entry is one screen still
    // waiting on Phase 4; the count is the remaining work, and it only ever
    // goes down.
    const pending = {
      'lib/features/view/main/presentation/pages/detail/widgets/transfer_table_dialog.dart',
      'lib/features/view/main/presentation/pages/main/widgets/time_based_table_badge.dart',
      'lib/features/view/main/presentation/pages/menu/menu_manage_screen.dart',
      'lib/features/view/main/presentation/pages/menu/menu_meals_list_screen.dart',
      'lib/features/view/main/presentation/pages/settings/sections/halls_tables_section.dart',
      'lib/features/view/main/presentation/pages/settings/sections/printers_section.dart',
      'lib/features/view/main/presentation/pages/transactions/sections/transaction_categories_section.dart',
      'lib/features/view/main/presentation/pages/transactions/sections/transactions_list_section.dart',
    };

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
    // Both remaining uses are image loading, which Phase 4 replaces with a
    // StreamBuilder over the local image table.
    const pending = {
      'lib/core/common/custom_network_image.dart',
      'lib/features/view/main/presentation/pages/menu/menu_manage_screen.dart',
    };

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

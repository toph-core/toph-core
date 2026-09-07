/// `ListAPI` pinned to the routes the backend actually registers.
///
/// Every entry in `lib/core/api/list_api.dart` is a claim about another
/// repository: "the API serves this path". Nothing checked that claim, and it
/// drifted — in all three ways a path can be wrong, each of which had shipped
/// at once:
///
///  * **A path that no longer exists.** `api/v1/auth/register` was removed from
///    the router ("public self-registration disabled — staff users are created
///    via POST /api/v1/users by admins"). Creating a staff member from POS
///    Settings answered 404, and a 404 is a verdict, so the queued create
///    quarantined instead of landing.
///  * **A path that never existed.** `/api/v1/goods/search` and
///    `/api/v1/media/{audio,book}/download` were constants for routes no build
///    has ever served.
///  * **The right path with the wrong verb.** `users.PATCH("/:id")` is the
///    registered route; the client sent `PUT` and got 405. (The handler's own
///    Swagger annotation said `[put]`, so reading the docs did not help — only
///    the router is the authority, which is what this test reads.)
///
/// So this stops asserting against a hand-maintained list and reads
/// `handler.go` instead, the same way `registry_backend_pin_test.dart` reads
/// the tenant migrations rather than a hand-maintained trigger set.
///
/// ## What it checks
///
///  1. Every path template in [ListAPI] is served by some route.
///  2. Every `(verb, path)` pair this package actually calls is served by a
///     route registered with that verb. The pairs are recovered from the
///     source — a call has to reach the network through a `DioClient`/`Dio`
///     receiver naming a `ListAPI` member, and that is a small enough shape to
///     find mechanically. Call sites that build their path indirectly (the
///     `switch` in `OfflineQueueService._execTimerAction`, say) are not
///     recovered and are covered by (1) alone.
///
/// ## When the backend checkout is not there
///
/// Skipped with a message, not failed — same reasoning, and the same env var
/// ([kBackendDirEnv]), as the registry pin test: the backend is a sibling
/// clone, not a dependency of this package. The parsers' own tests run
/// regardless, against inline source.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Where to look for the backend clone, in order. Mirrors
/// `kBackendCandidatePaths` in `registry_backend_pin_test.dart`.
const List<String> kBackendCandidatePaths = [
  '../back',
  '../mary-ai-backend',
  '../../back',
  '../../mary-ai-backend',
];

const String kBackendDirEnv = 'MARY_AI_BACKEND_DIR';

/// The router source, or null if the backend is not beside this checkout.
File? locateHandlerGo() {
  final override = Platform.environment[kBackendDirEnv];
  for (final path in [?override, ...kBackendCandidatePaths]) {
    final file = File('$path/app/internal/handler/handler.go');
    if (file.existsSync()) return file;
  }
  return null;
}

String? backendMissingSkipReason(File? handlerGo) => handlerGo == null
    ? 'Backend checkout not found — this group reads '
          'app/internal/handler/handler.go directly. Tried '
          '${kBackendCandidatePaths.join(', ')} relative to the package root; '
          'set $kBackendDirEnv to the backend clone to run it. Skipped rather '
          'than failed on purpose: the backend is a sibling clone, not a '
          'dependency of this package. The parser tests still ran.'
    : null;

// ── Route table ─────────────────────────────────────────────────────────────

/// One registered route, normalised for comparison.
typedef Route = ({String method, String path});

/// The HTTP verbs Echo route registrations use, as they appear in `handler.go`.
const _verbs = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'];

/// Reads `handler.go` into the set of routes it registers.
///
/// Groups nest (`api.Group("/settings")` then `settings.Group("/printer-
/// settings")`), so prefixes are resolved by walking the file in order and
/// keeping a variable → prefix map. A route on an unknown variable is recorded
/// under a `?`-prefixed path, which can never match a [ListAPI] entry and so
/// surfaces as a failure rather than a silent pass.
Set<Route> parseRoutes(String source) {
  final group = RegExp(r'^\s*(\w+)\s*:?=\s*(\w+)\.Group\(\s*"([^"]*)"');
  final route = RegExp('^\\s*(\\w+)\\.(${_verbs.join('|')})\\(\\s*"([^"]*)"');

  // `router` is the bare Echo instance and `api := router.Group("/api/v1")`
  // resolves through it like any other group.
  final prefixes = <String, String>{'router': ''};
  final routes = <Route>{};

  for (final line in const LineSplitter().convert(source)) {
    final g = group.firstMatch(line);
    if (g != null) {
      final parent = prefixes[g.group(2)];
      prefixes[g.group(1)!] = parent == null
          ? '?${g.group(2)}${g.group(3)}'
          : '$parent${g.group(3)}';
      continue;
    }
    final r = route.firstMatch(line);
    if (r != null) {
      final prefix = prefixes[r.group(1)] ?? '?${r.group(1)}';
      routes.add((method: r.group(2)!, path: '$prefix${r.group(3)}'));
    }
  }
  return routes;
}

// ── ListAPI ─────────────────────────────────────────────────────────────────

/// `ListAPI` member name → the path it produces, with every interpolated
/// value replaced by `:param` and any query string dropped.
///
/// Both member shapes are read: a `static const String x = "…"` and a
/// `static String x(…) => "…"`. Definitions wrap across lines, so the source
/// is flattened before matching.
Map<String, String> parseListApi(String source) {
  final flat = source.replaceAll(RegExp(r'\s+'), ' ');
  final member = RegExp(
    r'static\s+(?:const\s+)?String\s+(\w+)\s*(?:\([^)]*\))?\s*(?:=>|=)\s*"([^"]*)"',
  );
  return {
    for (final m in member.allMatches(flat))
      m.group(1)!: normalisePath(m.group(2)!),
  };
}

/// A path as the router sees it: leading slash, no query string, `:param` for
/// anything the client interpolates.
String normalisePath(String raw) {
  var path = raw.split('?').first;
  // `$id`, `$orderId`, and `${…}` alike: the router only cares that the
  // segment is a parameter.
  path = path.replaceAll(RegExp(r'\$\{[^}]*\}'), ':param');
  path = path.replaceAll(RegExp(r'\$\w+'), ':param');
  if (!path.startsWith('/')) path = '/$path';
  return path;
}

/// Whether [clientPath] addresses [routePath]: same segment count, literals
/// equal, and a parameter segment only ever matching another parameter
/// segment — so `/orders/:param` matches `/orders/:id` but not `/orders/my`.
bool pathMatches(String clientPath, String routePath) {
  final a = clientPath.split('/');
  final b = routePath.split('/');
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final isParamA = a[i].startsWith(':');
    final isParamB = b[i].startsWith(':');
    if (isParamA != isParamB) return false;
    if (!isParamA && a[i] != b[i]) return false;
  }
  return true;
}

// ── Call sites ──────────────────────────────────────────────────────────────

/// One `(verb, path)` this package sends, and where it is written.
typedef Call = ({String method, String path, String where});

/// Receivers that reach the network. Anything else with a `.get`/`.delete`
/// method — a map, a query object — is deliberately not matched, so a local
/// call that happens to sit above a `ListAPI` reference is not mistaken for a
/// request.
const _receivers = [
  r'_client\.dio',
  r'_client',
  r'dio\.dio',
  r'_dio',
  r'dio',
  r'\w*[Dd]io',
  r'client',
];

/// Recovers the `(verb, path)` pairs a Dart source sends, resolving each
/// `ListAPI` member through [listApi].
///
/// Arguments wrap, so a window of the following few lines is searched for the
/// member reference. Two spellings are resolved: a bare `ListAPI.member`, and
/// an interpolation like `'${ListAPI.printerSettings}/$id'` that appends to
/// one.
List<Call> parseCalls(
  String source,
  Map<String, String> listApi, {
  String where = '',
}) {
  final lines = const LineSplitter().convert(source);
  final call = RegExp(
    '\\b(?:${_receivers.join('|')})\\.(${_verbs.map((v) => v.toLowerCase()).join('|')})\\(',
  );
  final bare = RegExp(r'ListAPI\.(\w+)');
  final composite = RegExp(r"'\$\{ListAPI\.(\w+)\}([^']*)'");

  final calls = <Call>[];
  for (var i = 0; i < lines.length; i++) {
    final m = call.firstMatch(lines[i]);
    if (m == null) continue;
    final window = lines
        .sublist(i, (i + 4).clamp(0, lines.length))
        .join(' ');
    final tail = window.substring(m.end);

    final comp = composite.firstMatch(tail);
    final plain = bare.firstMatch(tail);
    // Whichever spelling appears first is the one this call used.
    final useComposite =
        comp != null && (plain == null || comp.start <= plain.start);

    final String? member = useComposite ? comp.group(1) : plain?.group(1);
    if (member == null) continue;
    final base = listApi[member];
    if (base == null) continue;

    final suffix = useComposite ? normalisePath(comp.group(2)!) : '';
    calls.add((
      method: m.group(1)!.toUpperCase(),
      path: suffix.isEmpty || suffix == '/' ? base : '$base$suffix',
      where: '$where:${i + 1}',
    ));
  }
  return calls;
}

// ── The pins ────────────────────────────────────────────────────────────────

void main() {
  final handlerGo = locateHandlerGo();

  group('the route parser', () {
    test('resolves nested groups and every verb', () {
      final routes = parseRoutes('''
        api := router.Group("/api/v1")
        settings := api.Group("/settings", mw.CheckAuth(h.cfg))
        printerSettings := settings.Group("/printer-settings")
        printerSettings.GET("", h.List, mw.CheckLanguage())
        printerSettings.PUT("/:id", h.Update)
        users := api.Group("/users")
        users.PATCH("/:id", h.UpdateUserByID)
      ''');
      expect(routes, contains((method: 'GET', path: '/api/v1/settings/printer-settings')));
      expect(routes, contains((method: 'PUT', path: '/api/v1/settings/printer-settings/:id')));
      expect(routes, contains((method: 'PATCH', path: '/api/v1/users/:id')));
    });

    test('a route on an unknown group is marked, not silently dropped', () {
      final routes = parseRoutes('mystery.GET("/x", h.Y)');
      expect(routes.single.path, startsWith('?'));
    });
  });

  group('the ListAPI parser', () {
    test('reads both member shapes and drops the query string', () {
      final api = parseListApi('''
        class ListAPI {
          static const String halls = "api/v1/halls";
          static String cafeTableById(String id) => "api/v1/cafe-tables/\$id";
          static String translations({int limit = 1000}) =>
              "/api/v1/translations?limit=\$limit";
        }
      ''');
      expect(api['halls'], '/api/v1/halls');
      expect(api['cafeTableById'], '/api/v1/cafe-tables/:param');
      expect(api['translations'], '/api/v1/translations');
    });
  });

  group('path matching', () {
    test('a parameter matches a parameter, never a literal segment', () {
      expect(pathMatches('/api/v1/orders/:param', '/api/v1/orders/:id'), isTrue);
      expect(pathMatches('/api/v1/orders/:param', '/api/v1/orders/my'), isFalse);
      expect(pathMatches('/api/v1/orders', '/api/v1/orders/:id'), isFalse);
    });
  });

  group('the call-site parser', () {
    test('reads a wrapped call and an interpolated path', () {
      final api = {
        'orders': '/api/v1/orders',
        'printerSettings': '/api/v1/settings/printer-settings',
      };
      final calls = parseCalls('''
        await _client.post(
          ListAPI.orders,
          data: body,
        );
        await _client.delete('\${ListAPI.printerSettings}/\$id');
      ''', api);
      expect(
        calls.map((c) => (c.method, c.path)),
        containsAll([
          ('POST', '/api/v1/orders'),
          ('DELETE', '/api/v1/settings/printer-settings/:param'),
        ]),
      );
    });

    test('a local method that is not a request is not counted', () {
      final calls = parseCalls('''
        final row = cache.get(key);
        final path = ListAPI.orders;
      ''', {'orders': '/api/v1/orders'});
      expect(calls, isEmpty);
    });
  });

  group(
    'ListAPI against the backend router',
    () {
      late Set<Route> routes;
      late Map<String, String> listApi;

      setUpAll(() {
        routes = parseRoutes(handlerGo!.readAsStringSync());
        listApi = parseListApi(
          File('lib/core/api/list_api.dart').readAsStringSync(),
        );
      });

      test('the fixtures parsed — a guard against a silent empty pass', () {
        expect(routes.length, greaterThan(100));
        expect(listApi.length, greaterThan(30));
        expect(
          routes.where((r) => r.path.startsWith('?')),
          isEmpty,
          reason: 'a route group this parser could not resolve',
        );
      });

      test('every path is served by some route', () {
        final unserved = <String>[];
        listApi.forEach((member, path) {
          if (!routes.any((r) => pathMatches(path, r.path))) {
            unserved.add('ListAPI.$member -> $path');
          }
        });
        expect(
          unserved,
          isEmpty,
          reason:
              'These paths are not registered by handler.go. A request to one '
              'answers 404, which the outbox treats as a verdict and '
              'quarantines. Point the constant at the route that replaced it, '
              'or delete it.',
        );
      });

      test('every verb this package sends is registered on that path', () {
        final calls = <Call>[];
        for (final entity in Directory('lib').listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          if (entity.path.endsWith('list_api.dart')) continue;
          calls.addAll(
            parseCalls(
              entity.readAsStringSync(),
              listApi,
              where: entity.path,
            ),
          );
        }

        expect(
          calls.length,
          greaterThan(40),
          reason: 'the call-site scan found almost nothing — it has drifted '
              'from how requests are written in this package',
        );

        final wrongVerb = <String>[];
        for (final call in calls) {
          final onPath = routes.where((r) => pathMatches(call.path, r.path));
          if (onPath.isEmpty) continue; // reported by the path test above
          if (onPath.any((r) => r.method == call.method)) continue;
          final served = (onPath.map((r) => r.method).toList()..sort()).join(', ');
          wrongVerb.add(
            '${call.method} ${call.path} (${call.where}) — the router serves '
            'only: $served',
          );
        }
        expect(
          wrongVerb,
          isEmpty,
          reason:
              'These calls use a verb the route is not registered with, so '
              'they answer 405. Note that a handler\'s Swagger annotation can '
              'disagree with its registration — the registration wins.',
        );
      });
    },
    skip: backendMissingSkipReason(handlerGo),
  );

  group('degrading without the backend checkout', () {
    test('a missing backend skips with a message, it does not fail', () {
      final reason = backendMissingSkipReason(null);
      expect(reason, isNotNull);
      expect(reason, contains(kBackendDirEnv));
    });
  });
}

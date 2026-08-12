/// OFFLINE_FIRST_EVERYWHERE_PLAN.md §7 — "No `FutureBuilder` anywhere in
/// `lib/`", and the reason that criterion is about more than a widget type.
///
/// Two call sites loaded images with a `FutureBuilder`, and each had ended up
/// making its own decisions about dedupe, retry and persistence. They had made
/// *different* ones: the menu editor wrote bytes to disk, the shared image
/// widget did not — so those images were re-downloaded every app start and were
/// simply absent offline. Collapsing both onto one subscription only works if
/// the thing behind it gets all three right, which is what these pin.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/media/local_image_cache.dart';

/// In-memory stand-in for the Hive image box.
class FakeStore {
  final Map<String, List<int>> data = {};
  final _controllers = <String, StreamController<List<int>?>>{};

  Stream<List<int>?> watch(String key) => (_controllers[key] ??=
          StreamController<List<int>?>.broadcast())
      .stream;

  List<int>? read(String key) => data[key];

  Future<void> write(String key, List<int> bytes) async {
    data[key] = bytes;
    _controllers[key]?.add(bytes);
  }
}

void main() {
  late FakeStore store;
  late List<String> fetched;

  setUp(() {
    store = FakeStore();
    fetched = [];
  });

  LocalImageCache cacheWith(
    Future<List<int>?> Function(String key) fetch,
  ) =>
      LocalImageCache(
        watch: store.watch,
        read: store.read,
        write: store.write,
        fetch: (key) {
          fetched.add(key);
          return fetch(key);
        },
      );

  LocalImageCache okCache([List<int> bytes = const [1, 2, 3]]) =>
      cacheWith((_) async => bytes);

  test('a cached image is ready on the first emission — no fetch', () async {
    store.data['pic'] = [9, 9];
    final cache = okCache();

    final first = await cache.stream('pic').first;

    expect(first.status, ImageStatus.ready);
    expect(first.bytes, [9, 9]);
    expect(fetched, isEmpty, reason: 'already on disk');
  });

  test('a miss reports loading, then ready once the bytes land', () async {
    final cache = okCache([4, 5, 6]);
    final seen = <LocalImage>[];
    final sub = cache.stream('pic').listen(seen.add);

    await Future<void>.delayed(Duration.zero);
    expect(seen.first.status, ImageStatus.loading);

    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(seen.last.status, ImageStatus.ready);
    expect(seen.last.bytes, [4, 5, 6]);

    await sub.cancel();
  });

  test('the bytes are written through, so the next run starts offline-ready',
      () async {
    // The half the shared image widget never did. Without this, every app start
    // re-downloaded every image and an offline terminal showed none of them.
    final cache = okCache([7]);
    final sub = cache.stream('pic').listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(store.data['pic'], [7]);
    await sub.cancel();
  });

  test('many subscribers to one image cause one fetch', () async {
    final cache = okCache();
    final subs = [
      for (var i = 0; i < 5; i++) cache.stream('pic').listen((_) {}),
    ];
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(fetched, ['pic']);
    for (final s in subs) {
      await s.cancel();
    }
  });

  group('failures settle instead of spinning', () {
    test('an empty response ends as missing, not a permanent spinner',
        () async {
      final cache = cacheWith((_) async => null);
      final seen = <LocalImage>[];
      final sub = cache.stream('pic').listen(seen.add);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(seen.first.status, ImageStatus.loading);
      expect(seen.last.status, ImageStatus.missing);
      await sub.cancel();
    });

    test('a throwing fetch ends as missing too', () async {
      final cache = cacheWith((_) async => throw StateError('offline'));
      final seen = <LocalImage>[];
      final sub = cache.stream('pic').listen(seen.add);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(seen.last.status, ImageStatus.missing);
      await sub.cancel();
    });

    test('a failed image is not retried on every rebuild', () async {
      // The `FutureBuilder` shape retried on each build. A menu of broken
      // images would hammer the network for as long as the screen was open.
      final cache = cacheWith((_) async => null);
      final a = cache.stream('pic').listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await a.cancel();

      final b = cache.stream('pic').listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await b.cancel();

      expect(fetched, ['pic']);
    });

    test('forgetFailures lets a reconnect try again', () async {
      var attempt = 0;
      final cache = cacheWith((_) async {
        attempt++;
        return attempt == 1 ? null : [1];
      });
      final seen = <LocalImage>[];
      final sub = cache.stream('pic').listen(seen.add);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(seen.last.status, ImageStatus.missing);

      cache.forgetFailures();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(seen.last.status, ImageStatus.ready);
      expect(fetched, ['pic', 'pic']);
      await sub.cancel();
    });
  });

  test('an empty object name is missing without touching the network', () async {
    final cache = okCache();

    expect((await cache.stream('   ').first).status, ImageStatus.missing);
    expect(fetched, isEmpty);
  });
}

import 'dart:async';

/// Where an image is in its journey from "referenced by a menu row" to "bytes
/// on this disk".
enum ImageStatus {
  /// Not here yet, and a fetch is running. Show a placeholder, not an error.
  loading,

  /// Bytes are available.
  ready,

  /// Not here and not coming: no object name, or the fetch failed. Offline with
  /// an image never yet cached lands here, which is correct — there is nothing
  /// to show and nothing to wait for.
  missing,
}

typedef LocalImage = ({ImageStatus status, List<int>? bytes});

/// Disk-backed image cache with fetch-on-miss, behind a single subscription.
///
/// Replaces two `FutureBuilder`s that each owned their own caching decisions.
/// A future rebuilt on every build refetches on every build, so the widget ends
/// up responsible for dedupe, retry and persistence — and the two call sites
/// had made different choices about all three. The menu editor cached; the
/// shared image widget did not, which meant its images were re-downloaded every
/// app start and did not exist offline at all.
///
/// Deliberately takes plain functions rather than a store or client interface.
/// The store is the Hive facade's three image methods and the fetcher is a
/// process-wide singleton with no seam of its own; naming either as a type here
/// would drag both into every test of this logic.
class LocalImageCache {
  final Stream<List<int>?> Function(String key) _watch;
  final List<int>? Function(String key) _read;
  final Future<void> Function(String key, List<int> bytes) _write;
  final Future<List<int>?> Function(String key) _fetch;

  LocalImageCache({
    required Stream<List<int>?> Function(String key) watch,
    required List<int>? Function(String key) read,
    required Future<void> Function(String key, List<int> bytes) write,
    required Future<List<int>?> Function(String key) fetch,
  })  : _watch = watch,
        _read = read,
        _write = write,
        _fetch = fetch;

  /// Keys currently being fetched, so N widgets showing one image cause one
  /// request rather than N.
  final Set<String> _fetching = {};

  /// Keys whose fetch came back empty or threw. Without this a failed image
  /// would sit on [ImageStatus.loading] forever, because nothing writes to the
  /// store and so nothing re-emits.
  final Set<String> _unavailable = {};

  /// Wakes subscribers for state changes the store does not produce — a fetch
  /// starting, and a fetch failing.
  final StreamController<String> _changes = StreamController<String>.broadcast();

  Stream<LocalImage> stream(String objectName) {
    final key = objectName.trim();
    if (key.isEmpty) {
      return Stream.value((status: ImageStatus.missing, bytes: null));
    }
    return Stream.multi((controller) {
      void emit() {
        if (!controller.isClosed) controller.add(state(key));
      }

      emit();
      final store = _watch(key).listen((_) => emit());
      final changes = _changes.stream.where((k) => k == key).listen((_) => emit());
      controller.onCancel = () async {
        await store.cancel();
        await changes.cancel();
      };
    });
  }

  /// Current state, starting a fetch if this is the first ask.
  ///
  /// The fetch is a side effect of reading, which is deliberate: it is what
  /// makes a subscription sufficient on its own. A caller that had to ask for
  /// the bytes *and* trigger the fetch is exactly the split that produced a
  /// `FutureBuilder` beside a `StreamBuilder` at both old call sites.
  LocalImage state(String key) {
    final cached = _read(key);
    if (cached != null && cached.isNotEmpty) {
      return (status: ImageStatus.ready, bytes: cached);
    }
    if (_unavailable.contains(key)) {
      return (status: ImageStatus.missing, bytes: null);
    }
    unawaited(_fetchOnce(key));
    return (status: ImageStatus.loading, bytes: null);
  }

  Future<void> _fetchOnce(String key) async {
    if (!_fetching.add(key)) return;
    try {
      final bytes = await _fetch(key);
      if (bytes != null && bytes.isNotEmpty) {
        // The write-through is what makes the next app start offline-capable,
        // and what re-emits this image's stream as ready.
        await _write(key, bytes);
      } else {
        _unavailable.add(key);
      }
    } catch (_) {
      _unavailable.add(key);
    } finally {
      _fetching.remove(key);
      if (!_changes.isClosed) _changes.add(key);
    }
  }

  /// Lets a retry path (a manual refresh, a reconnect) reconsider images that
  /// failed while the terminal was offline.
  void forgetFailures() {
    if (_unavailable.isEmpty) return;
    final keys = _unavailable.toList();
    _unavailable.clear();
    for (final k in keys) {
      if (!_changes.isClosed) _changes.add(k);
    }
  }

  Future<void> dispose() => _changes.close();
}

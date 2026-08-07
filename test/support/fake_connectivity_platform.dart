import 'dart:async';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';

/// A real, correct `ConnectivityPlatform` implementation backed by plain
/// mutable state, swapped in for [ConnectivityPlatform.instance] in tests —
/// same rationale and shape as `InMemorySecureStoragePlatform`
/// (test/support/in_memory_secure_storage.dart): `connectivity_plus` only
/// ships a `MethodChannel` implementation, which needs a real platform
/// channel unavailable in this sandbox, but its own platform-interface
/// package exposes a settable `.instance` for exactly this purpose.
///
/// This is what actually unblocks constructing a real `ConnectivityCubit`
/// (and therefore a real `DioClient`) in tests — previously disclosed
/// repeatedly across Phase 6 as needing "a real DioClient/ConnectivityCubit,
/// unavailable in this sandbox." [set] drives it from a test.
class FakeConnectivityPlatform extends ConnectivityPlatform {
  List<ConnectivityResult> _current;
  final _controller = StreamController<List<ConnectivityResult>>.broadcast();

  FakeConnectivityPlatform(this._current);

  static FakeConnectivityPlatform install({
    List<ConnectivityResult> initial = const [ConnectivityResult.wifi],
  }) {
    final platform = FakeConnectivityPlatform(initial);
    ConnectivityPlatform.instance = platform;
    return platform;
  }

  void set(List<ConnectivityResult> results) {
    _current = results;
    _controller.add(results);
  }

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => _current;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  void dispose() => _controller.close();
}

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../api/dio_client.dart';

/// Tracks whether the app can actually reach the cloud backend — not just
/// whether the OS reports a live network link. A WiFi/ethernet link can stay
/// "connected" while the backend itself is unreachable (DNS failure, server
/// down, captive portal); `connectivity_plus` alone only sees the local
/// interface and would keep reporting online for as long as that lasts.
class ConnectivityCubit extends Cubit<bool> {
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _probeTimer;
  DioClient? _probeClient;
  bool _linkUp = true;

  static const _probeInterval = Duration(seconds: 20);
  static const _probeTimeout = Duration(seconds: 5);

  ConnectivityCubit(this._connectivity) : super(true) {
    _init();
  }

  Future<void> _init() async {
    final results = await _connectivity.checkConnectivity();
    _linkUp = _isLinkUp(results);
    emit(_linkUp);
    _probeTimer = Timer.periodic(_probeInterval, (_) {
      if (_linkUp) unawaited(_probe());
    });
    _sub = _connectivity.onConnectivityChanged.listen((results) {
      _linkUp = _isLinkUp(results);
      if (!_linkUp) {
        emit(false);
      } else {
        unawaited(_probe());
      }
    });
  }

  bool get isOnline => state;

  /// Wired in from `di.dart` once `DioClient` exists — it depends on this
  /// cubit for its own offline gating, so this can't be a constructor
  /// argument here without a cycle. Reuses the app's existing Dio instance
  /// (same base URL, TLS trust config, interceptor stack) rather than
  /// standing up a second HTTP client just for probing.
  void attachProbeClient(DioClient client) {
    _probeClient = client;
    if (_linkUp) unawaited(_probe());
  }

  /// Forces an immediate reachability check instead of waiting for the next
  /// periodic tick — e.g. right before a user-triggered "retry".
  Future<void> probeNow() => _probe();

  Future<void> _probe() async {
    final client = _probeClient;
    if (client == null) return;
    try {
      await client.dio.get(
        '',
        options: Options(
          sendTimeout: _probeTimeout,
          receiveTimeout: _probeTimeout,
          validateStatus: (_) => true, // any HTTP response proves reachability
        ),
      );
      if (!isClosed) emit(true);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ConnectivityCubit] reachability probe failed: $e');
      }
      if (!isClosed) emit(false);
    }
  }

  bool _isLinkUp(List<ConnectivityResult> results) => results.any(
        (r) =>
            r == ConnectivityResult.wifi ||
            r == ConnectivityResult.ethernet ||
            r == ConnectivityResult.mobile ||
            r == ConnectivityResult.vpn ||
            r == ConnectivityResult.other,
      );

  @override
  Future<void> close() {
    _sub?.cancel();
    _probeTimer?.cancel();
    return super.close();
  }
}

import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/api/list_api.dart';
import 'pending_operation.dart';

/// What trying one operation against the cloud produced. Internal — callers
/// (`syncAll`'s loops, `executeRelayedOp`) translate this into "delete from
/// the box", "keep and count as a failure", or "keep, but don't treat this
/// pass as failed" (see [OpOutcome.notReadyYet]).
enum OpOutcome { synced, dropped, retryableFailure, notReadyYet }

/// Outcome of relaying one operation through the LAN leader (Phase 4) —
/// serialized as a plain string over `LanHubMessage.relayOpResult` and
/// reconstructed on the follower side. `terminalFailure` and `synced` both
/// mean "the leader is done with this, remove it locally"; `retryLater`
/// means "leave it queued, try again next time."
enum RelayOpResult { synced, terminalFailure, retryLater }

class OfflineQueueService {
  static const _boxName = 'offline_queue';
  late final Box<PendingOperation> _box;

  OfflineQueueService(this._box);

  static Future<OfflineQueueService> init() async {
    final box = await Hive.openBox<PendingOperation>(_boxName);
    return OfflineQueueService(box);
  }

  List<PendingOperation> get pending => _box.values.toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  bool get hasItems => _box.isNotEmpty;

  Future<void> enqueue(PendingOperation op) => _box.put(op.id, op);

  // ── Backoff & re-entrancy ────────────────────────────────────────────────
  // A branch reconnecting means every terminal's reconnect-edge listener AND
  // the periodic SyncEngine tick can call syncAll() around the same moment;
  // `_isSyncing` collapses those into one actual pass so the same pending op
  // is never posted twice concurrently. `_consecutiveFailures` backs off
  // (with jitter) after a failed pass so a still-flaky connection doesn't get
  // hammered on every tick.
  bool _isSyncing = false;
  DateTime? _lastAttemptAt;
  int _consecutiveFailures = 0;
  final Random _random = Random();

  static const _baseBackoff = Duration(seconds: 5);
  static const _maxBackoff = Duration(minutes: 2);

  Duration _currentBackoff() {
    if (_consecutiveFailures <= 0) return Duration.zero;
    final exponent = min(_consecutiveFailures, 5);
    final full = _baseBackoff.inMilliseconds * (1 << exponent);
    final capped = min(full, _maxBackoff.inMilliseconds);
    final jitter = _random.nextInt(max(1, (capped * 0.3).round()));
    return Duration(milliseconds: capped + jitter);
  }

  /// Replays queued mutations against the backend. Safe to call more often
  /// than needed — re-entrant calls are ignored, and a failed pass backs off
  /// before the next one is allowed to actually run. Pass [force] to bypass
  /// the backoff for a user-triggered manual retry.
  Future<void> syncAll(DioClient dio, {bool force = false}) async {
    if (_isSyncing) return;
    final ops = pending;
    if (ops.isEmpty) return;

    if (!force && _lastAttemptAt != null) {
      final elapsed = DateTime.now().difference(_lastAttemptAt!);
      final backoff = _currentBackoff();
      if (elapsed < backoff) {
        if (kDebugMode) {
          print(
            '[OfflineQueue] backing off — ${(backoff - elapsed).inSeconds}s remaining',
          );
        }
        return;
      }
    }

    _isSyncing = true;
    _lastAttemptAt = DateTime.now();
    var hadFailure = false;
    try {
      // Order matters: closeShift depends on openShift having landed in the
      // same pass (see _execCloseShift) — keep this exact sequence.
      const order = [
        PendingOperationType.createOrder,
        PendingOperationType.addItems,
        PendingOperationType.cancelLineItems,
        PendingOperationType.payOrder,
        PendingOperationType.openShift,
        PendingOperationType.closeShift,
      ];
      for (final type in order) {
        for (final op in ops.where((o) => o.type == type)) {
          final outcome = await _executeOp(dio, op);
          switch (outcome) {
            case OpOutcome.synced:
            case OpOutcome.dropped:
              await _box.delete(op.id);
              break;
            case OpOutcome.retryableFailure:
              hadFailure = true;
              break;
            case OpOutcome.notReadyYet:
              break;
          }
        }
      }
    } finally {
      _isSyncing = false;
    }
    _consecutiveFailures = hadFailure ? _consecutiveFailures + 1 : 0;
  }

  bool _isRelaying = false;

  /// LAN relay (Phase 4), follower side: sends each pending op to the leader
  /// instead of posting to the cloud directly, removing it locally only once
  /// the leader reports back `synced` or `terminalFailure`. No backoff of its
  /// own — a dropped LAN link is already handled by `LanHubClient`'s own
  /// reconnect backoff, so this just no-ops while not connected.
  Future<void> relayViaLan({
    required bool Function() isLeaderConnected,
    required Future<RelayOpResult?> Function(PendingOperation) relayOne,
  }) async {
    if (_isRelaying) return;
    if (!isLeaderConnected()) return;
    final ops = pending;
    if (ops.isEmpty) return;

    _isRelaying = true;
    try {
      for (final op in ops) {
        if (!isLeaderConnected()) break;
        final result = await relayOne(op);
        if (result == null) break; // no reply — timeout or dropped mid-flight
        if (result == RelayOpResult.synced ||
            result == RelayOpResult.terminalFailure) {
          await _box.delete(op.id);
        }
        // retryLater: leave queued; still try the rest of this pass — one
        // op's transient issue shouldn't block unrelated ones.
      }
    } finally {
      _isRelaying = false;
    }
  }

  /// LAN relay (Phase 4), leader side: executes one operation relayed from a
  /// follower right now, without touching this leader's own outbox — the
  /// follower owns that bookkeeping and decides what to do with the result.
  Future<RelayOpResult> executeRelayedOp(DioClient dio, PendingOperation op) async {
    final outcome = await _executeOp(dio, op);
    switch (outcome) {
      case OpOutcome.synced:
        return RelayOpResult.synced;
      case OpOutcome.dropped:
        return RelayOpResult.terminalFailure;
      case OpOutcome.retryableFailure:
      case OpOutcome.notReadyYet:
        return RelayOpResult.retryLater;
    }
  }

  Future<OpOutcome> _executeOp(DioClient dio, PendingOperation op) {
    switch (op.type) {
      case PendingOperationType.createOrder:
        return _execCreateOrder(dio, op);
      case PendingOperationType.addItems:
        return _execAddItems(dio, op);
      case PendingOperationType.cancelLineItems:
        return _execCancelLineItems(dio, op);
      case PendingOperationType.payOrder:
        return _execPayOrder(dio, op);
      case PendingOperationType.openShift:
        return _execOpenShift(dio, op);
      case PendingOperationType.closeShift:
        return _execCloseShift(dio, op);
    }
  }

  Future<OpOutcome> _execCreateOrder(DioClient dio, PendingOperation op) async {
    try {
      final payload = jsonDecode(op.payload) as Map<String, dynamic>;
      // UTC + 'Z' suffix — backend RFC3339 formatini talab qiladi
      payload['client_created_at'] = op.createdAt.toUtc().toIso8601String();
      await dio.post(ListAPI.orders, data: payload);
      return OpOutcome.synced;
    } catch (e) {
      if (kDebugMode) print('[OfflineQueue] createOrder sync error: $e');
      return _isTerminalError(e) ? OpOutcome.dropped : OpOutcome.retryableFailure;
    }
  }

  /// faqat ochiq (open) orderga qo'shiladi
  Future<OpOutcome> _execAddItems(DioClient dio, PendingOperation op) async {
    try {
      final orderId = await _getOpenOrderIdByTable(dio, op.tableId);
      if (orderId.isEmpty) {
        // Ochiq order yo'q — bu operatsiya eskirgan, queue dan o'chiramiz
        if (kDebugMode) {
          print('[OfflineQueue] addItems skipped (no open order for table ${op.tableId})');
        }
        return OpOutcome.dropped;
      }
      final payload = jsonDecode(op.payload) as Map<String, dynamic>;
      await dio.post(
        ListAPI.orderItems(orderId),
        queryParameters: {'lang': 'uz'},
        data: payload,
      );
      return OpOutcome.synced;
    } catch (e) {
      if (kDebugMode) print('[OfflineQueue] addItems sync error: $e');
      return _isTerminalError(e) ? OpOutcome.dropped : OpOutcome.retryableFailure;
    }
  }

  /// mavjud buyurtma pozitsiyalarini bekor qilish
  Future<OpOutcome> _execCancelLineItems(DioClient dio, PendingOperation op) async {
    try {
      final payload = jsonDecode(op.payload) as Map<String, dynamic>;
      final lineIds = (payload['line_ids'] as List?)?.cast<String>() ?? const [];
      final comment = payload['comment'] as String?;
      for (final id in lineIds) {
        try {
          await dio.post(
            ListAPI.orderItemCancel(id),
            data: <String, dynamic>{
              if (comment != null && comment.isNotEmpty) 'comment': comment,
            },
          );
        } on DioException catch (e) {
          // 404 — line allaqachon yo'q — davom etamiz
          if (e.response?.statusCode != 404) rethrow;
        }
      }
      return OpOutcome.synced;
    } catch (e) {
      if (kDebugMode) print('[OfflineQueue] cancelLineItems sync error: $e');
      return _isTerminalError(e) ? OpOutcome.dropped : OpOutcome.retryableFailure;
    }
  }

  /// order_id payload da saqlangan
  Future<OpOutcome> _execPayOrder(DioClient dio, PendingOperation op) async {
    try {
      final payload = jsonDecode(op.payload) as Map<String, dynamic>;
      final orderId = payload['order_id'] as String? ?? '';
      if (orderId.isEmpty) return OpOutcome.dropped;
      await dio.post(ListAPI.payToOrder(orderId), data: payload);
      return OpOutcome.synced;
    } catch (e) {
      if (kDebugMode) print('[OfflineQueue] payOrder sync error: $e');
      return _isTerminalError(e) ? OpOutcome.dropped : OpOutcome.retryableFailure;
    }
  }

  Future<OpOutcome> _execOpenShift(DioClient dio, PendingOperation op) async {
    try {
      final payload = jsonDecode(op.payload) as Map<String, dynamic>;
      await dio.post(ListAPI.openShift, data: payload);
      return OpOutcome.synced;
    } catch (e) {
      if (kDebugMode) print('[OfflineQueue] openShift sync error: $e');
      // "Already has an open shift" comes back as a 4xx — already-terminal
      // handling below drops it correctly (a real shift already exists
      // for this register; retrying can't help).
      return _isTerminalError(e) ? OpOutcome.dropped : OpOutcome.retryableFailure;
    }
  }

  /// shift's own id isn't known (opened offline), so this looks the active
  /// shift up by cash_register_id instead. Must run after openShift in the
  /// same pass so a same-pass open-then-close has something to find.
  Future<OpOutcome> _execCloseShift(DioClient dio, PendingOperation op) async {
    try {
      final payload = jsonDecode(op.payload) as Map<String, dynamic>;
      final cashRegisterId = payload['cash_register_id'] as String? ?? '';
      if (cashRegisterId.isEmpty) return OpOutcome.dropped;
      final shiftId = await _getActiveShiftId(dio, cashRegisterId);
      if (shiftId.isEmpty) {
        // Underlying openShift hasn't synced yet (or never will) — leave
        // queued rather than risk silently dropping a real close. Will
        // resolve on a later pass once/if the open lands.
        if (kDebugMode) {
          print('[OfflineQueue] closeShift: no active shift yet for register $cashRegisterId');
        }
        return OpOutcome.notReadyYet;
      }
      await dio.post(
        ListAPI.closeShift(shiftId),
        data: {
          'closing_cash': payload['closing_cash'],
          'closing_card': payload['closing_card'],
        },
      );
      return OpOutcome.synced;
    } catch (e) {
      if (kDebugMode) print('[OfflineQueue] closeShift sync error: $e');
      return _isTerminalError(e) ? OpOutcome.dropped : OpOutcome.retryableFailure;
    }
  }

  /// Returns the currently active shift's id for [cashRegisterId], or '' if
  /// none is open yet (including on any lookup error — same fail-soft style
  /// as `_getOpenOrderIdByTable` below).
  Future<String> _getActiveShiftId(DioClient dio, String cashRegisterId) async {
    try {
      final res = await dio.dio.get(
        ListAPI.activeShift,
        queryParameters: {'cash_register_id': cashRegisterId},
      );
      final data = res.data['data'];
      if (data is! Map || data.isEmpty) return '';
      return data['id'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Faqat ochiq (status: open) orderni qaytaradi.
  /// Agar stol to'langan yoki boshqa statusda bo'lsa — '' qaytaradi.
  Future<String> _getOpenOrderIdByTable(DioClient dio, String tableId) async {
    try {
      final res = await dio.dio.get(ListAPI.orderWithTableId(tableId));
      final data = res.data['data'];
      if (data is! List || data.isEmpty) return '';
      final order = data[0] as Map<String, dynamic>;
      final status = order['status']?.toString() ?? '';
      // Faqat ochiq orderga item qo'shish mumkin
      if (status != 'open') return '';
      return order['id'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Server tomonidan rad etilgan xatolar (qayta urinish kerak emas).
  bool _isTerminalError(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      // 4xx — client xato (eskirgan ma'lumot, noto'g'ri so'rov)
      if (code != null && code >= 400 && code < 500) return true;
    }
    return false;
  }

  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Object().hashCode.abs()}';
}

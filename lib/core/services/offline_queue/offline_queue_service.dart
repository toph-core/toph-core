import 'dart:convert';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/api/list_api.dart';
import 'package:mary_ai_pos/core/utils/order_conflict_helper.dart';
import 'package:mary_ai_pos/core/utils/uuid.dart';
import 'pending_operation.dart';
import 'quarantined_operation.dart';

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
  static const _quarantineBoxName = 'offline_queue_quarantine';
  late final Box<PendingOperation> _box;
  late final Box<QuarantinedOperation> _quarantineBox;

  OfflineQueueService(this._box, this._quarantineBox);

  static Future<OfflineQueueService> init() async {
    final box = await Hive.openBox<PendingOperation>(_boxName);
    final quarantineBox =
        await Hive.openBox<QuarantinedOperation>(_quarantineBoxName);
    return OfflineQueueService(box, quarantineBox);
  }

  List<PendingOperation> get pending => _box.values.toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  bool get hasItems => _box.isNotEmpty;

  /// Reactive backing for a status screen — `Box.listenable()` already fires
  /// on every put/delete, no extra bookkeeping needed on top.
  ValueListenable<Box<PendingOperation>> get listenable => _box.listenable();

  Future<void> enqueue(PendingOperation op) => _box.put(op.id, op);

  /// Newest-first — a manual-resolution screen cares about the most recent
  /// drop, not the oldest.
  List<QuarantinedOperation> get quarantined => _quarantineBox.values.toList()
    ..sort((a, b) => b.quarantinedAt.compareTo(a.quarantinedAt));

  ValueListenable<Box<QuarantinedOperation>> get quarantineListenable =>
      _quarantineBox.listenable();

  Future<void> _quarantine(PendingOperation op, String reason) =>
      _quarantineBox.put(op.id, QuarantinedOperation.fromDropped(op, reason));

  /// Manual resolution: re-enqueues a quarantined op for another attempt
  /// (e.g. the underlying issue was fixed server-side, or it was quarantined
  /// on a stale read that's no longer true). No-op if [id] isn't quarantined.
  Future<void> retryQuarantined(String id) async {
    final q = _quarantineBox.get(id);
    if (q == null) return;
    await enqueue(q.toRetryable());
    await _quarantineBox.delete(id);
  }

  /// Manual resolution: discards a quarantined op for good (the operator has
  /// decided it shouldn't be retried — e.g. the order was cancelled anyway).
  Future<void> dismissQuarantined(String id) => _quarantineBox.delete(id);

  // ── Backoff & re-entrancy ────────────────────────────────────────────────
  // A branch reconnecting means every terminal's reconnect-edge listener AND
  // the periodic SyncEngine tick can call syncAll() around the same moment;
  // `_isSyncing` collapses those into one actual pass so the same pending op
  // is never posted twice concurrently. `_consecutiveFailures` backs off
  // (with jitter) after a failed pass so a still-flaky connection doesn't get
  // hammered on every tick.
  // Uses package:clock's `clock.now()` rather than raw `DateTime.now()` —
  // the one place in this class where wall-clock time drives real logic
  // (vs. record-keeping timestamps elsewhere), so the Phase 6 soak test can
  // compress simulated hours via fake_async's `withClock`/`getClock`.
  bool _isSyncing = false;
  DateTime? _lastAttemptAt;
  int _consecutiveFailures = 0;
  final Random _random = Random();

  DateTime? get lastAttemptAt => _lastAttemptAt;

  /// Set immediately before an `_exec*` method returns `OpOutcome.dropped`,
  /// read right after by whichever caller (`syncAll`/`relayViaLan`) needs it
  /// to quarantine the op with a meaningful reason. A shared field rather
  /// than widening `OpOutcome` into a payload-carrying type — every call
  /// site in this class is already strictly sequential (single `await`
  /// chain, never concurrent `_exec*` calls), the same reasoning behind the
  /// existing `_isSyncing`/`_lastAttemptAt` shared fields above.
  String? _lastDropReason;

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
      final elapsed = clock.now().difference(_lastAttemptAt!);
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
    _lastAttemptAt = clock.now();
    var hadFailure = false;
    try {
      // Order matters: closeShift depends on openShift having landed in the
      // same pass (see _execCloseShift) — keep this exact sequence.
      const order = [
        PendingOperationType.createOrder,
        PendingOperationType.addItems,
        PendingOperationType.cancelLineItems,
        // After create (the order must exist server-side first), before pay
        // (a pay after a transfer should land against the final table).
        PendingOperationType.transferTable,
        PendingOperationType.payOrder,
        PendingOperationType.cancelOrder,
        PendingOperationType.openShift,
        PendingOperationType.closeShift,
      ];
      for (final type in order) {
        for (final op in ops.where((o) => o.type == type)) {
          final outcome = await _executeOp(dio, op);
          switch (outcome) {
            case OpOutcome.synced:
              await _box.delete(op.id);
              break;
            case OpOutcome.dropped:
              await _quarantine(op, _lastDropReason ?? "Noma'lum xatolik");
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
        if (result == RelayOpResult.synced) {
          await _box.delete(op.id);
        } else if (result == RelayOpResult.terminalFailure) {
          // The wire protocol only carries a bare RelayOpResult, not an
          // error string (see LanHubMessage.relayOpResult) — the leader
          // executed this exact same _executeOp logic, but its _lastDropReason
          // never crosses the socket, so this is deliberately generic rather
          // than fabricated detail.
          await _quarantine(op, 'Klaster yetakchisi rad etdi (server so\'rovni qabul qilmadi).');
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

  /// Records why an op is about to be dropped (read by `syncAll` right after
  /// `_executeOp` returns, to quarantine it) and returns `OpOutcome.dropped`
  /// — a one-liner so every drop site below stays as terse as it was before
  /// quarantining existed.
  OpOutcome _dropped(String reason) {
    _lastDropReason = reason;
    return OpOutcome.dropped;
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
      case PendingOperationType.cancelOrder:
        return _execCancelOrder(dio, op);
      case PendingOperationType.openShift:
        return _execOpenShift(dio, op);
      case PendingOperationType.closeShift:
        return _execCloseShift(dio, op);
      case PendingOperationType.transferTable:
        return _execTransferTable(dio, op);
    }
  }

  /// CLIENT_FACING_OFFLINE_PLAN.md §7 — replays `orders/{id}/transfer`, the
  /// same endpoint `transfer_table_dialog` used to await directly.
  Future<OpOutcome> _execTransferTable(DioClient dio, PendingOperation op) async {
    try {
      final payload = jsonDecode(op.payload) as Map<String, dynamic>;
      final orderId = payload['order_id'] as String? ?? '';
      final targetTableId = payload['target_table_id'] as String? ?? '';
      if (orderId.isEmpty || targetTableId.isEmpty) {
        return _dropped("Ko'chirish ma'lumotida order_id yoki target_table_id yo'q.");
      }
      await dio.post(
        ListAPI.orderTransfer(orderId),
        data: {'target_table_id': targetTableId},
      );
      return OpOutcome.synced;
    } catch (e) {
      if (kDebugMode) print('[OfflineQueue] transferTable sync error: $e');
      return _isTerminalError(e) ? _dropped(e.toString()) : OpOutcome.retryableFailure;
    }
  }

  Future<OpOutcome> _execCreateOrder(DioClient dio, PendingOperation op) async {
    try {
      final payload = jsonDecode(op.payload) as Map<String, dynamic>;
      // UTC + 'Z' suffix — backend RFC3339 formatini talab qiladi
      payload['client_created_at'] = op.createdAt.toUtc().toIso8601String();
      await dio.post(ListAPI.orders, data: payload);
      return OpOutcome.synced;
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        final merged = await _mergeCreateOrderConflict(dio, op, e);
        if (merged != null) return merged;
      }
      if (kDebugMode) print('[OfflineQueue] createOrder sync error: $e');
      return _isTerminalError(e) ? _dropped(e.toString()) : OpOutcome.retryableFailure;
    } catch (e) {
      if (kDebugMode) print('[OfflineQueue] createOrder sync error: $e');
      return _isTerminalError(e) ? _dropped(e.toString()) : OpOutcome.retryableFailure;
    }
  }

  /// offline-first-target-architecture.md §6/§13: the online path
  /// (`create_order_bloc.dart:213-227`) already merges a duplicate-table-open
  /// 409 into the winning order by re-submitting the losing terminal's items
  /// via add-items instead of discarding them. This replays the same merge
  /// for the offline-replay executor, which previously fell straight through
  /// to generic quarantine and silently dropped the bundled items. Returns
  /// null (caller falls back to its existing terminal-error handling) when
  /// the 409 body doesn't carry a resolvable winning order id — that
  /// unparseable residual is unchanged, pending the design doc's open
  /// question 4.
  Future<OpOutcome?> _mergeCreateOrderConflict(
    DioClient dio,
    PendingOperation op,
    DioException conflict,
  ) async {
    final data = conflict.response?.data;
    final message =
        (data is Map && data['error'] != null) ? data['error'].toString() : null;
    final winningOrderId = extractExistingOrderIdFromConflict(message);
    if (winningOrderId == null || winningOrderId.isEmpty) return null;

    final payload = jsonDecode(op.payload) as Map<String, dynamic>;
    final items =
        (payload['items'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    if (items.isEmpty) return OpOutcome.synced; // nothing to merge, order exists

    try {
      await dio.post(
        ListAPI.orderItems(winningOrderId),
        queryParameters: {'lang': 'uz'},
        data: {
          'items': [
            for (final item in items)
              {
                'comment': item['comment'],
                'good_id': item['good_id'],
                'quantity': item['quantity'],
                // Fresh at merge time, not reused from anywhere — this is
                // genuinely this terminal's first submission attempt (the
                // original create never landed under its own id).
                'client_item_id': generateUuidV4(),
              },
          ],
        },
      );
      return OpOutcome.synced;
    } catch (e) {
      if (kDebugMode) print('[OfflineQueue] createOrder 409-merge error: $e');
      return _isTerminalError(e) ? _dropped(e.toString()) : OpOutcome.retryableFailure;
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
        return _dropped("Stol ${op.tableId} uchun ochiq buyurtma topilmadi (eskirgan operatsiya).");
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
      return _isTerminalError(e) ? _dropped(e.toString()) : OpOutcome.retryableFailure;
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
      return _isTerminalError(e) ? _dropped(e.toString()) : OpOutcome.retryableFailure;
    }
  }

  /// order_id payload da saqlangan
  Future<OpOutcome> _execPayOrder(DioClient dio, PendingOperation op) async {
    try {
      final payload = jsonDecode(op.payload) as Map<String, dynamic>;
      final orderId = payload['order_id'] as String? ?? '';
      if (orderId.isEmpty) return _dropped("To'lov ma'lumotida order_id yo'q.");
      await dio.post(ListAPI.payToOrder(orderId), data: payload);
      return OpOutcome.synced;
    } catch (e) {
      if (kDebugMode) print('[OfflineQueue] payOrder sync error: $e');
      return _isTerminalError(e) ? _dropped(e.toString()) : OpOutcome.retryableFailure;
    }
  }

  /// Zero-total order cancel (e.g. a fully-discounted/comped check closed
  /// with nothing due) — order_id payload da saqlangan. 404 means the order
  /// is already gone/cancelled server-side, same tolerance `cancelLineItems`
  /// already gives its per-line 404s.
  Future<OpOutcome> _execCancelOrder(DioClient dio, PendingOperation op) async {
    try {
      final payload = jsonDecode(op.payload) as Map<String, dynamic>;
      final orderId = payload['order_id'] as String? ?? '';
      if (orderId.isEmpty) return _dropped("Bekor qilish ma'lumotida order_id yo'q.");
      try {
        await dio.post(ListAPI.cancelOrder(orderId));
      } on DioException catch (e) {
        if (e.response?.statusCode != 404) rethrow;
      }
      return OpOutcome.synced;
    } catch (e) {
      if (kDebugMode) print('[OfflineQueue] cancelOrder sync error: $e');
      return _isTerminalError(e) ? _dropped(e.toString()) : OpOutcome.retryableFailure;
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
      return _isTerminalError(e) ? _dropped(e.toString()) : OpOutcome.retryableFailure;
    }
  }

  /// shift's own id isn't known (opened offline), so this looks the active
  /// shift up by cash_register_id instead. Must run after openShift in the
  /// same pass so a same-pass open-then-close has something to find.
  Future<OpOutcome> _execCloseShift(DioClient dio, PendingOperation op) async {
    try {
      final payload = jsonDecode(op.payload) as Map<String, dynamic>;
      final cashRegisterId = payload['cash_register_id'] as String? ?? '';
      if (cashRegisterId.isEmpty) return _dropped('Kassa smenani yopish ma\'lumotida cash_register_id yo\'q.');
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
      return _isTerminalError(e) ? _dropped(e.toString()) : OpOutcome.retryableFailure;
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

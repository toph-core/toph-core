/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 (§B1) — how a queued order write
/// reaches the server.
///
/// The order aggregate is the reason the whole sync effort exists, and it is
/// the last write path still on the retiring Hive `OfflineQueueService`. These
/// handlers move its replay onto the single outbox the back-office already
/// uses: the screen calls a repository, the repository writes the replica and
/// enqueues through `LocalWriter`, and this runs later — possibly on a
/// different network, possibly after a restart.
///
/// **Why this file speaks HTTP directly (and is on the §9.1 allowlist).** The
/// staff handlers in `users_outbox.dart` delegate to `MainRepository`, whose
/// implementation owns the endpoints. The order path carries logic that has no
/// home in a plain CRUD repository — the create's 409 "table already open"
/// merge, the per-line 404-tolerant cancel — logic that is *proven* in
/// `OfflineQueueService._exec*` and is ported here verbatim rather than
/// reinvented behind an abstraction. So this is transport: the order
/// equivalent of `main_datasources.dart` for reads, and the one place an order
/// write touches Dio. It replaces `OfflineQueueService` on the §9.1 allowlist
/// — when Phase C deletes that class, the allowlist loses an entry and this
/// takes its place, so the ratchet does not grow.
///
/// **What the new model removes.** The old `_execAddItems` looked the order up
/// by table at replay time, because the server assigned the order its own id
/// and the client never learned it. Here the order id is client-supplied and
/// idempotent (`LocalWriter.write` doc), so an add posts straight to the known
/// order and the fragile table lookup is gone. `chainKey` returns the item's
/// `order_id`, so an add / cancel / pay never overtakes the create it depends
/// on (`outbox_executor.dart` `chainKeyOf`).
library;

import 'package:dio/dio.dart';
import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/api/list_api.dart';
import 'package:mary_ai_pos/core/utils/order_conflict_helper.dart';
import 'package:mary_ai_pos/core/utils/uuid.dart';

import 'outbox_executor.dart';
import 'outbox_operation.dart';

void registerOrdersOutboxHandlers(OutboxExecutors executors, DioClient dio) {
  // orders/create — POST /orders, mirroring OfflineQueueService._execCreateOrder.
  //
  // `client_created_at` is stamped from the op's own capture time so a late
  // replay still records when the cashier actually opened the check. On a 409
  // (another terminal already opened this table offline) the losing terminal's
  // items are merged into the winning order rather than dropped — the same
  // reconciliation the online create path performs (create_order_bloc), and
  // the reason a bare `ConflictFailure` → permanent mapping is not enough here.
  executors.register(
    'orders',
    'create',
    OutboxHandler(send: (op) async {
      final payload = <String, dynamic>{
        ...op.payload,
        'client_created_at': op.createdAt.toUtc().toIso8601String(),
      };
      try {
        await dio.post(ListAPI.orders, data: payload);
        return const OutboxExecutionResult.succeeded();
      } on DioException catch (e) {
        if (e.response?.statusCode == 409) {
          final merged = await _mergeCreateOrderConflict(dio, op, e);
          if (merged != null) return merged;
        }
        return _mapDioError(e);
      } catch (e) {
        return OutboxExecutionResult.retry(e.toString());
      }
    }),
  );

  // order_items/create — POST /orders/{order_id}/items.
  //
  // The op's entityId is the *item* id (its own row's key, so its pending
  // clears on ack); the order it belongs to is in the payload. chainKey is that
  // order id, so an item waits behind the order's own create instead of racing
  // to a server that has never heard of the order.
  executors.register(
    'order_items',
    'create',
    OutboxHandler(
      chainKey: (op) => (op.payload['order_id'] as String?) ?? '',
      send: (op) async {
        final orderId = op.payload['order_id'] as String? ?? '';
        if (orderId.isEmpty) {
          return const OutboxExecutionResult.permanent(
            'add items without an order id',
          );
        }
        return _send(() => dio.post(
              ListAPI.orderItems(orderId),
              queryParameters: {'lang': 'uz'},
              data: {'items': op.payload['items']},
            ));
      },
    ),
  );

  // order_items/delete — cancel one line (POST /order-items/{id}/cancel),
  // tolerating a 404 (the line is already gone, which is what a cancel wants).
  // The op is one-per-line (LocalWriter.delete), so entityId is the line id.
  // Chained to the order so a cancel never replays before the add that created
  // the line — without the chain it would 404 on a not-yet-added line and the
  // cancel would be silently lost.
  executors.register(
    'order_items',
    'delete',
    OutboxHandler(
      chainKey: (op) => (op.payload['order_id'] as String?) ?? '',
      send: (op) async {
        final lineId = op.entityId ?? '';
        if (lineId.isEmpty) {
          return const OutboxExecutionResult.permanent(
            'cancel without a line id',
          );
        }
        final comment = op.payload['comment'] as String?;
        try {
          await dio.post(
            ListAPI.orderItemCancel(lineId),
            data: <String, dynamic>{
              if (comment != null && comment.isNotEmpty) 'comment': comment,
            },
          );
          return const OutboxExecutionResult.succeeded();
        } on DioException catch (e) {
          if (e.response?.statusCode == 404) {
            return const OutboxExecutionResult.succeeded();
          }
          return _mapDioError(e);
        } catch (e) {
          return OutboxExecutionResult.retry(e.toString());
        }
      },
    ),
  );

  // orders/pay — POST /orders/{id}/pay. Idempotent on the server: paying an
  // already-paid order returns it unchanged, so a replay after an ack that
  // never came back is a success, not a double charge.
  executors.register(
    'orders',
    'pay',
    OutboxHandler(send: (op) async {
      final orderId = _orderIdOf(op);
      if (orderId.isEmpty) {
        return const OutboxExecutionResult.permanent('pay without an order id');
      }
      return _send(() => dio.post(ListAPI.payToOrder(orderId), data: op.payload));
    }),
  );

  // orders/cancel — zero-total order cancel (a fully-comped check). 404 means
  // the order is already gone server-side, same tolerance the per-line cancel
  // gives.
  executors.register(
    'orders',
    'cancel',
    OutboxHandler(send: (op) async {
      final orderId = _orderIdOf(op);
      if (orderId.isEmpty) {
        return const OutboxExecutionResult.permanent(
          'cancel without an order id',
        );
      }
      try {
        await dio.post(ListAPI.cancelOrder(orderId));
        return const OutboxExecutionResult.succeeded();
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) {
          return const OutboxExecutionResult.succeeded();
        }
        return _mapDioError(e);
      } catch (e) {
        return OutboxExecutionResult.retry(e.toString());
      }
    }),
  );

  // orders/transfer — POST /orders/{id}/transfer. Chained to the order (via
  // the default entity-id chain key) so it lands after the create.
  executors.register(
    'orders',
    'transfer',
    OutboxHandler(send: (op) async {
      final orderId = _orderIdOf(op);
      final targetTableId = op.payload['target_table_id'] as String? ?? '';
      if (orderId.isEmpty || targetTableId.isEmpty) {
        return const OutboxExecutionResult.permanent(
          'transfer missing order_id or target_table_id',
        );
      }
      return _send(() => dio.post(
            ListAPI.orderTransfer(orderId),
            data: {'target_table_id': targetTableId},
          ));
    }),
  );
}

/// The order id an `orders`-entity op addresses — its `entityId` (the order's
/// own key for pay / cancel / transfer), falling back to `order_id` in the
/// payload. `order_items` ops do not use this: their entityId is the line id,
/// and the order they belong to is read straight from the payload.
String _orderIdOf(OutboxOperation op) {
  final id = op.entityId;
  if (id != null && id.isNotEmpty) return id;
  return op.payload['order_id'] as String? ?? '';
}

/// Runs [request] and maps the outcome. A 4xx is a verdict → permanent;
/// anything else (5xx, timeout, dropped connection) never reached a verdict →
/// retry. The same rule `outcomeForFailure` applies to the `Failure`-typed
/// handlers, restated here because these speak `DioException` directly.
Future<OutboxExecutionResult> _send(Future<void> Function() request) async {
  try {
    await request();
    return const OutboxExecutionResult.succeeded();
  } on DioException catch (e) {
    return _mapDioError(e);
  } catch (e) {
    return OutboxExecutionResult.retry(e.toString());
  }
}

OutboxExecutionResult _mapDioError(DioException e) {
  final code = e.response?.statusCode;
  if (code != null && code >= 400 && code < 500) {
    return OutboxExecutionResult.permanent('HTTP $code: ${e.message ?? ''}');
  }
  return OutboxExecutionResult.retry(e.message ?? 'network error');
}

/// offline-first-target-architecture.md §6/§13 — a duplicate-table-open 409
/// merges the losing terminal's items into the winning order instead of
/// dropping them. A verbatim port of `OfflineQueueService._mergeCreateOrderConflict`.
/// Returns null when the 409 body carries no resolvable winning order id, so
/// the caller falls back to its ordinary 4xx handling.
Future<OutboxExecutionResult?> _mergeCreateOrderConflict(
  DioClient dio,
  OutboxOperation op,
  DioException conflict,
) async {
  final data = conflict.response?.data;
  final message =
      (data is Map && data['error'] != null) ? data['error'].toString() : null;
  final winningOrderId = extractExistingOrderIdFromConflict(message);
  if (winningOrderId == null || winningOrderId.isEmpty) return null;

  final items =
      (op.payload['items'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  if (items.isEmpty) return const OutboxExecutionResult.succeeded();

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
              // Fresh at merge time — this is genuinely this terminal's first
              // submission of these items to the winning order.
              'client_item_id': generateUuidV4(),
            },
        ],
      },
    );
    return const OutboxExecutionResult.succeeded();
  } on DioException catch (e) {
    return _mapDioError(e);
  } catch (e) {
    return OutboxExecutionResult.retry(e.toString());
  }
}

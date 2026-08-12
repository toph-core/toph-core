import 'dart:convert';

import 'package:mary_ai_pos/core/services/offline_queue/offline_queue_service.dart';
import 'package:mary_ai_pos/core/services/offline_queue/pending_operation.dart';
import 'package:mary_ai_pos/core/utils/uuid.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/payment_repository.dart';

class PaymentRepositoryImpl implements PaymentRepository {
  final OfflineQueueService _queue;

  PaymentRepositoryImpl({required OfflineQueueService queue}) : _queue = queue;

  @override
  Future<void> pay({
    required String orderId,
    required String tableId,
    required int paidAmount,
    required String paymentType,
    required bool applyService,
    int? discountAmount,
    int? discountPercent,
    int tableCharge = 0,
  }) async {
    final payload = jsonEncode({
      'order_id': orderId,
      'customer_paid_amount': paidAmount.toString(),
      'payment_type': paymentType,
      'apply_service': applyService,
      // §12 rule 1 (the design doc's own "single most safety-critical
      // finding") — this payload previously had no client-generated
      // idempotency key at all, unlike every other write in this app. A
      // retried payOrder POST (a timeout after the charge actually landed
      // server-side) had nothing for the backend to dedupe a duplicate
      // charge on. Generated once here, baked into the persisted
      // PendingOperation payload, so every replay attempt
      // (OfflineQueueService.syncAll's backoff loop) resends the identical
      // id rather than a fresh one per attempt.
      'client_payment_id': generateUuidV4(),
      // Phase 3: pin the table charge to the clock the receipt was printed
      // against. The value is frozen into the persisted payload here, so a
      // replay hours later still bills the minutes the customer actually sat.
      if (tableCharge > 0) 'table_charge': tableCharge,
      if (discountAmount != null && discountAmount > 0)
        'discount_amount': discountAmount,
      if (discountPercent != null && discountPercent > 0)
        'discount_percent': discountPercent,
    });
    await _queue.enqueue(PendingOperation(
      id: OfflineQueueService.newId(),
      type: PendingOperationType.payOrder,
      payload: payload,
      tableId: tableId,
      createdAt: DateTime.now(),
    ));
  }

  @override
  Future<void> cancelZeroTotalOrder({
    required String orderId,
    required String tableId,
  }) async {
    await _queue.enqueue(PendingOperation(
      id: OfflineQueueService.newId(),
      type: PendingOperationType.cancelOrder,
      payload: jsonEncode({'order_id': orderId}),
      tableId: tableId,
      createdAt: DateTime.now(),
    ));
  }
}

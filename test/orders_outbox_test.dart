/// OFFLINE_FIRST_EVERYWHERE_PLAN.md §B1 — the order outbox handlers, drained
/// against a fake HTTP adapter so the endpoint/retry/merge logic is proven
/// without a socket or a running app.
///
/// A genuine `DioClient` with its real interceptor stack, its adapter swapped
/// for `FakeHttpClientAdapter` — the same "real small implementation of the
/// platform's own extension point" the soak test uses. Each case shapes the
/// server's reply, invokes the registered handler exactly as the drainer
/// would (`executors.resolve(op)!.send(op)`), and asserts on both the request
/// that went out and the `OutboxOutcome` that came back.
library;

import 'dart:convert';

import 'package:alice/alice.dart';
import 'package:alice/model/alice_configuration.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/auth/storage/token_storage_impl.dart';
import 'package:mary_ai_pos/core/outbox/orders_outbox.dart';
import 'package:mary_ai_pos/core/outbox/outbox_executor.dart';
import 'package:mary_ai_pos/core/outbox/outbox_operation.dart';
import 'package:mary_ai_pos/core/services/connectivity/connectivity_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_connectivity_platform.dart';
import 'support/fake_http_client_adapter.dart';
import 'support/in_memory_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DioClient dioClient;
  late OutboxExecutors executors;
  late List<RequestOptions> requests;
  // Each test overrides this to shape the server's replies. Defaults to 200.
  late Future<ResponseBody> Function(RequestOptions) respond;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    InMemorySecureStoragePlatform.install();
    FakeConnectivityPlatform.install();

    final tokenStorage = AppTokenStorage(prefs, const FlutterSecureStorage());
    final connectivity = ConnectivityCubit(Connectivity());
    dioClient = DioClient(tokenStorage, connectivity);
    // DioClient's constructor unconditionally adds `aliceDioAdapter`, which
    // throws until an Alice instance registers it (mirrors di.dart).
    Alice(
      configuration: AliceConfiguration(
        showNotification: false,
        showInspectorOnShake: false,
      ),
    ).addAdapter(dioClient.aliceDioAdapter);

    requests = [];
    respond = (_) async => okResponse();
    dioClient.dio.httpClientAdapter = FakeHttpClientAdapter((options) async {
      requests.add(options);
      return respond(options);
    });

    executors = OutboxExecutors();
    registerOrdersOutboxHandlers(executors, dioClient);
  });

  Future<OutboxExecutionResult> run(OutboxOperation op) =>
      executors.resolve(op)!.send(op);

  OutboxOperation op({
    required String entity,
    required String action,
    String? entityId,
    Map<String, dynamic> payload = const {},
    DateTime? createdAt,
  }) =>
      OutboxOperation(
        id: 'op-$entity-$action',
        entity: entity,
        action: action,
        entityId: entityId,
        payload: payload,
        createdAt: createdAt ?? DateTime.utc(2026, 1, 2, 3, 4, 5),
        nextAttemptAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

  ResponseBody jsonResponse(int status, Object body) => ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  // The body Dio actually put on the wire, whether it kept the Map or the
  // transformer serialized it to a string first.
  Map<String, dynamic> bodyOf(RequestOptions o) {
    final d = o.data;
    if (d is Map) return d.cast<String, dynamic>();
    if (d is String && d.isNotEmpty) {
      return jsonDecode(d) as Map<String, dynamic>;
    }
    return {};
  }

  group('orders/create', () {
    final createOp = op(
      entity: 'orders',
      action: 'create',
      entityId: 'order-1',
      payload: {
        'id': 'order-1',
        'table_id': 't1',
        'items': [
          {'good_id': 'g1', 'quantity': 2, 'comment': ''},
        ],
      },
    );

    test('posts to /orders with a client_created_at stamp and succeeds',
        () async {
      final result = await run(createOp);

      expect(result.outcome, OutboxOutcome.succeeded);
      expect(requests, hasLength(1));
      expect(requests.single.uri.path, '/api/v1/orders');
      expect(requests.single.method, 'POST');
      // Captured from the op's own time, so a late replay still records when
      // the check was actually opened.
      expect(bodyOf(requests.single)['client_created_at'],
          '2026-01-02T03:04:05.000Z');
    });

    test('a dropped connection is retryable, not permanent', () async {
      respond = (options) async => connectionErrorResponse(options);
      final result = await run(createOp);
      expect(result.outcome, OutboxOutcome.retry);
    });

    test('a 4xx verdict is permanent', () async {
      respond = (options) async => jsonResponse(400, {'error': 'bad'});
      final result = await run(createOp);
      expect(result.outcome, OutboxOutcome.permanent);
    });

    test('a 5xx is retryable', () async {
      respond = (options) async => jsonResponse(500, {'error': 'boom'});
      final result = await run(createOp);
      expect(result.outcome, OutboxOutcome.retry);
    });

    test('409 with a resolvable id merges items into the winning order',
        () async {
      const winningId = '22222222-2222-2222-2222-222222222222';
      respond = (options) async {
        if (options.uri.path == '/api/v1/orders') {
          return jsonResponse(409, {
            'error': 'Stol allaqachon faol buyurtmaga ega: $winningId',
          });
        }
        return okResponse();
      };

      final result = await run(createOp);

      expect(result.outcome, OutboxOutcome.succeeded);
      expect(requests, hasLength(2));
      // The losing terminal's items are re-submitted to the winning order.
      expect(requests[1].uri.path, '/api/v1/orders/$winningId/items');
      final mergedItems = (bodyOf(requests[1])['items'] as List)
          .cast<Map<String, dynamic>>();
      expect(mergedItems.single['good_id'], 'g1');
      // A fresh client_item_id, minted at merge time.
      expect(mergedItems.single['client_item_id'], isNotEmpty);
    });

    test('409 with no resolvable id falls through to permanent', () async {
      respond = (options) async =>
          jsonResponse(409, {'error': 'table already open'});
      final result = await run(createOp);
      expect(result.outcome, OutboxOutcome.permanent);
      // Only the create was attempted — nothing to merge into.
      expect(requests, hasLength(1));
    });
  });

  group('order_items/create', () {
    final addOp = op(
      entity: 'order_items',
      action: 'create',
      payload: {
        'order_id': 'order-1',
        'items': [
          {'good_id': 'g2', 'quantity': 1, 'client_item_id': 'ci-1'},
        ],
      },
    );

    test('posts straight to the known order — no table lookup', () async {
      final result = await run(addOp);

      expect(result.outcome, OutboxOutcome.succeeded);
      // One request: the add. The old queue needed a GET to find the order by
      // table first; the client-supplied id removes it.
      expect(requests, hasLength(1));
      expect(requests.single.uri.path, '/api/v1/orders/order-1/items');
      expect(requests.single.uri.queryParameters['lang'], 'uz');
      expect((bodyOf(requests.single)['items'] as List).single['good_id'], 'g2');
    });

    test('chains behind its order so an item never overtakes the create', () {
      final createOp = op(entity: 'orders', action: 'create', entityId: 'order-1');
      // Same chain key → the drainer keeps them in order.
      expect(executors.chainKeyOf(addOp), 'order-1');
      expect(executors.chainKeyOf(createOp), 'order-1');
    });
  });

  group('order_items/cancel', () {
    final cancelOp = op(
      entity: 'order_items',
      action: 'cancel',
      payload: {
        'order_id': 'order-1',
        'line_ids': ['l1', 'l2'],
        'comment': 'wrong table',
      },
    );

    test('cancels each line, tolerating a 404 on an already-gone line',
        () async {
      respond = (options) async {
        if (options.uri.path.endsWith('/l1/cancel')) {
          return jsonResponse(404, {'error': 'gone'});
        }
        return okResponse();
      };

      final result = await run(cancelOp);

      expect(result.outcome, OutboxOutcome.succeeded);
      expect(requests, hasLength(2));
    });

    test('a non-404 error on a line is retryable', () async {
      respond = (options) async => jsonResponse(500, {'error': 'boom'});
      final result = await run(cancelOp);
      expect(result.outcome, OutboxOutcome.retry);
    });

    test('chains behind its order', () {
      expect(executors.chainKeyOf(cancelOp), 'order-1');
    });
  });

  group('orders/pay', () {
    final payOp = op(
      entity: 'orders',
      action: 'pay',
      entityId: 'order-1',
      payload: {'order_id': 'order-1', 'payment_type': 'cash', 'amount': 1000},
    );

    test('posts the pay body to /orders/{id}/pay', () async {
      final result = await run(payOp);
      expect(result.outcome, OutboxOutcome.succeeded);
      expect(requests.single.uri.path, '/api/v1/orders/order-1/pay');
      expect(bodyOf(requests.single)['amount'], 1000);
    });

    test('chains behind its order', () {
      expect(executors.chainKeyOf(payOp), 'order-1');
    });
  });

  group('orders/cancel', () {
    test('a 404 means already-cancelled and is a success', () async {
      respond = (options) async => jsonResponse(404, {'error': 'gone'});
      final result = await run(
        op(entity: 'orders', action: 'cancel', entityId: 'order-1'),
      );
      expect(result.outcome, OutboxOutcome.succeeded);
      expect(requests.single.uri.path, '/api/v1/orders/order-1/cancel');
    });
  });

  group('orders/transfer', () {
    test('posts the target table to /orders/{id}/transfer', () async {
      final result = await run(op(
        entity: 'orders',
        action: 'transfer',
        entityId: 'order-1',
        payload: {'target_table_id': 't2'},
      ));
      expect(result.outcome, OutboxOutcome.succeeded);
      expect(requests.single.uri.path, '/api/v1/orders/order-1/transfer');
      expect(bodyOf(requests.single)['target_table_id'], 't2');
    });

    test('a missing target table is a permanent, un-sendable op', () async {
      final result = await run(op(
        entity: 'orders',
        action: 'transfer',
        entityId: 'order-1',
        payload: const {},
      ));
      expect(result.outcome, OutboxOutcome.permanent);
      expect(requests, isEmpty);
    });
  });
}

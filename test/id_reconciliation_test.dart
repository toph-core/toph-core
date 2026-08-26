/// DECISIONS.md D1 — closing the create-id asymmetry.
///
/// Every create endpoint except `CreateOrder` assigns its own id; the swagger
/// spec confirms none of them accept a client-supplied one. That left two bad
/// options, and this repository had been taking the second: invent an id and
/// end up with two rows for one thing when replication delivers the server's,
/// or queue with no local row and have the operator watch nothing happen.
///
/// The third option is to invent an id, mark it provisional, and swap it for
/// the real one when the response arrives — including in anything still queued
/// that referenced it, which is what D11's translation ordering needs.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/db/apply_change.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/outbox/local_writer.dart';
import 'package:mary_ai_pos/core/outbox/outbox_drainer.dart';
import 'package:mary_ai_pos/core/outbox/outbox_executor.dart';
import 'package:mary_ai_pos/core/outbox/outbox_store.dart';

void main() {
  late LocalDatabase db;
  late OutboxStore store;
  late LocalWriter writer;
  late ChangeApplier applier;

  setUp(() {
    db = LocalDatabase.open(':memory:');
    applier = ChangeApplier(db);
    store = OutboxStore(db);
    writer = LocalWriter(db: db, applier: applier, outbox: store);
  });

  tearDown(() => db.dispose());

  OutboxDrainer drainerReturning(Map<String, dynamic>? Function(String entity) response) {
    final executors = OutboxExecutors();
    for (final entity in ['halls', 'translations', 'goods']) {
      executors.register(
        entity,
        'create',
        OutboxHandler(
          send: (op) async =>
              OutboxExecutionResult.succeeded(serverRow: response(op.entity)),
        ),
      );
      executors.register(
        entity,
        'update',
        OutboxHandler(send: (op) async => const OutboxExecutionResult.succeeded()),
      );
    }
    return OutboxDrainer(
      db: db,
      store: store,
      applier: applier,
      executors: executors,
    );
  }

  group('the local row appears immediately', () {
    test('a create writes a row under a provisional id', () {
      final localId = writer.create(
        entity: 'halls',
        row: {'name': 'Yangi zal', 'branch_id': 'b-1'},
      );

      expect(db.byId('halls', localId)!['name'], 'Yangi zal');
      expect(db.isProvisional('halls', localId), isTrue);
      expect(store.pending().single.action, 'create');
    });

    test('the queued body does not carry the invented id', () {
      // The server assigns it; sending ours would be noise at best and a
      // rejected request at worst.
      final localId = writer.create(
        entity: 'halls',
        row: {'name': 'Zal'},
        request: {'name': 'Zal'},
      );

      expect(store.pending().single.payload.containsKey('id'), isFalse);
      expect(store.pending().single.entityId, localId);
    });
  });

  group('reconciliation on success', () {
    test('the provisional row is replaced by the server row', () async {
      final localId = writer.create(entity: 'halls', row: {'name': 'Zal'});

      await drainerReturning((_) => {'id': 'server-1', 'name': 'Zal'}).drain();

      expect(db.byId('halls', localId), isNull, reason: 'stand-in is gone');
      expect(db.byId('halls', 'server-1')!['name'], 'Zal');
      expect(db.isProvisional('halls', localId), isFalse);
    });

    test('a `data` envelope is unwrapped', () async {
      writer.create(entity: 'halls', row: {'name': 'Zal'});

      await drainerReturning(
        (_) => {
          'data': {'id': 'server-1', 'name': 'Zal'},
        },
      ).drain();

      expect(db.byId('halls', 'server-1'), isNotNull);
    });

    test('exactly one row survives — the whole point', () async {
      writer.create(entity: 'halls', row: {'name': 'Zal'});
      await drainerReturning((_) => {'id': 'server-1', 'name': 'Zal'}).drain();

      // And a later replication pass delivering the same row changes nothing.
      applier.applyOne(
        entity: 'halls',
        action: 'update',
        entityId: 'server-1',
        payload: {'id': 'server-1', 'name': 'Zal'},
      );

      final rows = db.selectData('SELECT data FROM halls');
      expect(rows, hasLength(1));
    });

    test('a response with no id drops the stand-in rather than keeping a ghost',
        () async {
      final localId = writer.create(entity: 'halls', row: {'name': 'Zal'});

      await drainerReturning((_) => null).drain();

      expect(db.byId('halls', localId), isNull);
      expect(db.isProvisional('halls', localId), isFalse);
    });
  });

  group('queued references are repointed', () {
    test('a queued write referencing the provisional id is rewritten',
        () async {
      // D11: a meal queued with `name_i18n` pointing at a translation that has
      // not been created yet. Without the rewrite the server receives a
      // reference to a row it has never heard of.
      final translationId =
          writer.create(entity: 'translations', row: {'en': 'Pilaf'});
      writer.create(
        entity: 'goods',
        row: {'name': 'Osh', 'name_i18n': translationId},
        request: {'name': 'Osh', 'name_i18n': translationId},
      );

      await drainerReturning(
        (entity) => entity == 'translations'
            ? {'id': 'trans-real', 'en': 'Pilaf'}
            : {'id': 'good-real', 'name': 'Osh'},
      ).drain();

      // Both landed; the good's payload was repointed before it was sent.
      expect(db.byId('translations', 'trans-real'), isNotNull);
      expect(db.byId('goods', 'good-real'), isNotNull);
      expect(db.byId('translations', translationId), isNull);
    });

    test('rewriting reaches nested payloads', () {
      writer.enqueueOnly(
        entity: 'goods',
        action: 'create',
        request: {
          'good': {'name_i18n': 'local-1'},
          'calculations': [
            {'ingredient_id': 'local-1'},
            {'ingredient_id': 'other'},
          ],
        },
      );

      store.rewriteReferences(oldId: 'local-1', newId: 'real-1');

      final payload = store.pending().single.payload;
      expect((payload['good'] as Map)['name_i18n'], 'real-1');
      expect((payload['calculations'] as List)[0]['ingredient_id'], 'real-1');
      expect((payload['calculations'] as List)[1]['ingredient_id'], 'other');
    });

    test('a queued update to the provisional row follows it to the new id', () {
      writer.enqueueOnly(entity: 'halls', action: 'update', entityId: 'local-1');

      store.rewriteReferences(oldId: 'local-1', newId: 'real-1');

      expect(store.pending().single.entityId, 'real-1');
    });

    test('an id merely quoted inside text is not corrupted', () {
      // Whole-value matching, not substring: a description containing an id
      // must survive intact.
      writer.enqueueOnly(
        entity: 'goods',
        action: 'create',
        request: {'description': 'see local-1 for details'},
      );

      store.rewriteReferences(oldId: 'local-1', newId: 'real-1');

      expect(store.pending().single.payload['description'],
          'see local-1 for details');
    });

    test('operations already sent are left alone', () {
      final opId = writer.enqueueOnly(
        entity: 'halls',
        action: 'update',
        entityId: 'local-1',
      );
      store.markSucceeded(opId);

      expect(store.rewriteReferences(oldId: 'local-1', newId: 'real-1'), 0);
    });
  });

  group('a dependent write waits for the id it references', () {
    // The rewrite above only helps if the dependent has not already been sent.
    // Within one drain pass the queue is replayed in enqueue order, so the
    // translation goes first and the good is repointed in time. The interesting
    // case is the one that pass cannot fix: the translation's create *fails*,
    // and the good — a different row, so a different causal chain — would
    // otherwise sail past it carrying an id no server has ever assigned.

    /// Records what each handler was actually asked to send, and lets the
    /// translation create be failed on demand.
    ({OutboxDrainer drainer, List<Map<String, dynamic>> sent}) rig({
      required bool translationFails,
    }) {
      final sent = <Map<String, dynamic>>[];
      final executors = OutboxExecutors();
      executors.register(
        'translations',
        'create',
        OutboxHandler(
          send: (op) async {
            if (translationFails) {
              return const OutboxExecutionResult.retry('no connectivity');
            }
            sent.add({'entity': 'translations', ...op.payload});
            return const OutboxExecutionResult.succeeded(
              serverRow: {'id': 'trans-real', 'uz': 'Osh'},
            );
          },
        ),
      );
      executors.register(
        'goods',
        'create',
        OutboxHandler(
          send: (op) async {
            sent.add({'entity': 'goods', ...op.payload});
            return const OutboxExecutionResult.succeeded(
              serverRow: {'id': 'good-real', 'name': 'Osh'},
            );
          },
        ),
      );
      return (
        drainer: OutboxDrainer(
          db: db,
          store: store,
          applier: applier,
          executors: executors,
        ),
        sent: sent,
      );
    }

    /// The pair the menu editor composes offline: a translation row, then a
    /// good whose `name_i18n` points at it.
    String queueMealWithNewTranslation() {
      final translationId =
          writer.create(entity: 'translations', row: {'uz': 'Osh'});
      writer.create(
        entity: 'goods',
        row: {'name': 'Osh', 'name_i18n': translationId},
        request: {
          'good': {'name': 'Osh', 'name_i18n': translationId},
          'ingredient_calculations': const [],
        },
      );
      return translationId;
    }

    test('the good is sent with the real translation id, never the local one',
        () async {
      final translationId = queueMealWithNewTranslation();
      final r = rig(translationFails: false);

      final result = await r.drainer.drain();

      expect(result.sent, 2);
      final good = r.sent.firstWhere((e) => e['entity'] == 'goods');
      expect((good['good'] as Map)['name_i18n'], 'trans-real');
      expect((good['good'] as Map)['name_i18n'], isNot(translationId));
    });

    test('the good is held back while its translation is still failing',
        () async {
      queueMealWithNewTranslation();
      final r = rig(translationFails: true);

      final result = await r.drainer.drain();

      // Nothing left. Before the guard the good went out anyway — a different
      // entity id, so a different chain — and the server was handed a
      // `name_i18n` it could not resolve, which is a 4xx, which this queue
      // treats as permanent. The meal was lost for good.
      expect(r.sent, isEmpty);
      expect(result.sent, 0);
      expect(result.blocked, 1);
      expect(result.retrying, 1);
      // Still queued, both of them, so the next pass can finish the job.
      expect(store.pending().length, 2);
    });

    test('it goes out on the next pass, repointed', () async {
      queueMealWithNewTranslation();
      await rig(translationFails: true).drainer.drain();

      store.clearBackoff();
      final r = rig(translationFails: false);
      final result = await r.drainer.drain();

      expect(result.sent, 2);
      final good = r.sent.firstWhere((e) => e['entity'] == 'goods');
      expect((good['good'] as Map)['name_i18n'], 'trans-real');
    });

    test('an unrelated write is not held back by someone else\'s wait',
        () async {
      // The guard is a reference test, not a global stop: a good that names no
      // unresolved id must still leave while another one waits.
      queueMealWithNewTranslation();
      writer.create(
        entity: 'goods',
        row: {'name': 'Somsa'},
        request: {
          'good': {'name': 'Somsa'},
          'ingredient_calculations': const [],
        },
      );

      final r = rig(translationFails: true);
      final result = await r.drainer.drain();

      expect(result.sent, 1);
      expect(r.sent.single['good'], {'name': 'Somsa'});
    });

    test('a create quoting its own provisional id is not held by itself', () {
      // The op that resolves an id must never be the op that waits on it.
      final id = writer.create(
        entity: 'halls',
        row: {'name': 'Zal'},
        request: {'id': 'ignored', 'name': 'Zal'},
      );
      expect(db.isProvisional('halls', id), isTrue);

      // Re-queue the same body with the id in it, addressed to the same row.
      store.rewriteReferences(oldId: 'ignored', newId: id);

      expect(store.pending().single.entityId, id);
    });
  });

  group('client-supplied ids are left alone', () {
    test('a write that was never provisional keeps its id', () async {
      // Orders carry the id their terminal invents, because the backend accepts
      // it. Reconciliation must not touch those.
      writer.write(
        entity: 'halls',
        id: 'client-chosen',
        row: {'id': 'client-chosen', 'name': 'Zal'},
        action: 'update',
      );

      await drainerReturning((_) => {'id': 'client-chosen', 'name': 'Zal'})
          .drain();

      expect(db.byId('halls', 'client-chosen'), isNotNull);
      expect(db.isProvisional('halls', 'client-chosen'), isFalse);
    });
  });
}

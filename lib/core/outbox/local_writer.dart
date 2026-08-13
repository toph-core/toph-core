/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 2 — "write locally first, sync afterward."
///
/// The single primitive every repository calls in Phase 4. One method, one
/// transaction: the row the UI will render and the operation that will carry it
/// to the server are committed together or not at all.
///
/// Nothing here awaits the network, and nothing here can. That is the point —
/// once every write goes through this class, "the UI never waits on the
/// network" stops being a convention that review has to enforce and becomes a
/// property of the only way to write.
library;

import '../db/apply_change.dart';
import '../db/local_database.dart';
import '../utils/uuid.dart';
import 'outbox_store.dart';

class LocalWriter {
  final LocalDatabase _db;
  final ChangeApplier _applier;
  final OutboxStore _outbox;

  const LocalWriter({
    required LocalDatabase db,
    required ChangeApplier applier,
    required OutboxStore outbox,
  })  : _db = db,
        _applier = applier,
        _outbox = outbox;

  /// Writes [row] into the replica and queues [action] for replay.
  ///
  /// [id] is the row's primary key and is **client-generated** for creates. The
  /// backend accepts a client-supplied order id and returns the existing order
  /// when it already knows that id (`CreateOrder`, `service/order.go`), so a
  /// replayed create is idempotent and the id a terminal invents offline is the
  /// id the row keeps forever. No temporary keys, no reconciliation pass, no
  /// window where a receipt shows one number and the server another.
  ///
  /// [request] is the body to send, when it differs from the row — paying an
  /// order sends a payment request but leaves an updated order behind. It
  /// defaults to [row], which is right for ordinary creates and updates.
  ///
  /// Returns the outbox operation id.
  String write({
    required String entity,
    required String id,
    required Map<String, dynamic> row,
    String action = 'update',
    Map<String, dynamic>? request,
    String? operationId,
  }) {
    final opId = operationId ?? generateUuidV4();
    return _db.transaction(() {
      _applier.applyLocalWrite(entity: entity, id: id, payload: row);
      return _outbox.enqueue(
        id: opId,
        entity: entity,
        action: action,
        entityId: id,
        payload: request ?? row,
      );
    });
  }

  /// Creates a row under a client-invented id that the server will replace.
  ///
  /// Every create endpoint except `CreateOrder` assigns its own id. Until this
  /// existed, that left one bad choice and one worse one: invent an id anyway
  /// and end up with two rows for one thing when replication delivers the
  /// server's, or queue the create with no local row and have the operator
  /// watch nothing happen.
  ///
  /// So the row is written under a provisional id and *marked* as provisional.
  /// When the create's response comes back, the drainer swaps it for the real
  /// row and rewrites anything still queued that referenced the old id. The
  /// operator sees their row immediately; the id underneath it changes once,
  /// invisibly, and only ever before the row has been sent anywhere else.
  ///
  /// Returns the provisional id.
  String create({
    required String entity,
    required Map<String, dynamic> row,
    Map<String, dynamic>? request,
    String? id,
    String? operationId,
  }) {
    final localId = id ?? generateUuidV4();
    final opId = operationId ?? generateUuidV4();
    _db.transaction(() {
      _applier.applyLocalWrite(
        entity: entity,
        id: localId,
        payload: {...row, 'id': localId},
      );
      _db.markProvisional(entity, localId);
      _outbox.enqueue(
        id: opId,
        entity: entity,
        action: 'create',
        entityId: localId,
        payload: request ?? row,
      );
    });
    return localId;
  }

  /// Removes a row locally and queues the delete.
  ///
  /// The row goes immediately — the operator asked for it gone, so it is gone
  /// on their screen. The `_pending` guard keeps replication from resurrecting
  /// it from a pull that was already in flight; if the delete is ultimately
  /// rejected, quarantine releases the guard and the row comes back, which is
  /// the correct outcome and a visible one.
  String delete({
    required String entity,
    required String id,
    Map<String, dynamic> request = const {},
    String? operationId,
  }) {
    final opId = operationId ?? generateUuidV4();
    return _db.transaction(() {
      _db.deleteRow(entity, id);
      _db.markPending(entity, id);
      return _outbox.enqueue(
        id: opId,
        entity: entity,
        action: 'delete',
        entityId: id,
        payload: request,
      );
    });
  }

  /// Queues an operation with no local row of its own.
  ///
  /// For actions whose local effect is already covered by another write, or
  /// that have no representable local state — closing a shift, sending a
  /// kitchen ticket. Rare by design: an action with no local effect is usually
  /// a sign that something the UI should be showing is missing from the
  /// replica.
  String enqueueOnly({
    required String entity,
    required String action,
    String? entityId,
    Map<String, dynamic> request = const {},
    String? operationId,
  }) {
    final opId = operationId ?? generateUuidV4();
    return _outbox.enqueue(
      id: opId,
      entity: entity,
      action: action,
      entityId: entityId,
      payload: request,
    );
  }
}

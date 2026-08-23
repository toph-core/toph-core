import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:mary_ai_pos/core/db/apply_change.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_message.dart';

/// The one timer transition with no server verb: dropping the local record
/// when an order closes. `start`/`pause`/`resume` reuse the `kTimer*`
/// constants the outbox already replays.
const String kTimerEvict = 'evict';

/// Peer-to-peer propagation of this terminal's own writes.
///
/// ## Why this exists beside `ChangeFeedRelay`
///
/// `ChangeFeedRelay` distributes what the *leader pulled from the cloud*. That
/// makes N terminals cost one cloud poll instead of N, which is what Phase 5
/// set out to do — but it says nothing about a venue whose internet is down.
/// With no uplink the leader has no batch to relay, so nothing moves between
/// terminals at all: a cashier's order stayed invisible to the till three
/// metres away until the connection came back.
///
/// This closes that. Every terminal broadcasts each row it commits, and every
/// terminal applies what it hears. The cloud is no longer in the path, so the
/// venue stays consistent with itself whether or not it can reach the server.
///
/// ## What keeps the two feeds from fighting
///
/// They write through the same [ChangeApplier] and therefore obey the same
/// precedence rule, which is the only rule that matters here: a row with an
/// unsynced local edit is never overwritten by an incoming one. So a peer's
/// broadcast loses to work this terminal has not yet sent, and the cloud's
/// canonical version wins over a peer's copy as soon as it arrives, because by
/// then the originator's pending guard has cleared.
///
/// A peer's row is applied **unguarded and unqueued** — see
/// [ChangeApplier.applyFromPeer]. The terminal that wrote it owns its trip to
/// the server. Without that, every terminal in the venue would queue the same
/// create and the server would see one order N times.
///
/// ## Ordering
///
/// A parent row and its children are separate messages (an order, then its
/// line items), sent in that order over one WebSocket, which preserves it. A
/// child that somehow arrives first is still stored — the queries join on
/// `order_id` and simply do not surface it until the parent lands — so the
/// worst case is a brief invisibility, not a lost row.
///
/// ## Table timers
///
/// Timers ride the same wire but not the same applier — see [broadcastTimer].
class LocalChangeRelay {
  final ChangeApplier _applier;

  /// For table timers, which are local-authority state and so never pass
  /// through [ChangeApplier] — see [broadcastTimer].
  final LocalDatabase _db;

  /// Hands one encoded change to the hub. Null on a terminal with no LAN
  /// wiring; set by `di.dart`, which owns the `LanHubService` this reaches.
  final void Function(LanHubMessage message)? _send;

  /// This terminal's stable id, stamped on outbound messages for diagnostics.
  /// A function rather than a value because the id lives in
  /// `PrintQueueService`, which `di.dart` registers after this.
  final String Function()? _terminalId;

  LocalChangeRelay({
    required ChangeApplier applier,
    required LocalDatabase db,
    void Function(LanHubMessage message)? send,
    String Function()? terminalId,
  })  : _applier = applier,
        _db = db,
        _send = send,
        _terminalId = terminalId;

  /// How many changes this terminal has broadcast, and applied from peers.
  ///
  /// Surfaced on the sync-status screen so "is the venue actually talking?"
  /// has an answer that does not require reading logs — the one question a
  /// manager can otherwise only answer by ringing something in on one till and
  /// walking to another. A [ValueNotifier] rather than a plain getter so that
  /// screen needs no polling timer of its own; this file's neighbours already
  /// carry that convention (`LanHubServer.clientCountNotifier`).
  ///
  /// Counts frames this process has handled. It resets on restart, and is
  /// diagnostics rather than bookkeeping — nothing branches on it.
  final ValueNotifier<({int sent, int received})> countersListenable =
      ValueNotifier((sent: 0, received: 0));

  ({int sent, int received}) get counters => countersListenable.value;

  void _countSent() {
    final c = countersListenable.value;
    countersListenable.value = (sent: c.sent + 1, received: c.received);
  }

  void _countReceived() {
    final c = countersListenable.value;
    countersListenable.value = (sent: c.sent, received: c.received + 1);
  }

  /// Outbound: called by [ChangeApplier] once a local write has committed.
  ///
  /// Fire-and-forget by construction. A disconnected peer, a hub that is not
  /// running, a socket that throws — none of it can reach the caller, because
  /// the write it describes is already durable and the operator is already
  /// looking at it. Convergence for whoever missed this message is the next
  /// cloud pull's job, not this method's.
  void broadcast({
    required String entity,
    required String action,
    required String id,
    Map<String, dynamic>? payload,
  }) {
    final send = _send;
    if (send == null) return;
    final String? encoded;
    try {
      encoded = payload == null ? null : jsonEncode(payload);
    } catch (_) {
      // A payload that will not encode cannot be sent, and must not take the
      // commit down with it — it is already in this terminal's database.
      return;
    }
    _countSent();
    send(
      LanHubMessage.localChange(
        entity: entity,
        action: action,
        entityId: id,
        payloadJson: encoded,
        origin: _terminalId?.call(),
      ),
    );
  }

  /// Inbound: applies one peer's broadcast. Returns null if the message was
  /// unusable, so a malformed frame from an older build is dropped rather than
  /// throwing on a socket callback.
  ApplyStats? apply(LanHubMessage msg) {
    final entity = msg.changeEntity;
    final action = msg.changeAction;
    final id = msg.changeEntityId;
    if (entity == null || entity.isEmpty) return null;
    if (action == null || action.isEmpty) return null;
    if (id == null || id.isEmpty) return null;

    Map<String, dynamic>? payload;
    final raw = msg.changePayload;
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) return null;
        payload = decoded;
      } catch (_) {
        return null;
      }
    }
    // A create/update with no payload has nothing to write; only a delete is
    // meaningful without one.
    if (payload == null && action != 'delete') return null;

    _countReceived();
    return _applier.applyFromPeer(
      entity: entity,
      action: action,
      entityId: id,
      payload: payload,
    );
  }

  /// Outbound: announces that a table timer started, paused, resumed, or was
  /// dropped.
  ///
  /// Separate from [broadcast] because table timers are **local-authority**
  /// state. `table_time_sessions` is not a replicated entity (see
  /// `kIntentionallyNotReplicated`), the local record's shape is not the
  /// server's, and it lives in `LocalTables.tableTimers` rather than an entity
  /// table — so `ChangeApplier` has nothing to say about it and the row feed
  /// cannot carry it. Left there, a table paused on one till kept counting on
  /// every other one, which is the visible confusion this fixes.
  ///
  /// [record] is the settled record the transition produced, null for
  /// [kTimerEvict]. See `LanHubMessage.timerRecord` for why the event carries
  /// its result rather than making each receiver recompute it.
  void broadcastTimer({
    required String orderId,
    required String action,
    Map<String, dynamic>? record,
  }) {
    final send = _send;
    if (send == null) return;
    final String? encoded;
    try {
      encoded = record == null ? null : jsonEncode(record);
    } catch (_) {
      return;
    }
    _countSent();
    send(
      LanHubMessage.timerAction(
        orderId: orderId,
        action: action,
        recordJson: encoded,
        origin: _terminalId?.call(),
      ),
    );
  }

  /// Inbound: applies a peer's timer transition to this terminal's own record.
  ///
  /// Writes straight to [LocalDatabase], which is what stops the echo: the
  /// emission point is `TableTimerLocalRepositoryImpl._commitTimerAction`, and
  /// this never goes near it. That also means no outbox row — the terminal
  /// where the waiter actually tapped pause owns telling the server, exactly as
  /// with [apply]. Two terminals queueing the same pause would bill the table
  /// twice for one action.
  ///
  /// Returns false when the frame was unusable.
  bool applyTimer(LanHubMessage msg) {
    final orderId = msg.timerOrderId;
    final action = msg.timerActionName;
    if (orderId == null || orderId.isEmpty) return false;
    if (action == null || action.isEmpty) return false;

    if (action == kTimerEvict) {
      _countReceived();
      _db.evictTableTimer(orderId);
      return true;
    }

    final raw = msg.timerRecord;
    if (raw == null) return false;
    final Map<String, dynamic> record;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return false;
      record = decoded;
    } catch (_) {
      return false;
    }

    _countReceived();
    _db.saveTableTimer(orderId, record);
    return true;
  }
}

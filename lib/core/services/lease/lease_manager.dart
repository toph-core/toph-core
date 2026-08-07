import 'package:mary_ai_pos/core/database/local_database.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_message.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_service.dart';
import 'package:mary_ai_pos/core/services/print_queue/print_queue_service.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';

/// offline-first-target-architecture.md §6.
///
/// "The one deliberate exception to 'UI never waits on anything'" — every
/// other write in this app (§4) commits locally and returns immediately;
/// opening a table is the one operation the design doc accepts as needing a
/// network round trip, because it's the one case where two different local
/// databases might each think they're right, and only asking somebody who's
/// talked to both resolves that.
///
/// `LeaseManager` never writes business data — its job ends at yes/no
/// arbitration. The order-open write itself belongs entirely to
/// `OrdersRepository`/`CreateOrderBloc` as an ordinary follow-up step (§4's
/// flow), called only after a `granted` result here.
///
/// **Not yet wired into `CreateOrderBloc`'s table-open path.** §11 step 4 is
/// explicit that this wiring should land only after Phase 2 has rewritten
/// that same Bloc onto `LocalRepository`/`LocalDatabase` and that rewrite's
/// own canary window has cleared — specifically so a table-open regression
/// can be attributed to one change at a time. This class is additive and
/// dark until then, the same way Phase 0's `LocalDatabase` shipped dark
/// before Phase 1 read from it. See EXECUTION_CONCERNS.md.
class LeaseResult {
  final bool isGranted;

  /// [rejected] only: which terminal currently holds the table, when known —
  /// surfaced to the cashier as "already opened on another terminal", not
  /// required for the arbitration logic itself.
  final String? heldBy;

  /// Non-null only for [unreachable] — distinguishes "the leader said no"
  /// from "the leader couldn't be reached at all", so a caller applying §6's
  /// timeout-policy table (Block/Allow-unverified/Solo) can tell the two
  /// apart for its error copy.
  final String? unreachableReason;

  const LeaseResult._({
    required this.isGranted,
    this.heldBy,
    this.unreachableReason,
  });

  const LeaseResult.granted() : this._(isGranted: true);

  const LeaseResult.rejected({String? heldBy})
      : this._(isGranted: false, heldBy: heldBy);

  const LeaseResult.unreachable(String reason)
      : this._(isGranted: false, unreachableReason: reason);

  bool get isUnreachable => unreachableReason != null;
}

class LeaseManager {
  final LanHubService _lanHub;
  final LocalDatabase _localDb;

  LeaseManager({required LanHubService lanHub, required LocalDatabase localDb})
      : _lanHub = lanHub,
        _localDb = localDb;

  /// Leader-only, in-memory, intentionally lost on restart/failover (§6
  /// Lease Recovery: losing this only means an in-flight request retries,
  /// never a silent double-booking, since the durable check below still
  /// applies to whatever *did* land). `tableId -> (claimant, claimedAt)`.
  final Map<String, ({String claimant, DateTime claimedAt})> _ephemeralClaims = {};

  /// A few seconds, per §6 Lease Recovery — the normal case evicts a claim
  /// the instant its corresponding durable write is confirmed
  /// (`releaseTableLease`/`handleLeaseReleaseAsLeader`, same-process or one
  /// LAN message away); this is only the backstop for an abandoned UI action
  /// that never calls that at all.
  static const _ephemeralTtl = Duration(seconds: 5);

  /// Reuses `PrintQueueService`'s existing persisted per-terminal id
  /// (`print_terminal_id` in `SharedPreferences`) rather than inventing a
  /// second one — this codebase already has exactly one stable identity per
  /// installed terminal, and a lease claimant needs the same kind of value a
  /// print-job owner already does.
  String get _myTerminalId => inject<PrintQueueService>().terminalId;

  /// §6's one public entry point for the UI side (only `CreateOrderBloc`'s
  /// table-open path, once wired). Resolves the current `LanMode` at call
  /// time rather than caching it — the mode can change between one
  /// table-open attempt and the next (a manager reconfiguring in the
  /// settings screen, or Phase 4 failover once that lands).
  Future<LeaseResult> acquireTableLease(String tableId) async {
    switch (_lanHub.mode) {
      case LanMode.disabled:
        // §6 table: "this terminal IS the leader (solo mode)" — no
        // coordination possible or needed with exactly one terminal.
        return _arbitrate(tableId, claimant: _myTerminalId);
      case LanMode.server:
        // This terminal already IS the leader — arbitrate against its own
        // state directly, no network round trip.
        return _arbitrate(tableId, claimant: _myTerminalId);
      case LanMode.client:
        if (!_lanHub.isClientConnected) {
          return const LeaseResult.unreachable(
            "Klaster yetakchisiga ulanish yo'q — stol egaligini tekshirib bo'lmadi.",
          );
        }
        final reply = await _lanHub.requestLease(
          tableId: tableId,
          terminalId: _myTerminalId,
        );
        if (reply == null) {
          return const LeaseResult.unreachable(
            "Klaster yetakchisi javob bermadi — stol egaligini tekshirib bo'lmadi.",
          );
        }
        if (reply.type == LanHubMessageType.leaseGranted) {
          return const LeaseResult.granted();
        }
        return LeaseResult.rejected(heldBy: reply.leaseHeldBy);
    }
  }

  /// Called by the UI the instant the lease-holding action (the order-open
  /// write, §4) has committed or been abandoned — a same-process callback
  /// when this terminal IS the leader, a fire-and-forget LAN message
  /// otherwise. See the class doc's §6 Lease Recovery reference: the TTL
  /// above is only a backstop for the path where this is never called.
  void releaseTableLease(String tableId) {
    _ephemeralClaims.remove(tableId);
    if (_lanHub.mode == LanMode.client) {
      _lanHub.releaseLease(tableId: tableId, terminalId: _myTerminalId);
    }
  }

  /// Leader side of the wire protocol — wired into `LanHubService`'s server
  /// callbacks, resolved lazily via `inject` (same DI-ordering reason
  /// `SyncEngine._hydrateReferenceData`'s doc comment already explains for
  /// `MainRepository`: `LeaseManager` is registered after `LanHubService`).
  Future<LanHubMessage> handleLeaseRequestAsLeader(LanHubMessage request) async {
    final tableId = request.tableId ?? '';
    final terminalId = request.leaseTerminalId ?? '';
    final result = _arbitrate(tableId, claimant: terminalId);
    return result.isGranted
        ? LanHubMessage.leaseGranted(tableId: tableId)
        : LanHubMessage.leaseRejected(tableId: tableId, heldBy: result.heldBy);
  }

  void handleLeaseReleaseAsLeader(LanHubMessage release) {
    final tableId = release.tableId ?? '';
    final claim = _ephemeralClaims[tableId];
    if (claim != null && claim.claimant == release.leaseTerminalId) {
      _ephemeralClaims.remove(tableId);
    }
  }

  /// §6's two-mechanism split: a durable check (`LocalDatabase`'s replica of
  /// table status — ordinary business data, already durable, naturally
  /// correct across restart with no lease-specific recovery step needed) and
  /// an ephemeral check (only for tables free in durable state but being
  /// raced on *right now*, safe to lose on failover — see §6 Lease
  /// Recovery).
  LeaseResult _arbitrate(String tableId, {required String claimant}) {
    final busy = _localDb
        .getTables()
        .any((t) => t.id == tableId && t.status == TableStatus.busy);
    if (busy) return const LeaseResult.rejected();

    final now = DateTime.now();
    final existing = _ephemeralClaims[tableId];
    if (existing != null &&
        now.difference(existing.claimedAt) < _ephemeralTtl &&
        existing.claimant != claimant) {
      return LeaseResult.rejected(heldBy: existing.claimant);
    }
    _ephemeralClaims[tableId] = (claimant: claimant, claimedAt: now);
    return const LeaseResult.granted();
  }
}

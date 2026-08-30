/// The venue's shift, across terminals and across an outage.
///
/// This is the defect these tests exist for: the shift used to be a
/// `SharedPreferences` record each terminal kept privately, so two tills in one
/// branch each opened a shift of their own, neither could see the other's, and
/// closing on one left the other still trading. Nothing in the codebase could
/// answer "what is this branch's shift?".
///
/// The shift is a replicated `branch_shifts` row now, so the question has an
/// answer and these tests are what hold it to it. They reuse the `Terminal`
/// harness from `local_change_relay_test.dart` — two POS terminals sharing a
/// network and nothing else, exchanging real frames through
/// `toJson`/`tryParse` — because "the terminals agree" is only meaningful if
/// nothing but the wire is shared between them.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/db/branch_shift_query.dart';
import 'package:mary_ai_pos/core/db/entity_registry.dart';
import 'package:mary_ai_pos/core/db/payload_normalizer.dart';
import 'package:mary_ai_pos/core/outbox/branch_shift_outbox.dart';

import 'local_change_relay_test.dart' show Terminal;

const kBranch = 'br-1';
const kOtherBranch = 'br-2';

/// The row `ShiftBloc._openShift` writes, in the same shape.
///
/// Deliberately built here rather than by calling the bloc: the bloc needs a
/// `BuildContext`, a `UserBloc` and a printer, none of which say anything about
/// whether two terminals end up agreeing. What matters is the row and the path
/// it travels, and both are exactly what the bloc produces.
Map<String, dynamic> openRow(
  String id, {
  String branchId = kBranch,
  String openedBy = 'u-1',
  String openingCash = '0',
  DateTime? openedAt,
}) =>
    {
      'id': id,
      'branch_id': branchId,
      'opened_by': openedBy,
      'closed_by': null,
      'opened_at': (openedAt ?? DateTime.now().toUtc()).toIso8601String(),
      'closed_at': null,
      'opening_cash': openingCash,
      'opening_card': '0',
      'closing_cash': null,
      'closing_card': null,
    };

void openShiftOn(Terminal t, String id, {String branchId = kBranch}) {
  final row = openRow(id, branchId: branchId);
  t.writer.create(
    entity: kBranchShiftEntity,
    id: id,
    row: row,
    request: {'id': id, 'opening_cash': '0', 'opening_card': '0'},
  );
}

void closeShiftOn(Terminal t, String id, {String cash = '700'}) {
  t.writer.write(
    entity: kBranchShiftEntity,
    id: id,
    action: kBranchShiftClose,
    merge: true,
    row: {
      'id': id,
      'closed_at': DateTime.now().toUtc().toIso8601String(),
      'closed_by': 'u-2',
      'closing_cash': cash,
      'closing_card': '0',
    },
    request: {'closing_cash': cash, 'closing_card': '0'},
  );
}

void main() {
  test('branch_shifts is a replicated entity', () {
    // The premise everything else here rests on. If the spec were missing,
    // `LocalWriter` would throw rather than quietly do nothing — but the
    // failure would surface as an unrelated crash in a bloc, so it is asserted
    // where it can be read.
    expect(kEntitiesByName[kBranchShiftEntity], isNotNull);
    expect(kEntitiesByName[kBranchShiftEntity]!.isFed, isTrue);
  });

  group('one shift, every terminal', () {
    late Terminal a;
    late Terminal b;

    setUp(() {
      a = Terminal('A');
      b = Terminal('B');
    });

    tearDown(() {
      a.dispose();
      b.dispose();
    });

    test('a shift opened on one till is open on the till beside it', () {
      openShiftOn(a, 's-1');

      // Before the frame is delivered, B knows nothing — this is the state the
      // old design left B in permanently.
      expect(BranchShiftQuery(b.db).activeShift(kBranch), isNull);

      a.flushTo([b]);

      final onB = BranchShiftQuery(b.db).activeShift(kBranch);
      expect(onB, isNotNull, reason: "the peer's shift never arrived");
      expect(onB!['id'], 's-1');
      expect(BranchShiftQuery(a.db).activeShift(kBranch)!['id'], 's-1');
    });

    test('no server is involved — this works with the uplink down', () {
      openShiftOn(a, 's-1');
      a.flushTo([b]);

      // The row reached B over the LAN. A's outbox still holds the operation,
      // unsent, which is the whole point: the venue agreed about its shift
      // without anything leaving the building.
      expect(BranchShiftQuery(b.db).activeShift(kBranch), isNotNull);
      expect(a.outboxDepth, 1, reason: 'the open should still be queued');
      expect(
        b.outboxDepth,
        0,
        reason: 'the terminal that received the shift must not queue it too — '
            'two terminals reporting one open would double the branch',
      );
    });

    test('closing on one till closes the branch, not just that till', () {
      openShiftOn(a, 's-1');
      a.flushTo([b]);
      expect(BranchShiftQuery(b.db).activeShift(kBranch), isNotNull);

      // B closes it — a different terminal from the one that opened it, which
      // is the case the old per-terminal record could not express at all.
      closeShiftOn(b, 's-1');
      b.flushTo([a]);

      expect(
        BranchShiftQuery(a.db).activeShift(kBranch),
        isNull,
        reason: 'the till that opened the shift is still trading under it',
      );
      expect(BranchShiftQuery(b.db).activeShift(kBranch), isNull);
    });

    test('a close preserves what the opening terminal recorded', () {
      // A opened with a 100 float; B closes counting 700. B's write is a merge,
      // so it must not overwrite the float A recorded — that figure is what the
      // drawer is reconciled against.
      final row = openRow('s-1', openingCash: '100');
      a.writer.create(
        entity: kBranchShiftEntity,
        id: 's-1',
        row: row,
        request: {'id': 's-1', 'opening_cash': '100', 'opening_card': '0'},
      );
      a.flushTo([b]);

      closeShiftOn(b, 's-1', cash: '700');

      final stored = BranchShiftQuery(b.db).byId('s-1');
      expect(stored, isNotNull);
      expect(stored!['opening_cash'], '100',
          reason: "the closing terminal overwrote the opening terminal's float");
      expect(stored['closing_cash'], '700');
      expect(stored['closed_at'], isNotNull);
    });

    test('another branch\'s shift is not this branch\'s shift', () {
      // Terminals are branch-scoped by the LAN hub's auth, but the query must
      // hold the line too — a mis-delivered row must not put a neighbouring
      // venue's shift on this till.
      openShiftOn(a, 's-other', branchId: kOtherBranch);
      a.flushTo([b]);

      expect(BranchShiftQuery(b.db).activeShift(kBranch), isNull);
      expect(BranchShiftQuery(b.db).activeShift(kOtherBranch)!['id'], 's-other');
    });

    test('the active shift is watchable, so a peer\'s open lands live', () async {
      final seen = <String?>[];
      final sub = BranchShiftQuery(b.db)
          .watchActiveShift(kBranch)
          .listen((row) => seen.add(row?['id'] as String?));

      await Future<void>.delayed(Duration.zero);
      openShiftOn(a, 's-1');
      a.flushTo([b]);
      await Future<void>.delayed(Duration.zero);

      // This is what lets `ShiftBloc` update without anyone reloading: the
      // stream emits null first (no shift), then the peer's shift.
      expect(seen.first, isNull);
      expect(seen.last, 's-1');
      await sub.cancel();
    });
  });

  group('two terminals opening offline at once', () {
    late Terminal a;
    late Terminal b;

    setUp(() {
      a = Terminal('A');
      b = Terminal('B');
    });

    tearDown(() {
      a.dispose();
      b.dispose();
    });

    test('both rows exist locally until the server arbitrates', () {
      // The genuinely ambiguous window: A and B are both offline and cannot see
      // each other, so both open. Neither is wrong yet, and neither cashier is
      // shown an error — the arbitration happens when the queues drain, and the
      // loser is reconciled onto the winner by the outbox drainer
      // (`_reconcile`, exercised by id_reconciliation_test.dart).
      openShiftOn(a, 's-a');
      openShiftOn(b, 's-b');

      // Each till shows a shift and can keep trading, which is the behaviour a
      // venue with no internet actually needs.
      expect(BranchShiftQuery(a.db).activeShift(kBranch)!['id'], 's-a');
      expect(BranchShiftQuery(b.db).activeShift(kBranch)!['id'], 's-b');

      // And each has queued its own open, so the server sees both and decides.
      expect(a.outboxDepth, 1);
      expect(b.outboxDepth, 1);
    });

    test('the newest is shown while both rows are still present', () {
      // Once the LAN carries them to each other, a terminal holds two open rows
      // for one branch. It has to pick one to trade under until reconciliation
      // removes the loser, and picking the newest is deterministic — picking
      // arbitrarily would let the two tills disagree even while connected.
      final older = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
      a.writer.create(
        entity: kBranchShiftEntity,
        id: 's-a',
        row: openRow('s-a', openedAt: older),
        request: {'id': 's-a', 'opening_cash': '0', 'opening_card': '0'},
      );
      openShiftOn(b, 's-b');
      a.flushTo([b]);
      b.flushTo([a]);

      expect(BranchShiftQuery(a.db).activeShift(kBranch)!['id'], 's-b');
      expect(BranchShiftQuery(b.db).activeShift(kBranch)!['id'], 's-b');
    });
  });

  group('the pending guard, and the one thing that gets past it', () {
    late Terminal a;
    late Terminal b;

    setUp(() {
      a = Terminal('A');
      b = Terminal('B');
    });

    tearDown(() {
      a.dispose();
      b.dispose();
    });

    test("a peer's close gets past this terminal's pending open", () {
      // The bug this exception exists for. A opened the shift, so A holds the
      // row pending until its queue drains. Without the monotonic-set rule the
      // pending guard drops B's close, and A keeps trading under a shift the
      // branch has already closed.
      openShiftOn(a, 's-1');
      a.flushTo([b]);
      expect(a.db.isPending(kBranchShiftEntity, 's-1'), isTrue,
          reason: 'the premise: A owes the server this row');

      closeShiftOn(b, 's-1');
      b.flushTo([a]);

      expect(BranchShiftQuery(a.db).activeShift(kBranch), isNull);
      expect(BranchShiftQuery(a.db).byId('s-1')!['closing_cash'], '700');
    });

    test('an arriving open does NOT reopen a shift this terminal just closed',
        () {
      // The other direction, which must stay guarded. A closes the shift and
      // has not reported it yet; the cloud still thinks the shift is open and
      // delivers that row. Letting it through would reopen a closed till.
      openShiftOn(a, 's-1');
      closeShiftOn(a, 's-1');
      expect(BranchShiftQuery(a.db).activeShift(kBranch), isNull);

      final stats = a.applier.applyOne(
        entity: kBranchShiftEntity,
        action: 'update',
        entityId: 's-1',
        payload: openRow('s-1'),
      );

      expect(stats.skippedPending, 1,
          reason: 'the still-open server copy was allowed to reopen the shift');
      expect(BranchShiftQuery(a.db).activeShift(kBranch), isNull);
    });

    test('the exception is scoped — other entities keep the guard', () {
      // `monotonicSetKey` is opt-in per entity. An entity that does not declare
      // one must behave exactly as before, or this change quietly loosened the
      // rule for the whole replica.
      expect(kEntitiesByName['orders']!.monotonicSetKey, isNull);

      final spec = kEntitiesByName['goods']!;
      a.db.upsert(spec, 'g-1',
          PayloadNormalizer.normalize(spec, {'id': 'g-1', 'name': 'Mine'}));
      a.db.markPending('goods', 'g-1');

      final stats = a.applier.applyOne(
        entity: 'goods',
        action: 'update',
        entityId: 'g-1',
        payload: {'id': 'g-1', 'name': 'Theirs'},
      );

      expect(stats.skippedPending, 1);
      expect(a.db.byId('goods', 'g-1')!['name'], 'Mine');
    });
  });

  group('draining the queue must not undo a close', () {
    late Terminal a;
    late Terminal b;

    setUp(() {
      a = Terminal('A');
      b = Terminal('B');
    });

    tearDown(() {
      a.dispose();
      b.dispose();
    });

    test('a drained open cannot reopen a shift that was already closed', () {
      // The sequence that broke: A opens offline, B closes it over the LAN,
      // then A's queue drains. The server has not seen B's close yet, so it
      // answers A's open with an *open* row — and `OutboxDrainer._succeed`
      // clears the pending guard before applying it, so the guard that stopped
      // this in `applyFromPeer` could not see it. A reopened, and broadcast the
      // reopen to the venue.
      openShiftOn(a, 's-1');
      a.flushTo([b]);
      closeShiftOn(b, 's-1');
      b.flushTo([a]);
      expect(BranchShiftQuery(a.db).activeShift(kBranch), isNull,
          reason: 'the premise: A has the close');

      // The drainer's post-success apply, with pending already cleared.
      a.db.clearPending(kBranchShiftEntity, 's-1');
      final stats = a.applier.applyOne(
        entity: kBranchShiftEntity,
        action: 'update',
        entityId: 's-1',
        payload: openRow('s-1'),
      );

      expect(stats.applied, 0, reason: 'the stale open row was applied');
      expect(BranchShiftQuery(a.db).activeShift(kBranch), isNull,
          reason: 'draining the open reopened a closed shift');
    });

    test('the reopen is not broadcast to peers either', () {
      openShiftOn(a, 's-1');
      a.flushTo([b]);
      closeShiftOn(b, 's-1');
      b.flushTo([a]);
      a.outbound.clear();

      a.db.clearPending(kBranchShiftEntity, 's-1');
      a.applier.applyOne(
        entity: kBranchShiftEntity,
        action: 'update',
        entityId: 's-1',
        payload: openRow('s-1'),
      );

      // `applyOne` emits whenever a row lands, so a reopen that got through
      // would not just be local — it would reopen the shift on every till.
      expect(a.outbound, isEmpty,
          reason: 'a reopen was broadcast to the venue');
    });

    test('a close still applies normally — the guard is one-directional', () {
      // The rule must not block the legitimate direction, or a close arriving
      // from the server would never land.
      openShiftOn(a, 's-1');
      a.db.clearPending(kBranchShiftEntity, 's-1');

      final closed = openRow('s-1')
        ..['closed_at'] = DateTime.now().toUtc().toIso8601String()
        ..['closing_cash'] = '700';
      final stats = a.applier.applyOne(
        entity: kBranchShiftEntity,
        action: 'update',
        entityId: 's-1',
        payload: closed,
      );

      expect(stats.applied, 1);
      expect(BranchShiftQuery(a.db).activeShift(kBranch), isNull);
      expect(BranchShiftQuery(a.db).byId('s-1')!['closing_cash'], '700');
    });
  });
}

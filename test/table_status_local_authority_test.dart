/// The settings screen's table status is a local write, not a queued one.
///
/// The table editor offers three statuses — Free, Busy and Closed (`away`) —
/// and `_save()` used to put the chosen one in the table `PUT` body. Two things
/// were wrong with that, and the second one lost data:
///
///  1. Occupancy is local authority. It lives in `LocalTables.tableStatus` and
///     is overlaid on every table read by `HallsTablesQuery._withLiveStatus`,
///     precisely so a replication pass cannot overwrite the venue's live answer
///     with whatever the server last logged. Sending it upstream inverts that.
///  2. `away` is not a value the API can hold: `table_status` is a two-value
///     Postgres enum (`free`, `busy`), and the update endpoint rejects anything
///     else. So saving a table as Closed produced a 400 — and `outcomeForFailure`
///     quarantines a 4xx permanently, taking the whole edit (price, size,
///     number, everything) with it, silently.
///
/// So the status now goes straight to the overlay and queues nothing.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/db/apply_change.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/outbox/local_writer.dart';
import 'package:mary_ai_pos/core/outbox/outbox_store.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/halls_tables_local_repository_impl.dart';

void main() {
  late LocalDatabase db;
  late OutboxStore outbox;
  late HallsTablesLocalRepositoryImpl repo;

  setUp(() {
    db = LocalDatabase.open(':memory:');
    outbox = OutboxStore(db);
    repo = HallsTablesLocalRepositoryImpl(
      db,
      LocalWriter(db: db, applier: ChangeApplier(db), outbox: outbox),
    );
  });

  tearDown(() => db.dispose());

  test('setTableStatus writes the occupancy overlay and queues nothing', () {
    final before = outbox.pending().length;

    final result = repo.setTableStatus('table-1', TableStatus.busy);

    expect(result.isRight(), isTrue);
    expect(db.tableStatuses()['table-1'], TableStatus.busy.name);
    expect(outbox.pending().length, before,
        reason: 'occupancy is local authority — nothing to send');
  });

  test('away is storable locally, though the API has no such status', () {
    repo.setTableStatus('table-1', TableStatus.away);

    expect(db.tableStatuses()['table-1'], 'away');
    expect(outbox.pending(), isEmpty);
  });

  test('createTable returns the provisional id, so the new row is addressable',
      () {
    final created = repo.createTable({
      'hall_id': 'hall-1',
      'number': 3,
      'capacity': 4,
      'table_type': 'simple',
    });

    final id = created.getOrElse(() => '');
    expect(id, isNotEmpty);

    // The status can then be set on the table the server has not named yet.
    repo.setTableStatus(id, TableStatus.away);
    expect(db.tableStatuses()[id], 'away');

    // The create itself is still queued — only the status is local.
    expect(outbox.pending().where((op) => op.entity == 'cafe_tables'), isNotEmpty);
  });
}

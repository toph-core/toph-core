/// OFFLINE_FIRST_EVERYWHERE_PLAN.md §9 guardrail 2 — "no second write path".
///
/// > "repositories are the only writers; a test asserts every mutation method
/// > inserts an `_outbox` row."
///
/// Guardrails 1 and 3 exist (`architecture_guard_test.dart` and the offline
/// integration suite). This is the missing middle one, and it is the one the
/// plan's own post-mortem points at: the previous attempts failed "on
/// discipline, not knowledge — fixes landed on one path and not its
/// duplicate." A write that skips the outbox is exactly that failure, and it
/// is invisible in review because the screen still updates.
///
/// ## Ground truth
///
///  * [LocalWriter] is the sanctioned write path. Its four methods commit the
///    local row and the `_outbox` operation in one transaction, which is the
///    whole point — see its class doc.
///  * `lib/core/outbox/orders_outbox.dart` is a documented exception: the
///    order aggregate's transport speaks Dio directly because the 409
///    table-open merge and the 404-tolerant per-line cancel are order logic
///    with no home in a CRUD repository. It is on the §9.1 allowlist for the
///    same reason.
///  * Repositories under `lib/features/**/data/repository/` are the writers.
///  * `OfflineQueueService` is a **retiring** second write path, still
///    carrying payment, table timers and shift open/close. That is known,
///    mid-migration debt — it belongs on the countdown below with a note, not
///    treated as a fresh violation.
///
/// ## Static or behavioural? Both, and they check each other
///
/// The plan's wording ("a test asserts every mutation method inserts an
/// `_outbox` row") suggests behavioural, and behavioural is much harder to
/// fool: it drives the real repository against a real (in-memory) database and
/// looks in the real `_outbox` table. A method that names a field `_writer`
/// and never calls it passes any amount of source inspection and fails this on
/// the first run.
///
/// But behavioural alone cannot be *complete*. Dart has no reflection in a
/// test binary, so every drive is hand-written, and a mutation method added
/// tomorrow is simply one nobody wrote a drive for — the guard stays green
/// while the hole opens. Completeness is exactly what a guardrail is for.
///
/// So this file does both, and makes them check each other:
///
///  * **Part 1 — behavioural.** Every repository that can be constructed
///    without a network stack is driven, method by method, and each mutation
///    must leave an `_outbox` row behind. The two deliberate non-enqueuing
///    writes are driven too, and asserted to write *only* their local-authority
///    table.
///  * **Part 2 — static census.** Every method of every repository impl is
///    classified by what its body actually reaches, transitively through the
///    file's own private helpers: the sanctioned writer, a delegated
///    repository, a raw local write, the legacy queue, or a mutating HTTP call.
///    Nothing is classified by its name, because names are the first thing to
///    drift. The offenders are ratcheted in both directions, the way
///    `architecture_guard_test.dart` does it: a new one fails, and a stale
///    allowlist entry fails too, so the list is a countdown and not a rug.
///  * **Part 3 — the join.** The census's "compliant mutation" set must equal
///    the set Part 1 actually drove, for every file Part 1 claims to cover.
///    Add a compliant mutation and forget the drive, and Part 3 fails naming
///    it. That is what stops the behavioural half from decaying.
///
/// The static half decides *what must be true*; the behavioural half proves it
/// *is* true. Neither is sufficient alone and the pair is hard to defeat by
/// accident.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/db/apply_change.dart';
import 'package:mary_ai_pos/core/db/entity_registry.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/db/order_detail_query.dart';
import 'package:mary_ai_pos/core/db/payload_normalizer.dart';
import 'package:mary_ai_pos/core/outbox/local_writer.dart';
import 'package:mary_ai_pos/core/outbox/outbox_store.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_service.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart'
    show TableStatus;
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/halls_tables_local_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/menu_admin_local_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/orders_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/tables_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/users_local_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/tables_repository.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart'
    show OrderItem;

// ─────────────────────────────────────────────────────────────────────────────
// The ratchets
// ─────────────────────────────────────────────────────────────────────────────

/// Mutations that reach a write and never enqueue an outbox operation.
///
/// **This is the countdown.** Every entry is a live second write path: an
/// operator's change that will be lost if the terminal is offline, or that
/// lands on the server without ever reaching the local database. Entries leave
/// this list by being fixed, and the test fails if one is fixed and left here.
///
/// Two families, and they are not the same kind of debt:
///
///  * **The legacy queue.** `OfflineQueueService` still carries payment, the
///    table timers and shift open/close. These *are* durable and *do* replay —
///    they simply do it through the Hive-era queue the outbox replaces, so they
///    are a second mechanism rather than a lost write. Known, mid-migration,
///    tracked by the plan's Phase C.
///  * **The back-office Dio writes.** These have no offline story at all: the
///    call goes straight out over HTTP and fails when the terminal is offline,
///    with no local row and nothing queued. Found while building this guard;
///    left alone on purpose — they sit in files this change does not own.
const Map<String, String> kOutboxBypass = {
  // ── Legacy OfflineQueueService (Phase C deletes it) ──────────────────────
  'lib/features/view/main/data/repository/payment_repository_impl.dart#pay':
      'Payment enqueues a PendingOperation on the retiring OfflineQueueService '
      'rather than the outbox, and writes no local row — the order keeps '
      'bill_status "open" locally until the pay syncs back. Durable and '
      'replayable, but through the second mechanism.',
  'lib/features/view/main/data/repository/payment_repository_impl.dart#cancelZeroTotalOrder':
      'Same queue as pay(), same reason.',
  'lib/features/view/main/data/repository/table_timer_local_repository_impl.dart#createTimedOrder':
      'Writes the timer record to LocalTables.tableTimers and delegates the '
      'order create to OrdersRepository (which does enqueue) — but its own '
      'timer half never reaches the outbox; SyncEngine hydration is what '
      'reconciles it.',
  'lib/features/view/main/data/repository/table_timer_local_repository_impl.dart#startTimer':
      'Timer start/pause/resume write LocalTables.tableTimers and enqueue a '
      'PendingOperationType.timerAction on the legacy queue.',
  'lib/features/view/main/data/repository/table_timer_local_repository_impl.dart#pauseTimer':
      'As startTimer.',
  'lib/features/view/main/data/repository/table_timer_local_repository_impl.dart#resumeTimer':
      'As startTimer.',

  // ── Back-office writes that bypass the outbox entirely ───────────────────
  // Reported, deliberately not fixed here: every one of them lives in
  // main_repository_impl.dart / main_datasources.dart, which this change does
  // not own. Each is a POST/PUT/DELETE with no local row and nothing queued,
  // so offline it simply fails.
  'lib/features/view/main/data/repository/main_repository_impl.dart#createIncomeExpenseTransaction':
      'Transaction-ledger write, straight to Dio. No local row, nothing '
      'queued; fails offline. `transactions` replicates now, so the local '
      'half of this is buildable.',
  'lib/features/view/main/data/repository/main_repository_impl.dart#createTransferTransaction':
      'As createIncomeExpenseTransaction.',
  'lib/features/view/main/data/repository/main_repository_impl.dart#updateTransaction':
      'As createIncomeExpenseTransaction.',
  'lib/features/view/main/data/repository/main_repository_impl.dart#deleteTransaction':
      'As createIncomeExpenseTransaction.',
  'lib/features/view/main/data/repository/main_repository_impl.dart#createTransactionGroup':
      'Transaction-group create, straight to Dio. The group picker reads the '
      'replica, so a group created offline is lost and one created online '
      'only appears after the next pull.',
  'lib/features/view/main/data/repository/main_repository_impl.dart#updateTransactionGroup':
      'As createTransactionGroup.',
  'lib/features/view/main/data/repository/main_repository_impl.dart#deleteTransactionGroup':
      'As createTransactionGroup.',
  'lib/features/view/main/data/repository/main_repository_impl.dart#pushPrinterSetting':
      'Printer settings push, straight to Dio. printer_settings is logged by '
      'the backend now but not replicated (see registry_backend_pin_test), '
      'so neither half of this screen is local yet.',
  'lib/features/view/main/data/repository/main_repository_impl.dart#deletePrinterSetting':
      'As pushPrinterSetting.',
  'lib/features/view/main/data/repository/main_repository_impl.dart#saveServiceCharge':
      'Service-charge save, straight to Dio. Documented in the file as "one '
      'low-volume config value with no reason to carry offline-write '
      'machinery; the cubit already refuses the edit when offline" — a '
      'deliberate choice, but still a second write path, so it is counted.',

  // ── The remainder of MainRepositoryImpl ──────────────────────────────────
  // Superseded rather than pending: each of these has a local, outbox-backed
  // twin already in service (UsersLocalRepositoryImpl,
  // HallsTablesLocalRepositoryImpl, MenuAdminLocalRepositoryImpl,
  // OrdersRepositoryImpl). The methods survive only because MainRepository is
  // one wide interface that di.dart still hands out. They leave this list when
  // the interface is split, not when someone rewrites them.
  'lib/features/view/main/data/repository/main_repository_impl.dart#createUser':
      'Superseded by UsersLocalRepositoryImpl.createUser.',
  'lib/features/view/main/data/repository/main_repository_impl.dart#updateUser':
      'Superseded by UsersLocalRepositoryImpl.updateUser.',
  'lib/features/view/main/data/repository/main_repository_impl.dart#deleteUser':
      'Superseded by UsersLocalRepositoryImpl.deleteUser.',
  'lib/features/view/main/data/repository/main_repository_impl.dart#createHall':
      'Superseded by HallsTablesLocalRepositoryImpl.createHall.',
  'lib/features/view/main/data/repository/main_repository_impl.dart#updateHall':
      'Superseded by HallsTablesLocalRepositoryImpl.updateHall.',
  'lib/features/view/main/data/repository/main_repository_impl.dart#deleteHall':
      'Superseded by HallsTablesLocalRepositoryImpl.deleteHall.',
  'lib/features/view/main/data/repository/main_repository_impl.dart#createTable':
      'Superseded by HallsTablesLocalRepositoryImpl.createTable.',
  'lib/features/view/main/data/repository/main_repository_impl.dart#updateTable':
      'Superseded by HallsTablesLocalRepositoryImpl.updateTable.',
  'lib/features/view/main/data/repository/main_repository_impl.dart#deleteTable':
      'Superseded by HallsTablesLocalRepositoryImpl.deleteTable.',
  'lib/features/view/main/data/repository/main_repository_impl.dart#createCategory':
      'Superseded by MenuAdminLocalRepositoryImpl.createCategory.',
  'lib/features/view/main/data/repository/main_repository_impl.dart#createTranslation':
      'Superseded by MenuAdminLocalRepositoryImpl.createTranslation.',
  'lib/features/view/main/data/repository/main_repository_impl.dart#updateTranslation':
      'Superseded by MenuAdminLocalRepositoryImpl.updateTranslation.',
  'lib/features/view/main/data/repository/main_repository_impl.dart#saveGoodWithCalculations':
      'Superseded by MenuAdminLocalRepositoryImpl.saveGood.',
  'lib/features/view/main/data/repository/main_repository_impl.dart#deleteGood':
      'Superseded by MenuAdminLocalRepositoryImpl.deleteGood.',
  'lib/features/view/main/data/repository/main_repository_impl.dart#createOrder':
      'Superseded by OrdersRepositoryImpl.createOrder.',
  'lib/features/view/main/data/repository/main_repository_impl.dart#createTakewayOrder':
      'Superseded by OrdersRepositoryImpl.createTakeawayOrder.',
  'lib/features/view/main/data/repository/main_repository_impl.dart#cancelOrder':
      'Superseded by the orders/cancel outbox op.',
  'lib/features/view/main/data/repository/main_repository_impl.dart#cancelOrderItem':
      'Superseded by OrdersRepositoryImpl.cancelLineItems.',
  'lib/features/view/main/data/repository/main_repository_impl.dart#transferTable':
      'Superseded by OrdersRepositoryImpl.transferTable.',
  'lib/features/view/main/data/repository/main_repository_impl.dart#openShift':
      'Shift open/close/check is still REST end to end; the legacy queue '
      'carries the offline half.',
  'lib/features/view/main/data/repository/main_repository_impl.dart#closeShift':
      'As openShift.',
  'lib/features/view/main/data/repository/main_repository_impl.dart#resumeOrderTableTimer':
      'Timer actions still go through the legacy queue; this is its online '
      'twin.',
  'lib/features/view/main/data/repository/main_repository_impl.dart#pauseOrderTableTimer':
      'As resumeOrderTableTimer.',
};

/// Writes that correctly touch only a table the server does not own, and so
/// have nothing to enqueue.
///
/// Not debt, and not expected to shrink: these are the local-authority tables
/// [LocalTables] documents — occupancy is decided here, not delivered by the
/// feed, and the server learns of it indirectly when the order that caused it
/// syncs. Still ratcheted, because "this write needs no outbox row" is a claim
/// that stops being true the moment the write starts touching a replicated
/// entity, and that is precisely when nobody would think to look here.
const Map<String, String> kLocalAuthorityWrites = {
  'lib/features/view/main/data/repository/tables_repository_impl.dart#updateTableStatus':
      'Writes LocalTables.tableStatus only. Occupancy is local authority — see '
      'the doc on that constant — and reaches other terminals over the LAN '
      'hub, not the outbox.',
  'lib/features/view/main/data/repository/table_timer_local_repository_impl.dart#evictTimer':
      'Clears the LocalTables.tableTimers record after a bill is paid. There '
      'is nothing to send: the server closes its own table_time_sessions '
      'row when the payment lands, so an outbox op here would be a second '
      'request for something already done. Note this is the one method of '
      'that repository NOT on the countdown above — the timer start/pause/'
      'resume writes do have a server counterpart and take the legacy '
      'queue to reach it.',
  'lib/features/view/main/data/repository/orders_repository_impl.dart#saveOrderDetailSnapshot':
      'An idempotent re-upsert of rows the create path already wrote AND '
      'queued, for callers that hand a pre-built bill in. Enqueuing again '
      'would double-send the order. ChangeApplier also refuses to overwrite '
      'a row whose pending guard is held, so it cannot thin out a fresh '
      'create.',
};

/// Repository files Part 1 drives, and therefore Part 3 cross-checks.
///
/// A file absent from here is covered by the static census only, and must say
/// why. The reasons are real limits, not convenience: two need a live Dio or
/// the Hive queue to construct, and one has no writes of its own at all.
const Map<String, String> kNotBehaviourallyDriven = {
  'lib/features/view/main/data/repository/main_repository_impl.dart':
      'Every method is a pass-through to MainDataSources over Dio. Driving it '
      'would prove only that a fake HTTP client was called.',
  'lib/features/view/main/data/repository/payment_repository_impl.dart':
      'Needs a constructed OfflineQueueService (Hive boxes). Its writes are on '
      'the legacy queue by definition; outbox_test.dart and '
      'offline_queue_quarantine_test.dart cover that mechanism.',
  'lib/features/view/main/data/repository/table_timer_local_repository_impl.dart':
      'Same OfflineQueueService dependency, plus the lease manager. Its '
      'billing behaviour is covered by full_shift_soak_test.dart.',
  'lib/features/view/main/data/repository/waiter_local_repository_impl.dart':
      'Has no writes of its own — every mutation delegates to OrdersRepository, '
      'PaymentRepository, TablesRepository or the timer repository, which '
      'are driven or allowlisted in their own right. The census still '
      'checks that the delegation is all it does.',
  'lib/features/view/main/data/repository/archives_local_repository_impl.dart':
      'Read-only; the census confirms it has no mutations at all.',
  'lib/features/view/main/data/repository/menu_repository_impl.dart':
      'Read-only; as archives.',
  'lib/features/view/main/data/repository/transactions_repository_impl.dart':
      'Read-only; as archives.',
};

// ─────────────────────────────────────────────────────────────────────────────
// Part 2's machinery: a small Dart member reader
// ─────────────────────────────────────────────────────────────────────────────

/// One class member, as text.
typedef Member = ({String name, String body});

/// Source with comments removed, newlines preserved.
///
/// Same reasoning as `architecture_guard_test.dart`'s copy: several of these
/// files discuss `_dataSources` and the outbox in prose precisely because they
/// are migrating away from one of them. Kept local rather than shared because
/// that file is another agent's and importing across test files couples two
/// guards that should be able to change independently.
String stripComments(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    if (source.startsWith('/*', i)) {
      final end = source.indexOf('*/', i + 2);
      i = end == -1 ? source.length : end + 2;
      continue;
    }
    if (source.startsWith('//', i)) {
      final end = source.indexOf('\n', i);
      i = end == -1 ? source.length : end;
      continue;
    }
    out.write(source[i]);
    i++;
  }
  return out.toString();
}

/// Splits a formatted Dart file into its class members.
///
/// Indentation, not a parser. Every file this runs over is `dart format`
/// output, where a class member starts at exactly two spaces and everything
/// belonging to it is indented further — so a line at column 2 that is not a
/// closer begins the next member. That is enough to hand each method its own
/// body, which is all the classifier needs, and it fails loudly (a member
/// swallowing the next) rather than silently if the assumption breaks — the
/// self-tests at the bottom of this file pin the cases that matter.
///
/// A real analyzer would be exact. It would also mean depending on
/// `package:analyzer` and pinning its version against the SDK, for a guard
/// whose whole appeal is that it runs anywhere the suite runs.
List<Member> membersOf(String source) {
  final lines = stripComments(source).split('\n');
  final members = <Member>[];
  var current = <String>[];

  void flush() {
    if (current.isEmpty) return;
    final body = current.join('\n');
    final name = _declaredName(body);
    if (name != null) members.add((name: name, body: body));
    current = <String>[];
  }

  for (final line in lines) {
    if (_startsMember(line)) {
      flush();
      current.add(line);
    } else if (current.isNotEmpty) {
      current.add(line);
    }
  }
  flush();
  return members;
}

/// True for a line at exactly two spaces of indent that opens a declaration.
///
/// The exclusions are the shapes a formatter puts at column 2 that continue
/// the previous member instead of starting one: a closing bracket, a
/// constructor's `:` initialiser list, a cascade, a chained call.
bool _startsMember(String line) {
  if (!RegExp(r'^  [^\s]').hasMatch(line)) return false;
  final trimmed = line.trimLeft();
  const continuations = ['}', ')', ']', '=>', ':', '..', '.', ',', ';'];
  return !continuations.any(trimmed.startsWith);
}

/// The method name a member declares, or null when it declares no method.
///
/// Requires `<something> <name>(`, which excludes fields (no parentheses),
/// getters (no parameter list) and constructors (no return type before the
/// name). The lazy quantifier stops at the first name that is actually
/// followed by a parameter list, so a return type containing parentheses —
/// `Future<Either<Failure, ({List<...> items, int? total})>> getTransactions(`
/// — resolves to `getTransactions` and not to something inside the record
/// type.
String? _declaredName(String member) =>
    _declaration.firstMatch(member)?.group(1);

final _declaration = RegExp(
  // The type must begin with a real character, not whitespace. Without that
  // anchor the indentation itself satisfies the type part and every
  // constructor (`  Foo(this._bar);`) reads as a method called `Foo`.
  r'^[ \t]*(?:@\w+\s*)*(?:static\s+)?'
  r'(?:[\w<>?\[\]${}()][\w<>,\s?\[\]${}()]*?)'
  r'\s+([A-Za-z_$][\w$]*)\s*\(',
  dotAll: true,
);

/// What a method body reaches, after following the file's private helpers.
class WriteEffects {
  /// A call on [LocalWriter] — the sanctioned path.
  final bool outbox;

  /// A call on a field whose type names a repository: the write happens, it
  /// just happens somewhere this census also inspects.
  final bool delegates;

  /// A row written straight into the database, outbox or not.
  final bool localWrite;

  /// A `PendingOperation` on the retiring `OfflineQueueService`.
  final bool legacyQueue;

  /// A mutating HTTP call, via a data source method that issues a non-GET
  /// request.
  final bool networkWrite;

  const WriteEffects({
    this.outbox = false,
    this.delegates = false,
    this.localWrite = false,
    this.legacyQueue = false,
    this.networkWrite = false,
  });

  /// Whether this method changes anything at all.
  bool get mutates =>
      outbox || delegates || localWrite || legacyQueue || networkWrite;

  /// Whether the change is carried by the sanctioned path and nothing else.
  ///
  /// The `outbox || !localWrite` clause is what stops a delegation from
  /// covering for a raw write beside it.
  /// `TableTimerLocalRepositoryImpl.createTimedOrder` is the live example: it
  /// hands the order create to `OrdersRepository`, which does enqueue, and
  /// then writes its own timer record straight into the database with nothing
  /// queued for it. Only the first half is carried.
  bool get compliant =>
      (outbox || delegates) &&
      !legacyQueue &&
      !networkWrite &&
      (outbox || !localWrite);
}

/// Classifies the methods of one repository file.
///
/// Effects are resolved **transitively** through the file's own private
/// members, because that is how these repositories are written:
/// `HallsTablesLocalRepositoryImpl.createHall` calls `_queueCreate`, which
/// calls `_guard`, which runs the closure that calls `_writer.create`. A
/// classifier that read only the public method's own text would see a bare
/// delegation and conclude nothing happens.
class WritePathCensus {
  final String path;
  final Map<String, WriteEffects> byMethod;

  const WritePathCensus(this.path, this.byMethod);

  /// [mutatingDataSourceCalls] is the set of data-source method names whose
  /// implementation issues a POST/PUT/PATCH/DELETE — see
  /// [mutatingDataSourceMethods]. Passing it in rather than hard-coding a list
  /// of verbs-by-name is what keeps `getOrderIdWithTableId` (a POST that
  /// reads) and `createTakewayOrder` honest without a special case.
  factory WritePathCensus.of(
    String path,
    String source,
    Set<String> mutatingDataSourceCalls,
  ) {
    final members = membersOf(source);
    final bodies = {for (final m in members) m.name: m.body};

    // Fields whose declared type ends in `Repository` — a call on one of these
    // is a delegation, not an escape.
    final delegateFields = {
      for (final m in RegExp(
        r'final\s+\w*Repository\s+(_\w+)\s*;',
      ).allMatches(stripComments(source)))
        m.group(1)!,
    };

    String expand(String name, Set<String> seen) {
      if (!seen.add(name)) return '';
      final body = bodies[name];
      if (body == null) return '';
      final buffer = StringBuffer(body);
      // Only private helpers are followed. A call to a *public* method of the
      // same class is rare here and would double-count its effects onto the
      // caller, which is exactly what the census is trying to attribute
      // precisely.
      for (final call in RegExp(r'\b(_\w+)\s*\(').allMatches(body)) {
        buffer.write(expand(call.group(1)!, seen));
      }
      return buffer.toString();
    }

    final byMethod = <String, WriteEffects>{};
    for (final member in members) {
      final reach = expand(member.name, <String>{});
      byMethod[member.name] = WriteEffects(
        outbox: _writerCall.hasMatch(reach),
        delegates: delegateFields.any((f) => reach.contains('$f.')),
        localWrite: _localWrite.hasMatch(reach),
        legacyQueue: _legacyQueue.hasMatch(reach),
        networkWrite: mutatingDataSourceCalls.any(
          (m) => reach.contains('_dataSources.$m('),
        ),
      );
    }
    return WritePathCensus(path, byMethod);
  }

  /// `_writer.write(` / `.create(` / `.delete(` / `.enqueueOnly(`.
  static final _writerCall = RegExp(
    r'_writer\.(write|create|delete|enqueueOnly)\s*\(',
  );

  /// Every [LocalDatabase] method that changes stored state, plus the two
  /// [ChangeApplier] entry points. Matched on the method name rather than the
  /// receiver, because the field is spelled `_db` in some files and `_localDb`
  /// in others and a third spelling would otherwise walk straight through.
  static final _localWrite = RegExp(
    r'\.(upsert|deleteRow|executeOn|setTableStatus|pruneTableStatuses'
    r'|saveTableTimer|evictTableTimer|saveImage|markPending|clearPending'
    r'|markProvisional|clearProvisional|setMeta|markBootstrapped|clearAll'
    r'|applyOne|applyLocalWrite)\s*\(',
  );

  static final _legacyQueue = RegExp(
    r'PendingOperation\(|_queue\.enqueue\s*\(',
  );

  /// Data-source methods that issue a mutating request.
  ///
  /// Read out of `main_datasources.dart` rather than listed here: the abstract
  /// declaration and its implementation are both members named the same, so
  /// the union across members with that name is "does any definition of this
  /// method write". A name-based rule would have to guess about
  /// `getOrderIdWithTableId`, which POSTs a query.
  static Set<String> mutatingDataSourceMethods(String source) {
    final verbs = RegExp(r'\.(post|put|patch|delete)\s*\(');
    return {
      for (final member in membersOf(source))
        if (verbs.hasMatch(member.body)) member.name,
    };
  }
}

/// Every repository implementation the rule applies to.
const String kRepositoryRoot = 'lib/features/view/main/data/repository';

List<String> repositoryFiles() =>
    Directory(kRepositoryRoot)
        .listSync()
        .whereType<File>()
        .map((f) => f.path.replaceAll(r'\', '/'))
        .where((p) => p.endsWith('.dart'))
        .toList()
      ..sort();

// ─────────────────────────────────────────────────────────────────────────────
// Part 1's fixtures
// ─────────────────────────────────────────────────────────────────────────────

class _FakeLanHub implements LanHubService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeTables implements TablesRepository {
  @override
  Future<void> updateTableStatus(String tableId, TableStatus status) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // ───────────────────────────────────────────────────────────────────────
  // Part 1 — drive the real repositories, look in the real _outbox
  // ───────────────────────────────────────────────────────────────────────
  group('§9.2 — every mutation leaves an _outbox row (behavioural)', () {
    late LocalDatabase db;
    late OutboxStore outbox;
    late LocalWriter writer;

    /// Method names actually driven, per repository file. Part 3 reads this.
    final driven = <String, Set<String>>{};

    setUp(() {
      db = LocalDatabase.open(':memory:');
      final applier = ChangeApplier(db);
      outbox = OutboxStore(db);
      writer = LocalWriter(db: db, applier: applier, outbox: outbox);
    });

    tearDown(() => db.dispose());

    void seed(String entity, Map<String, dynamic> data) {
      final spec = kEntitiesByName[entity]!;
      db.upsert(
        spec,
        data[spec.pk] as String,
        PayloadNormalizer.normalize(spec, data),
      );
    }

    int outboxDepth() => outbox.pending().length;

    /// Runs [mutation] and asserts it left at least one outbox operation
    /// behind. [file] and [method] are what Part 3 joins on.
    ///
    /// Takes a `FutureOr` so the synchronous repositories and the order
    /// aggregate's futures use the same helper — and so the bookkeeping that
    /// Part 3 reads cannot drift apart from the assertion that earns it.
    Future<void> enqueues(
      String file,
      String method,
      FutureOr<void> Function() mutation,
    ) async {
      driven.putIfAbsent(file, () => <String>{}).add(method);
      final before = outboxDepth();
      await mutation();
      expect(
        outboxDepth(),
        greaterThan(before),
        reason:
            '$file#$method changed local state without queuing anything '
            'to send. Offline, that change is lost the moment the app '
            'restarts; online, the server never hears about it. Write through '
            'LocalWriter.',
      );
    }

    group('UsersLocalRepositoryImpl', () {
      const file =
          'lib/features/view/main/data/repository/users_local_repository_impl.dart';
      late UsersLocalRepositoryImpl repo;

      setUp(() => repo = UsersLocalRepositoryImpl(db, writer));

      test('createUser', () async {
        await enqueues(file, 'createUser', () {
          final result = repo.createUser({
            'full_name': 'Aziza',
            'username': 'aziza',
            'role': 'waiter',
            'password': 'hunter2',
          });
          expect(result.isRight(), isTrue);
        });
        // The row is visible immediately, which is the other half of the
        // contract — a queued write the operator cannot see is no better than
        // a failed one.
        expect(db.allOf('users'), hasLength(1));
        // ...and the credential the create had to carry never reached it.
        expect(db.allOf('users').single.containsKey('password'), isFalse);
      });

      test('updateUser', () async {
        seed('users', {'id': 'u1', 'full_name': 'Aziza', 'deleted_at': 0});
        await enqueues(
          file,
          'updateUser',
          () => repo.updateUser('u1', {'full_name': 'Aziza N.'}),
        );
        expect(db.byId('users', 'u1')!['full_name'], 'Aziza N.');
      });

      test('deleteUser', () async {
        seed('users', {'id': 'u1', 'full_name': 'Aziza', 'deleted_at': 0});
        await enqueues(file, 'deleteUser', () => repo.deleteUser('u1'));
        expect(db.byId('users', 'u1'), isNull);
      });
    });

    group('HallsTablesLocalRepositoryImpl', () {
      const file =
          'lib/features/view/main/data/repository/halls_tables_local_repository_impl.dart';
      late HallsTablesLocalRepositoryImpl repo;

      setUp(() {
        repo = HallsTablesLocalRepositoryImpl(db, writer);
        seed('halls', {'id': 'h1', 'name': 'Main', 'deleted_at': 0});
        seed('cafe_tables', {
          'id': 't1',
          'hall_id': 'h1',
          'number': 1,
          'deleted_at': 0,
        });
      });

      test(
        'createHall',
        () => enqueues(
          file,
          'createHall',
          () => repo.createHall({'name': 'Terrace', 'branch_id': 'b1'}),
        ),
      );

      test(
        'updateHall',
        () => enqueues(
          file,
          'updateHall',
          () => repo.updateHall('h1', {'name': 'Main hall'}),
        ),
      );

      test(
        'deleteHall',
        () => enqueues(file, 'deleteHall', () => repo.deleteHall('h1')),
      );

      test(
        'createTable',
        () => enqueues(
          file,
          'createTable',
          () => repo.createTable({'hall_id': 'h1', 'number': 9}),
        ),
      );

      test(
        'updateTable',
        () => enqueues(
          file,
          'updateTable',
          () => repo.updateTable('t1', {'number': 12}),
        ),
      );

      test(
        'deleteTable',
        () => enqueues(file, 'deleteTable', () => repo.deleteTable('t1')),
      );

      test('an update merges rather than replaces the stored row', () {
        // Not a second write path, but the failure the outbox cannot catch:
        // a compliant write that queues correctly and still corrupts the
        // replica by sending a partial row to disk.
        repo.updateHall('h1', {'name': 'Main hall'});
        final row = db.byId('halls', 'h1')!;
        expect(row['name'], 'Main hall');
        expect(row['id'], 'h1');
      });
    });

    group('MenuAdminLocalRepositoryImpl', () {
      const file =
          'lib/features/view/main/data/repository/menu_admin_local_repository_impl.dart';
      late MenuAdminLocalRepositoryImpl repo;

      setUp(() {
        repo = MenuAdminLocalRepositoryImpl(db, writer);
        seed('goods', {
          'id': 'g1',
          'name': 'Osh',
          'price': 30000,
          'deleted_at': 0,
        });
        seed('translations', {'id': 'tr1', 'key': 'osh', 'deleted_at': 0});
      });

      test(
        'createCategory',
        () => enqueues(
          file,
          'createCategory',
          () => repo.createCategory('Salatlar'),
        ),
      );

      test('saveGood (create)', () async {
        await enqueues(
          file,
          'saveGood',
          () => repo.saveGood(body: {'name': 'Lagmon', 'price': 32000}),
        );
        // `calculations` is the server's own table; a nested list must not be
        // smuggled into the goods row.
        expect(
          db.allOf('goods').any((g) => g.containsKey('calculations')),
          isFalse,
        );
      });

      test('saveGood (update)', () {
        final before = outboxDepth();
        repo.saveGood(mealId: 'g1', body: {'name': 'Osh (katta)'});
        expect(outboxDepth(), greaterThan(before));
        expect(db.byId('goods', 'g1')!['name'], 'Osh (katta)');
      });

      test(
        'deleteGood',
        () => enqueues(file, 'deleteGood', () => repo.deleteGood('g1')),
      );

      test(
        'createTranslation',
        () => enqueues(
          file,
          'createTranslation',
          () => repo.createTranslation({'key': 'lagmon'}),
        ),
      );

      test(
        'updateTranslation',
        () => enqueues(
          file,
          'updateTranslation',
          () => repo.updateTranslation('tr1', {'key': 'osh2'}),
        ),
      );
    });

    group('OrdersRepositoryImpl', () {
      const file =
          'lib/features/view/main/data/repository/orders_repository_impl.dart';
      late OrdersRepositoryImpl repo;

      OrderItem line(String goodId) => OrderItem(
        goods: GoodsModel(
          id: goodId,
          name: 'Osh',
          price: '30000',
          categoryId: '',
          cookTime: 0,
          costPrice: '0',
          description: '',
          profit: '0',
          profitMargin: '0',
        ),
        quantity: 1,
        comment: '',
      );

      setUp(() {
        final applier = ChangeApplier(db);
        repo = OrdersRepositoryImpl(
          db: db,
          applier: applier,
          writer: writer,
          detail: OrderDetailQuery(db),
          lanHub: _FakeLanHub(),
          tables: _FakeTables(),
        );
        seed('halls', {'id': 'h1', 'name': 'Main', 'deleted_at': 0});
        seed('cafe_tables', {
          'id': 't1',
          'hall_id': 'h1',
          'number': 1,
          'deleted_at': 0,
        });
        seed('cafe_tables', {
          'id': 't2',
          'hall_id': 'h1',
          'number': 2,
          'deleted_at': 0,
        });
        seed('goods', {
          'id': 'g1',
          'name': 'Osh',
          'price': 30000,
          'deleted_at': 0,
        });
      });

      test('createOrder', () async {
        await enqueues(
          file,
          'createOrder',
          () => repo.createOrder(
            tableId: 't1',
            clientOrderId: 'o1',
            guestCount: 2,
            items: [line('g1')],
            tableStatus: TableStatus.busy,
          ),
        );
        expect(db.byId('orders', 'o1'), isNotNull);
        expect(db.allOf('order_items'), hasLength(1));
      });

      test('createTakeawayOrder', () async {
        await enqueues(
          file,
          'createTakeawayOrder',
          () => repo.createTakeawayOrder(
            clientOrderId: 'o2',
            guestCount: 1,
            items: [line('g1')],
          ),
        );
      });

      test('addItems', () async {
        await repo.createOrder(
          tableId: 't1',
          clientOrderId: 'o1',
          guestCount: 2,
          items: const [],
          tableStatus: TableStatus.busy,
        );
        await enqueues(
          file,
          'addItems',
          () =>
              repo.addItems(tableId: 't1', orderId: 'o1', items: [line('g1')]),
        );
      });

      test('cancelLineItems', () async {
        await repo.createOrder(
          tableId: 't1',
          clientOrderId: 'o1',
          guestCount: 2,
          items: const [],
          tableStatus: TableStatus.busy,
        );
        await repo.addItems(
          tableId: 't1',
          orderId: 'o1',
          items: [line('g1')],
          itemClientIds: const ['i1'],
        );
        await enqueues(
          file,
          'cancelLineItems',
          () => repo.cancelLineItems(lineIds: const ['i1']),
        );
        expect(db.byId('order_items', 'i1'), isNull);
      });

      test('transferTable', () async {
        await repo.createOrder(
          tableId: 't1',
          clientOrderId: 'o1',
          guestCount: 2,
          items: const [],
          tableStatus: TableStatus.busy,
        );
        await enqueues(
          file,
          'transferTable',
          () => repo.transferTable(
            orderId: 'o1',
            sourceTableId: 't1',
            targetTableId: 't2',
          ),
        );
        expect(db.byId('orders', 'o1')!['table_id'], 't2');
      });

      test(
        'transferTable queues even when the order is not in the replica',
        () async {
          // The branch that exists because another terminal opened the bill.
          // `enqueueOnly` is the only sanctioned way to have an effect with no
          // local row, and this is the one production caller of it.
          final before = outbox.pending().length;
          await repo.transferTable(
            orderId: 'unknown',
            sourceTableId: 't1',
            targetTableId: 't2',
          );
          expect(outbox.pending().length, greaterThan(before));
        },
      );
    });

    group('deliberate non-enqueuing writes', () {
      test(
        'TablesRepositoryImpl.updateTableStatus writes local authority only',
        () async {
          // Asserted, not assumed. If occupancy ever starts writing `cafe_tables`
          // it becomes a replicated-entity write with no outbox row — the exact
          // shape this guard exists to catch — and the allowlist entry above
          // would be quietly wrong.
          final repo = TablesRepositoryImpl(localDb: db);
          seed('halls', {'id': 'h1', 'name': 'Main', 'deleted_at': 0});
          seed('cafe_tables', {
            'id': 't1',
            'hall_id': 'h1',
            'number': 1,
            'deleted_at': 0,
          });
          final storedBefore = db.byId('cafe_tables', 't1');

          await repo.updateTableStatus('t1', TableStatus.busy);

          expect(
            outbox.pending(),
            isEmpty,
            reason: 'occupancy is not the server\'s to know directly',
          );
          expect(db.tableStatuses()['t1'], TableStatus.busy.name);
          expect(
            db.byId('cafe_tables', 't1'),
            storedBefore,
            reason:
                'the replicated row must be untouched, so a pull can '
                'refresh geometry without fighting over occupancy',
          );
        },
      );
    });

    // ─────────────────────────────────────────────────────────────────────
    // Part 3 — the join between the two halves
    // ─────────────────────────────────────────────────────────────────────
    tearDownAll(() {
      final datasources = File(
        'lib/features/view/main/data/data_source/main_datasources.dart',
      ).readAsStringSync();
      final mutating = WritePathCensus.mutatingDataSourceMethods(datasources);

      final missing = <String>[];
      final extra = <String>[];

      for (final path in repositoryFiles()) {
        if (kNotBehaviourallyDriven.containsKey(path)) continue;
        final census = WritePathCensus.of(
          path,
          File(path).readAsStringSync(),
          mutating,
        );
        final compliant = {
          for (final entry in census.byMethod.entries)
            if (entry.value.compliant &&
                !entry.key.startsWith('_') &&
                !kLocalAuthorityWrites.containsKey('$path#${entry.key}'))
              entry.key,
        };
        final drivenHere = driven[path] ?? const <String>{};
        missing.addAll(compliant.difference(drivenHere).map((m) => '$path#$m'));
        extra.addAll(drivenHere.difference(compliant).map((m) => '$path#$m'));
      }
      missing.sort();
      extra.sort();

      expect(
        missing,
        isEmpty,
        reason:
            'These mutations go through LocalWriter but nothing in Part 1 '
            'drives them, so nobody has proved the row and the operation '
            'actually land together:\n'
            '${missing.map((m) => '  - $m').join('\n')}\n\n'
            'Add a drive above, or — if the repository genuinely cannot be '
            'constructed in a unit test — add its file to '
            'kNotBehaviourallyDriven with the reason.',
      );
      expect(
        extra,
        isEmpty,
        reason:
            'Part 1 drives these but the census no longer sees a '
            'compliant mutation there. Either the method was renamed and the '
            'drive was not, or it stopped writing through LocalWriter:\n'
            '${extra.map((m) => '  - $m').join('\n')}',
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // Part 2 — the census, ratcheted in both directions
  // ───────────────────────────────────────────────────────────────────────
  group('§9.2 — no second write path (static census)', () {
    late Set<String> mutatingDataSourceCalls;
    late Map<String, WritePathCensus> censuses;

    setUpAll(() {
      mutatingDataSourceCalls = WritePathCensus.mutatingDataSourceMethods(
        File(
          'lib/features/view/main/data/data_source/main_datasources.dart',
        ).readAsStringSync(),
      );
      censuses = {
        for (final path in repositoryFiles())
          path: WritePathCensus.of(
            path,
            File(path).readAsStringSync(),
            mutatingDataSourceCalls,
          ),
      };
    });

    /// Every public mutation, as `path#method`.
    Map<String, WriteEffects> publicMutations() => {
      for (final census in censuses.values)
        for (final entry in census.byMethod.entries)
          if (!entry.key.startsWith('_') && entry.value.mutates)
            '${census.path}#${entry.key}': entry.value,
    };

    test('the census reads the data source, not a list of verbs', () {
      // A guard on the guard: if this parse comes back empty, every Dio write
      // below is classified as harmless and the whole countdown reads as
      // finished.
      expect(mutatingDataSourceCalls, contains('createUser'));
      expect(mutatingDataSourceCalls, contains('deleteTransaction'));
      expect(mutatingDataSourceCalls, isNot(contains('getHalls')));
      expect(mutatingDataSourceCalls.length, greaterThan(20));
    });

    test('the census found the repositories at all', () {
      expect(repositoryFiles().length, greaterThan(8));
      expect(publicMutations().length, greaterThan(30));
    });

    test('no new mutation bypasses the outbox', () {
      final found = {
        for (final entry in publicMutations().entries)
          if (!entry.value.compliant &&
              !kLocalAuthorityWrites.containsKey(entry.key))
            entry.key,
      };
      final introduced = found.difference(kOutboxBypass.keys.toSet()).toList()
        ..sort();

      expect(
        introduced,
        isEmpty,
        reason:
            'These repository mutations write without going through '
            'LocalWriter — a raw database write with nothing queued, a '
            'PendingOperation on the retiring OfflineQueueService, or a '
            'mutating HTTP call:\n'
            '${introduced.map((m) => '  - $m').join('\n')}\n\n'
            'Write through LocalWriter: the local row and the outbox '
            'operation commit in one transaction, so the screen updates '
            'immediately and the change survives being offline. If the write '
            'touches only a table the server does not own, put it in '
            'kLocalAuthorityWrites and say which table.',
      );
    });

    test('the bypass list is a countdown, not a rug', () {
      // The direction that gives this file its teeth. Fixing a bypass and
      // leaving its entry here fails, so the number on the left of
      // `kOutboxBypass` only ever goes down.
      final found = {
        for (final entry in publicMutations().entries)
          if (!entry.value.compliant) entry.key,
      };
      final fixed = kOutboxBypass.keys.toSet().difference(found).toList()
        ..sort();

      expect(
        fixed,
        isEmpty,
        reason:
            'These no longer bypass the outbox (or no longer exist). '
            'Delete them from kOutboxBypass in this file:\n'
            '${fixed.map((m) => '  - $m').join('\n')}',
      );
    });

    test('the local-authority exemptions still write local authority only', () {
      final found = {
        for (final entry in publicMutations().entries)
          if (!entry.value.compliant) entry.key,
      };
      final stale =
          kLocalAuthorityWrites.keys.toSet().difference(found).toList()..sort();

      expect(
        stale,
        isEmpty,
        reason:
            'These are exempted from the outbox rule but no longer look '
            'like plain local writes — they now enqueue, delegate, or have '
            'been removed. Delete the exemption:\n'
            '${stale.map((m) => '  - $m').join('\n')}',
      );
    });

    test('the not-driven list names only files that exist', () {
      final paths = repositoryFiles().toSet();
      final gone =
          kNotBehaviourallyDriven.keys.toSet().difference(paths).toList()
            ..sort();
      expect(
        gone,
        isEmpty,
        reason:
            'kNotBehaviourallyDriven names files that are no longer '
            'there:\n${gone.map((m) => '  - $m').join('\n')}',
      );
    });

    test('the read-only repositories really are read-only', () {
      // Named individually because "no mutations" is a claim
      // kNotBehaviourallyDriven leans on to excuse itself from Part 1.
      for (final path in const [
        'lib/features/view/main/data/repository/archives_local_repository_impl.dart',
        'lib/features/view/main/data/repository/menu_repository_impl.dart',
        'lib/features/view/main/data/repository/transactions_repository_impl.dart',
      ]) {
        final mutating =
            censuses[path]!.byMethod.entries
                .where((e) => e.value.mutates)
                .map((e) => e.key)
                .toList()
              ..sort();
        expect(
          mutating,
          isEmpty,
          reason: '$path is listed as read-only but $mutating write',
        );
      }
    });

    test('the waiter repository only delegates', () {
      // Its four writes are the clearest statement of the rule in the
      // codebase: the screen-facing repository owns no write of its own, it
      // routes to the one that does. Pinned so a future "just write it here"
      // shortcut fails.
      const path =
          'lib/features/view/main/data/repository/waiter_local_repository_impl.dart';
      final offenders =
          censuses[path]!.byMethod.entries
              .where(
                (e) =>
                    !e.key.startsWith('_') &&
                    e.value.mutates &&
                    !(e.value.delegates &&
                        !e.value.localWrite &&
                        !e.value.legacyQueue &&
                        !e.value.networkWrite),
              )
              .map((e) => e.key)
              .toList()
            ..sort();
      expect(
        offenders,
        isEmpty,
        reason:
            'WaiterLocalRepositoryImpl should route every write to '
            'another repository, but these do something themselves: '
            '$offenders',
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // The guard itself
  // ───────────────────────────────────────────────────────────────────────
  group('the census machinery', () {
    test('splits a class into its members', () {
      const source = '''
class Foo {
  final Bar _bar;

  Foo(this._bar);

  @override
  Future<void> doThing(String id) async {
    _bar.write(id);
  }

  Stream<int> watchThing() => _bar.stream;
}
''';
      expect(membersOf(source).map((m) => m.name), ['doThing', 'watchThing']);
    });

    test('a record return type does not steal the method name', () {
      // The shape that breaks a naive "identifier before the first paren".
      const source = '''
class Foo {
  Future<Either<Failure, ({List<Map<String, dynamic>> items, int? total})>>
      getTransactions({required int limit}) async {
    return _x;
  }
}
''';
      expect(membersOf(source).map((m) => m.name), ['getTransactions']);
    });

    test('a field with an initialiser is not read as a method', () {
      const source = '''
class Foo {
  final Query _query = Query(db);
  static const _entity = 'users';
}
''';
      expect(membersOf(source), isEmpty);
    });

    test(
      'effects follow private helpers, which is how these files are written',
      () {
        const source = '''
class Foo {
  final LocalWriter _writer;

  @override
  Either<Failure, Unit> createHall(Map<String, dynamic> body) =>
      _queueCreate('halls', body);

  Either<Failure, Unit> _queueCreate(String entity, Map<String, dynamic> body) =>
      _guard(() {
        _writer.create(entity: entity, row: body, request: body);
        return unit;
      });

  Either<Failure, Unit> _guard(Unit Function() body) => Right(body());
}
''';
        final census = WritePathCensus.of('x.dart', source, const {});
        expect(census.byMethod['createHall']!.outbox, isTrue);
        expect(census.byMethod['createHall']!.compliant, isTrue);
      },
    );

    test('a raw database write with nothing queued is not compliant', () {
      const source = '''
class Foo {
  @override
  Future<void> setThing(String id) async {
    _db.upsert(spec, id, row);
  }
}
''';
      final effects = WritePathCensus.of(
        'x.dart',
        source,
        const {},
      ).byMethod['setThing']!;
      expect(effects.localWrite, isTrue);
      expect(effects.mutates, isTrue);
      expect(effects.compliant, isFalse);
    });

    test('a mutating data-source call is not compliant, a reading one is not a '
        'mutation at all', () {
      const source = '''
class Foo {
  @override
  Future<void> createThing() => _dataSources.createThing(body);

  @override
  Future<void> readThing() => _dataSources.getThing();
}
''';
      final census = WritePathCensus.of('x.dart', source, const {
        'createThing',
      });
      expect(census.byMethod['createThing']!.networkWrite, isTrue);
      expect(census.byMethod['createThing']!.compliant, isFalse);
      expect(census.byMethod['readThing']!.mutates, isFalse);
    });

    test('a delegation to another repository counts as compliant', () {
      const source = '''
class Foo {
  final OrdersRepository _orders;

  @override
  Future<void> sendItems() => _orders.addItems(items: items);
}
''';
      final effects = WritePathCensus.of(
        'x.dart',
        source,
        const {},
      ).byMethod['sendItems']!;
      expect(effects.delegates, isTrue);
      expect(effects.compliant, isTrue);
    });

    test('the legacy queue is a bypass even though it is durable', () {
      const source = r'''
class Foo {
  @override
  Future<void> pay() async {
    await _queue.enqueue(PendingOperation(id: '1'));
  }
}
''';
      final effects = WritePathCensus.of(
        'x.dart',
        source,
        const {},
      ).byMethod['pay']!;
      expect(effects.legacyQueue, isTrue);
      expect(effects.compliant, isFalse);
    });

    test('prose about the outbox does not make a method compliant', () {
      const source = '''
class Foo {
  /// This one day goes through _writer.create(...) and the outbox.
  @override
  Future<void> doThing() async {
    _db.upsert(spec, id, row);
  }
}
''';
      final effects = WritePathCensus.of(
        'x.dart',
        source,
        const {},
      ).byMethod['doThing']!;
      expect(effects.outbox, isFalse);
      expect(effects.compliant, isFalse);
    });
  });
}

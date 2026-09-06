import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mary_ai_pos/core/service/printer/print_dispatch_result.dart';
import 'package:mary_ai_pos/core/service/printer/printer_config.dart';
import 'package:mary_ai_pos/core/service/printer/printer_config_storage.dart';
import 'package:mary_ai_pos/core/service/printer/printer_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'print_job.dart';

/// Broadcasts a `printJobAnnounce` for [jobId] — every other terminal on the
/// LAN hub hears it; only the one that owns [entryId] locally acts on it.
typedef PrintAnnounceBroadcaster = void Function({
  required String jobId,
  required String jobType,
  required String entryId,
  required String payloadBase64,
});
/// Announces that this terminal wants to print [jobId]. Carries the claimant's
/// own terminal id so the originator can grant exactly one of several.
typedef PrintClaimBroadcaster = void Function(String jobId, String terminalId);

/// The originator naming the single terminal allowed to print [jobId].
typedef PrintGrantBroadcaster = void Function(String jobId, String terminalId);

typedef PrintResultBroadcaster = void Function(
  String jobId,
  String result,
  String? error,
);

/// Persisted print-job queue + claim/lease relay (Phase 5). Deliberately
/// free of any `lan_hub_*` import — the LAN broadcast/receive side is
/// injected as plain callbacks (`PrintAnnounceBroadcaster` etc.), the same
/// typedef-callback pattern `OfflineQueueService.relayViaLan` and
/// `LanHubServer`'s `LanAuthValidator`/`LanRelayHandler` already use to keep
/// this class and `LanHubService` from importing each other — see
/// offline-first-architecture-plan.md §11 Phase 5 for why that matters here
/// specifically (this class already depends on `PrinterService` for
/// transport; a `LanHubService` import back into this file would complete a
/// real two-way circular import, not just an inconvenient one).
class PrintQueueService {
  static const _boxName = 'print_queue';
  static const _keyTerminalId = 'print_terminal_id';

  /// How long the originator waits for *any* terminal to claim an announced
  /// job before treating it as unclaimed (no owner currently online).
  /// Overridable only so tests don't need to actually wait out the real
  /// production value — always the 3s default outside tests.
  final Duration claimWait;

  /// How long a claiming terminal has to report a result before the
  /// originator gives up on it and (once, per [PrintJob.retryCount]) tries
  /// again — mirrors the plan's own §8 sketch ("recommend 10s"). Same
  /// test-only override rationale as [claimWait].
  final Duration lease;

  /// How long a job whose printer belongs to a terminal that is not currently
  /// answering stays alive, re-announcing, before it is finally given up on.
  ///
  /// This is the window that makes "the order was closed on the hub but the
  /// close-check printer hangs off till 2" survive till 2 being briefly away —
  /// mid-restart, on a flapping access point, or just not yet booted. Before
  /// this existed the job was announced twice, three seconds apart, and then
  /// declared failed; a closing check with a customer standing at the counter
  /// was gone in six seconds and had to be found on the sync-status screen and
  /// retried by hand.
  ///
  /// Bounded rather than infinite on purpose: a receipt that surfaces an hour
  /// later, long after the customer has left, is its own kind of wrong.
  final Duration ownerWait;

  /// The hard ceiling on how long [submitJob] may take to answer its caller.
  ///
  /// The relay protocol has several stages — announce, claim, grant, print,
  /// result — and any of them can be slowed by a terminal that is busy, on a
  /// weak link, or absent. None of that may reach the till: a cashier closing
  /// an order or a shift must get an answer promptly and every time.
  ///
  /// 450ms rather than a round 500: the timer itself, plus completing the
  /// future, costs a millisecond or two, and the ceiling is on what the till
  /// actually waits — not on when the timer was armed.
  ///
  /// So the caller's answer is decoupled from the protocol. When this elapses
  /// the caller is released with `deferred: true` and the job carries on in the
  /// background exactly as it was; if it finishes a moment later, it finishes
  /// normally, and if it fails, [_onLateFailure] surfaces that. Nothing is
  /// abandoned — only the waiting is.
  final Duration callerBudget;

  /// How often a job waiting on its owner re-announces. The owning terminal
  /// coming back is normally noticed immediately — `di.dart` calls
  /// [retryPendingRelays] the moment the LAN peer set changes — so this is the
  /// backstop for the cases that produce no such event, not the primary path.
  final Duration deferredRetryInterval;

  final Box<PrintJob> _box;
  final PrinterService _printerService;
  final PrinterConfigStorage _printerConfigStorage;
  final SharedPreferences _prefs;
  final bool Function() _isLanRelayPossible;

  /// Called when a job fails *after* its caller was already released on
  /// [callerBudget]. Without this a receipt could quietly never appear: the
  /// till was told "queued", and the eventual failure had nowhere to go.
  final void Function(PrintJob job)? _onLateFailure;

  /// Jobs whose caller has been released but which are still running.
  final Set<String> _callerReleased = <String>{};

  final Map<String, Timer> _budgetTimers = {};
  final PrintAnnounceBroadcaster _broadcastAnnounce;
  final PrintClaimBroadcaster _broadcastClaim;
  final PrintGrantBroadcaster _broadcastGrant;
  final PrintResultBroadcaster _broadcastResult;

  final Map<String, Timer> _claimTimers = {};

  /// Job ids this terminal has already put through a printer, newest last.
  ///
  /// A re-announce does not mean "print another" — it means the originator
  /// never heard a result. It re-announces on claim timeout and on lease
  /// expiry, and both fire happily against a terminal that printed the ticket
  /// and then had its `printJobResult` dropped, or was simply slower than the
  /// lease. Nothing on this side remembered the job, so the paper came out
  /// twice; the originator's own state guards sit on the *other* terminal and
  /// cannot see it.
  ///
  /// Only successful prints are recorded. A failure produced no paper, so
  /// re-announcing it is a genuine retry and must be allowed through.
  ///
  /// Persisted in `SharedPreferences` ([_rememberPrinted]), so it survives a
  /// restart of this terminal — which it has to, now that [ownerWait] keeps a
  /// job re-announcing for minutes rather than seconds.
  static const int _printedMemory = 500;
  static const _keyPrintedJobIds = 'print_printed_job_ids';
  late final Set<String> _printedJobIds = _loadPrintedJobIds();
  final Map<String, Timer> _leaseTimers = {};

  /// Re-announce timers for jobs waiting on an owning terminal to come back.
  final Map<String, Timer> _deferredTimers = {};

  /// Jobs this terminal is putting through a printer *right now*.
  ///
  /// [_printedJobIds] only closes the window after a print finishes; this
  /// closes the one during it. A deferred job is re-announced on a timer and
  /// again whenever the LAN peer set changes, so two announcements for the same
  /// job can easily land within the second or two a receipt takes to render and
  /// spool — and without this both would pass the printed check, both would
  /// print, and the customer would get two copies.
  final Set<String> _printingJobIds = <String>{};

  /// Jobs this terminal has claimed and is waiting to be granted, with the
  /// payload held ready so the grant does not have to carry it back.
  final Map<String, ({PrinterConfig config, String payloadBase64})>
      _awaitingGrant = {};

  /// Gives up on a claim that was never answered, so an un-granted payload is
  /// not held indefinitely.
  final Map<String, Timer> _grantTimeouts = {};

  final Map<String, Completer<PrintDispatchResult>> _pending = {};

  Set<String> _loadPrintedJobIds() {
    final raw = _prefs.getStringList(_keyPrintedJobIds);
    return raw == null ? <String>{} : raw.toSet();
  }

  /// Records that [jobId] has physically come out of a printer here.
  ///
  /// Persisted, unlike the in-memory set this replaces. The set only ever had
  /// to cover the claim/lease window — a few seconds — because that was the
  /// whole life of a job. [ownerWait] stretches a re-announce out over minutes,
  /// which is long enough to span a restart of the owning terminal: it would
  /// print the ticket, lose the memory, hear the same job announced again and
  /// print a second copy. Writing the ids down closes that.
  Future<void> _rememberPrinted(String jobId) async {
    _printedJobIds.add(jobId);
    var ids = _printedJobIds.toList();
    if (ids.length > _printedMemory) {
      ids = ids.sublist(ids.length - _printedMemory);
      _printedJobIds
        ..clear()
        ..addAll(ids);
    }
    await _prefs.setStringList(_keyPrintedJobIds, ids);
  }

  PrintQueueService(
    this._box,
    this._printerService,
    this._printerConfigStorage,
    this._prefs, {
    required bool Function() isLanRelayPossible,
    required PrintAnnounceBroadcaster broadcastAnnounce,
    required PrintClaimBroadcaster broadcastClaim,
    required PrintGrantBroadcaster broadcastGrant,
    required PrintResultBroadcaster broadcastResult,
    this.claimWait = const Duration(seconds: 3),
    this.lease = const Duration(seconds: 10),
    this.ownerWait = const Duration(minutes: 10),
    this.deferredRetryInterval = const Duration(seconds: 30),
    this.callerBudget = const Duration(milliseconds: 450),
    void Function(PrintJob job)? onLateFailure,
  })  : _onLateFailure = onLateFailure,
        _isLanRelayPossible = isLanRelayPossible,
        _broadcastAnnounce = broadcastAnnounce,
        _broadcastClaim = broadcastClaim,
        _broadcastGrant = broadcastGrant,
        _broadcastResult = broadcastResult {
    _recoverStaleJobs();
  }

  static Future<PrintQueueService> init(
    PrinterService printerService,
    PrinterConfigStorage printerConfigStorage,
    SharedPreferences prefs, {
    required bool Function() isLanRelayPossible,
    required PrintAnnounceBroadcaster broadcastAnnounce,
    required PrintClaimBroadcaster broadcastClaim,
    required PrintGrantBroadcaster broadcastGrant,
    required PrintResultBroadcaster broadcastResult,
    void Function(PrintJob job)? onLateFailure,
  }) async {
    final box = await Hive.openBox<PrintJob>(_boxName);
    return PrintQueueService(
      box,
      printerService,
      printerConfigStorage,
      prefs,
      isLanRelayPossible: isLanRelayPossible,
      broadcastAnnounce: broadcastAnnounce,
      broadcastClaim: broadcastClaim,
      broadcastGrant: broadcastGrant,
      broadcastResult: broadcastResult,
      onLateFailure: onLateFailure,
    );
  }

  /// A `queued`/`claimed` row left over from a previous app run has no live
  /// timer backing it anymore (timers don't survive a restart) — without
  /// this sweep it would sit unresolved forever, invisible, which is exactly
  /// the "silently stuck" failure mode this whole slice exists to avoid.
  /// Finalized as `failed` with a clear reason instead, visible for manual
  /// retry once Phase 6's print-status screen exists.
  void _recoverStaleJobs() {
    for (final job in _box.values.toList()) {
      if (job.stateEnum != PrintJobState.queued &&
          job.stateEnum != PrintJobState.claimed) {
        continue;
      }

      // A job for another terminal's printer that is still inside its window
      // is picked back up rather than written off. This is the restart case of
      // the same problem `ownerWait` exists for: the till was closed for the
      // night with a receipt still waiting on the kitchen terminal, and the
      // receipt should still come out when both are back, not be silently
      // discarded because this side bounced.
      if (_ownerOf(job) != null && _withinOwnerWait(job)) {
        job.stateEnum = PrintJobState.queued;
        job.claimedAt = null;
        job.lastError =
            "Chek boshqa terminaldagi printerni kutmoqda — o'sha terminal "
            "tarmoqqa qaytganda avtomatik chop etiladi.";
        job.save();
        // Nothing awaits these across a restart (the completer died with the
        // previous run), so they only need the retry loop.
        _scheduleDeferredRetry(job.id);
        continue;
      }

      job.stateEnum = PrintJobState.failed;
      job.lastError = "Ilova qayta ishga tushirilgani sababli chop etish to'xtatildi.";
      job.save();
    }
  }

  List<PrintJob> get jobs => _box.values.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Reactive backing for a status screen — same `Box.listenable()` idiom as
  /// `OfflineQueueService.listenable`.
  ValueListenable<Box<PrintJob>> get listenable => _box.listenable();

  int get queuedCount =>
      _box.values.where((j) => j.stateEnum == PrintJobState.queued).length;
  int get claimedCount =>
      _box.values.where((j) => j.stateEnum == PrintJobState.claimed).length;
  int get failedCount =>
      _box.values.where((j) => j.stateEnum == PrintJobState.failed).length;

  /// Manual retry for a `failed` job from the sync-status screen (§11 Phase
  /// 6) — rebuilds the original `PrinterConfig` from what was persisted and
  /// resubmits through the normal `submitJob` path (a fresh job id, so this
  /// shows up as a new row rather than mutating history — same reasoning as
  /// `_recoverStaleJobs` leaving failed rows in place instead of editing
  /// them in place). No-op if [jobId] doesn't exist or isn't `failed`.
  Future<PrintDispatchResult?> retryFailedJob(String jobId) async {
    final job = _box.get(jobId);
    if (job == null || job.stateEnum != PrintJobState.failed) return null;
    // The owner is read back from the entry rather than stored on the job:
    // reassigning a printer to another terminal should change where a retry
    // goes, and a job row that predates ownership carries none anyway.
    final config = PrinterConfig(
      ip: job.ip,
      port: job.port,
      connectionType: job.connectionType,
      entryId: job.entryId,
      windowsPrinterName: _usbPrinterNameFor(job),
      ownerCashRegisterId:
          _printerConfigStorage.entryById(job.entryId)?.ownerCashRegisterId ??
              '',
    );
    final bytes = base64Decode(job.payloadBase64);
    return submitJob(config, bytes, jobType: job.jobType, beep: false);
  }

  String? _usbPrinterNameFor(PrintJob job) =>
      job.connectionType.toLowerCase() == 'usb'
          ? _printerConfigStorage.getUsbPrinterName(job.entryId)
          : null;

  /// Removes a `failed` job from the visible queue without retrying — for
  /// operator-acknowledged failures that don't need a resubmit. No-op if
  /// [jobId] doesn't exist or isn't `failed`.
  Future<void> dismissFailedJob(String jobId) async {
    final job = _box.get(jobId);
    if (job == null || job.stateEnum != PrintJobState.failed) return;
    _deferredTimers.remove(jobId)?.cancel();
    await _box.delete(jobId);
  }

  String get terminalId {
    var id = _prefs.getString(_keyTerminalId);
    if (id == null || id.isEmpty) {
      id = _generateTerminalId();
      unawaited(_prefs.setString(_keyTerminalId, id));
    }
    return id;
  }

  static String _generateTerminalId() {
    final rand = Random();
    return List.generate(16, (_) => rand.nextInt(16).toRadixString(16)).join();
  }

  String _newJobId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 31)}';

  /// The single entry point `PrinterService` dispatches through (via
  /// `attachPrintQueue`). Decides locally-print-vs-relay right here, and
  /// resolves only once the job is fully finalized (printed or terminally
  /// failed) — including the relay path's claim-wait + lease + one retry —
  /// so `PrinterService`'s existing `if (!r.ok) { ...toast... }` callers
  /// keep seeing one, final, meaningful outcome instead of a premature
  /// "enqueued" success.
  ///
  /// The routing rule is ownership first, transport second:
  ///
  ///  * **Owned by another terminal** → relay, whatever the transport. This is
  ///    the case that used to be wrong. Until printers had owners this method
  ///    reasoned that "a network/TCP printer never needs relay — any terminal
  ///    can already reach it directly", which is only true of a flat network
  ///    where every printer answers every machine. A kitchen printer on the
  ///    kitchen's own switch, or one behind a second access point, answers
  ///    exactly one machine, and every job raised elsewhere burned its socket
  ///    timeout and failed.
  ///  * **Owned by this terminal, or unowned** → print here. An unowned
  ///    printer keeps the old behaviour exactly, which is what makes this
  ///    change safe for existing installs: every row that predates
  ///    75_printer_settings_owner has no owner and is still printed directly
  ///    by whoever raised the job.
  ///
  /// USB is no longer a special case in the routing, only in what "print here"
  /// needs: the device-local Windows printer name. What is special is a USB
  /// printer registered to *this* terminal with no such name saved — see
  /// below, that fails fast rather than relaying into silence.
  Future<PrintDispatchResult> submitJob(
    PrinterConfig config,
    List<int> bytes, {
    required String jobType,
    bool beep = true,
  }) async {
    final job = PrintJob(
      id: _newJobId(),
      jobType: jobType,
      entryId: config.entryId ?? '',
      payloadBase64: base64Encode(bytes),
      connectionType: config.connectionType,
      ip: config.ip,
      port: config.port,
      createdAt: DateTime.now().toUtc(),
    );
    await _box.put(job.id, job);

    // Ownership, in the order the two sources are trusted:
    //
    //  1. `owner_cash_register_id`, when the backend has populated it. It is
    //     the real registry and it keeps deciding, exactly as before.
    //  2. Otherwise, what the terminal that owns the printer told us over the
    //     LAN (`PrinterConfigStorage.applyPeerPrinterSettings`). In this venue
    //     that is all there is: the deployed backend has no owner column and
    //     the token carries no cash register id, so every entry reads as
    //     unowned and every terminal used to dial every printer itself.
    final lanOwner = _printerConfigStorage.lanOwnerOf(job.entryId);
    final ownedElsewhere = config.isUnowned
        ? (lanOwner != null && lanOwner != terminalId)
        : !config.isOwnedBy(_printerConfigStorage.myCashRegisterId);

    if (!ownedElsewhere) {
      if (!config.usesWindowsPrinter) {
        // Ours (or unowned) and addressable from here. Still a persisted row,
        // so a crash mid-print stays visible and retryable.
        return _printLocallyAndFinish(
          job,
          config: config,
          bytes: bytes,
          beep: beep,
        );
      }

      final ownWindowsName = config.windowsPrinterName ??
          _printerConfigStorage.getUsbPrinterName(job.entryId);
      if (ownWindowsName != null && ownWindowsName.isNotEmpty) {
        return _printLocallyAndFinish(
          job,
          config: config.copyWith(windowsPrinterName: ownWindowsName),
          bytes: bytes,
          beep: beep,
        );
      }

      if (!config.isUnowned) {
        // Registered to this terminal, but no Windows printer has been picked
        // on this machine — the usual cause is a reinstall, since that mapping
        // is device-local and never synced. Relaying would be pointless: no
        // other terminal owns it either, so the job would sit through the
        // claim wait and a retry before failing with a vaguer message.
        job.stateEnum = PrintJobState.failed;
        job.lastError =
            "Bu USB printer shu terminalga biriktirilgan, lekin Windows printeri "
            "tanlanmagan. Sozlamalar > Printerlar bo'limidan printerni tanlang.";
        await job.save();
        return (ok: false, error: job.lastError, deferred: false);
      }
      // Unowned USB with no local name: fall through to the legacy relay, where
      // whichever terminal does hold a name for this entry claims it.
    }

    if (!_isLanRelayPossible()) {
      job.stateEnum = PrintJobState.failed;
      job.lastError =
          "LAN rejimi o'chirilgan — boshqa terminalga biriktirilgan printerga chek "
          "yubora olmaymiz. Sozlamalar > Tarmoq bo'limidan LAN rejimni yoqing yoki "
          "printerni shu terminalga biriktiring.";
      await job.save();
      return (ok: false, error: job.lastError, deferred: false);
    }

    final completer = Completer<PrintDispatchResult>();
    _pending[job.id] = completer;
    _armCallerBudget(job);
    _announceAndWaitForClaim(job);
    return completer.future;
  }

  Future<PrintDispatchResult> _printLocallyAndFinish(
    PrintJob job, {
    required PrinterConfig config,
    required List<int> bytes,
    required bool beep,
  }) async {
    final r = await _printerService.printRenderedBytes(config, bytes, beep: beep);
    if (!r.ok && r.connectFailed && _isLanRelayPossible()) {
      return _relayAfterLocalFailure(job, r.error);
    }
    job.ownerTerminalId = terminalId;
    if (r.ok) {
      job.stateEnum = PrintJobState.printed;
      job.printedAt = DateTime.now().toUtc();
    } else {
      job.stateEnum = PrintJobState.failed;
      job.lastError = r.error;
    }
    await job.save();
    // Reaches `_onLateFailure` when this print is the tail of a job whose
    // caller was already released; a no-op when the caller is still waiting,
    // since the returned record answers it directly.
    if (_callerReleased.contains(job.id)) {
      _complete(job.id, ok: r.ok, error: r.error);
    } else {
      _clearCallerBudget(job.id);
    }
    return (ok: r.ok, error: r.error, deferred: false);
  }

  /// This terminal could not reach the printer — offer the job to the LAN
  /// before writing it off.
  ///
  /// Why this exists: ownership is what normally routes a job to the terminal
  /// that can reach the printer, and every printer row created before the
  /// backend could record an owner has none. To this terminal an unowned
  /// printer looks reachable, so a kitchen ticket raised on the client dials
  /// the kitchen printer directly, cannot reach it across the venue's network,
  /// and dies — while the hub, sitting on the same switch as the printer,
  /// could have printed it. Announcing lets that terminal put its hand up.
  ///
  /// Reached **only** on [PrintAttempt.connectFailed] — no socket ever opened,
  /// so nothing reached the printer and handing the same bytes to another
  /// terminal cannot produce a second receipt. Every other failure (a write
  /// that broke half way, a USB spooler error) finalizes exactly as before.
  ///
  /// The claim/grant/lease protocol is untouched: this is the same announce
  /// the owned-elsewhere path makes, on the same timers, and the caller is
  /// released on the same [callerBudget] rather than waiting out the claim.
  Future<PrintDispatchResult> _relayAfterLocalFailure(
    PrintJob job,
    String? localError,
  ) async {
    job.lastError = "Printerga shu terminaldan ulanib bo'lmadi "
        "($localError) — chek boshqa terminallarga taklif qilindi.";
    job.stateEnum = PrintJobState.queued;
    await job.save();

    // Answered now, not after the claim wait. The local attempt has already
    // cost the caller a socket timeout (up to 6s), and the till may not be
    // held for the relay's stages on top of that — the announce and everything
    // after it run behind the released caller. Marking the caller released is
    // what obliges `_complete` to surface a later failure through
    // `_onLateFailure`: the till has been told the receipt is queued.
    _callerReleased.add(job.id);
    _announceAndWaitForClaim(job);
    return (ok: false, error: job.lastError, deferred: true);
  }

  /// Releases the caller after [callerBudget] whatever stage the job is at.
  /// The job itself is untouched and goes on running.
  void _armCallerBudget(PrintJob job) {
    _budgetTimers.remove(job.id)?.cancel();
    _budgetTimers[job.id] = Timer(callerBudget, () {
      _budgetTimers.remove(job.id);
      if (!_pending.containsKey(job.id)) return; // already answered
      _callerReleased.add(job.id);
      _complete(
        job.id,
        ok: false,
        deferred: true,
        error: "Chek boshqa terminaldagi printerga yuborildi — "
            "chop etilishi kutilmoqda.",
      );
    });
  }

  void _clearCallerBudget(String jobId) {
    _budgetTimers.remove(jobId)?.cancel();
  }

  void _announceAndWaitForClaim(PrintJob job) {
    _broadcastAnnounce(
      jobId: job.id,
      jobType: job.jobType,
      entryId: job.entryId,
      payloadBase64: job.payloadBase64,
    );
    _claimTimers.remove(job.id)?.cancel();
    _claimTimers[job.id] = Timer(claimWait, () => _onClaimTimeout(job.id));
  }

  Future<void> _onClaimTimeout(String jobId) async {
    _claimTimers.remove(jobId);
    final job = _box.get(jobId);
    // Already claimed (a claim can race in just as the timer fires) or
    // already finalized some other way — nothing to do.
    if (job == null || job.stateEnum != PrintJobState.queued) return;

    // A printer with a known owner does not get the second synchronous
    // announce. The announce travels over the hub's WebSocket, so it is not
    // dropped in transit — an owner that is actually there claims on the first
    // one within milliseconds (measured: 14ms end to end). A second round of
    // `claimWait` therefore only re-confirms an absence we have already
    // established, at the cost of doubling how long the caller waits before it
    // is told the receipt is queued. That wait is visible: `_closeShift` shows
    // a loading state across it. Re-announcing still happens — on the deferred
    // loop, which fires the instant the owner rejoins the LAN.
    if (_ownerOf(job) != null) {
      await _deferUntilOwnerReturns(job);
      return;
    }

    // No owner, so there is nobody to wait for and a retry is all we have. The
    // pre-ownership behaviour, unchanged: announce twice, then give up.
    if (job.retryCount < 1) {
      job.retryCount++;
      await job.save();
      _announceAndWaitForClaim(job);
      return;
    }
    job.stateEnum = PrintJobState.failed;
    job.lastError = 'Hech qanday terminal ushbu printerni egallamadi '
        '(barcha terminallar offline yoki printer sozlanmagan).';
    await job.save();
    _complete(jobId, ok: false, error: job.lastError);
  }

  /// The cash register that owns [job]'s printer and is not this terminal, or
  /// `null` when the printer is unowned, unknown, or ours.
  ///
  /// Read from the current entry list rather than from the job row, so that
  /// reassigning a printer in settings redirects the jobs already waiting for
  /// it instead of stranding them on a terminal that no longer has it.
  String? _ownerOf(PrintJob job) {
    final entry = _printerConfigStorage.entryById(job.entryId);
    if (entry == null || entry.isUnowned) return null;
    if (_printerConfigStorage.isOwnedByThisTerminal(entry)) return null;
    return entry.ownerCashRegisterId;
  }

  /// Whether [job] is still inside its [ownerWait] window.
  bool _withinOwnerWait(PrintJob job) =>
      DateTime.now().toUtc().difference(job.createdAt) < ownerWait;

  /// Jobs parked waiting for the terminal that owns their printer. Still
  /// `queued` — they are genuinely pending, not a separate state — but with
  /// [PrintJob.lastError] carrying the reason so the sync-status screen can
  /// say what is being waited on rather than showing a bare spinner.
  List<PrintJob> get deferredJobs => _box.values
      .where((j) =>
          j.stateEnum == PrintJobState.queued && _deferredTimers.containsKey(j.id))
      .toList();

  int get deferredCount => deferredJobs.length;

  /// Hands the caller back its answer now, and keeps the job alive in the
  /// background until the owning terminal answers or [ownerWait] runs out.
  ///
  /// Resolving early matters most for the shift close: `ShiftBloc._closeShift`
  /// emits `Status.LOADING` and `await`s the receipt before it closes the
  /// shift, so a job that hung on until the owner reappeared would hold the
  /// cashier on a spinner — and hold the shift open — for as long as that took.
  /// The order-close path is looser (`PaymentBloc`/`WaiterCubit` fire the
  /// cashier receipt without awaiting it, and kitchen tickets go through
  /// `unawaited`), but it still needs an answer it can show: `deferred: true`
  /// tells the operator the check is queued for the other terminal rather than
  /// lost, which is what stops them reprinting it.
  Future<void> _deferUntilOwnerReturns(PrintJob job) async {
    job.lastError = "Chek boshqa terminaldagi printerga navbatga qo'yildi — "
        "o'sha terminal tarmoqqa qaytganda avtomatik chop etiladi.";
    await job.save();
    _complete(job.id, ok: false, error: job.lastError, deferred: true);
    _scheduleDeferredRetry(job.id);
  }

  void _scheduleDeferredRetry(String jobId) {
    _deferredTimers.remove(jobId)?.cancel();
    _deferredTimers[jobId] =
        Timer(deferredRetryInterval, () => _retryDeferred(jobId));
  }

  Future<void> _retryDeferred(String jobId) async {
    // Cancel, not just remove: `retryPendingRelays` can call this while the
    // interval timer is still armed, and a merely-dropped timer would still
    // fire and stack a second retry loop on top of the one below.
    _deferredTimers.remove(jobId)?.cancel();
    final job = _box.get(jobId);
    if (job == null || job.stateEnum != PrintJobState.queued) return;

    if (!_withinOwnerWait(job)) {
      job.stateEnum = PrintJobState.failed;
      job.lastError =
          "Printer egasi bo'lgan terminal ${ownerWait.inMinutes} daqiqa ichida "
          "tarmoqqa qaytmadi — chek chop etilmadi.";
      await job.save();
      _complete(jobId, ok: false, error: job.lastError);
      return;
    }

    // Reassigned to us while it waited, or the owner was cleared: print it
    // here rather than going on announcing into an empty room.
    final config = _printerConfigStorage.configForEntryId(job.entryId);
    if (config != null && _ownerOf(job) == null) {
      await _printLocallyAndFinish(
        job,
        config: config,
        bytes: base64Decode(job.payloadBase64),
        beep: false,
      );
      return;
    }

    if (!_isLanRelayPossible()) {
      _scheduleDeferredRetry(jobId);
      return;
    }

    _broadcastAnnounce(
      jobId: job.id,
      jobType: job.jobType,
      entryId: job.entryId,
      payloadBase64: job.payloadBase64,
    );
    // No claim timer here: a claim moves the job to `claimed` and the lease
    // takes over, while silence just means another interval of waiting.
    _scheduleDeferredRetry(jobId);
  }

  /// Re-announce everything that is waiting on an absent terminal, now.
  ///
  /// `di.dart` wires this to the LAN peer set changing, which is what makes
  /// the common case feel immediate: the moment the till holding the
  /// close-check printer finishes booting and joins the hub, the receipt that
  /// has been waiting for it comes out — rather than up to
  /// [deferredRetryInterval] later.
  void retryPendingRelays() {
    for (final job in _box.values.toList()) {
      if (job.stateEnum != PrintJobState.queued) continue;
      if (!_deferredTimers.containsKey(job.id)) continue;
      unawaited(_retryDeferred(job.id));
    }
  }

  /// `LanHubService` calls this when a `printJobClaim` arrives for a job
  /// this terminal originated.
  void onRemoteClaim(String jobId, String claimantTerminalId) {
    final job = _box.get(jobId);
    if (job == null || job.stateEnum != PrintJobState.queued) {
      // Not ours, or a second/late claim. Crucially the loser gets no grant,
      // and a claimant never prints without one — which is what stops two
      // terminals answering the same announcement from producing two receipts.
      return;
    }
    _claimTimers.remove(jobId)?.cancel();
    job.ownerTerminalId = claimantTerminalId;
    // The winner is told, by name. Everyone else hears this too and stands
    // down, since the id is not theirs.
    _broadcastGrant(jobId, claimantTerminalId);
    // Someone has it. Stop re-announcing for the length of the lease — the
    // lease timer is the thing tracking it now, and a stray announce in the
    // middle risks a second terminal picking up a job already in progress.
    _deferredTimers.remove(jobId)?.cancel();
    job.stateEnum = PrintJobState.claimed;
    job.claimedAt = DateTime.now().toUtc();
    job.save();
    _leaseTimers.remove(jobId)?.cancel();
    _leaseTimers[jobId] = Timer(lease, () => _onLeaseExpired(jobId));
  }

  Future<void> _onLeaseExpired(String jobId) async {
    _leaseTimers.remove(jobId);
    final job = _box.get(jobId);
    if (job == null || job.stateEnum != PrintJobState.claimed) return;
    if (job.retryCount < 1) {
      job.stateEnum = PrintJobState.queued;
      job.retryCount++;
      job.claimedAt = null;
      await job.save();
      _announceAndWaitForClaim(job);
      return;
    }
    // The owner claimed it and then went quiet — most likely it dropped off the
    // network mid-print. That is the same situation as never having answered,
    // so it gets the same treatment rather than being written off.
    if (_ownerOf(job) != null && _withinOwnerWait(job)) {
      job.stateEnum = PrintJobState.queued;
      job.claimedAt = null;
      await _deferUntilOwnerReturns(job);
      return;
    }
    job.stateEnum = PrintJobState.failed;
    job.lastError =
        'Egallagan terminal ${lease.inSeconds}s ichida natija bermadi.';
    await job.save();
    _complete(jobId, ok: false, error: job.lastError);
  }

  /// `LanHubService` calls this when a `printJobResult` arrives for a job
  /// this terminal originated.
  void onRemoteResult(String jobId, String result, String? error) {
    final job = _box.get(jobId);
    if (job == null || job.stateEnum != PrintJobState.claimed) return;
    _leaseTimers.remove(jobId)?.cancel();
    _deferredTimers.remove(jobId)?.cancel();
    if (result == 'printed') {
      job.stateEnum = PrintJobState.printed;
      job.printedAt = DateTime.now().toUtc();
      job.save();
      _complete(jobId, ok: true, error: null);
    } else {
      job.stateEnum = PrintJobState.failed;
      job.lastError = error ?? 'Masofadagi terminalda chop etish muvaffaqiyatsiz.';
      job.save();
      _complete(jobId, ok: false, error: job.lastError);
    }
  }

  void _complete(
    String jobId, {
    required bool ok,
    String? error,
    bool deferred = false,
  }) {
    if (!deferred) _clearCallerBudget(jobId);
    final completer = _pending.remove(jobId);
    if (completer != null && !completer.isCompleted) {
      completer.complete((ok: ok, error: error, deferred: deferred));
      return;
    }
    // Nobody is waiting any more — the caller was released on its budget. A
    // failure now would otherwise vanish silently, having been reported to the
    // till as "queued".
    if (!ok && _callerReleased.remove(jobId)) {
      final job = _box.get(jobId);
      if (job != null) _onLateFailure?.call(job);
    } else {
      _callerReleased.remove(jobId);
    }
  }

  /// The printer this terminal would drive for an announced `entryId`, or
  /// `null` when the announcement is not this terminal's to answer.
  ///
  /// Three ways a job can be ours, in priority order:
  ///
  ///  1. **The synced entry names our cash register as its owner.** This is the
  ///     real registry, and it covers every transport — a network printer only
  ///     this machine can route to relays here just as a USB one does. The
  ///     config is rebuilt from the local copy of the entry rather than from
  ///     the announcement, which is why `printJobAnnounce` never had to grow
  ///     ip/port/connection fields: every terminal already holds the same
  ///     printer list.
  ///  2. **We hold a Windows printer name for it.** The pre-ownership rule,
  ///     kept for unowned USB rows — `getUsbPrinterName` was the only "who owns
  ///     this printer" signal that existed before the backend could record one,
  ///     and rows created under the old scheme still rely on it.
  ///  3. **It is an unowned network printer** and the originator has already
  ///     failed to reach it. Detailed at the branch itself.
  ///
  /// Rules 2 and 3 are off the table for an entry a peer has announced as its
  /// own over the LAN: that announcement is a positive statement about which
  /// machine the printer is plugged into, and this terminal answering it would
  /// take the job away from the one that can print it.
  ///
  /// A USB printer we own but have no Windows name for is deliberately *not*
  /// claimed: claiming a job we cannot print would consume the originator's
  /// lease and then fail it, when leaving it unclaimed lets another terminal
  /// (or the originator's own retry) have a go.
  PrinterConfig? _claimableConfigFor(String entryId) {
    if (entryId.isEmpty) return null;

    final entry = _printerConfigStorage.entryById(entryId);
    if (entry != null && _printerConfigStorage.isOwnedByThisTerminal(entry)) {
      final config = _printerConfigStorage.configForEntryId(entryId);
      if (config == null) return null;
      if (config.usesWindowsPrinter &&
          (config.windowsPrinterName == null ||
              config.windowsPrinterName!.isEmpty)) {
        return null;
      }
      return config;
    }

    final lanOwner = _printerConfigStorage.lanOwnerOf(entryId);
    if (lanOwner != null && lanOwner != terminalId) {
      // Another terminal has announced this printer as its own. Whatever else
      // this terminal knows about the entry, the job is not ours to take.
      return null;
    }

    final windowsName = _printerConfigStorage.getUsbPrinterName(entryId);
    if (windowsName != null && windowsName.isNotEmpty) {
      return PrinterConfig(
        ip: '',
        connectionType: 'usb',
        entryId: entryId,
        windowsPrinterName: windowsName,
      );
    }

    //  3. **An unowned network printer this terminal may be able to reach.**
    //     Only announced at all because the originator tried it and could not
    //     get a socket open (`_relayAfterLocalFailure`) — on a venue whose
    //     printer rows carry no owner, that is the sole signal that some other
    //     terminal has to try. So this terminal offers to, and finds out by
    //     dialing: the config is the same entry, the same address, the same
    //     ticket, and if it cannot reach it either the job fails exactly as it
    //     would have.
    //
    //     Owned entries deliberately do not reach here — an owner is a
    //     positive statement about which machine can drive the printer, and a
    //     non-owner claiming would undo it.
    if (entry != null &&
        entry.isUnowned &&
        entry.isNetworkTcp &&
        // Not one we learned from a peer: that peer said the printer is
        // attached to *it*, so claiming would take a job away from the
        // terminal that can actually reach it.
        !_printerConfigStorage.isLanLearned(entryId)) {
      final config = _printerConfigStorage.configForEntryId(entryId);
      if (config != null && config.ip.isNotEmpty && config.port > 0) {
        return config;
      }
    }
    return null;
  }

  /// `LanHubService` calls this when a `printJobAnnounce` arrives from
  /// another terminal — claims and prints it iff this terminal is the one that
  /// can actually reach the announced printer ([_claimableConfigFor]).
  Future<void> onRemoteAnnounce({
    required String jobId,
    required String jobType,
    required String entryId,
    required String payloadBase64,
  }) async {
    final config = _claimableConfigFor(entryId);
    if (config == null) return; // not mine
    if (_printedJobIds.contains(jobId)) {
      // Already printed here. The originator is asking again because it never
      // heard the result, so answer it — but do not put a second ticket
      // through the printer.
      _broadcastClaim(jobId, terminalId);
      _broadcastResult(jobId, 'printed', null);
      return;
    }
    // Already printing this one here — a second announcement is the originator
    // being impatient, not a second receipt. Checked and set with no await in
    // between, so two announcements arriving together cannot both get past it.
    if (_printingJobIds.contains(jobId)) {
      _broadcastClaim(jobId, terminalId);
      return;
    }

    // Put a hand up and wait to be picked. Printing here, unbidden, is what
    // used to produce two receipts whenever two terminals could both serve the
    // announced printer.
    _awaitingGrant[jobId] = (config: config, payloadBase64: payloadBase64);
    _grantTimeouts.remove(jobId)?.cancel();
    _grantTimeouts[jobId] = Timer(claimWait, () {
      // No grant: either someone else was picked, or the originator has gone
      // away. Either way this terminal is not printing it, so drop the payload
      // rather than hold it forever.
      _awaitingGrant.remove(jobId);
      _grantTimeouts.remove(jobId);
    });
    _broadcastClaim(jobId, terminalId);
  }

  /// The originator has picked a terminal for [jobId]. If it is this one, print.
  ///
  /// This is the only path on which a relayed receipt reaches a printer, which
  /// is what makes "exactly one copy" a property of the protocol rather than of
  /// how carefully each terminal guesses whether the job is its own.
  Future<void> onRemoteGrant(String jobId, String grantedTerminalId) async {
    final pending = _awaitingGrant.remove(jobId);
    _grantTimeouts.remove(jobId)?.cancel();
    if (pending == null) return; // never claimed this job
    if (grantedTerminalId != terminalId) return; // someone else was picked

    if (_printedJobIds.contains(jobId)) {
      // Printed here on an earlier round and the result never got through.
      // Answer again; do not put a second ticket out.
      _broadcastResult(jobId, 'printed', null);
      return;
    }
    if (_printingJobIds.contains(jobId)) return; // already underway

    _printingJobIds.add(jobId);
    try {
      final bytes = base64Decode(pending.payloadBase64);
      final r = await _printerService.printRenderedBytes(pending.config, bytes);
      if (r.ok) await _rememberPrinted(jobId);
      _broadcastResult(jobId, r.ok ? 'printed' : 'failed', r.error);
    } catch (e) {
      if (kDebugMode) print('[PrintQueue] Relayed print xatosi: $e');
      _broadcastResult(jobId, 'failed', e.toString());
    } finally {
      _printingJobIds.remove(jobId);
    }
  }
}

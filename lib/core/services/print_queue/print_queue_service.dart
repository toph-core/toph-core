import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mary_ai_pos/core/service/printer/printer_config.dart';
import 'package:mary_ai_pos/core/service/printer/printer_service.dart';
import 'package:mary_ai_pos/core/services/cache/cache_service.dart';
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
typedef PrintClaimBroadcaster = void Function(String jobId);
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

  final Box<PrintJob> _box;
  final PrinterService _printerService;
  final CacheService _cacheService;
  final SharedPreferences _prefs;
  final bool Function() _isLanRelayPossible;
  final PrintAnnounceBroadcaster _broadcastAnnounce;
  final PrintClaimBroadcaster _broadcastClaim;
  final PrintResultBroadcaster _broadcastResult;

  final Map<String, Timer> _claimTimers = {};
  final Map<String, Timer> _leaseTimers = {};
  final Map<String, Completer<({bool ok, String? error})>> _pending = {};

  PrintQueueService(
    this._box,
    this._printerService,
    this._cacheService,
    this._prefs, {
    required bool Function() isLanRelayPossible,
    required PrintAnnounceBroadcaster broadcastAnnounce,
    required PrintClaimBroadcaster broadcastClaim,
    required PrintResultBroadcaster broadcastResult,
    this.claimWait = const Duration(seconds: 3),
    this.lease = const Duration(seconds: 10),
  })  : _isLanRelayPossible = isLanRelayPossible,
        _broadcastAnnounce = broadcastAnnounce,
        _broadcastClaim = broadcastClaim,
        _broadcastResult = broadcastResult {
    _recoverStaleJobs();
  }

  static Future<PrintQueueService> init(
    PrinterService printerService,
    CacheService cacheService,
    SharedPreferences prefs, {
    required bool Function() isLanRelayPossible,
    required PrintAnnounceBroadcaster broadcastAnnounce,
    required PrintClaimBroadcaster broadcastClaim,
    required PrintResultBroadcaster broadcastResult,
  }) async {
    final box = await Hive.openBox<PrintJob>(_boxName);
    return PrintQueueService(
      box,
      printerService,
      cacheService,
      prefs,
      isLanRelayPossible: isLanRelayPossible,
      broadcastAnnounce: broadcastAnnounce,
      broadcastClaim: broadcastClaim,
      broadcastResult: broadcastResult,
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
      if (job.stateEnum == PrintJobState.queued ||
          job.stateEnum == PrintJobState.claimed) {
        job.stateEnum = PrintJobState.failed;
        job.lastError = "Ilova qayta ishga tushirilgani sababli chop etish to'xtatildi.";
        job.save();
      }
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
  Future<({bool ok, String? error})?> retryFailedJob(String jobId) async {
    final job = _box.get(jobId);
    if (job == null || job.stateEnum != PrintJobState.failed) return null;
    final config = PrinterConfig(
      ip: job.ip,
      port: job.port,
      connectionType: job.connectionType,
      entryId: job.entryId,
      windowsPrinterName: _usbPrinterNameFor(job),
    );
    final bytes = base64Decode(job.payloadBase64);
    return submitJob(config, bytes, jobType: job.jobType, beep: false);
  }

  String? _usbPrinterNameFor(PrintJob job) =>
      job.connectionType.toLowerCase() == 'usb'
          ? _cacheService.getUsbPrinterName(job.entryId)
          : null;

  /// Removes a `failed` job from the visible queue without retrying — for
  /// operator-acknowledged failures that don't need a resubmit. No-op if
  /// [jobId] doesn't exist or isn't `failed`.
  Future<void> dismissFailedJob(String jobId) async {
    final job = _box.get(jobId);
    if (job == null || job.stateEnum != PrintJobState.failed) return;
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
  /// `attachPrintQueue`). Decides locally-print-vs-relay right here: a
  /// network/TCP printer never needs relay (any terminal can already reach
  /// it directly); a USB printer this terminal doesn't itself own does.
  /// Resolves only once the job is fully finalized (printed or terminally
  /// failed) — including the relay path's claim-wait + lease + one retry —
  /// so `PrinterService`'s existing `if (!r.ok) { ...toast... }` callers
  /// keep seeing one, final, meaningful outcome instead of a premature
  /// "enqueued" success.
  Future<({bool ok, String? error})> submitJob(
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

    if (!config.usesWindowsPrinter) {
      // Network/TCP — any terminal can already reach it directly; still a
      // persisted row (so a crash mid-print is visible/retryable), just no
      // ownership question and no relay.
      return _printLocallyAndFinish(job, config: config, bytes: bytes, beep: beep);
    }

    final ownWindowsName =
        config.windowsPrinterName ?? _cacheService.getUsbPrinterName(job.entryId);
    if (ownWindowsName != null && ownWindowsName.isNotEmpty) {
      return _printLocallyAndFinish(
        job,
        config: config.copyWith(windowsPrinterName: ownWindowsName),
        bytes: bytes,
        beep: beep,
      );
    }

    if (!_isLanRelayPossible()) {
      job.stateEnum = PrintJobState.failed;
      job.lastError = "LAN rejimi o'chirilgan — boshqa terminaldagi USB printerga chek "
          "yubora olmaymiz. Sozlamalar > Tarmoq bo'limidan LAN rejimni yoqing yoki "
          "printerni shu terminalga ulang.";
      await job.save();
      return (ok: false, error: job.lastError);
    }

    final completer = Completer<({bool ok, String? error})>();
    _pending[job.id] = completer;
    _announceAndWaitForClaim(job);
    return completer.future;
  }

  Future<({bool ok, String? error})> _printLocallyAndFinish(
    PrintJob job, {
    required PrinterConfig config,
    required List<int> bytes,
    required bool beep,
  }) async {
    final r = await _printerService.printRenderedBytes(config, bytes, beep: beep);
    job.ownerTerminalId = terminalId;
    if (r.ok) {
      job.stateEnum = PrintJobState.printed;
      job.printedAt = DateTime.now().toUtc();
    } else {
      job.stateEnum = PrintJobState.failed;
      job.lastError = r.error;
    }
    await job.save();
    return r;
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

  /// `LanHubService` calls this when a `printJobClaim` arrives for a job
  /// this terminal originated.
  void onRemoteClaim(String jobId) {
    final job = _box.get(jobId);
    if (job == null || job.stateEnum != PrintJobState.queued) {
      return; // not ours, or a second/late claim — first claim already won
    }
    _claimTimers.remove(jobId)?.cancel();
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

  void _complete(String jobId, {required bool ok, String? error}) {
    final completer = _pending.remove(jobId);
    if (completer != null && !completer.isCompleted) {
      completer.complete((ok: ok, error: error));
    }
  }

  /// `LanHubService` calls this when a `printJobAnnounce` arrives from
  /// another terminal — claims and prints it iff (and only if) this
  /// terminal has a locally-saved Windows printer name for the announced
  /// `entryId` (`CacheService.getUsbPrinterName` is the closest thing to a
  /// "who owns this USB printer" registry that exists anywhere in this
  /// codebase — see the Phase 5 research this was based on).
  Future<void> onRemoteAnnounce({
    required String jobId,
    required String jobType,
    required String entryId,
    required String payloadBase64,
  }) async {
    final windowsName = _cacheService.getUsbPrinterName(entryId);
    if (windowsName == null || windowsName.isEmpty) return; // not mine
    _broadcastClaim(jobId);
    try {
      final bytes = base64Decode(payloadBase64);
      final config = PrinterConfig(
        ip: '',
        connectionType: 'usb',
        entryId: entryId,
        windowsPrinterName: windowsName,
      );
      final r = await _printerService.printRenderedBytes(config, bytes);
      _broadcastResult(jobId, r.ok ? 'printed' : 'failed', r.error);
    } catch (e) {
      if (kDebugMode) print('[PrintQueue] Relayed print xatosi: $e');
      _broadcastResult(jobId, 'failed', e.toString());
    }
  }
}

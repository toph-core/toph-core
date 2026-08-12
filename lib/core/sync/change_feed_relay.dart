import 'dart:convert';

import 'package:mary_ai_pos/core/db/apply_change.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 5 — the follower side of the
/// leader's change feed.
///
/// The leader broadcasts every pull batch it applies; a follower applies the
/// same bytes with the same [ChangeApplier.applyPullResponse] the cloud path
/// uses. There is no second format and no second code path, which is the whole
/// reason this phase is small.
///
/// What the plan does not address, and this does: a follower can *miss*
/// batches — it was disconnected, or it joined the venue late. Applying a
/// batch blindly would then be silently destructive, because applying advances
/// the cursor to the batch's `next_sync_cursor`, and the rows between the
/// follower's old cursor and this batch's start would be skipped forever. The
/// follower would look caught up while missing arbitrary rows.
///
/// So a gap is detected rather than ignored, and handled by *not* advancing the
/// cursor. The rows in hand still apply — they are upserts, so having them
/// early is harmless and better than dropping them — but the cursor stays at
/// the last position this terminal can actually vouch for, and [needsBackfill]
/// goes up. That leaves exactly one recovery path, and it is one that already
/// exists: a cloud pull from the honest cursor, which fills the hole and
/// clears the flag.
class ChangeFeedRelay {
  final LocalDatabase _db;
  final ChangeApplier _applier;

  ChangeFeedRelay({required LocalDatabase db, required ChangeApplier applier})
      : _db = db,
        _applier = applier;

  bool _needsBackfill = false;

  /// Whether this terminal is knowingly behind the leader.
  ///
  /// The one thing a follower still needs its own uplink for. It is not a
  /// periodic poll: it goes true only when a gap is observed, and false again
  /// as soon as one pull closes it.
  bool get needsBackfill => _needsBackfill;

  /// Called by the sync tick once a cloud pull has run to completion.
  void backfillDone() => _needsBackfill = false;

  /// Applies one broadcast batch. Returns null if the payload was unusable.
  ApplyStats? apply({required String body, required int fromCursor}) {
    final Map<String, dynamic> decoded;
    try {
      final parsed = jsonDecode(body);
      if (parsed is! Map<String, dynamic>) return null;
      decoded = parsed;
    } catch (_) {
      return null;
    }

    // The leader started this batch further along than we are, so whatever sits
    // between is a hole we never received.
    final gap = fromCursor > _db.syncCursor;
    if (gap) _needsBackfill = true;

    return _applier.applyPullResponse(decoded, advanceCursor: !gap);
  }
}

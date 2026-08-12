/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — what a local write actually did,
/// so a screen can be honest about what the operator will see.
///
/// The distinction exists because of one unresolved backend question (§5.4):
/// endpoints that assign their own ids cannot be mirrored locally before the
/// server answers, since a client-invented id would become a second identity
/// for the same row — the server's version would arrive through replication and
/// the invented one would sit beside it, undeletable.
///
/// So creates queue and everything else applies. When client-supplied ids land,
/// or when the outbox learns to reconcile a provisional id against the one the
/// server returns, [queued] stops being reachable and this enum can go.
enum LocalWriteResult {
  /// The replica changed. The screen reflects it on the next frame.
  applied,

  /// Queued for the server, with no local row to show yet.
  queued,
}

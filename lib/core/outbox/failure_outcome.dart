/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 2/4 — the retry/quarantine decision,
/// in one place.
///
/// Every outbox handler faces the same question about the [Failure] its send
/// returned: try again later, or stop and ask a human? Getting it wrong is
/// expensive in both directions. Retrying a rejection burns the attempt budget
/// and, because a failed operation blocks its causal chain, delays every write
/// queued behind it. Quarantining a timeout strands a write that would have
/// succeeded on the next tick.
///
/// So the rule is: **transient means the server did not answer on the merits.**
/// No connection, a timeout, a 5xx, an unrecognised error — the request never
/// got a verdict, so it keeps its place in the queue. A 4xx is a verdict, and
/// replaying it produces the same verdict forever.
library;

import '../error/failure.dart';
import 'outbox_executor.dart';

/// Whether [failure] should be retried or quarantined.
OutboxOutcome outcomeForFailure(Failure failure) => switch (failure) {
      // No verdict — the request did not reach a server that could judge it.
      ConnectionFailure() => OutboxOutcome.retry,
      TimeoutFailure() => OutboxOutcome.retry,
      ServerFailure() => OutboxOutcome.retry,

      // 401. Deliberately transient: an expired access token is the ordinary
      // case here, and the interceptor refreshes it. Quarantining on 401 would
      // dump the entire queue the first time a token lapsed mid-shift, which is
      // both common and recoverable. If it never recovers, the attempt budget
      // quarantines it anyway — just later, and for the right reason.
      UnauthorizedFailure() => OutboxOutcome.retry,

      // 403. A permission refusal is a verdict and will not change by itself.
      UnauthenticatedFailure() => OutboxOutcome.permanent,

      // 400/422, 404, and a 4xx body carrying the server's own message.
      ValidationFailure() => OutboxOutcome.permanent,
      NotFoundFailure() => OutboxOutcome.permanent,
      MessageFailure() => OutboxOutcome.permanent,

      // 409. Ambiguous by nature — it is either "your earlier attempt already
      // landed" or "someone else owns this now", and the status alone does not
      // say which. Quarantine sends it to the one place equipped to tell the
      // difference: a person, with the payload in front of them. A handler that
      // *can* distinguish them (an idempotent create whose response carries the
      // existing row) should decide before calling this and not ask.
      ConflictFailure() => OutboxOutcome.permanent,

      // Anything unclassified is treated as transient. An unknown failure that
      // is really permanent costs a few retries; an unknown failure that is
      // really transient and gets quarantined costs a write.
      _ => OutboxOutcome.retry,
    };

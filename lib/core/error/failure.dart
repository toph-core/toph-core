import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/utils/helper/helper_widget.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

abstract class LocalizedMessage {
  String getLocalizedMessage(BuildContext context);
}

abstract class Failure extends Equatable implements LocalizedMessage {
  const Failure();

  @override
  List<Object> get props => [];
}

class EmptyFailure extends Failure {
  const EmptyFailure() : super();

  @override
  String getLocalizedMessage(BuildContext context) => '';
}

class MessageFailure extends Failure {
  final String message;
  const MessageFailure(this.message) : super();

  @override
  String getLocalizedMessage(BuildContext context) => message;
}

class CacheFailure extends Failure {
  const CacheFailure() : super();

  @override
  String getLocalizedMessage(BuildContext context) =>
      S.of(context).strFailureMessage_cache;
}

class UnknownFailure extends Failure {
  const UnknownFailure() : super();

  @override
  String getLocalizedMessage(BuildContext context) =>
      S.of(context).strFailureMessage_unknown;
}

class ServerFailure extends Failure {
  const ServerFailure() : super();

  @override
  String getLocalizedMessage(BuildContext context) =>
      S.of(context).strFailureMessage_server;
}

class ConnectionFailure extends Failure {
  const ConnectionFailure() : super();

  @override
  String getLocalizedMessage(BuildContext context) =>
      S.of(context).strFailureMessage_connection;
}

class ParsingFailure extends Failure {
  const ParsingFailure();

  @override
  String getLocalizedMessage(BuildContext context) =>
      S.of(context).strFailureMessage_parsing;
}

class TimeoutFailure extends Failure {
  const TimeoutFailure();

  @override
  String getLocalizedMessage(BuildContext context) =>
      S.of(context).strFailureMessage_timeout;
}

class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure();

  @override
  String getLocalizedMessage(BuildContext context) =>
      S.of(context).strFailureMessage_unauthorized;
}

class UnauthenticatedFailure extends Failure {
  const UnauthenticatedFailure();

  @override
  String getLocalizedMessage(BuildContext context) =>
      S.of(context).strFailureMessage_unauthenticated;
}

class NotFoundFailure extends Failure {
  const NotFoundFailure();

  @override
  String getLocalizedMessage(BuildContext context) =>
      S.of(context).strFailureMessage_notFound;
}

/// HTTP 409 — a real, structural conflict (e.g. the target of a mutation is
/// already busy/taken by another actor), distinct from a plain validation
/// error. Carries the caller through to a specific, useful message rather
/// than a generic one.
class ConflictFailure extends Failure {
  const ConflictFailure();

  @override
  String getLocalizedMessage(BuildContext context) =>
      S.of(context).strFailureMessage_validation;
}

class ValidationFailure extends Failure {
  const ValidationFailure();

  @override
  String getLocalizedMessage(BuildContext context) =>
      S.of(context).strFailureMessage_validation;
}

class OtherFailure extends Failure {
  const OtherFailure();

  @override
  String getLocalizedMessage(BuildContext context) =>
      S.of(context).strFailureMessage_other;
}

extension ShowErrorExt on Failure {
  void showErrorMsg() {
    showErrorMessage(
      navigatorKey.currentContext!,
      getLocalizedMessage(navigatorKey.currentContext!),
    );
  }
}

/// Distinguishes a definite, authoritative "no" from the server — the
/// pincode/password is wrong, or the account is no longer valid — from
/// simply failing to get a real answer at all (no connection, a timeout, or
/// the server erroring out). Used by every offline-auth fallback path (PIN
/// login, brand/password login, session restore) to decide: fall back to
/// the locally cached credential (inconclusive — we don't actually know
/// whether it's still valid), or trust what the server just said and never
/// touch the cache either way (a real answer, whether it's yes or no).
///
/// This is also the mechanism that bounds how long a revoked credential
/// keeps working offline: there's no time-based expiry on the offline auth
/// cache by design — a cached credential is trusted until the *next* time
/// the app gets a definite answer about it from the server, at which point
/// a rejection here is what triggers actually purging it
/// (`OfflineAuthCache.removeForPin`/`removeUser`).
extension AuthFailureClassification on Failure {
  // Note: 403 (`UnauthenticatedFailure`) is deliberately excluded. The
  // backend uses 401 (`UnauthorizedFailure`) for "this pincode/password is
  // wrong" (confirmed against `LoginWithPincode`'s handler), while 403 is
  // used for role/permission gating on unrelated endpoints (e.g.
  // admin-only routes) — treating it as a definite credential rejection
  // here would risk purging a valid offline-cached user because of a
  // permission check that has nothing to do with whether their credential
  // is still valid.
  bool get isDefiniteAuthRejection =>
      this is ValidationFailure ||
      this is UnauthorizedFailure ||
      this is NotFoundFailure ||
      this is MessageFailure;
}

/// Shared "should this write be queued for later instead of shown as an
/// error" classification, used by every Bloc that enqueues a mutation into
/// `OfflineQueueService` on failure. Includes `TimeoutFailure` alongside
/// `ConnectionFailure` — a request that eventually times out is not a
/// definite server rejection either, the same reasoning `isDefiniteAuthRejection`
/// applies on the auth side. Previously each Bloc re-implemented this check
/// with inconsistent scope (some excluded timeouts); this is the one place
/// to change that decision going forward.
extension ConnectivityFailureClassification on Failure {
  bool get isConnectivityIssue =>
      this is ConnectionFailure || this is TimeoutFailure;
}

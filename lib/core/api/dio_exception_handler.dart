import 'dart:io';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:dio/dio.dart';

Failure handleDioException(DioException error) {
  try {
    // ===== TIMEOUT =====
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return const TimeoutFailure();
    }

    // ===== NO INTERNET =====
    if (error.type == DioExceptionType.connectionError ||
        error.error is SocketException) {
      return const ConnectionFailure();
    }

    // ===== REQUEST CANCELLED =====
    if (error.type == DioExceptionType.cancel) {
      return const OtherFailure();
    }

    // ===== SERVER RESPONSE =====
    final response = error.response;
    if (response != null) {
      final data = response.data;
      final statusCode = response.statusCode ?? 0;

      // ===== Backend message =====
      // Only trust an `error` body as a *definite* answer for 4xx — a 5xx
      // response is the server failing, not authoritatively rejecting the
      // request, even if it happens to include an `error` field. Mapping a
      // 5xx to `MessageFailure` here would make it look like a definite
      // auth rejection to `isDefiniteAuthRejection`, which could purge a
      // valid offline-cached credential during exactly the kind of backend
      // outage that mechanism exists to survive.
      //
      // The transient 4xx (401 token lapse, 408 request timeout, 429 throttle)
      // are excluded for the same reason on the write side: `MessageFailure`
      // is quarantined by `outcomeForFailure`, so capturing a 401-with-body
      // here would strand an outbox write the interceptor's refresh would
      // otherwise recover. They fall through to the switch below (401 →
      // `UnauthorizedFailure`, 408 → `TimeoutFailure`, 429 → `UnknownFailure`),
      // all of which retry — and 401 still classifies as a definite auth
      // rejection via `UnauthorizedFailure`, so PIN-cache revocation is intact.
      const transientStatuses = {401, 408, 429};
      if (statusCode >= 400 &&
          statusCode < 500 &&
          !transientStatuses.contains(statusCode) &&
          data is Map<String, dynamic>) {
        if (data['error'] != null) {
          return MessageFailure(data['error'].toString());
        }
      }

      switch (statusCode) {
        case 400:
        case 422:
          return const ValidationFailure();

        case 401:
          return const UnauthorizedFailure();

        case 403:
          return const UnauthenticatedFailure();

        case 404:
          return const NotFoundFailure();

        case 409:
          return const ConflictFailure();

        case 408:
          return const TimeoutFailure();

        case 500:
        case 502:
        case 503:
        case 504:
          return const ServerFailure();
      }
    }

    // ===== UNKNOWN =====
    return const UnknownFailure();
  } catch (_) {
    return const UnknownFailure();
  }
}

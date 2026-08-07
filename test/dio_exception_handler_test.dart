import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/api/dio_exception_handler.dart';
import 'package:mary_ai_pos/core/error/failure.dart';

/// Covers the fix for a real bug found during the offline-first compliance
/// audit: a 5xx response whose body happens to include an `error` field was
/// being mapped to `MessageFailure` — which `isDefiniteAuthRejection` treats
/// as a definite credential rejection — purging a valid offline-cached user
/// over a transient server failure instead of a real "no" from the server.
void main() {
  DioException withResponse(int statusCode, Object? data) {
    final options = RequestOptions(path: '/x');
    return DioException(
      requestOptions: options,
      response: Response(requestOptions: options, statusCode: statusCode, data: data),
      type: DioExceptionType.badResponse,
    );
  }

  group('handleDioException', () {
    test('a 4xx response with an error body maps to MessageFailure', () {
      final failure = handleDioException(withResponse(400, {'error': 'bad input'}));
      expect(failure, isA<MessageFailure>());
      expect((failure as MessageFailure).message, 'bad input');
    });

    test('a 401 with an error body still maps to MessageFailure (message wins)', () {
      final failure = handleDioException(withResponse(401, {'error': 'wrong pincode'}));
      expect(failure, isA<MessageFailure>());
    });

    test(
      '5xx with an error-shaped body maps to ServerFailure, not MessageFailure',
      () {
        for (final code in [500, 502, 503, 504]) {
          final failure = handleDioException(withResponse(code, {'error': 'db down'}));
          expect(
            failure,
            isA<ServerFailure>(),
            reason: 'status $code should not become a MessageFailure',
          );
          expect(failure.isDefiniteAuthRejection, isFalse);
        }
      },
    );

    test('5xx with no body still maps to ServerFailure', () {
      final failure = handleDioException(withResponse(500, null));
      expect(failure, isA<ServerFailure>());
    });

    test('404 maps to NotFoundFailure when the body has no error field', () {
      final failure = handleDioException(withResponse(404, {'message': 'not found'}));
      expect(failure, isA<NotFoundFailure>());
    });
  });
}

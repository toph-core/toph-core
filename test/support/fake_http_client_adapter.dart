import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A real `HttpClientAdapter` backed by a pluggable handler — no real socket
/// ever opens. Swapped onto `DioClient.dio.httpClientAdapter` (a public
/// getter, so no production constructor change was needed) in tests that
/// need a genuine `DioClient`/`syncAll` round trip without real network —
/// same "real small implementation of the platform's own extension point"
/// pattern as `InMemorySecureStoragePlatform` and `FakeConnectivityPlatform`.
///
/// [handler] returns either a `ResponseBody` (success or an HTTP error
/// status Dio will turn into a `DioException` via `validateStatus`) or
/// throws a `DioException` directly (e.g. `DioExceptionType.connectionError`)
/// to simulate a dropped connection.
class FakeHttpClientAdapter implements HttpClientAdapter {
  Future<ResponseBody> Function(RequestOptions options) handler;

  FakeHttpClientAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody okResponse([Object? data]) => ResponseBody.fromString(
      data == null ? '{}' : data.toString(),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

Never connectionErrorResponse(RequestOptions options) => throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
      message: 'simulated connection error',
    );

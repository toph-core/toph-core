import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mary_ai_pos/core/auth/storage/token_storage_impl.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/api//dio_interceptor.dart';

class DioClient {
  final AppTokenStorage _tokenStorage;
  late final Dio _dio;

  DioClient(this._tokenStorage) {
    _dio = Dio(
      BaseOptions(
        baseUrl: BASE_URL,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        validateStatus: (status) => status != null && status < 400,
      ),
    );

    _dio.interceptors.add(MySmartDioInterceptor(_dio, _tokenStorage));

    if (kDebugMode) {
      _dio.interceptors.add(
        LogInterceptor(
          responseBody: true,
          requestBody: true,
          requestHeader: true,
        ),
      );
    }
  }

  Dio get dio => _dio;

  // ==== HTTP Methods ====

  Future<Response<dynamic>> get(
    String url, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.get(url, queryParameters: queryParameters);
      if (response.statusCode != 200) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
        );
      }
      return response;
    } on DioException {
      rethrow;
    }
  }

  Future<Response<dynamic>> post(
    String url, {
    dynamic data,
    Map<String, dynamic>? headers,
    Options? options,
  }) async {
    try {
      final response = await _dio.post(
        url,
        data: data,
        options: options ?? Options(headers: headers),
      );
      if (response.statusCode == 200 ||
          response.statusCode == 201 ||
          response.statusCode == 203) {
        return response;
      } else {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
        );
      }
    } on DioException {
      rethrow;
    }
  }

  Future<Response<dynamic>> put(
    String url, {
    dynamic data,
    Map<String, dynamic>? headers,
  }) async {
    try {
      final response = await _dio.put(
        url,
        data: data,
        options: Options(headers: headers),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return response;
      } else {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
        );
      }
    } on DioException {
      rethrow;
    }
  }

  Future<Response<dynamic>> patch(
    String url, {
    dynamic data,
    Map<String, dynamic>? headers,
  }) async {
    try {
      final response = await _dio.patch(
        url,
        data: data,
        options: Options(headers: headers),
      );
      if (response.statusCode == 200) {
        return response;
      } else {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
        );
      }
    } on DioException {
      rethrow;
    }
  }

  Future<dynamic> delete(
    String url, {
    dynamic data,
    Map<String, dynamic>? headers,
  }) async {
    try {
      final response = await _dio.delete(
        url,
        data: data,
        options: Options(headers: headers),
      );
      if (response.statusCode == 204) {
        return true;
      }
      return response.data;
    } on DioException {
      rethrow;
    }
  }
}

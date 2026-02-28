import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:flutter/foundation.dart';

class MinioService {
  MinioService._();

  static final MinioService _instance = MinioService._();

  static MinioService get instance => _instance;

  final DioClient _client = inject<DioClient>();

  Future<Uint8List?> getImageByObjectName(String objectName) async {
    try {
      final Response response = await _client.post(
        ListAPI.mediaImage,
        data: {"object_name": objectName},
        options: Options(responseType: ResponseType.bytes),
      );

      return response.data;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> getAudioByObjectName(String objectName) async {
    try {
      final Response response = await _client.post(
        ListAPI.mediaAudio,
        data: {"object_name": objectName},
        options: Options(responseType: ResponseType.bytes),
      );

      return response.data;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> getBookByObjectName(String objectName) async {
    try {
      final Response response = await _client.post(
        ListAPI.mediaBook,
        data: {"object_name": objectName},
        options: Options(responseType: ResponseType.bytes),
      );

      return response.data;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> getVideoByObjectName(String objectName) async {
    try {
      final Response response = await _client.post(
        ListAPI.mediaVideo,
        data: {"object_name": objectName},
        options: Options(responseType: ResponseType.bytes),
      );

      return response.data;
    } catch (_) {
      return null;
    }
  }

  Future<String?> postImage(File imageFile) async {
    try {
      final FormData formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          imageFile.path,
          filename: imageFile.path.split('/').last,
        ),
      });

      final Response response = await _client.post(
        ListAPI.mediaImagePost,
        data: formData,
      );

      return response.data['data']['object_name'] as String;
    } catch (e) {
      return null;
    }
  }
}

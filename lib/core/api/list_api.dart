class ListAPI {
  ListAPI._();
  //! Auth
  static const String login = "api/v1/auth/login";
  static const String loginPinCode = "api/v1/auth/login-pincode";
  static const String refresh = "api/v1/auth/refresh";

  //! general
  static const String cafeTablesByHallId = "api/v1/cafe-tables/available/hall";
  static const String halls = "api/v1/halls";

  //! minio
  static const String minioAudio = "api/v1/minio/audio/download";
  static const String minioImage = "api/v1/minio/image/download";
  static const String minioBook = "api/v1/minio/book/download";
  static const String minioVideo = "api/v1/minio/video/download";
  static const String minioImagePost = "api/v1/minio/image";
}

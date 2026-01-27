class ListAPI {
  ListAPI._();
  //! Auth
  static const String login = "v1/auth/login";
  static const String loginWithGoogle = "/v1/auth/login/with-google";
  static const String register = "v1/auth/register";
  static const String refresh = "v1/auth/refresh";
  static const String verifyPhoneNumber = "/v1/auth/verify/phone-number";
  static const String sendOtp = "/v1/auth/send-otp";
  static const String userMe = "/v1/user/me";
  static const String userUpdate = "/v1/user/update";
  static const String logout = "/v1/auth/logout";

  //! Profile
  static const String userPasswordUpdate = "v1/user/password-update";

  //! Library
  static const String libAudios = "v1/library/audios";
  static const String libBooks = "v1/library/books";
  static const String libVideos = "v1/library/videos";

  //! minio
  static const String minioAudio = "v1/minio/audio/download";
  static const String minioImage = "v1/minio/image/download";
  static const String minioBook = "v1/minio/book/download";
  static const String minioVideo = "v1/minio/video/download";
  static const String minioImagePost = "v1/minio/image";

  //! Faqs
  static const String faqs = "v1/faq";

  static const String unitList = "v1/unit/list";
  static const String courseList = "v1/course/list";
}

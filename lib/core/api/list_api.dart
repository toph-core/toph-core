class ListAPI {
  ListAPI._();
  //! Auth
  static const String login = "api/v1/auth/login";
  static const String loginPinCode = "api/v1/auth/login-pincode";
  static const String refresh = "api/v1/auth/refresh";

  //! general
  static const String cafeTablesByHallId = "api/v1/cafe-tables/available/hall";
  static const String halls = "api/v1/halls";
  static const String categories = "api/v1/categories";
  static String categoriesGoods(String categoryId) =>
      "api/v1/categories/$categoryId/goods";

  //! media
  static const String mediaAudio = "api/v1/media/audio/download";
  static const String mediaImage = "api/v1/media/image/download";
  static const String mediaBook = "api/v1/media/book/download";
  static const String mediaVideo = "api/v1/media/video/download";
  static const String mediaImagePost = "api/v1/media/image";

  //! Orders
  static const String orders = "/api/v1/orders";
}

class ListAPI {
  ListAPI._();
  //! Auth
  static const String login = "api/v1/auth/login";
  static const String loginPinCode = "api/v1/auth/login-pincode";
  static const String refresh = "api/v1/auth/refresh";
  static const String user = "api/v1/user/me";

  //! general
  static const String cafeTablesByHallId = "api/v1/cafe-tables/hall";
  static const String halls = "api/v1/halls";
  static const String categories = "api/v1/categories";
  static String categoriesGoods(String categoryId) => "api/v1/categories/$categoryId/goods";
  static const String goods = "/api/v1/goods";
  static const String goodsSearch = "/api/v1/goods/search";

  //! media
  static const String mediaAudio = "api/v1/media/audio/download";
  static const String mediaImage = "api/v1/media/image/download";
  static const String mediaBook = "api/v1/media/book/download";
  static const String mediaVideo = "api/v1/media/video/download";
  static const String mediaImagePost = "api/v1/media/image";

  //! Orders
  static const String orders = "/api/v1/orders";
  static const String archives = "/api/v1/bills";
  static String archiveWithId(String id) => "/api/v1/bills/$id";
  static String orderWithTableId(String id) => "/api/v1/orders/table/$id";
  static const String createOrderItems = "/api/v1/order-items";
  static String payToOrder(String id) => "/api/v1/orders/$id/pay";
  static String orderHourPrice(String id) => "/api/v1/orders/$id/table-price";

  //! ChashRegisterShfit
  static const String activeShift = "api/v1/cash-register-shifts/active";
  static String closeShift(String id) => "/api/v1/cash-register-shifts/$id/close";
  static const String openShift = "/api/v1/cash-register-shifts";
}

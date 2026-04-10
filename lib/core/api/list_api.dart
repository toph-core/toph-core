class ListAPI {
  ListAPI._();
  //! Auth
  static const String login = "api/v1/auth/login";
  static const String loginPinCode = "api/v1/auth/login-pincode";
  static const String refresh = "api/v1/auth/refresh";
  static const String user = "api/v1/user/me";
  static const String users = "api/v1/users";

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
  static String orderById(String orderId) => "/api/v1/orders/$orderId";
  /// Current user's orders (Bearer token). Query: lang, scope, limit, offset.
  static const String ordersMy = "api/v1/orders/my";
  /// Orders assigned to / history for a waiter.
  static String ordersByWaiter(String waiterId) =>
      "api/v1/orders/waiter/$waiterId";
  static const String archives = "/api/v1/bills";
  static String archiveWithId(String id) => "/api/v1/bills/$id";
  static String orderWithTableId(String id) => "/api/v1/orders/table/$id";
  static String orderItemsListByOrder(String orderId) =>
      "/api/v1/order-items/order/$orderId";
  static String orderItemCancel(String orderItemId) =>
      "/api/v1/order-items/$orderItemId/cancel";
  static String orderItems(String orderId) => "/api/v1/orders/$orderId/items";
  static String payToOrder(String id) => "/api/v1/orders/$id/pay";
  static String orderHourPrice(String id) => "/api/v1/orders/$id/table-price";

  /// Vaqt bo‘yicha stol (time_based) — faqat `dine_in` + tegishli stol.
  static String orderTableTimer(String orderId) =>
      "/api/v1/orders/$orderId/table-timer";
  static String orderTableTimerStart(String orderId) =>
      "/api/v1/orders/$orderId/table-timer/start";
  static String orderTableTimerPause(String orderId) =>
      "/api/v1/orders/$orderId/table-timer/pause";
  static String orderTableTimerResume(String orderId) =>
      "/api/v1/orders/$orderId/table-timer/resume";

  //! ChashRegisterShfit
  static const String activeShift = "/api/v1/cash-register-shifts/active";
  static String closeShift(String id) => "/api/v1/cash-register-shifts/$id/close";
  static const String openShift = "/api/v1/cash-register-shifts";

  //! POS printers (ESC/POS TCP) — branch/cafe sozlamalari
  /// GET/PUT — `{ data: { cashier_printer_ip, kitchen_printer_ip, printer_port } }`
  static const String printerSettings = "api/v1/settings/printer";
}

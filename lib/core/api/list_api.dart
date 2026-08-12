class ListAPI {
  ListAPI._();
  //! Auth
  static const String login = "api/v1/auth/login";
  static const String loginPinCode = "api/v1/auth/login-pincode";
  static const String refresh = "api/v1/auth/refresh";
  static const String user = "api/v1/user/me";
  /// Staff list reachable by a normal terminal/waiter/cashier session — unlike
  /// [users] (admin-only), this is the endpoint the backend's own doc comment
  /// says is meant for "Flutter reads during initial data pull".
  static const String usersStaff = "api/v1/users/staff";
  static String userById(String id) => "api/v1/users/$id";
  static const String authRegister = "api/v1/auth/register";
  static const String passwordUpdate = "api/v1/user/password-update";

  //! general
  static const String cafeTables = "api/v1/cafe-tables";
  static String cafeTableById(String id) => "api/v1/cafe-tables/$id";
  static const String halls = "api/v1/halls";
  static const String categories = "api/v1/categories";
  static String categoryById(String id) => "api/v1/categories/$id";
  static String categoriesGoods(String categoryId) =>
      "api/v1/categories/$categoryId/goods";
  static String categoriesByDepartment(String departmentId) =>
      "api/v1/categories/department/$departmentId";
  static const String departments = "api/v1/departments";
  static const String goods = "/api/v1/goods";
  static const String goodsWithCalculations = "/api/v1/goods/with-calculations";
  static String goodById(String id) => "/api/v1/goods/$id";
  static String goodWithCalculationsById(String id) =>
      "/api/v1/goods/$id/with-calculations";
  static String translations({int limit = 1000, int offset = 0}) =>
      "/api/v1/translations?limit=$limit&offset=$offset";
  static const String createTranslation = "/api/v1/translations";
  static String translationById(String id) => "/api/v1/translations/$id";
  static const String goodsSearch = "/api/v1/goods/search";
  static String goodsPaginated({int limit = 100, int offset = 0}) =>
      "/api/v1/goods?limit=$limit&offset=$offset";

  //! Ingredients / compounds (recipe-editor reference data) — each has a
  //! `-lang` fallback path the backend may serve instead depending on
  //! deployment; both are tried in order, see `MainDataSourcesImpl
  //! .getIngredients`/`.getCompounds`.
  static const String ingredients = "/api/v1/ingredients";
  static const String ingredientsLang = "/api/v1/ingredients-lang";
  static const String compounds = "/api/v1/compounds";
  static const String compoundsLang = "/api/v1/compounds-lang";

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
  static String archiveWithId(String id) => "/api/v1/bills/$id";
  static String orderWithTableId(String id) => "/api/v1/orders/table/$id";
  static String orderItemsListByOrder(String orderId) =>
      "/api/v1/order-items/order/$orderId";
  static String orderItemCancel(String orderItemId) =>
      "/api/v1/order-items/$orderItemId/cancel";
  static String orderItems(String orderId) => "/api/v1/orders/$orderId/items";
  static const String orderItemsCreate = "/api/v1/order-items";
  static String payToOrder(String id) => "/api/v1/orders/$id/pay";
  static String cancelOrder(String id) => "/api/v1/orders/$id/cancel";
  static String orderTransfer(String id) => "/api/v1/orders/$id/transfer";

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
  static String closeShift(String id) =>
      "/api/v1/cash-register-shifts/$id/close";
  static const String openShift = "/api/v1/cash-register-shifts";

  //! POS printers (ESC/POS TCP) — `data`: printer yozuvlari massivi
  static const String printerSettings = "api/v1/settings/printer-settings";

  //! Branches — branch settings (default service percent, etc.)
  static String branchById(String id) => "/api/v1/branches/$id";

  //! Cash registers (for select dropdowns)
  static const String cashRegisters = "api/v1/cash-registers";

  //! Transactions (cashbox income/expense/transfer)
  static const String transactions = "api/v1/transactions";
  static String transactionById(String id) => "api/v1/transactions/$id";
  static const String transactionsIncomeExpense =
      "api/v1/transactions/income-expense";
  static const String transactionsTransfer = "api/v1/transactions/transfer";
  static const String transactionsReport = "api/v1/transactions/report";

  //! Group transactions ("categories" for transactions)
  static const String groupTransactions = "api/v1/group-transactions";
  static String groupTransactionById(String id) =>
      "api/v1/group-transactions/$id";
}

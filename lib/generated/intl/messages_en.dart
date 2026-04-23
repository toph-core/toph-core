// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a en locale. All the
// messages from the main program should be duplicated here with the same
// function name.

// Ignore issues from commonly used lints in this file.
// ignore_for_file:unnecessary_brace_in_string_interps, unnecessary_new
// ignore_for_file:prefer_single_quotes,comment_references, directives_ordering
// ignore_for_file:annotate_overrides,prefer_generic_function_type_aliases
// ignore_for_file:unused_import, file_names, avoid_escaping_inner_quotes
// ignore_for_file:unnecessary_string_interpolations, unnecessary_string_escapes

import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'en';

  static String m0(count) => "${count} Compounds";

  static String m1(item) => "Delete \'${item}\'?";

  static String m2(name) =>
      "Account ${name} will be deleted. This action cannot be undone.";

  static String m3(count) => "${count} Ingredients";

  static String m4(count, avg) => "${count} items · avg ${avg}";

  static String m5(count, time) => "${count} items · ${time}";

  static String m6(n) => "${n} tables";

  static String m7(count) => "${count} orders";

  static String m8(count, avg) => "${count} orders · avg ${avg}";

  static String m9(size) => "${size} / page";

  static String m10(count) => "${count} tables not saved";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
        "all": MessageLookupByLibrary.simpleMessage("All"),
        "month": MessageLookupByLibrary.simpleMessage("Month"),
        "strAccessRestricted":
            MessageLookupByLibrary.simpleMessage("Access restricted"),
        "strActionColumnHeader": MessageLookupByLibrary.simpleMessage("Action"),
        "strActionsColumn": MessageLookupByLibrary.simpleMessage("Actions"),
        "strAdd": MessageLookupByLibrary.simpleMessage("Add"),
        "strAddCategory": MessageLookupByLibrary.simpleMessage("Add category"),
        "strAddFirstEmployee":
            MessageLookupByLibrary.simpleMessage("Add first employee"),
        "strAddFirstHall":
            MessageLookupByLibrary.simpleMessage("Add first hall"),
        "strAddFirstPrinter":
            MessageLookupByLibrary.simpleMessage("Add first printer"),
        "strAddFirstTable":
            MessageLookupByLibrary.simpleMessage("Add first table"),
        "strAddItems": MessageLookupByLibrary.simpleMessage("Add"),
        "strAddNewEmployee":
            MessageLookupByLibrary.simpleMessage("New employee"),
        "strAddNewHall": MessageLookupByLibrary.simpleMessage("New hall"),
        "strAddOrder": MessageLookupByLibrary.simpleMessage("Add order"),
        "strAddPrinter": MessageLookupByLibrary.simpleMessage("New printer"),
        "strAddress": MessageLookupByLibrary.simpleMessage("Address"),
        "strAllColon": MessageLookupByLibrary.simpleMessage("All:"),
        "strAllDishes": MessageLookupByLibrary.simpleMessage("All dishes"),
        "strAllHalls": MessageLookupByLibrary.simpleMessage("All"),
        "strAllOrdersTitle": MessageLookupByLibrary.simpleMessage("All Orders"),
        "strAllRoles": MessageLookupByLibrary.simpleMessage("All"),
        "strAmountColumn": MessageLookupByLibrary.simpleMessage("Amount"),
        "strAmountColumnHeader": MessageLookupByLibrary.simpleMessage("Amount"),
        "strAngleDegrees": MessageLookupByLibrary.simpleMessage("Angle (°)"),
        "strAppLanguage": MessageLookupByLibrary.simpleMessage("App language"),
        "strAppliesToAllUsers":
            MessageLookupByLibrary.simpleMessage("Applied to all users"),
        "strApril": MessageLookupByLibrary.simpleMessage("April"),
        "strArchive": MessageLookupByLibrary.simpleMessage("Orders"),
        "strArchiveEmpty":
            MessageLookupByLibrary.simpleMessage("Orders not found"),
        "strAugust": MessageLookupByLibrary.simpleMessage("August"),
        "strAverageCheck":
            MessageLookupByLibrary.simpleMessage("Average check"),
        "strAverageShort": MessageLookupByLibrary.simpleMessage("avg"),
        "strBackToScreen": MessageLookupByLibrary.simpleMessage("Go back"),
        "strBillSuffix": MessageLookupByLibrary.simpleMessage("bill"),
        "strBusy": MessageLookupByLibrary.simpleMessage("Busy"),
        "strCable": MessageLookupByLibrary.simpleMessage("Cable"),
        "strCancel": MessageLookupByLibrary.simpleMessage("Cancel"),
        "strCancelShort": MessageLookupByLibrary.simpleMessage("Cancel"),
        "strCancelled": MessageLookupByLibrary.simpleMessage("Cancelled"),
        "strCapacityPersons":
            MessageLookupByLibrary.simpleMessage("Capacity (persons)"),
        "strCard": MessageLookupByLibrary.simpleMessage("Card"),
        "strCash": MessageLookupByLibrary.simpleMessage("Cash"),
        "strCashBalance": MessageLookupByLibrary.simpleMessage("Cash balance"),
        "strCashier": MessageLookupByLibrary.simpleMessage("Cashier"),
        "strCashierLabel": MessageLookupByLibrary.simpleMessage("Cashier:"),
        "strCashierRole": MessageLookupByLibrary.simpleMessage("Cashier"),
        "strCategory": MessageLookupByLibrary.simpleMessage("Category"),
        "strChange": MessageLookupByLibrary.simpleMessage("Change"),
        "strCheckForDetails": MessageLookupByLibrary.simpleMessage(
            "Tap on a check to see details!"),
        "strCheckInternetConnection": MessageLookupByLibrary.simpleMessage(
            "Please check your internet connection"),
        "strCheckNotFound":
            MessageLookupByLibrary.simpleMessage("Check not found"),
        "strCheckNumberLabel":
            MessageLookupByLibrary.simpleMessage("Check number:"),
        "strCheckPrinter":
            MessageLookupByLibrary.simpleMessage("Check printer"),
        "strClear": MessageLookupByLibrary.simpleMessage("Clear"),
        "strClient": MessageLookupByLibrary.simpleMessage("Client"),
        "strCloseAction": MessageLookupByLibrary.simpleMessage("Close"),
        "strCloseShift": MessageLookupByLibrary.simpleMessage("Close shift"),
        "strCloseShiftInstruction": MessageLookupByLibrary.simpleMessage(
            "Press the button in the bottom right to close the shift."),
        "strCloseShiftShort":
            MessageLookupByLibrary.simpleMessage("Close shift"),
        "strClosedStatus": MessageLookupByLibrary.simpleMessage("Closed"),
        "strClosedToday": MessageLookupByLibrary.simpleMessage("Closed today"),
        "strCompounds": MessageLookupByLibrary.simpleMessage("Compounds"),
        "strCompoundsCount": m0,
        "strConfirmCardPayment": MessageLookupByLibrary.simpleMessage(
            "Confirm that customer paid by card"),
        "strConfirmDelete":
            MessageLookupByLibrary.simpleMessage("Confirm deletion"),
        "strConfirmDeleteItem": m1,
        "strConnected": MessageLookupByLibrary.simpleMessage("Connected"),
        "strConnectedCategories":
            MessageLookupByLibrary.simpleMessage("Connected categories"),
        "strConnectionType":
            MessageLookupByLibrary.simpleMessage("Connection type"),
        "strContinue": MessageLookupByLibrary.simpleMessage("Continue"),
        "strCooking": MessageLookupByLibrary.simpleMessage("Cooking"),
        "strCurrentShift":
            MessageLookupByLibrary.simpleMessage("Current shift"),
        "strCustomer": MessageLookupByLibrary.simpleMessage("Customer"),
        "strDate": MessageLookupByLibrary.simpleMessage("Date"),
        "strDateLabel": MessageLookupByLibrary.simpleMessage("Date:"),
        "strDecember": MessageLookupByLibrary.simpleMessage("December"),
        "strDelete": MessageLookupByLibrary.simpleMessage("Delete"),
        "strDeleteCategory":
            MessageLookupByLibrary.simpleMessage("Delete category"),
        "strDeleteEmployee":
            MessageLookupByLibrary.simpleMessage("Delete employee"),
        "strDeleteEmployeeConfirm": m2,
        "strDeleteError": MessageLookupByLibrary.simpleMessage("Delete error"),
        "strDeleteHall": MessageLookupByLibrary.simpleMessage("Delete hall"),
        "strDeleteMeal": MessageLookupByLibrary.simpleMessage("Delete meal"),
        "strDeletePrinter":
            MessageLookupByLibrary.simpleMessage("Delete printer"),
        "strDeleteTable": MessageLookupByLibrary.simpleMessage("Delete table"),
        "strDeviceSynchronization":
            MessageLookupByLibrary.simpleMessage("Device synchronization"),
        "strDisabled": MessageLookupByLibrary.simpleMessage("Disabled"),
        "strDiscount": MessageLookupByLibrary.simpleMessage("Discount"),
        "strDiscountServiceTitle":
            MessageLookupByLibrary.simpleMessage("Discount & Service"),
        "strDiscounts": MessageLookupByLibrary.simpleMessage("Discounts"),
        "strDishesColumn": MessageLookupByLibrary.simpleMessage("Dishes"),
        "strDoYouWantClearOrders": MessageLookupByLibrary.simpleMessage(
            "Are you sure you want to clear orders?"),
        "strDoYouWantSendOrdersToKitchken":
            MessageLookupByLibrary.simpleMessage(
                "Are you sure you want to send the order to the kitchen?"),
        "strDoYouWantToLogout":
            MessageLookupByLibrary.simpleMessage("Do you want to logout?"),
        "strDragHint": MessageLookupByLibrary.simpleMessage("Drag"),
        "strDuration": MessageLookupByLibrary.simpleMessage("Duration"),
        "strDurationLabel": MessageLookupByLibrary.simpleMessage("Duration"),
        "strEdit": MessageLookupByLibrary.simpleMessage("Edit"),
        "strEditMeal": MessageLookupByLibrary.simpleMessage("Edit meal"),
        "strEditPrinter": MessageLookupByLibrary.simpleMessage("Edit printer"),
        "strEmail": MessageLookupByLibrary.simpleMessage("Email"),
        "strEnlarge": MessageLookupByLibrary.simpleMessage("Zoom in"),
        "strEnterBrandID":
            MessageLookupByLibrary.simpleMessage("Enter Brand ID"),
        "strEnterCode": MessageLookupByLibrary.simpleMessage("Enter code"),
        "strEnterNotes": MessageLookupByLibrary.simpleMessage("Enter notes..."),
        "strEnterPinCode":
            MessageLookupByLibrary.simpleMessage("Enter 2-6 digits"),
        "strError": MessageLookupByLibrary.simpleMessage("Error"),
        "strEscPosDevices":
            MessageLookupByLibrary.simpleMessage("ESC/POS devices"),
        "strExactAmount": MessageLookupByLibrary.simpleMessage("Exact amount"),
        "strExistingOrders":
            MessageLookupByLibrary.simpleMessage("Existing orders"),
        "strExpectedBalance":
            MessageLookupByLibrary.simpleMessage("Expected balance"),
        "strExport": MessageLookupByLibrary.simpleMessage("Export"),
        "strExtraSalt": MessageLookupByLibrary.simpleMessage("Extra salt"),
        "strExtraSpicy": MessageLookupByLibrary.simpleMessage("Extra spicy"),
        "strExtras": MessageLookupByLibrary.simpleMessage("Extras"),
        "strFailureMessage_cache":
            MessageLookupByLibrary.simpleMessage("Error accessing cache"),
        "strFailureMessage_connection": MessageLookupByLibrary.simpleMessage(
            "You appear to be offline, please check your network connection"),
        "strFailureMessage_firebaseAuthFailure":
            MessageLookupByLibrary.simpleMessage(
                "An error occurred when logging in via Firebase"),
        "strFailureMessage_initializingFailure":
            MessageLookupByLibrary.simpleMessage(
                "An error occurred while initializing the app"),
        "strFailureMessage_notFound": MessageLookupByLibrary.simpleMessage(
            "The requested data was not found or does not exist"),
        "strFailureMessage_other": MessageLookupByLibrary.simpleMessage(
            "An unexpected error occurred"),
        "strFailureMessage_parsing":
            MessageLookupByLibrary.simpleMessage("A parsing error occurred"),
        "strFailureMessage_server":
            MessageLookupByLibrary.simpleMessage("A server error occurred"),
        "strFailureMessage_timeout": MessageLookupByLibrary.simpleMessage(
            "Connection timed out, the network may be slow or busy"),
        "strFailureMessage_unauthenticated":
            MessageLookupByLibrary.simpleMessage(
                "You are not logged in, please sign in first"),
        "strFailureMessage_unauthorized": MessageLookupByLibrary.simpleMessage(
            "Authentication failed, please log in again"),
        "strFailureMessage_unknown":
            MessageLookupByLibrary.simpleMessage("An unknown error occurred"),
        "strFailureMessage_validation": MessageLookupByLibrary.simpleMessage(
            "Validation error, please check your fields"),
        "strFebruary": MessageLookupByLibrary.simpleMessage("February"),
        "strFieldCannotBeEmpty":
            MessageLookupByLibrary.simpleMessage("This field cannot be empty"),
        "strFileTooLarge":
            MessageLookupByLibrary.simpleMessage("File must not exceed 5 MB"),
        "strFloorMap": MessageLookupByLibrary.simpleMessage("Floor Map"),
        "strFoodsCategoriesNotFound":
            MessageLookupByLibrary.simpleMessage("Food categories not found!"),
        "strFoodsColumn": MessageLookupByLibrary.simpleMessage("Foods"),
        "strForNotes": MessageLookupByLibrary.simpleMessage("For notes"),
        "strFree": MessageLookupByLibrary.simpleMessage("Free"),
        "strFriday": MessageLookupByLibrary.simpleMessage("Friday"),
        "strFullName": MessageLookupByLibrary.simpleMessage("Full name"),
        "strGiven": MessageLookupByLibrary.simpleMessage("Given"),
        "strGoToPayment": MessageLookupByLibrary.simpleMessage("Go to payment"),
        "strGrid": MessageLookupByLibrary.simpleMessage("Grid"),
        "strGridView": MessageLookupByLibrary.simpleMessage("Grid view"),
        "strGuest": MessageLookupByLibrary.simpleMessage("Guest"),
        "strGuestsSuffix": MessageLookupByLibrary.simpleMessage("guests"),
        "strHall": MessageLookupByLibrary.simpleMessage("Hall"),
        "strHallName": MessageLookupByLibrary.simpleMessage("Hall name"),
        "strHalls": MessageLookupByLibrary.simpleMessage("Halls"),
        "strHallsAndTables":
            MessageLookupByLibrary.simpleMessage("Halls and tables"),
        "strHeightMeters": MessageLookupByLibrary.simpleMessage("Height (m)"),
        "strHeightShort": MessageLookupByLibrary.simpleMessage("Height (m)"),
        "strHotter": MessageLookupByLibrary.simpleMessage("Hotter"),
        "strHourly": MessageLookupByLibrary.simpleMessage("Hourly"),
        "strHourlyPrice":
            MessageLookupByLibrary.simpleMessage("Hourly price (som)"),
        "strHourlySalesDynamics":
            MessageLookupByLibrary.simpleMessage("Hourly sales dynamics"),
        "strHub": MessageLookupByLibrary.simpleMessage("Hub"),
        "strHubClientSettings":
            MessageLookupByLibrary.simpleMessage("Hub and client settings"),
        "strIPAddress": MessageLookupByLibrary.simpleMessage("IP address"),
        "strImages": MessageLookupByLibrary.simpleMessage("Images"),
        "strIngredients": MessageLookupByLibrary.simpleMessage("Ingredients"),
        "strIngredientsCount": m3,
        "strInitialBalance":
            MessageLookupByLibrary.simpleMessage("Initial balance"),
        "strInitialStatus":
            MessageLookupByLibrary.simpleMessage("Initial status"),
        "strInterfaceLanguage":
            MessageLookupByLibrary.simpleMessage("Interface language"),
        "strInterfaceSettings": MessageLookupByLibrary.simpleMessage(
            "Language, interface and menu view"),
        "strInvalidDate": MessageLookupByLibrary.simpleMessage("Invalid date"),
        "strInvalidName": MessageLookupByLibrary.simpleMessage("Invalid name"),
        "strInvalidNumber":
            MessageLookupByLibrary.simpleMessage("Invalid number"),
        "strItemsCountWithAvg": m4,
        "strItemsCountWithTime": m5,
        "strJanuary": MessageLookupByLibrary.simpleMessage("January"),
        "strJuly": MessageLookupByLibrary.simpleMessage("July"),
        "strJune": MessageLookupByLibrary.simpleMessage("June"),
        "strLanNetwork": MessageLookupByLibrary.simpleMessage("LAN Network"),
        "strLanguageAndGeneral":
            MessageLookupByLibrary.simpleMessage("Language and general"),
        "strLoadCompositionError": MessageLookupByLibrary.simpleMessage(
            "Failed to load meal composition"),
        "strLoadError": MessageLookupByLibrary.simpleMessage("Load error"),
        "strLocationMap": MessageLookupByLibrary.simpleMessage("Location map"),
        "strLogin": MessageLookupByLibrary.simpleMessage("Login"),
        "strLogout": MessageLookupByLibrary.simpleMessage("Logout"),
        "strLogoutConfirm": MessageLookupByLibrary.simpleMessage(
            "Are you sure you want to logout?"),
        "strMap": MessageLookupByLibrary.simpleMessage("Map"),
        "strMapView": MessageLookupByLibrary.simpleMessage("Map view"),
        "strMarch": MessageLookupByLibrary.simpleMessage("March"),
        "strMay": MessageLookupByLibrary.simpleMessage("May"),
        "strMenu": MessageLookupByLibrary.simpleMessage("Menu"),
        "strMenuImages": MessageLookupByLibrary.simpleMessage("Menu images"),
        "strMode": MessageLookupByLibrary.simpleMessage("Mode"),
        "strModeDescription": MessageLookupByLibrary.simpleMessage(
            "This device\'s role in the LAN network"),
        "strMonday": MessageLookupByLibrary.simpleMessage("Monday"),
        "strMoreKetchup": MessageLookupByLibrary.simpleMessage("More ketchup"),
        "strNPeopleTable": m6,
        "strNameTooShort":
            MessageLookupByLibrary.simpleMessage("Name is too short"),
        "strNeedAttention":
            MessageLookupByLibrary.simpleMessage("Needs attention"),
        "strNetworkLAN": MessageLookupByLibrary.simpleMessage("Network (LAN)"),
        "strNewMeal": MessageLookupByLibrary.simpleMessage("New meal"),
        "strNewPrinter": MessageLookupByLibrary.simpleMessage("New printer"),
        "strNewTable": MessageLookupByLibrary.simpleMessage("New table"),
        "strNo": MessageLookupByLibrary.simpleMessage("No"),
        "strNoDataFound": MessageLookupByLibrary.simpleMessage("No data found"),
        "strNoDiscountYet":
            MessageLookupByLibrary.simpleMessage("No discount yet"),
        "strNoEmployeesYet":
            MessageLookupByLibrary.simpleMessage("No employees yet"),
        "strNoHallsYet": MessageLookupByLibrary.simpleMessage("No halls yet"),
        "strNoInternetConnection":
            MessageLookupByLibrary.simpleMessage("No internet connection"),
        "strNoOrdersInShift":
            MessageLookupByLibrary.simpleMessage("No orders in this shift yet"),
        "strNoPrintersYet":
            MessageLookupByLibrary.simpleMessage("No printers yet"),
        "strNoSalesData":
            MessageLookupByLibrary.simpleMessage("No sales data yet"),
        "strNoServiceChargeYet":
            MessageLookupByLibrary.simpleMessage("No service charge yet"),
        "strNoTables": MessageLookupByLibrary.simpleMessage("No tables"),
        "strNoTablesInHall":
            MessageLookupByLibrary.simpleMessage("No tables in this hall"),
        "strNotOrdered": MessageLookupByLibrary.simpleMessage("Not ordered"),
        "strNotYet": MessageLookupByLibrary.simpleMessage("Not yet"),
        "strNotifications":
            MessageLookupByLibrary.simpleMessage("Notifications"),
        "strNotifyKitchen":
            MessageLookupByLibrary.simpleMessage("Notify kitchen"),
        "strNovember": MessageLookupByLibrary.simpleMessage("November"),
        "strNowActive":
            MessageLookupByLibrary.simpleMessage("Currently active"),
        "strNowShort": MessageLookupByLibrary.simpleMessage("now"),
        "strNumberColumn": MessageLookupByLibrary.simpleMessage("#"),
        "strOK": MessageLookupByLibrary.simpleMessage("OK"),
        "strOctober": MessageLookupByLibrary.simpleMessage("October"),
        "strOfflineModeMessage": MessageLookupByLibrary.simpleMessage(
            "Offline mode — data will sync when connection returns"),
        "strOpenBills": MessageLookupByLibrary.simpleMessage("Open bills"),
        "strOpenShift": MessageLookupByLibrary.simpleMessage("Open shift"),
        "strOpenedAt": MessageLookupByLibrary.simpleMessage("Opened"),
        "strOpeningBalance":
            MessageLookupByLibrary.simpleMessage("Opening balance"),
        "strOrderDetails":
            MessageLookupByLibrary.simpleMessage("Order details"),
        "strOrderNumber": MessageLookupByLibrary.simpleMessage("# Order"),
        "strOrderSuccessCreated":
            MessageLookupByLibrary.simpleMessage("Order successfully created"),
        "strOrderType": MessageLookupByLibrary.simpleMessage("Order type"),
        "strOrders": MessageLookupByLibrary.simpleMessage("Orders"),
        "strOrdersCountShort": m7,
        "strOrdersCountWithAvg": m8,
        "strOrdersEmpty":
            MessageLookupByLibrary.simpleMessage("Orders not found"),
        "strOrgName": MessageLookupByLibrary.simpleMessage("Organization name"),
        "strOther": MessageLookupByLibrary.simpleMessage("Other"),
        "strPageSize": m9,
        "strPassword": MessageLookupByLibrary.simpleMessage("Password"),
        "strPasswordContainAtLeastChars": MessageLookupByLibrary.simpleMessage(
            "Password must be at least 8 characters."),
        "strPasswordsNotSame":
            MessageLookupByLibrary.simpleMessage("Passwords do not match"),
        "strPauseAction": MessageLookupByLibrary.simpleMessage("Pause"),
        "strPayment": MessageLookupByLibrary.simpleMessage("Payment"),
        "strPaymentInfoNotFound":
            MessageLookupByLibrary.simpleMessage("Payment info not found"),
        "strPaymentLabel": MessageLookupByLibrary.simpleMessage("Payment:"),
        "strPaymentMethodLabel":
            MessageLookupByLibrary.simpleMessage("Payment method:"),
        "strPeakTime": MessageLookupByLibrary.simpleMessage("Peak time"),
        "strPersonsSuffix": MessageLookupByLibrary.simpleMessage("people"),
        "strPhone": MessageLookupByLibrary.simpleMessage("Phone"),
        "strPhoneMask":
            MessageLookupByLibrary.simpleMessage("+998 (__) ___ __ __"),
        "strPhoneOrPasswordWrong": MessageLookupByLibrary.simpleMessage(
            "Wrong phone number or password"),
        "strPinOptional":
            MessageLookupByLibrary.simpleMessage("PIN code (optional)"),
        "strPort": MessageLookupByLibrary.simpleMessage("Port"),
        "strPositionX": MessageLookupByLibrary.simpleMessage("Position X (m)"),
        "strPositionY": MessageLookupByLibrary.simpleMessage("Position Y (m)"),
        "strPositionsSaved":
            MessageLookupByLibrary.simpleMessage("Positions saved"),
        "strPrint": MessageLookupByLibrary.simpleMessage("Print"),
        "strPrinterSettings":
            MessageLookupByLibrary.simpleMessage("Printer settings"),
        "strPrinterType": MessageLookupByLibrary.simpleMessage("Printer type"),
        "strProductNotFound":
            MessageLookupByLibrary.simpleMessage("Products not found"),
        "strProfile": MessageLookupByLibrary.simpleMessage("Profile"),
        "strPullDownToRefresh":
            MessageLookupByLibrary.simpleMessage("Pull down to refresh"),
        "strQuantity": MessageLookupByLibrary.simpleMessage("Quantity"),
        "strReceiptInfo": MessageLookupByLibrary.simpleMessage("Receipt info"),
        "strReceived": MessageLookupByLibrary.simpleMessage("Received"),
        "strRecentOrders":
            MessageLookupByLibrary.simpleMessage("Recent orders"),
        "strRecenter": MessageLookupByLibrary.simpleMessage("Re-center"),
        "strRefresh": MessageLookupByLibrary.simpleMessage("Refresh"),
        "strRefreshCompleted":
            MessageLookupByLibrary.simpleMessage("Refresh complete"),
        "strRefreshFailed":
            MessageLookupByLibrary.simpleMessage("Refresh failed"),
        "strRefreshing":
            MessageLookupByLibrary.simpleMessage("Refreshing data..."),
        "strRegular": MessageLookupByLibrary.simpleMessage("Regular"),
        "strReleaseToRefresh":
            MessageLookupByLibrary.simpleMessage("Release to refresh"),
        "strRequiredFields": MessageLookupByLibrary.simpleMessage(
            "Name, category and price are required"),
        "strReserved": MessageLookupByLibrary.simpleMessage("Reserved"),
        "strRestaurantStaff":
            MessageLookupByLibrary.simpleMessage("Restaurant staff"),
        "strResumeAction": MessageLookupByLibrary.simpleMessage("Resume"),
        "strRetry": MessageLookupByLibrary.simpleMessage("Retry"),
        "strRole": MessageLookupByLibrary.simpleMessage("Role"),
        "strRoleAdmin": MessageLookupByLibrary.simpleMessage("Admin"),
        "strRoleCashier": MessageLookupByLibrary.simpleMessage("Cashier"),
        "strRoleChef": MessageLookupByLibrary.simpleMessage("Chef"),
        "strRoleManager": MessageLookupByLibrary.simpleMessage("Manager"),
        "strRoleSuperadmin": MessageLookupByLibrary.simpleMessage("Superadmin"),
        "strRoleUser": MessageLookupByLibrary.simpleMessage("User"),
        "strRoleWaiter": MessageLookupByLibrary.simpleMessage("Waiter"),
        "strRound": MessageLookupByLibrary.simpleMessage("Round"),
        "strRussian": MessageLookupByLibrary.simpleMessage("Русский"),
        "strSaturday": MessageLookupByLibrary.simpleMessage("Saturday"),
        "strSave": MessageLookupByLibrary.simpleMessage("Save"),
        "strSaveError": MessageLookupByLibrary.simpleMessage("Save error"),
        "strSavePositionError":
            MessageLookupByLibrary.simpleMessage("Error saving position"),
        "strSavedBadge": MessageLookupByLibrary.simpleMessage("Saved"),
        "strSearch": MessageLookupByLibrary.simpleMessage("Search..."),
        "strSearchByCheckNumber":
            MessageLookupByLibrary.simpleMessage("Search by check number"),
        "strSearchHint": MessageLookupByLibrary.simpleMessage("Search..."),
        "strSearchNameOrUsername":
            MessageLookupByLibrary.simpleMessage("Search by name or username"),
        "strSearchTableOrCheck":
            MessageLookupByLibrary.simpleMessage("Table, check number..."),
        "strSelectFile": MessageLookupByLibrary.simpleMessage("Select file"),
        "strSelectFoodsNotFound": MessageLookupByLibrary.simpleMessage(
            "No orders. Tap a dish to add"),
        "strSelectGuestsCount":
            MessageLookupByLibrary.simpleMessage("Set number of guests"),
        "strSemiFinished":
            MessageLookupByLibrary.simpleMessage("Semi-finished"),
        "strSeptember": MessageLookupByLibrary.simpleMessage("September"),
        "strService": MessageLookupByLibrary.simpleMessage("Service"),
        "strServiceCharge":
            MessageLookupByLibrary.simpleMessage("Service charge"),
        "strSettings": MessageLookupByLibrary.simpleMessage("Settings"),
        "strSettingsAdminOnly": MessageLookupByLibrary.simpleMessage(
            "Only administrator or manager can access settings."),
        "strShape": MessageLookupByLibrary.simpleMessage("Shape"),
        "strShift": MessageLookupByLibrary.simpleMessage("Shift"),
        "strShiftHash": MessageLookupByLibrary.simpleMessage("Shift"),
        "strShiftJustStarted":
            MessageLookupByLibrary.simpleMessage("Shift just started"),
        "strShiftNotOpenError": MessageLookupByLibrary.simpleMessage(
            "Open shift first. Shift must be open to create orders."),
        "strShiftOpen": MessageLookupByLibrary.simpleMessage("Shift open"),
        "strShiftOpened": MessageLookupByLibrary.simpleMessage("Shift opened"),
        "strShiftReport": MessageLookupByLibrary.simpleMessage("Shift report"),
        "strShiftRevenue":
            MessageLookupByLibrary.simpleMessage("Shift revenue"),
        "strShowProductImages": MessageLookupByLibrary.simpleMessage(
            "Show images in product cards"),
        "strShrink": MessageLookupByLibrary.simpleMessage("Zoom out"),
        "strSom": MessageLookupByLibrary.simpleMessage("sum"),
        "strSquare": MessageLookupByLibrary.simpleMessage("Square"),
        "strStaffRoles":
            MessageLookupByLibrary.simpleMessage("Staff and roles"),
        "strStart": MessageLookupByLibrary.simpleMessage("Start"),
        "strStartWorkInstruction": MessageLookupByLibrary.simpleMessage(
            "Press the button below to start work."),
        "strStatusColumn": MessageLookupByLibrary.simpleMessage("Status"),
        "strStatusColumnHeader": MessageLookupByLibrary.simpleMessage("Status"),
        "strSunday": MessageLookupByLibrary.simpleMessage("Sunday"),
        "strTable": MessageLookupByLibrary.simpleMessage("Table"),
        "strTableHall": MessageLookupByLibrary.simpleMessage("Table / Hall"),
        "strTableLabel": MessageLookupByLibrary.simpleMessage("Table:"),
        "strTableNumber": MessageLookupByLibrary.simpleMessage("Table"),
        "strTableType": MessageLookupByLibrary.simpleMessage("Type"),
        "strTables": MessageLookupByLibrary.simpleMessage("Tables"),
        "strTablesNotSavedCount": m10,
        "strTakeaway": MessageLookupByLibrary.simpleMessage("Takeaway"),
        "strTerminal": MessageLookupByLibrary.simpleMessage("Terminal"),
        "strThursday": MessageLookupByLibrary.simpleMessage("Thursday"),
        "strTimeColumn": MessageLookupByLibrary.simpleMessage("Time"),
        "strTimeColumnHeader": MessageLookupByLibrary.simpleMessage("Time"),
        "strTodayRevenue":
            MessageLookupByLibrary.simpleMessage("Today\'s revenue"),
        "strTotalCapacity":
            MessageLookupByLibrary.simpleMessage("Total capacity"),
        "strTotalColon": MessageLookupByLibrary.simpleMessage("Total:"),
        "strTotalLabel": MessageLookupByLibrary.simpleMessage("Total:"),
        "strTotalRevenueLabel":
            MessageLookupByLibrary.simpleMessage("Total revenue"),
        "strTotalSales": MessageLookupByLibrary.simpleMessage("Total sales"),
        "strTotalSum": MessageLookupByLibrary.simpleMessage("Total"),
        "strTotalTables": MessageLookupByLibrary.simpleMessage("Total tables"),
        "strTuesday": MessageLookupByLibrary.simpleMessage("Tuesday"),
        "strTypeColumnHeader": MessageLookupByLibrary.simpleMessage("Type"),
        "strUmumiySumma": MessageLookupByLibrary.simpleMessage("Total amount"),
        "strUnacceptableDate":
            MessageLookupByLibrary.simpleMessage("Unacceptable date"),
        "strUploadError": MessageLookupByLibrary.simpleMessage("Upload error"),
        "strUploadFailed":
            MessageLookupByLibrary.simpleMessage("Failed to upload image"),
        "strUsername": MessageLookupByLibrary.simpleMessage("Username"),
        "strUsersRolesPerms": MessageLookupByLibrary.simpleMessage(
            "Users, roles and permissions"),
        "strUzbek": MessageLookupByLibrary.simpleMessage("O\'zbek"),
        "strViewAll": MessageLookupByLibrary.simpleMessage("View all"),
        "strViewReceipt": MessageLookupByLibrary.simpleMessage("View receipt"),
        "strWaiterRole": MessageLookupByLibrary.simpleMessage("Waiter"),
        "strWaiting": MessageLookupByLibrary.simpleMessage("Waiting"),
        "strWaitingForOrder":
            MessageLookupByLibrary.simpleMessage("Waiting for order"),
        "strWaitingForOrderStatus":
            MessageLookupByLibrary.simpleMessage("Waiting for order"),
        "strWednesday": MessageLookupByLibrary.simpleMessage("Wednesday"),
        "strWiFi": MessageLookupByLibrary.simpleMessage("Wi-Fi"),
        "strWidthMeters": MessageLookupByLibrary.simpleMessage("Width (m)"),
        "strWidthShort": MessageLookupByLibrary.simpleMessage("Width (m)"),
        "strYes": MessageLookupByLibrary.simpleMessage("Yes"),
        "strYouWantLeaveOrderScreen": MessageLookupByLibrary.simpleMessage(
            "Are you sure you want to leave? Foods will be cancelled."),
        "today": MessageLookupByLibrary.simpleMessage("Today"),
        "week": MessageLookupByLibrary.simpleMessage("Week"),
        "strOrder": MessageLookupByLibrary.simpleMessage("Order"),
        "strAcceptedAmount": MessageLookupByLibrary.simpleMessage("Accepted"),
        "strManualInput":
            MessageLookupByLibrary.simpleMessage("Manual input"),
        "strPaymentAmount":
            MessageLookupByLibrary.simpleMessage("Payment amount"),
        "strSubtotal": MessageLookupByLibrary.simpleMessage("Subtotal"),
        "strHourlyPayment":
            MessageLookupByLibrary.simpleMessage("Hourly fee"),
        "strOrderNotFound":
            MessageLookupByLibrary.simpleMessage("Order not found"),
        "strConfirm": MessageLookupByLibrary.simpleMessage("Confirm"),
        "strPiecesSuffix": MessageLookupByLibrary.simpleMessage("pcs")
      };
}

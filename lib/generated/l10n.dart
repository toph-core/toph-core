// GENERATED CODE - DO NOT MODIFY BY HAND
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'intl/messages_all.dart';

// **************************************************************************
// Generator: Flutter Intl IDE plugin
// Made by Localizely
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, lines_longer_than_80_chars
// ignore_for_file: join_return_with_assignment, prefer_final_in_for_each
// ignore_for_file: avoid_redundant_argument_values, avoid_escaping_inner_quotes

class S {
  S();

  static S? _current;

  static S get current {
    assert(_current != null,
        'No instance of S was loaded. Try to initialize the S delegate before accessing S.current.');
    return _current!;
  }

  static const AppLocalizationDelegate delegate = AppLocalizationDelegate();

  static Future<S> load(Locale locale) {
    final name = (locale.countryCode?.isEmpty ?? false)
        ? locale.languageCode
        : locale.toString();
    final localeName = Intl.canonicalizedLocale(name);
    return initializeMessages(localeName).then((_) {
      Intl.defaultLocale = localeName;
      final instance = S();
      S._current = instance;

      return instance;
    });
  }

  static S of(BuildContext context) {
    final instance = S.maybeOf(context);
    assert(instance != null,
        'No instance of S present in the widget tree. Did you add S.delegate in localizationsDelegates?');
    return instance!;
  }

  static S? maybeOf(BuildContext context) {
    return Localizations.of<S>(context, S);
  }

  /// `Error accessing cache`
  String get strFailureMessage_cache {
    return Intl.message(
      'Error accessing cache',
      name: 'strFailureMessage_cache',
      desc: '',
      args: [],
    );
  }

  /// `An unknown error occurred`
  String get strFailureMessage_unknown {
    return Intl.message(
      'An unknown error occurred',
      name: 'strFailureMessage_unknown',
      desc: '',
      args: [],
    );
  }

  /// `A parsing error occurred`
  String get strFailureMessage_parsing {
    return Intl.message(
      'A parsing error occurred',
      name: 'strFailureMessage_parsing',
      desc: '',
      args: [],
    );
  }

  /// `A server error occurred`
  String get strFailureMessage_server {
    return Intl.message(
      'A server error occurred',
      name: 'strFailureMessage_server',
      desc: '',
      args: [],
    );
  }

  /// `You appear to be offline, please check your network connection`
  String get strFailureMessage_connection {
    return Intl.message(
      'You appear to be offline, please check your network connection',
      name: 'strFailureMessage_connection',
      desc: '',
      args: [],
    );
  }

  /// `Connection timed out, the network may be slow or busy`
  String get strFailureMessage_timeout {
    return Intl.message(
      'Connection timed out, the network may be slow or busy',
      name: 'strFailureMessage_timeout',
      desc: '',
      args: [],
    );
  }

  /// `The requested data was not found or does not exist`
  String get strFailureMessage_notFound {
    return Intl.message(
      'The requested data was not found or does not exist',
      name: 'strFailureMessage_notFound',
      desc: '',
      args: [],
    );
  }

  /// `An unexpected error occurred`
  String get strFailureMessage_other {
    return Intl.message(
      'An unexpected error occurred',
      name: 'strFailureMessage_other',
      desc: '',
      args: [],
    );
  }

  /// `Authentication failed, please log in again`
  String get strFailureMessage_unauthorized {
    return Intl.message(
      'Authentication failed, please log in again',
      name: 'strFailureMessage_unauthorized',
      desc: '',
      args: [],
    );
  }

  /// `Validation error, please check your fields`
  String get strFailureMessage_validation {
    return Intl.message(
      'Validation error, please check your fields',
      name: 'strFailureMessage_validation',
      desc: '',
      args: [],
    );
  }

  /// `You are not logged in, please sign in first`
  String get strFailureMessage_unauthenticated {
    return Intl.message(
      'You are not logged in, please sign in first',
      name: 'strFailureMessage_unauthenticated',
      desc: '',
      args: [],
    );
  }

  /// `An error occurred when logging in via Firebase`
  String get strFailureMessage_firebaseAuthFailure {
    return Intl.message(
      'An error occurred when logging in via Firebase',
      name: 'strFailureMessage_firebaseAuthFailure',
      desc: '',
      args: [],
    );
  }

  /// `An error occurred while initializing the app`
  String get strFailureMessage_initializingFailure {
    return Intl.message(
      'An error occurred while initializing the app',
      name: 'strFailureMessage_initializingFailure',
      desc: '',
      args: [],
    );
  }

  /// `Please check your internet connection`
  String get strCheckInternetConnection {
    return Intl.message(
      'Please check your internet connection',
      name: 'strCheckInternetConnection',
      desc: '',
      args: [],
    );
  }

  /// `No internet connection`
  String get strNoInternetConnection {
    return Intl.message(
      'No internet connection',
      name: 'strNoInternetConnection',
      desc: '',
      args: [],
    );
  }

  /// `Yes`
  String get strYes {
    return Intl.message(
      'Yes',
      name: 'strYes',
      desc: '',
      args: [],
    );
  }

  /// `No`
  String get strNo {
    return Intl.message(
      'No',
      name: 'strNo',
      desc: '',
      args: [],
    );
  }

  /// `No data found`
  String get strNoDataFound {
    return Intl.message(
      'No data found',
      name: 'strNoDataFound',
      desc: '',
      args: [],
    );
  }

  /// `Pull down to refresh`
  String get strPullDownToRefresh {
    return Intl.message(
      'Pull down to refresh',
      name: 'strPullDownToRefresh',
      desc: '',
      args: [],
    );
  }

  /// `Release to refresh`
  String get strReleaseToRefresh {
    return Intl.message(
      'Release to refresh',
      name: 'strReleaseToRefresh',
      desc: '',
      args: [],
    );
  }

  /// `Refreshing data...`
  String get strRefreshing {
    return Intl.message(
      'Refreshing data...',
      name: 'strRefreshing',
      desc: '',
      args: [],
    );
  }

  /// `Refresh complete`
  String get strRefreshCompleted {
    return Intl.message(
      'Refresh complete',
      name: 'strRefreshCompleted',
      desc: '',
      args: [],
    );
  }

  /// `Refresh failed`
  String get strRefreshFailed {
    return Intl.message(
      'Refresh failed',
      name: 'strRefreshFailed',
      desc: '',
      args: [],
    );
  }

  /// `Retry`
  String get strRetry {
    return Intl.message(
      'Retry',
      name: 'strRetry',
      desc: '',
      args: [],
    );
  }

  /// `This field cannot be empty`
  String get strFieldCannotBeEmpty {
    return Intl.message(
      'This field cannot be empty',
      name: 'strFieldCannotBeEmpty',
      desc: '',
      args: [],
    );
  }

  /// `Password must be at least 8 characters.`
  String get strPasswordContainAtLeastChars {
    return Intl.message(
      'Password must be at least 8 characters.',
      name: 'strPasswordContainAtLeastChars',
      desc: '',
      args: [],
    );
  }

  /// `Invalid number`
  String get strInvalidNumber {
    return Intl.message(
      'Invalid number',
      name: 'strInvalidNumber',
      desc: '',
      args: [],
    );
  }

  /// `Wrong phone number or password`
  String get strPhoneOrPasswordWrong {
    return Intl.message(
      'Wrong phone number or password',
      name: 'strPhoneOrPasswordWrong',
      desc: '',
      args: [],
    );
  }

  /// `Continue`
  String get strContinue {
    return Intl.message(
      'Continue',
      name: 'strContinue',
      desc: '',
      args: [],
    );
  }

  /// `App language`
  String get strAppLanguage {
    return Intl.message(
      'App language',
      name: 'strAppLanguage',
      desc: '',
      args: [],
    );
  }

  /// `Logout`
  String get strLogout {
    return Intl.message(
      'Logout',
      name: 'strLogout',
      desc: '',
      args: [],
    );
  }

  /// `Do you want to logout?`
  String get strDoYouWantToLogout {
    return Intl.message(
      'Do you want to logout?',
      name: 'strDoYouWantToLogout',
      desc: '',
      args: [],
    );
  }

  /// `Profile`
  String get strProfile {
    return Intl.message(
      'Profile',
      name: 'strProfile',
      desc: '',
      args: [],
    );
  }

  /// `Invalid name`
  String get strInvalidName {
    return Intl.message(
      'Invalid name',
      name: 'strInvalidName',
      desc: '',
      args: [],
    );
  }

  /// `Name is too short`
  String get strNameTooShort {
    return Intl.message(
      'Name is too short',
      name: 'strNameTooShort',
      desc: '',
      args: [],
    );
  }

  /// `Invalid date`
  String get strInvalidDate {
    return Intl.message(
      'Invalid date',
      name: 'strInvalidDate',
      desc: '',
      args: [],
    );
  }

  /// `Unacceptable date`
  String get strUnacceptableDate {
    return Intl.message(
      'Unacceptable date',
      name: 'strUnacceptableDate',
      desc: '',
      args: [],
    );
  }

  /// `Passwords do not match`
  String get strPasswordsNotSame {
    return Intl.message(
      'Passwords do not match',
      name: 'strPasswordsNotSame',
      desc: '',
      args: [],
    );
  }

  /// `Enter Brand ID`
  String get strEnterBrandID {
    return Intl.message(
      'Enter Brand ID',
      name: 'strEnterBrandID',
      desc: '',
      args: [],
    );
  }

  /// `Password`
  String get strPassword {
    return Intl.message(
      'Password',
      name: 'strPassword',
      desc: '',
      args: [],
    );
  }

  /// `Enter code`
  String get strEnterCode {
    return Intl.message(
      'Enter code',
      name: 'strEnterCode',
      desc: '',
      args: [],
    );
  }

  /// `Login`
  String get strLogin {
    return Intl.message(
      'Login',
      name: 'strLogin',
      desc: '',
      args: [],
    );
  }

  /// `Products not found`
  String get strProductNotFound {
    return Intl.message(
      'Products not found',
      name: 'strProductNotFound',
      desc: '',
      args: [],
    );
  }

  /// `Food categories not found!`
  String get strFoodsCategoriesNotFound {
    return Intl.message(
      'Food categories not found!',
      name: 'strFoodsCategoriesNotFound',
      desc: '',
      args: [],
    );
  }

  /// `No orders. Tap a dish to add`
  String get strSelectFoodsNotFound {
    return Intl.message(
      'No orders. Tap a dish to add',
      name: 'strSelectFoodsNotFound',
      desc: '',
      args: [],
    );
  }

  /// `Are you sure you want to clear orders?`
  String get strDoYouWantClearOrders {
    return Intl.message(
      'Are you sure you want to clear orders?',
      name: 'strDoYouWantClearOrders',
      desc: '',
      args: [],
    );
  }

  /// `Cancel`
  String get strCancel {
    return Intl.message(
      'Cancel',
      name: 'strCancel',
      desc: '',
      args: [],
    );
  }

  /// `Go back`
  String get strBackToScreen {
    return Intl.message(
      'Go back',
      name: 'strBackToScreen',
      desc: '',
      args: [],
    );
  }

  /// `Are you sure you want to leave? Foods will be cancelled.`
  String get strYouWantLeaveOrderScreen {
    return Intl.message(
      'Are you sure you want to leave? Foods will be cancelled.',
      name: 'strYouWantLeaveOrderScreen',
      desc: '',
      args: [],
    );
  }

  /// `Save`
  String get strSave {
    return Intl.message(
      'Save',
      name: 'strSave',
      desc: '',
      args: [],
    );
  }

  /// `Are you sure you want to send the order to the kitchen?`
  String get strDoYouWantSendOrdersToKitchken {
    return Intl.message(
      'Are you sure you want to send the order to the kitchen?',
      name: 'strDoYouWantSendOrdersToKitchken',
      desc: '',
      args: [],
    );
  }

  /// `Order successfully created`
  String get strOrderSuccessCreated {
    return Intl.message(
      'Order successfully created',
      name: 'strOrderSuccessCreated',
      desc: '',
      args: [],
    );
  }

  /// `Table`
  String get strTable {
    return Intl.message(
      'Table',
      name: 'strTable',
      desc: '',
      args: [],
    );
  }

  /// `Set number of guests`
  String get strSelectGuestsCount {
    return Intl.message(
      'Set number of guests',
      name: 'strSelectGuestsCount',
      desc: '',
      args: [],
    );
  }

  /// `Add`
  String get strAdd {
    return Intl.message(
      'Add',
      name: 'strAdd',
      desc: '',
      args: [],
    );
  }

  /// `All`
  String get all {
    return Intl.message(
      'All',
      name: 'all',
      desc: '',
      args: [],
    );
  }

  /// `Today`
  String get today {
    return Intl.message(
      'Today',
      name: 'today',
      desc: '',
      args: [],
    );
  }

  /// `Week`
  String get week {
    return Intl.message(
      'Week',
      name: 'week',
      desc: '',
      args: [],
    );
  }

  /// `Month`
  String get month {
    return Intl.message(
      'Month',
      name: 'month',
      desc: '',
      args: [],
    );
  }

  /// `Floor Map`
  String get strFloorMap {
    return Intl.message(
      'Floor Map',
      name: 'strFloorMap',
      desc: '',
      args: [],
    );
  }

  /// `Takeaway`
  String get strTakeaway {
    return Intl.message(
      'Takeaway',
      name: 'strTakeaway',
      desc: '',
      args: [],
    );
  }

  /// `Refresh`
  String get strRefresh {
    return Intl.message(
      'Refresh',
      name: 'strRefresh',
      desc: '',
      args: [],
    );
  }

  /// `Grid view`
  String get strGridView {
    return Intl.message(
      'Grid view',
      name: 'strGridView',
      desc: '',
      args: [],
    );
  }

  /// `Map view`
  String get strMapView {
    return Intl.message(
      'Map view',
      name: 'strMapView',
      desc: '',
      args: [],
    );
  }

  /// `Grid`
  String get strGrid {
    return Intl.message(
      'Grid',
      name: 'strGrid',
      desc: '',
      args: [],
    );
  }

  /// `Map`
  String get strMap {
    return Intl.message(
      'Map',
      name: 'strMap',
      desc: '',
      args: [],
    );
  }

  /// `No tables`
  String get strNoTables {
    return Intl.message(
      'No tables',
      name: 'strNoTables',
      desc: '',
      args: [],
    );
  }

  /// `Busy`
  String get strBusy {
    return Intl.message(
      'Busy',
      name: 'strBusy',
      desc: '',
      args: [],
    );
  }

  /// `Reserved`
  String get strReserved {
    return Intl.message(
      'Reserved',
      name: 'strReserved',
      desc: '',
      args: [],
    );
  }

  /// `Free`
  String get strFree {
    return Intl.message(
      'Free',
      name: 'strFree',
      desc: '',
      args: [],
    );
  }

  /// `Saved`
  String get strSavedBadge {
    return Intl.message(
      'Saved',
      name: 'strSavedBadge',
      desc: '',
      args: [],
    );
  }

  /// `guests`
  String get strGuestsSuffix {
    return Intl.message(
      'guests',
      name: 'strGuestsSuffix',
      desc: '',
      args: [],
    );
  }

  /// `people`
  String get strPersonsSuffix {
    return Intl.message(
      'people',
      name: 'strPersonsSuffix',
      desc: '',
      args: [],
    );
  }

  /// `Search...`
  String get strSearchHint {
    return Intl.message(
      'Search...',
      name: 'strSearchHint',
      desc: '',
      args: [],
    );
  }

  /// `Clear`
  String get strClear {
    return Intl.message(
      'Clear',
      name: 'strClear',
      desc: '',
      args: [],
    );
  }

  /// `Orders`
  String get strOrders {
    return Intl.message(
      'Orders',
      name: 'strOrders',
      desc: '',
      args: [],
    );
  }

  /// `Existing orders`
  String get strExistingOrders {
    return Intl.message(
      'Existing orders',
      name: 'strExistingOrders',
      desc: '',
      args: [],
    );
  }

  /// `Extras`
  String get strExtras {
    return Intl.message(
      'Extras',
      name: 'strExtras',
      desc: '',
      args: [],
    );
  }

  /// `Total:`
  String get strTotalLabel {
    return Intl.message(
      'Total:',
      name: 'strTotalLabel',
      desc: '',
      args: [],
    );
  }

  /// `Payment:`
  String get strPaymentLabel {
    return Intl.message(
      'Payment:',
      name: 'strPaymentLabel',
      desc: '',
      args: [],
    );
  }

  /// `Payment`
  String get strPayment {
    return Intl.message(
      'Payment',
      name: 'strPayment',
      desc: '',
      args: [],
    );
  }

  /// `Add`
  String get strAddItems {
    return Intl.message(
      'Add',
      name: 'strAddItems',
      desc: '',
      args: [],
    );
  }

  /// `Archive`
  String get strArchive {
    return Intl.message(
      'Archive',
      name: 'strArchive',
      desc: '',
      args: [],
    );
  }

  /// `Open bills`
  String get strOpenBills {
    return Intl.message(
      'Open bills',
      name: 'strOpenBills',
      desc: '',
      args: [],
    );
  }

  /// `Currently active`
  String get strNowActive {
    return Intl.message(
      'Currently active',
      name: 'strNowActive',
      desc: '',
      args: [],
    );
  }

  /// `Today's revenue`
  String get strTodayRevenue {
    return Intl.message(
      'Today\'s revenue',
      name: 'strTodayRevenue',
      desc: '',
      args: [],
    );
  }

  /// `sum`
  String get strSom {
    return Intl.message(
      'sum',
      name: 'strSom',
      desc: '',
      args: [],
    );
  }

  /// `Closed today`
  String get strClosedToday {
    return Intl.message(
      'Closed today',
      name: 'strClosedToday',
      desc: '',
      args: [],
    );
  }

  /// `bill`
  String get strBillSuffix {
    return Intl.message(
      'bill',
      name: 'strBillSuffix',
      desc: '',
      args: [],
    );
  }

  /// `Average check`
  String get strAverageCheck {
    return Intl.message(
      'Average check',
      name: 'strAverageCheck',
      desc: '',
      args: [],
    );
  }

  /// `Status`
  String get strStatusColumn {
    return Intl.message(
      'Status',
      name: 'strStatusColumn',
      desc: '',
      args: [],
    );
  }

  /// `Foods`
  String get strFoodsColumn {
    return Intl.message(
      'Foods',
      name: 'strFoodsColumn',
      desc: '',
      args: [],
    );
  }

  /// `Amount`
  String get strAmountColumn {
    return Intl.message(
      'Amount',
      name: 'strAmountColumn',
      desc: '',
      args: [],
    );
  }

  /// `Time`
  String get strTimeColumn {
    return Intl.message(
      'Time',
      name: 'strTimeColumn',
      desc: '',
      args: [],
    );
  }

  /// `Actions`
  String get strActionsColumn {
    return Intl.message(
      'Actions',
      name: 'strActionsColumn',
      desc: '',
      args: [],
    );
  }

  /// `Archive is empty`
  String get strArchiveEmpty {
    return Intl.message(
      'Archive is empty',
      name: 'strArchiveEmpty',
      desc: '',
      args: [],
    );
  }

  /// `Date`
  String get strDate {
    return Intl.message(
      'Date',
      name: 'strDate',
      desc: '',
      args: [],
    );
  }

  /// `All Orders`
  String get strAllOrdersTitle {
    return Intl.message(
      'All Orders',
      name: 'strAllOrdersTitle',
      desc: '',
      args: [],
    );
  }

  /// `Order type`
  String get strOrderType {
    return Intl.message(
      'Order type',
      name: 'strOrderType',
      desc: '',
      args: [],
    );
  }

  /// `Orders not found`
  String get strOrdersEmpty {
    return Intl.message(
      'Orders not found',
      name: 'strOrdersEmpty',
      desc: '',
      args: [],
    );
  }

  /// `Waiter`
  String get strWaiterRole {
    return Intl.message(
      'Waiter',
      name: 'strWaiterRole',
      desc: '',
      args: [],
    );
  }

  /// `Cashier`
  String get strCashierRole {
    return Intl.message(
      'Cashier',
      name: 'strCashierRole',
      desc: '',
      args: [],
    );
  }

  /// `Hall`
  String get strHall {
    return Intl.message(
      'Hall',
      name: 'strHall',
      desc: '',
      args: [],
    );
  }

  /// `Table`
  String get strTableNumber {
    return Intl.message(
      'Table',
      name: 'strTableNumber',
      desc: '',
      args: [],
    );
  }

  /// `Settings`
  String get strSettings {
    return Intl.message(
      'Settings',
      name: 'strSettings',
      desc: '',
      args: [],
    );
  }

  /// `Restaurant staff`
  String get strRestaurantStaff {
    return Intl.message(
      'Restaurant staff',
      name: 'strRestaurantStaff',
      desc: '',
      args: [],
    );
  }

  /// `Staff and roles`
  String get strStaffRoles {
    return Intl.message(
      'Staff and roles',
      name: 'strStaffRoles',
      desc: '',
      args: [],
    );
  }

  /// `Halls`
  String get strHalls {
    return Intl.message(
      'Halls',
      name: 'strHalls',
      desc: '',
      args: [],
    );
  }

  /// `Halls and tables`
  String get strHallsAndTables {
    return Intl.message(
      'Halls and tables',
      name: 'strHallsAndTables',
      desc: '',
      args: [],
    );
  }

  /// `Language and general`
  String get strLanguageAndGeneral {
    return Intl.message(
      'Language and general',
      name: 'strLanguageAndGeneral',
      desc: '',
      args: [],
    );
  }

  /// `Printer settings`
  String get strPrinterSettings {
    return Intl.message(
      'Printer settings',
      name: 'strPrinterSettings',
      desc: '',
      args: [],
    );
  }

  /// `ESC/POS devices`
  String get strEscPosDevices {
    return Intl.message(
      'ESC/POS devices',
      name: 'strEscPosDevices',
      desc: '',
      args: [],
    );
  }

  /// `LAN Network`
  String get strLanNetwork {
    return Intl.message(
      'LAN Network',
      name: 'strLanNetwork',
      desc: '',
      args: [],
    );
  }

  /// `Hub and client settings`
  String get strHubClientSettings {
    return Intl.message(
      'Hub and client settings',
      name: 'strHubClientSettings',
      desc: '',
      args: [],
    );
  }

  /// `Access restricted`
  String get strAccessRestricted {
    return Intl.message(
      'Access restricted',
      name: 'strAccessRestricted',
      desc: '',
      args: [],
    );
  }

  /// `Only administrator or manager can access settings.`
  String get strSettingsAdminOnly {
    return Intl.message(
      'Only administrator or manager can access settings.',
      name: 'strSettingsAdminOnly',
      desc: '',
      args: [],
    );
  }

  /// `Language, interface and menu view`
  String get strInterfaceSettings {
    return Intl.message(
      'Language, interface and menu view',
      name: 'strInterfaceSettings',
      desc: '',
      args: [],
    );
  }

  /// `Interface language`
  String get strInterfaceLanguage {
    return Intl.message(
      'Interface language',
      name: 'strInterfaceLanguage',
      desc: '',
      args: [],
    );
  }

  /// `Applied to all users`
  String get strAppliesToAllUsers {
    return Intl.message(
      'Applied to all users',
      name: 'strAppliesToAllUsers',
      desc: '',
      args: [],
    );
  }

  /// `Menu images`
  String get strMenuImages {
    return Intl.message(
      'Menu images',
      name: 'strMenuImages',
      desc: '',
      args: [],
    );
  }

  /// `Show images in product cards`
  String get strShowProductImages {
    return Intl.message(
      'Show images in product cards',
      name: 'strShowProductImages',
      desc: '',
      args: [],
    );
  }

  /// `O'zbek`
  String get strUzbek {
    return Intl.message(
      'O\'zbek',
      name: 'strUzbek',
      desc: '',
      args: [],
    );
  }

  /// `Русский`
  String get strRussian {
    return Intl.message(
      'Русский',
      name: 'strRussian',
      desc: '',
      args: [],
    );
  }

  /// `Open shift`
  String get strOpenShift {
    return Intl.message(
      'Open shift',
      name: 'strOpenShift',
      desc: '',
      args: [],
    );
  }

  /// `Press the button below to start work.`
  String get strStartWorkInstruction {
    return Intl.message(
      'Press the button below to start work.',
      name: 'strStartWorkInstruction',
      desc: '',
      args: [],
    );
  }

  /// `Close shift`
  String get strCloseShift {
    return Intl.message(
      'Close shift',
      name: 'strCloseShift',
      desc: '',
      args: [],
    );
  }

  /// `Press the button in the bottom right to close the shift.`
  String get strCloseShiftInstruction {
    return Intl.message(
      'Press the button in the bottom right to close the shift.',
      name: 'strCloseShiftInstruction',
      desc: '',
      args: [],
    );
  }

  /// `Shift opened`
  String get strShiftOpened {
    return Intl.message(
      'Shift opened',
      name: 'strShiftOpened',
      desc: '',
      args: [],
    );
  }

  /// `Terminal`
  String get strTerminal {
    return Intl.message(
      'Terminal',
      name: 'strTerminal',
      desc: '',
      args: [],
    );
  }

  /// `Connected`
  String get strConnected {
    return Intl.message(
      'Connected',
      name: 'strConnected',
      desc: '',
      args: [],
    );
  }

  /// `Duration`
  String get strDuration {
    return Intl.message(
      'Duration',
      name: 'strDuration',
      desc: '',
      args: [],
    );
  }

  /// `January`
  String get strJanuary {
    return Intl.message(
      'January',
      name: 'strJanuary',
      desc: '',
      args: [],
    );
  }

  /// `February`
  String get strFebruary {
    return Intl.message(
      'February',
      name: 'strFebruary',
      desc: '',
      args: [],
    );
  }

  /// `March`
  String get strMarch {
    return Intl.message(
      'March',
      name: 'strMarch',
      desc: '',
      args: [],
    );
  }

  /// `April`
  String get strApril {
    return Intl.message(
      'April',
      name: 'strApril',
      desc: '',
      args: [],
    );
  }

  /// `May`
  String get strMay {
    return Intl.message(
      'May',
      name: 'strMay',
      desc: '',
      args: [],
    );
  }

  /// `June`
  String get strJune {
    return Intl.message(
      'June',
      name: 'strJune',
      desc: '',
      args: [],
    );
  }

  /// `July`
  String get strJuly {
    return Intl.message(
      'July',
      name: 'strJuly',
      desc: '',
      args: [],
    );
  }

  /// `August`
  String get strAugust {
    return Intl.message(
      'August',
      name: 'strAugust',
      desc: '',
      args: [],
    );
  }

  /// `September`
  String get strSeptember {
    return Intl.message(
      'September',
      name: 'strSeptember',
      desc: '',
      args: [],
    );
  }

  /// `October`
  String get strOctober {
    return Intl.message(
      'October',
      name: 'strOctober',
      desc: '',
      args: [],
    );
  }

  /// `November`
  String get strNovember {
    return Intl.message(
      'November',
      name: 'strNovember',
      desc: '',
      args: [],
    );
  }

  /// `December`
  String get strDecember {
    return Intl.message(
      'December',
      name: 'strDecember',
      desc: '',
      args: [],
    );
  }

  /// `Monday`
  String get strMonday {
    return Intl.message(
      'Monday',
      name: 'strMonday',
      desc: '',
      args: [],
    );
  }

  /// `Tuesday`
  String get strTuesday {
    return Intl.message(
      'Tuesday',
      name: 'strTuesday',
      desc: '',
      args: [],
    );
  }

  /// `Wednesday`
  String get strWednesday {
    return Intl.message(
      'Wednesday',
      name: 'strWednesday',
      desc: '',
      args: [],
    );
  }

  /// `Thursday`
  String get strThursday {
    return Intl.message(
      'Thursday',
      name: 'strThursday',
      desc: '',
      args: [],
    );
  }

  /// `Friday`
  String get strFriday {
    return Intl.message(
      'Friday',
      name: 'strFriday',
      desc: '',
      args: [],
    );
  }

  /// `Saturday`
  String get strSaturday {
    return Intl.message(
      'Saturday',
      name: 'strSaturday',
      desc: '',
      args: [],
    );
  }

  /// `Sunday`
  String get strSunday {
    return Intl.message(
      'Sunday',
      name: 'strSunday',
      desc: '',
      args: [],
    );
  }

  /// `Print`
  String get strPrint {
    return Intl.message(
      'Print',
      name: 'strPrint',
      desc: '',
      args: [],
    );
  }

  /// `Tables`
  String get strTables {
    return Intl.message(
      'Tables',
      name: 'strTables',
      desc: '',
      args: [],
    );
  }

  /// `Shift`
  String get strShift {
    return Intl.message(
      'Shift',
      name: 'strShift',
      desc: '',
      args: [],
    );
  }

  /// `Menu`
  String get strMenu {
    return Intl.message(
      'Menu',
      name: 'strMenu',
      desc: '',
      args: [],
    );
  }

  /// `Admin`
  String get strRoleAdmin {
    return Intl.message(
      'Admin',
      name: 'strRoleAdmin',
      desc: '',
      args: [],
    );
  }

  /// `Superadmin`
  String get strRoleSuperadmin {
    return Intl.message(
      'Superadmin',
      name: 'strRoleSuperadmin',
      desc: '',
      args: [],
    );
  }

  /// `Manager`
  String get strRoleManager {
    return Intl.message(
      'Manager',
      name: 'strRoleManager',
      desc: '',
      args: [],
    );
  }

  /// `Cashier`
  String get strRoleCashier {
    return Intl.message(
      'Cashier',
      name: 'strRoleCashier',
      desc: '',
      args: [],
    );
  }

  /// `Waiter`
  String get strRoleWaiter {
    return Intl.message(
      'Waiter',
      name: 'strRoleWaiter',
      desc: '',
      args: [],
    );
  }

  /// `Chef`
  String get strRoleChef {
    return Intl.message(
      'Chef',
      name: 'strRoleChef',
      desc: '',
      args: [],
    );
  }

  /// `User`
  String get strRoleUser {
    return Intl.message(
      'User',
      name: 'strRoleUser',
      desc: '',
      args: [],
    );
  }

  /// `Drag`
  String get strDragHint {
    return Intl.message(
      'Drag',
      name: 'strDragHint',
      desc: '',
      args: [],
    );
  }

  /// `Zoom in`
  String get strEnlarge {
    return Intl.message(
      'Zoom in',
      name: 'strEnlarge',
      desc: '',
      args: [],
    );
  }

  /// `Zoom out`
  String get strShrink {
    return Intl.message(
      'Zoom out',
      name: 'strShrink',
      desc: '',
      args: [],
    );
  }

  /// `Re-center`
  String get strRecenter {
    return Intl.message(
      'Re-center',
      name: 'strRecenter',
      desc: '',
      args: [],
    );
  }

  /// `{n} tables`
  String strNPeopleTable(Object n) {
    return Intl.message(
      '$n tables',
      name: 'strNPeopleTable',
      desc: '',
      args: [n],
    );
  }

  /// `Are you sure you want to logout?`
  String get strLogoutConfirm {
    return Intl.message(
      'Are you sure you want to logout?',
      name: 'strLogoutConfirm',
      desc: '',
      args: [],
    );
  }
}

class AppLocalizationDelegate extends LocalizationsDelegate<S> {
  const AppLocalizationDelegate();

  List<Locale> get supportedLocales {
    return const <Locale>[
      Locale.fromSubtags(languageCode: 'en'),
      Locale.fromSubtags(languageCode: 'ru'),
      Locale.fromSubtags(languageCode: 'uz'),
    ];
  }

  @override
  bool isSupported(Locale locale) => _isSupported(locale);
  @override
  Future<S> load(Locale locale) => S.load(locale);
  @override
  bool shouldReload(AppLocalizationDelegate old) => false;

  bool _isSupported(Locale locale) {
    for (var supportedLocale in supportedLocales) {
      if (supportedLocale.languageCode == locale.languageCode) {
        return true;
      }
    }
    return false;
  }
}

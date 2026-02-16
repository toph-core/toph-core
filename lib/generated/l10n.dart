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

  /// `Internet aloqasini tekshiring`
  String get strCheckInternetConnection {
    return Intl.message(
      'Internet aloqasini tekshiring',
      name: 'strCheckInternetConnection',
      desc: '',
      args: [],
    );
  }

  /// `Internet aloqasi yo‘q`
  String get strNoInternetConnection {
    return Intl.message(
      'Internet aloqasi yo‘q',
      name: 'strNoInternetConnection',
      desc: '',
      args: [],
    );
  }

  /// `Ha`
  String get strYes {
    return Intl.message(
      'Ha',
      name: 'strYes',
      desc: '',
      args: [],
    );
  }

  /// `Yo'q`
  String get strNo {
    return Intl.message(
      'Yo\'q',
      name: 'strNo',
      desc: '',
      args: [],
    );
  }

  /// `Ma'lumot topilmadi`
  String get strNoDataFound {
    return Intl.message(
      'Ma\'lumot topilmadi',
      name: 'strNoDataFound',
      desc: '',
      args: [],
    );
  }

  /// `Yangilash uchun pastga torting`
  String get strPullDownToRefresh {
    return Intl.message(
      'Yangilash uchun pastga torting',
      name: 'strPullDownToRefresh',
      desc: '',
      args: [],
    );
  }

  /// `Qo‘yib yuboring — yangilanadi`
  String get strReleaseToRefresh {
    return Intl.message(
      'Qo‘yib yuboring — yangilanadi',
      name: 'strReleaseToRefresh',
      desc: '',
      args: [],
    );
  }

  /// `Ma’lumot yangilanmoqda...`
  String get strRefreshing {
    return Intl.message(
      'Ma’lumot yangilanmoqda...',
      name: 'strRefreshing',
      desc: '',
      args: [],
    );
  }

  /// `Yangilash tugadi`
  String get strRefreshCompleted {
    return Intl.message(
      'Yangilash tugadi',
      name: 'strRefreshCompleted',
      desc: '',
      args: [],
    );
  }

  /// `Yangilash amalga oshmadi`
  String get strRefreshFailed {
    return Intl.message(
      'Yangilash amalga oshmadi',
      name: 'strRefreshFailed',
      desc: '',
      args: [],
    );
  }

  /// `Qayta urinib ko‘rish`
  String get strRetry {
    return Intl.message(
      'Qayta urinib ko‘rish',
      name: 'strRetry',
      desc: '',
      args: [],
    );
  }

  /// `Bu maydon bo‘sh bo‘lishi mumkin emas`
  String get strFieldCannotBeEmpty {
    return Intl.message(
      'Bu maydon bo‘sh bo‘lishi mumkin emas',
      name: 'strFieldCannotBeEmpty',
      desc: '',
      args: [],
    );
  }

  /// `Parol kamida 8 ta belgidan iborat bo‘lishi kerak.`
  String get strPasswordContainAtLeastChars {
    return Intl.message(
      'Parol kamida 8 ta belgidan iborat bo‘lishi kerak.',
      name: 'strPasswordContainAtLeastChars',
      desc: '',
      args: [],
    );
  }

  /// `Noto‘g‘ri raqam`
  String get strInvalidNumber {
    return Intl.message(
      'Noto‘g‘ri raqam',
      name: 'strInvalidNumber',
      desc: '',
      args: [],
    );
  }

  /// `Telefon raqami yoki parol noto‘g‘ri`
  String get strPhoneOrPasswordWrong {
    return Intl.message(
      'Telefon raqami yoki parol noto‘g‘ri',
      name: 'strPhoneOrPasswordWrong',
      desc: '',
      args: [],
    );
  }

  /// `Davom etish`
  String get strContinue {
    return Intl.message(
      'Davom etish',
      name: 'strContinue',
      desc: '',
      args: [],
    );
  }

  /// `Ilova tili`
  String get strAppLanguage {
    return Intl.message(
      'Ilova tili',
      name: 'strAppLanguage',
      desc: '',
      args: [],
    );
  }

  /// `Chiqish`
  String get strLogout {
    return Intl.message(
      'Chiqish',
      name: 'strLogout',
      desc: '',
      args: [],
    );
  }

  /// `Ilovadan chiqishni xohlaysizmi?`
  String get strDoYouWantToLogout {
    return Intl.message(
      'Ilovadan chiqishni xohlaysizmi?',
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

  /// `Passwords are not same`
  String get strPasswordsNotSame {
    return Intl.message(
      'Passwords are not same',
      name: 'strPasswordsNotSame',
      desc: '',
      args: [],
    );
  }

  /// `Brand id ni yozing`
  String get strEnterBrandID {
    return Intl.message(
      'Brand id ni yozing',
      name: 'strEnterBrandID',
      desc: '',
      args: [],
    );
  }

  /// `Parol`
  String get strPassword {
    return Intl.message(
      'Parol',
      name: 'strPassword',
      desc: '',
      args: [],
    );
  }

  /// `Kodni yozing`
  String get strEnterCode {
    return Intl.message(
      'Kodni yozing',
      name: 'strEnterCode',
      desc: '',
      args: [],
    );
  }

  /// `Kirish`
  String get strLogin {
    return Intl.message(
      'Kirish',
      name: 'strLogin',
      desc: '',
      args: [],
    );
  }

  /// `Mahsulotlar topilmadi`
  String get strProductNotFound {
    return Intl.message(
      'Mahsulotlar topilmadi',
      name: 'strProductNotFound',
      desc: '',
      args: [],
    );
  }

  /// `Taomlar kategoriyasi topilmadi!`
  String get strFoodsCategoriesNotFound {
    return Intl.message(
      'Taomlar kategoriyasi topilmadi!',
      name: 'strFoodsCategoriesNotFound',
      desc: '',
      args: [],
    );
  }

  /// `Buyurtmalar yo’q. Qo’shish uchun ovqat ustiga bosing`
  String get strSelectFoodsNotFound {
    return Intl.message(
      'Buyurtmalar yo’q. Qo’shish uchun ovqat ustiga bosing',
      name: 'strSelectFoodsNotFound',
      desc: '',
      args: [],
    );
  }

  /// `Siz rostdan ham buyurtmalarni tozalashni hohlaysizmi?`
  String get strDoYouWantClearOrders {
    return Intl.message(
      'Siz rostdan ham buyurtmalarni tozalashni hohlaysizmi?',
      name: 'strDoYouWantClearOrders',
      desc: '',
      args: [],
    );
  }

  /// `Bekor qilish`
  String get strCancel {
    return Intl.message(
      'Bekor qilish',
      name: 'strCancel',
      desc: '',
      args: [],
    );
  }

  /// `Orgaga qaytish`
  String get strBackToScreen {
    return Intl.message(
      'Orgaga qaytish',
      name: 'strBackToScreen',
      desc: '',
      args: [],
    );
  }

  /// `Rostdan ham chiqmoxchimisiz? Chiqsangiz ovqatlar bekor qilinadi.`
  String get strYouWantLeaveOrderScreen {
    return Intl.message(
      'Rostdan ham chiqmoxchimisiz? Chiqsangiz ovqatlar bekor qilinadi.',
      name: 'strYouWantLeaveOrderScreen',
      desc: '',
      args: [],
    );
  }

  /// `Saqlash`
  String get strSave {
    return Intl.message(
      'Saqlash',
      name: 'strSave',
      desc: '',
      args: [],
    );
  }

  /// `Siz rostdan ham buyurtmani oshxonaga yuborishni hohlaysizmi?`
  String get strDoYouWantSendOrdersToKitchken {
    return Intl.message(
      'Siz rostdan ham buyurtmani oshxonaga yuborishni hohlaysizmi?',
      name: 'strDoYouWantSendOrdersToKitchken',
      desc: '',
      args: [],
    );
  }

  /// `Buyurtma muvafaqqiyatli yaratildi`
  String get strOrderSuccessCreated {
    return Intl.message(
      'Buyurtma muvafaqqiyatli yaratildi',
      name: 'strOrderSuccessCreated',
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

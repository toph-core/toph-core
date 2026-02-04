import 'package:flutter/material.dart';
import 'package:mary_ai_pos/core/theme/tokens/theme_colors.dart';
import 'package:mary_ai_pos/core/theme/tokens/theme_radius.dart';
import 'package:mary_ai_pos/core/theme/tokens/theme_text_style.dart';

class AppTheme {
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,

    fontFamily: 'Inter',

    // 🔹 Main colors
    primaryColor: _lightColors.textBrand,
    scaffoldBackgroundColor: _lightColors.bgDefault,

    // 🔹 Material ColorScheme
    colorScheme: ColorScheme(
      brightness: Brightness.light,
      primary: _lightColors.textBrand,
      onPrimary: _lightColors.textOnBrand,
      secondary: _lightColors.bgSecondary,
      onSecondary: _lightColors.textDefault,
      error: _lightColors.systemError,
      onError: _lightColors.textOnBrand,
      background: _lightColors.bgDefault,
      onBackground: _lightColors.textDefault,
      surface: _lightColors.bgSecondary,
      onSurface: _lightColors.textDefault,
    ),

    // 🔹 AppBar
    appBarTheme: AppBarTheme(
      backgroundColor: _lightColors.bgDefault,
      foregroundColor: _lightColors.textDefault,
      elevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: _lightColors.iconDefault),
      titleTextStyle: _lightTextStyles.headingMd,
    ),

    // 🔹 BottomNavigationBar
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: _lightColors.bgSecondary,
      selectedItemColor: _lightColors.textBrand,
      unselectedItemColor: _lightColors.iconSecondary,
      showUnselectedLabels: true,
    ),

    // 🔹 Buttons
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: _lightColors.textBrand,
        foregroundColor: _lightColors.textOnBrand,
        textStyle: _lightTextStyles.buttonText,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: _lightColors.textBrand,
        textStyle: _lightTextStyles.linkText,
      ),
    ),

    // 🔹 Input (TextField)
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _lightColors.bgSecondary,
      hintStyle: _lightTextStyles.bodySm.copyWith(
        color: _lightColors.textTertiary,
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: _lightColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: _lightColors.textBrand),
        borderRadius: BorderRadius.circular(12),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: _lightColors.systemError),
        borderRadius: BorderRadius.circular(12),
      ),
    ),

    // 🔹 Divider
    dividerTheme: DividerThemeData(color: _lightColors.border, thickness: 1),

    // 🔹 Chip
    chipTheme: ChipThemeData(
      backgroundColor: _lightColors.buttonSecondary,
      selectedColor: _lightColors.textSecondary,
      disabledColor: _lightColors.buttonDisabledBg,
      labelStyle: _lightTextStyles.bodySm,
      secondaryLabelStyle: _lightTextStyles.bodySm,
    ),

    // 🔹 Extensions (custom)
    extensions: <ThemeExtension<dynamic>>[
      _lightColors,
      _lightTextStyles,
      _radius,
    ],
  );

  /// Radiuses
  static const _radius = ThemeRadius(
    buttonSm: BorderRadius.all(Radius.circular(9)),
    buttonMd: BorderRadius.all(Radius.circular(12)),
    buttonLg: BorderRadius.all(Radius.circular(16)),
    buttonXl: BorderRadius.all(Radius.circular(18)),
    cardInner: BorderRadius.all(Radius.circular(14)),
    card: BorderRadius.all(Radius.circular(16)),
    card24: BorderRadius.all(Radius.circular(24)),
    card20: BorderRadius.all(Radius.circular(20)),
    bottomSheet: BorderRadius.vertical(top: Radius.circular(20)),
    topBar: BorderRadius.vertical(bottom: Radius.circular(24)),
    segmentedControl: BorderRadius.all(Radius.circular(100)),
  );

  /// Light colors (JSON based)
  static const _lightColors = ThemeColors(
    textBrand: Color(0xFFFB6633),
    textDefault: Color(0xFF19160B),
    textButtonSecondary: Color(0xFF19160B),
    textSecondary: Color(0xFF888888),
    textTertiary: Color(0xFFAAAAAA),
    textOnBrand: Color(0xFFFFFFFF),
    textOnBrandDark: Color(0xFF09131A),

    iconBrand: Color(0xFFFB6633),
    iconDefault: Color(0xFF19160B),
    iconSecondary: Color(0xFF888888),
    iconButtonSecondary: Color(0xFF19160B),
    iconTertiary: Color(0xFFA0A0A0),
    iconOnBrand: Color(0xFFFFFFFF),
    iconOnBrandDark: Color(0xFF09131A),

    bgBrand: Color(0xFFFB6633),
    bgDefault: Color(0xFFFFFFFF),
    bgSecondary: Color(0xFFF8F9FA),
    bgTritary: Color(0xFFF6F7F9),
    bgDefaultTritary: Color(0xFFF5F5F5),
    bgSecondaryTritary: Color(0xFFFFFFFF),
    bgBottomSheet: Color(0x3309131A),

    borderBrand: Color(0xFFFB6633),
    border: Color(0xFFEBEFF2),

    buttonBrand: Color(0xFF2D2D2D),
    buttonBrandSecondary: Color(0xFFF2F2F4),
    buttonSecondary: Color(0xFFF8F9FA),
    buttonDisabledBg: Color(0xFFF8F9FA),

    systemAccent: Color(0xFFF5A524),
    systemSuccess: Color(0xFF17C964),
    systemError: Color(0xFFEB295B),

    extraPurple: Color(0xFF9470DC),
    extraCyan: Color(0xFF32AACF),
    extraOrange: Color(0xFFCF8506),
  );

  /// Light text styles
  static final _lightTextStyles = ThemeTextStyle(
    fontFamily: "Inter",
    displayXl: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.bold,
      height: 40 / 32,
      color: _lightColors.textDefault,
    ),
    displayLg: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.bold,
      height: 36 / 28,
      color: _lightColors.textDefault,
    ),
    headingMd: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      height: 32 / 24,
      color: _lightColors.textDefault,
    ),
    headingSm: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      height: 28 / 20,
      color: _lightColors.textDefault,
    ),
    bodyLg: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.normal,
      height: 26 / 18,
      color: _lightColors.textSecondary,
    ),
    bodyMd: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.normal,
      height: 24 / 16,
      color: _lightColors.textTertiary,
    ),
    bodySm: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.normal,
      height: 20 / 14,
      color: _lightColors.textSecondary,
    ),
    caption: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.normal,
      height: 16 / 12,
      color: _lightColors.textTertiary,
    ),
    badgeText: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.normal,
      height: 16 / 12,
      color: _lightColors.textOnBrand,
    ),
    buttonText: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      height: 20 / 16,
      color: _lightColors.textOnBrand,
    ),
    linkText: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 20 / 14,
      color: _lightColors.textBrand,
    ),
    bold14: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.bold,
      color: _lightColors.textDefault,
    ),
    bold16: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: _lightColors.textDefault,
    ),
    bold18: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.bold,
      color: _lightColors.textDefault,
    ),
    bold20: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.bold,
      color: _lightColors.textDefault,
    ),
    bold24: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.bold,
      color: _lightColors.textDefault,
    ),
    semibold14: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: _lightColors.textDefault,
    ),
    semibold16: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: _lightColors.textDefault,
    ),
    semibold18: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: _lightColors.textDefault,
    ),
    semibold20: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: _lightColors.textDefault,
    ),
    semibold24: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      color: _lightColors.textDefault,
    ),
  );
}

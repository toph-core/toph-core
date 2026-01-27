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

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'Montserrat',
    primaryColor: _darkColors.textBrand,
    scaffoldBackgroundColor: _darkColors.bgDefault,
    colorScheme: ColorScheme(
      brightness: Brightness.dark,
      primary: _darkColors.textBrand,
      onPrimary: _darkColors.textOnBrand,
      secondary: _darkColors.bgSecondary,
      onSecondary: _darkColors.textDefault,
      error: _darkColors.systemError,
      onError: _darkColors.textOnBrand,
      background: _darkColors.bgDefault,
      onBackground: _darkColors.textDefault,
      surface: _darkColors.bgSecondary,
      onSurface: _darkColors.textDefault,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: _darkColors.bgSecondary,
      foregroundColor: _darkColors.textDefault,
      elevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: _darkColors.iconDefault),
      titleTextStyle: _darkTextStyles.headingMd,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: _darkColors.bgSecondary,
      selectedItemColor: _darkColors.textBrand,
      unselectedItemColor: _darkColors.iconSecondary,
      showUnselectedLabels: true,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: _darkColors.textBrand,
        foregroundColor: _darkColors.textOnBrand,
        textStyle: _darkTextStyles.buttonText,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: _darkColors.textBrand,
        textStyle: _darkTextStyles.linkText,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _darkColors.bgSecondary,
      hintStyle: _darkTextStyles.bodySm.copyWith(
        color: _darkColors.textTertiary,
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: _darkColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: _darkColors.textBrand),
        borderRadius: BorderRadius.circular(12),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: _darkColors.systemError),
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    dividerTheme: DividerThemeData(color: _darkColors.border, thickness: 1),
    chipTheme: ChipThemeData(
      backgroundColor: _darkColors.buttonSecondary,
      selectedColor: _darkColors.textSecondary,
      disabledColor: _darkColors.buttonDisabledBg,
      labelStyle: _darkTextStyles.bodySm,
      secondaryLabelStyle: _darkTextStyles.bodySm,
    ),
    extensions: <ThemeExtension<dynamic>>[
      _darkColors,
      _darkTextStyles,
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
    textBrand: Color(0xFF2529D8),
    textDefault: Color(0xFF000000),
    textButtonSecondary: Color(0xFF000000),
    textSecondary: Color(0xFF888888),
    textTertiary: Color(0xFFAAAAAA),
    textOnBrand: Color(0xFFFFFFFF),
    textOnBrandDark: Color(0xFF09131A),

    iconBrand: Color(0xFF2529D8),
    iconDefault: Color(0xFF000000),
    iconSecondary: Color(0xFF888888),
    iconButtonSecondary: Color(0xFF000000),
    iconTertiary: Color(0xFFA0A0A0),
    iconOnBrand: Color(0xFFFFFFFF),
    iconOnBrandDark: Color(0xFF09131A),

    bgBrand: Color(0xFF2529D8),
    bgDefault: Color(0xFFFFFFFF),
    bgSecondary: Color(0xFFF8F9FA),
    bgTritary: Color(0xFFEBEBEB),
    bgDefaultTritary: Color(0xFFF5F5F5),
    bgSecondaryTritary: Color(0xFFFFFFFF),
    bgBottomSheet: Color(0x3309131A),

    borderBrand: Color(0xFF2529D8),
    border: Color(0xFFEBEFF2),

    buttonBrand: Color(0xFF2529D8),
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

  /// Dark colors (JSON based)
  static const _darkColors = ThemeColors(
    textBrand: Color(0xFF2529D8),
    textDefault: Color(0xFFEDEDED),
    textButtonSecondary: Color(0xFFEDEDED),
    textSecondary: Color(0xFFB0B0B0),
    textTertiary: Color(0xFF888888),
    textOnBrand: Color(0xFFFFFFFF),
    textOnBrandDark: Color(0xFFE8EEFF),

    iconBrand: Color(0xFF2529D8),
    iconDefault: Color(0xFFEDEDED),
    iconSecondary: Color(0xFFB0B0B0),
    iconButtonSecondary: Color(0xFFEDEDED),
    iconTertiary: Color(0xFF888888),
    iconOnBrand: Color(0xFFFFFFFF),
    iconOnBrandDark: Color(0xFFE8EEFF),

    bgBrand: Color(0xFF2529D8),
    bgDefault: Color(0xFF0F1115),
    bgSecondary: Color(0xFF1A1D22),
    bgTritary: Color(0xFF222529),
    bgDefaultTritary: Color(0xFF1E2025),
    bgSecondaryTritary: Color(0xFF17191E),
    bgBottomSheet: Color(0xCC0F1115),

    borderBrand: Color(0xFF2529D8),
    border: Color(0xFF33363A),

    buttonBrand: Color(0xFF2529D8),
    buttonBrandSecondary: Color(0xFF2A2D6B),
    buttonSecondary: Color(0xFF2A2E35),
    buttonDisabledBg: Color(0xFF222529),

    systemAccent: Color(0xFFFFC046),
    systemSuccess: Color(0xFF4CAF50),
    systemError: Color(0xFFF44336),

    extraPurple: Color(0xFFBA9BF8),
    extraCyan: Color(0xFF4FC3F7),
    extraOrange: Color(0xFFFFB74D),
  );

  /// Light text styles
  static final _lightTextStyles = ThemeTextStyle(
    fontFamily: "Montserrat",
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

  /// Dark text styles
  static final _darkTextStyles = ThemeTextStyle(
    fontFamily: "Montserrat",
    displayXl: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.bold,
      height: 40 / 32,
      color: _darkColors.textDefault,
    ),
    displayLg: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.bold,
      height: 36 / 28,
      color: _darkColors.textDefault,
    ),
    headingMd: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      height: 32 / 24,
      color: _darkColors.textDefault,
    ),
    headingSm: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      height: 28 / 20,
      color: _darkColors.textDefault,
    ),
    bodyLg: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.normal,
      height: 26 / 18,
      color: _darkColors.textSecondary,
    ),
    bodyMd: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.normal,
      height: 24 / 16,
      color: _darkColors.textTertiary,
    ),
    bodySm: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.normal,
      height: 20 / 14,
      color: _darkColors.textSecondary,
    ),
    caption: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.normal,
      height: 16 / 12,
      color: _darkColors.textTertiary,
    ),
    badgeText: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.normal,
      height: 16 / 12,
      color: _darkColors.textOnBrand,
    ),
    buttonText: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      height: 20 / 16,
      color: _darkColors.textOnBrand,
    ),
    linkText: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 20 / 14,
      color: _darkColors.textBrand,
    ),
    bold14: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.bold,
      color: _darkColors.textDefault,
    ),
    bold16: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: _darkColors.textDefault,
    ),
    bold18: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.bold,
      color: _darkColors.textDefault,
    ),
    bold20: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.bold,
      color: _darkColors.textDefault,
    ),
    bold24: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.bold,
      color: _darkColors.textDefault,
    ),
    semibold14: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: _darkColors.textDefault,
    ),
    semibold16: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: _darkColors.textDefault,
    ),
    semibold18: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: _darkColors.textDefault,
    ),
    semibold20: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: _darkColors.textDefault,
    ),
    semibold24: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      color: _darkColors.textDefault,
    ),
  );
}

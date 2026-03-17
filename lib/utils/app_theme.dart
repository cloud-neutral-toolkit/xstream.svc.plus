import 'package:flutter/material.dart';

// ──────────────────────────────────────────────────────────────────
// Semantic color tokens – used throughout the app for consistent
// light/dark mode contrast.  Never hard-code raw hex colors in
// widget code; always pull from Theme.of(context) or these tokens.
// ──────────────────────────────────────────────────────────────────

class AppColors {
  AppColors._();

  // Brand accent
  static const Color brand = Color(0xFF5C6BC0);
  static const Color brandLight = Color(0xFF7986CB);
  static const Color brandDark = Color(0xFF9FA8DA);

  // Status semantics – must pass WCAG AA (4.5:1) on both surfaces
  static const Color success = Color(0xFF3E8F5A);
  static const Color successDark = Color(0xFF5CB978);
  static const Color warning = Color(0xFFBF8A3A);
  static const Color warningDark = Color(0xFFE0AE5A);
  static const Color error = Color(0xFFC3655C);
  static const Color errorDark = Color(0xFFEF9A9A);

  // Metric accent colors
  static const Color download = Color(0xFF5B8DEF);
  static const Color downloadDark = Color(0xFF82AAFF);
  static const Color upload = Color(0xFFDA6A87);
  static const Color uploadDark = Color(0xFFEF9AAF);
}

/// Theme extension to expose extra semantic colors through the theme.
@immutable
class XStreamColors extends ThemeExtension<XStreamColors> {
  const XStreamColors({
    required this.brand,
    required this.success,
    required this.warning,
    required this.error,
    required this.download,
    required this.upload,
    required this.cardBackground,
    required this.cardBorder,
    required this.mutedText,
    required this.subtleText,
    required this.warningBannerBackground,
    required this.warningBannerBorder,
    required this.warningBannerText,
  });

  final Color brand;
  final Color success;
  final Color warning;
  final Color error;
  final Color download;
  final Color upload;
  final Color cardBackground;
  final Color cardBorder;
  final Color mutedText;
  final Color subtleText;
  final Color warningBannerBackground;
  final Color warningBannerBorder;
  final Color warningBannerText;

  static const light = XStreamColors(
    brand: AppColors.brand,
    success: AppColors.success,
    warning: AppColors.warning,
    error: AppColors.error,
    download: AppColors.download,
    upload: AppColors.upload,
    cardBackground: Color(0xFFF3F4F6),
    cardBorder: Color(0xFFE9EBEF),
    mutedText: Color(0xFF667085),
    subtleText: Color(0xFF98A1B2),
    warningBannerBackground: Color(0xFFFFF3CD),
    warningBannerBorder: Color(0xFFFFE69C),
    warningBannerText: Color(0xFF664D03),
  );

  static const dark = XStreamColors(
    brand: AppColors.brandDark,
    success: AppColors.successDark,
    warning: AppColors.warningDark,
    error: AppColors.errorDark,
    download: AppColors.downloadDark,
    upload: AppColors.uploadDark,
    cardBackground: Color(0xFF1E1E2E),
    cardBorder: Color(0xFF383850),
    mutedText: Color(0xFFB0B8C8),
    subtleText: Color(0xFF8B95A8),
    warningBannerBackground: Color(0xFF3D3520),
    warningBannerBorder: Color(0xFF5C5030),
    warningBannerText: Color(0xFFFFE082),
  );

  @override
  XStreamColors copyWith({
    Color? brand,
    Color? success,
    Color? warning,
    Color? error,
    Color? download,
    Color? upload,
    Color? cardBackground,
    Color? cardBorder,
    Color? mutedText,
    Color? subtleText,
    Color? warningBannerBackground,
    Color? warningBannerBorder,
    Color? warningBannerText,
  }) {
    return XStreamColors(
      brand: brand ?? this.brand,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      download: download ?? this.download,
      upload: upload ?? this.upload,
      cardBackground: cardBackground ?? this.cardBackground,
      cardBorder: cardBorder ?? this.cardBorder,
      mutedText: mutedText ?? this.mutedText,
      subtleText: subtleText ?? this.subtleText,
      warningBannerBackground:
          warningBannerBackground ?? this.warningBannerBackground,
      warningBannerBorder: warningBannerBorder ?? this.warningBannerBorder,
      warningBannerText: warningBannerText ?? this.warningBannerText,
    );
  }

  @override
  XStreamColors lerp(XStreamColors? other, double t) {
    if (other is! XStreamColors) return this;
    return XStreamColors(
      brand: Color.lerp(brand, other.brand, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      download: Color.lerp(download, other.download, t)!,
      upload: Color.lerp(upload, other.upload, t)!,
      cardBackground: Color.lerp(cardBackground, other.cardBackground, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
      subtleText: Color.lerp(subtleText, other.subtleText, t)!,
      warningBannerBackground: Color.lerp(
          warningBannerBackground, other.warningBannerBackground, t)!,
      warningBannerBorder:
          Color.lerp(warningBannerBorder, other.warningBannerBorder, t)!,
      warningBannerText:
          Color.lerp(warningBannerText, other.warningBannerText, t)!,
    );
  }
}

/// Convenience extension so any widget can use `context.xColors`.
extension XStreamThemeContext on BuildContext {
  XStreamColors get xColors =>
      Theme.of(this).extension<XStreamColors>() ?? XStreamColors.light;
}

class AppTheme {
  AppTheme._();

  // ── Light ColorScheme ─────────────────────────────────────────
  static const _lightColorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.brand,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFE8EAF6),
    onPrimaryContainer: Color(0xFF1A237E),
    secondary: Color(0xFF5B8DEF),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFD6E4FF),
    onSecondaryContainer: Color(0xFF1A3A6B),
    surface: Colors.white,
    onSurface: Color(0xFF1C1B1F),
    onSurfaceVariant: Color(0xFF49454F),
    error: Color(0xFFB3261E),
    onError: Colors.white,
    outline: Color(0xFF79747E),
    outlineVariant: Color(0xFFCAC4D0),
    shadow: Color(0x1A000000),
  );

  // ── Dark ColorScheme ──────────────────────────────────────────
  static const _darkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.brandDark,
    onPrimary: Color(0xFF1A237E),
    primaryContainer: Color(0xFF3949AB),
    onPrimaryContainer: Color(0xFFE8EAF6),
    secondary: AppColors.downloadDark,
    onSecondary: Color(0xFF0D2147),
    secondaryContainer: Color(0xFF1A3A6B),
    onSecondaryContainer: Color(0xFFD6E4FF),
    surface: Color(0xFF141422),
    onSurface: Color(0xFFE6E1E5),
    onSurfaceVariant: Color(0xFFCAC4D0),
    error: Color(0xFFF2B8B5),
    onError: Color(0xFF601410),
    outline: Color(0xFF938F99),
    outlineVariant: Color(0xFF49454F),
    shadow: Color(0x40000000),
  );

  // ── Shared InputDecorationTheme ───────────────────────────────
  static InputDecorationTheme _inputDecoration(ColorScheme cs) {
    return InputDecorationTheme(
      filled: true,
      fillColor: cs.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.primary, width: 2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      labelStyle: TextStyle(color: cs.onSurfaceVariant),
      hintStyle: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
      prefixIconColor: cs.onSurfaceVariant,
    );
  }

  // ── Shared DialogTheme ────────────────────────────────────────
  static DialogThemeData _dialogTheme(ColorScheme cs) {
    return DialogThemeData(
      backgroundColor: cs.surface,
      surfaceTintColor: cs.surfaceTint,
      titleTextStyle: TextStyle(
        color: cs.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: TextStyle(color: cs.onSurface, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  // ── Shared AppBarTheme ────────────────────────────────────────
  static AppBarTheme _appBarTheme(ColorScheme cs) {
    return AppBarTheme(
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      surfaceTintColor: cs.surfaceTint,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: cs.onSurface,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(color: cs.onSurfaceVariant),
    );
  }

  // ── Shared NavigationRailTheme ────────────────────────────────
  static NavigationRailThemeData _navigationRailTheme(ColorScheme cs) {
    return NavigationRailThemeData(
      backgroundColor: cs.surface,
      selectedIconTheme: IconThemeData(color: cs.primary),
      unselectedIconTheme: IconThemeData(color: cs.onSurfaceVariant),
      selectedLabelTextStyle: TextStyle(
        color: cs.primary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: TextStyle(
        color: cs.onSurfaceVariant,
        fontSize: 12,
      ),
    );
  }

  // ── Shared CardTheme ──────────────────────────────────────────
  static CardThemeData _cardTheme(ColorScheme cs) {
    return CardThemeData(
      color: cs.surface,
      surfaceTintColor: cs.surfaceTint,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  // ── Shared SnackBarTheme ──────────────────────────────────────
  static SnackBarThemeData _snackBarTheme(ColorScheme cs) {
    return SnackBarThemeData(
      backgroundColor: cs.inverseSurface,
      contentTextStyle: TextStyle(color: cs.onInverseSurface),
    );
  }

  // ── Shared PopupMenuTheme ─────────────────────────────────────
  static PopupMenuThemeData _popupMenuTheme(ColorScheme cs) {
    return PopupMenuThemeData(
      color: cs.surface,
      surfaceTintColor: cs.surfaceTint,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: TextStyle(
        fontSize: 15,
        color: cs.onSurface,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  // ── Shared ElevatedButtonTheme ────────────────────────────────
  static ElevatedButtonThemeData _elevatedButtonTheme(ColorScheme cs) {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── Shared SwitchListTileTheme ────────────────────────────────
  static ListTileThemeData _listTileTheme(ColorScheme cs) {
    return ListTileThemeData(
      textColor: cs.onSurface,
      iconColor: cs.onSurfaceVariant,
      subtitleTextStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
    );
  }

  // ── LIGHT THEME ───────────────────────────────────────────────
  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: _lightColorScheme,
    scaffoldBackgroundColor: _lightColorScheme.surface,
    appBarTheme: _appBarTheme(_lightColorScheme),
    inputDecorationTheme: _inputDecoration(_lightColorScheme),
    dialogTheme: _dialogTheme(_lightColorScheme),
    navigationRailTheme: _navigationRailTheme(_lightColorScheme),
    cardTheme: _cardTheme(_lightColorScheme),
    snackBarTheme: _snackBarTheme(_lightColorScheme),
    popupMenuTheme: _popupMenuTheme(_lightColorScheme),
    elevatedButtonTheme: _elevatedButtonTheme(_lightColorScheme),
    listTileTheme: _listTileTheme(_lightColorScheme),
    dividerTheme: DividerThemeData(
      color: _lightColorScheme.outlineVariant,
      thickness: 1,
    ),
    extensions: const <ThemeExtension<dynamic>>[XStreamColors.light],
  );

  // ── DARK THEME ────────────────────────────────────────────────
  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: _darkColorScheme,
    scaffoldBackgroundColor: _darkColorScheme.surface,
    appBarTheme: _appBarTheme(_darkColorScheme),
    inputDecorationTheme: _inputDecoration(_darkColorScheme),
    dialogTheme: _dialogTheme(_darkColorScheme),
    navigationRailTheme: _navigationRailTheme(_darkColorScheme),
    cardTheme: _cardTheme(_darkColorScheme),
    snackBarTheme: _snackBarTheme(_darkColorScheme),
    popupMenuTheme: _popupMenuTheme(_darkColorScheme),
    elevatedButtonTheme: _elevatedButtonTheme(_darkColorScheme),
    listTileTheme: _listTileTheme(_darkColorScheme),
    dividerTheme: DividerThemeData(
      color: _darkColorScheme.outlineVariant,
      thickness: 1,
    ),
    extensions: const <ThemeExtension<dynamic>>[XStreamColors.dark],
  );
}

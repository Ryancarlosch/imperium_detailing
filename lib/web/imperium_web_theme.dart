import 'package:flutter/material.dart';

import '../config/app_branding.dart';

class ImperiumWebTheme {
  ImperiumWebTheme._();

  static const Color background = AppBranding.webBackground;
  static const Color surface = AppBranding.webSurface;
  static const Color surfaceRaised = AppBranding.webSurfaceRaised;
  static const Color border = AppBranding.webBorder;
  static const Color accent = AppBranding.webAccent;
  static const Color accentStrong = AppBranding.webAccentStrong;

  static ThemeData dark() {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
          surface: surface,
        ).copyWith(
          primary: accentStrong,
          onPrimary: const Color(0xFF261B00),
          secondary: const Color(0xFF9BB7FF),
          surface: surface,
          onSurface: const Color(0xFFF4F6F8),
          outline: border,
          outlineVariant: const Color(0xFF20262E),
        );

    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
    );

    final radius = BorderRadius.circular(14);

    return base.copyWith(
      canvasColor: background,
      dividerColor: border,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Color(0xFFF4F6F8),
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: const BorderSide(color: border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceRaised,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: const BorderSide(color: accentStrong, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: const BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: const Color(0xFFB7C0CA),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selectedColor: accentStrong,
        selectedTileColor: accentStrong.withValues(alpha: 0.10),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF252C34),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(color: Colors.white),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceRaised,
        contentTextStyle: const TextStyle(color: Color(0xFFF4F6F8)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accentStrong,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accentStrong,
        selectionColor: accentStrong.withValues(alpha: 0.28),
        selectionHandleColor: accentStrong,
      ),
    );
  }
}

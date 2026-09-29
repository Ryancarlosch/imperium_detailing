import 'package:flutter/material.dart';

import '../config/app_branding.dart';

/// Design system do workspace Web.
///
/// Mantém a identidade Imperium centralizada e evita estilos divergentes entre
/// os módulos. Regras de negócio e serviços Cloud não devem depender deste
/// arquivo.
class ImperiumWebTheme {
  ImperiumWebTheme._();

  static const Color background = AppBranding.webBackground;
  static const Color surface = AppBranding.webSurface;
  static const Color surfaceRaised = AppBranding.webSurfaceRaised;
  static const Color border = AppBranding.webBorder;
  static const Color accent = AppBranding.webAccent;
  static const Color accentStrong = AppBranding.webAccentStrong;

  static const Color textPrimary = Color(0xFFF7F8FA);
  static const Color textSecondary = Color(0xFFADB6C0);
  static const Color textMuted = Color(0xFF7F8A96);
  static const Color surfaceSoft = Color(0xFF14191F);
  static const Color hover = Color(0xFF1C222A);
  static const Color success = Color(0xFF58C58B);
  static const Color warning = Color(0xFFF0B84A);
  static const Color danger = Color(0xFFFF7474);

  static const double contentMaxWidth = 1680;
  static const double sidebarWidth = 276;
  static const double radiusSmall = 10;
  static const double radius = 14;
  static const double radiusLarge = 18;

  static ThemeData dark() {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
          surface: surface,
        ).copyWith(
          primary: accentStrong,
          onPrimary: const Color(0xFF241A00),
          secondary: const Color(0xFFB8C9FF),
          onSecondary: const Color(0xFF0B1020),
          surface: surface,
          onSurface: textPrimary,
          error: danger,
          outline: border,
          outlineVariant: const Color(0xFF202730),
        );

    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      visualDensity: VisualDensity.standard,
    );

    final mediumRadius = BorderRadius.circular(radius);
    final smallRadius = BorderRadius.circular(radiusSmall);

    final textTheme = base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        color: textPrimary,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.1,
      ),
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        color: textPrimary,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        color: textPrimary,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        color: textPrimary,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.35,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        color: textPrimary,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        color: textPrimary,
        fontWeight: FontWeight.w700,
      ),
      titleSmall: base.textTheme.titleSmall?.copyWith(
        color: textPrimary,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(
        color: textPrimary,
        height: 1.45,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        color: textSecondary,
        height: 1.42,
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        color: textMuted,
        height: 1.35,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.05,
      ),
    );

    return base.copyWith(
      textTheme: textTheme,
      canvasColor: background,
      dividerColor: border,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: textPrimary,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          side: const BorderSide(color: border),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 18,
        backgroundColor: surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          side: const BorderSide(color: border),
        ),
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
        hintStyle: const TextStyle(color: textMuted),
        labelStyle: const TextStyle(color: textSecondary),
        floatingLabelStyle: const TextStyle(
          color: accentStrong,
          fontWeight: FontWeight.w700,
        ),
        border: OutlineInputBorder(
          borderRadius: mediumRadius,
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: mediumRadius,
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: mediumRadius,
          borderSide: const BorderSide(color: accentStrong, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: mediumRadius,
          borderSide: const BorderSide(color: danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: mediumRadius,
          borderSide: const BorderSide(color: danger, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          foregroundColor: const Color(0xFF241A00),
          backgroundColor: accentStrong,
          disabledBackgroundColor: border,
          disabledForegroundColor: textMuted,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: mediumRadius),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          foregroundColor: textPrimary,
          side: const BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: mediumRadius),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentStrong,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: smallRadius),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: textSecondary,
          highlightColor: accentStrong.withValues(alpha: 0.08),
          shape: RoundedRectangleBorder(borderRadius: smallRadius),
        ),
      ),
      listTileTheme: ListTileThemeData(
        dense: true,
        minTileHeight: 46,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        iconColor: textSecondary,
        textColor: textSecondary,
        shape: RoundedRectangleBorder(borderRadius: smallRadius),
        selectedColor: accentStrong,
        selectedTileColor: accentStrong.withValues(alpha: 0.10),
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        iconColor: textSecondary,
        collapsedIconColor: textMuted,
        textColor: textPrimary,
        collapsedTextColor: textSecondary,
        shape: Border(),
        collapsedShape: Border(),
        tilePadding: EdgeInsets.symmetric(horizontal: 12),
      ),
      popupMenuTheme: PopupMenuThemeData(
        elevation: 12,
        color: surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: mediumRadius,
          side: const BorderSide(color: border),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(surfaceRaised),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: mediumRadius,
              side: const BorderSide(color: border),
            ),
          ),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: const WidgetStatePropertyAll(surfaceSoft),
        dataRowColor: const WidgetStatePropertyAll(surface),
        headingTextStyle: const TextStyle(
          color: textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
        dataTextStyle: const TextStyle(color: textPrimary, fontSize: 13),
        dividerThickness: 1,
        decoration: BoxDecoration(
          border: Border.all(color: border),
          borderRadius: mediumRadius,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surfaceRaised,
        selectedColor: accentStrong.withValues(alpha: 0.14),
        disabledColor: surfaceSoft,
        side: const BorderSide(color: border),
        labelStyle: const TextStyle(
          color: textSecondary,
          fontWeight: FontWeight.w700,
        ),
        secondaryLabelStyle: const TextStyle(
          color: accentStrong,
          fontWeight: FontWeight.w800,
        ),
        shape: RoundedRectangleBorder(borderRadius: smallRadius),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accentStrong
              : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(Color(0xFF241A00)),
        side: const BorderSide(color: textMuted),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? const Color(0xFF241A00)
              : textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accentStrong
              : surfaceRaised,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(border),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        decoration: BoxDecoration(
          color: const Color(0xFF252C34),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceRaised,
        contentTextStyle: const TextStyle(color: textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: border),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accentStrong,
        linearTrackColor: surfaceRaised,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accentStrong,
        selectionColor: accentStrong.withValues(alpha: 0.28),
        selectionHandleColor: accentStrong,
      ),
    );
  }
}

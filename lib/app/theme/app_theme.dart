import 'package:flutter/material.dart';

import 'palette.dart';
import 'status_colors.dart';

export 'palette.dart';
export 'status_colors.dart';

/// Couleurs de marque (cahier des charges § 5.2).
abstract final class AppColors {
  static const primary = Color(0xFF176B4D);
  static const secondary = Color(0xFF2E8B62);
  static const text = Color(0xFF18211D);
  static const textSecondary = Color(0xFF66736C);
}

const _fontFamily = 'Manrope';

ThemeData buildLightTheme() {
  const palette = AppPalette.light;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
      ).copyWith(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        primaryContainer: const Color(0xFFDCEFE5),
        onPrimaryContainer: const Color(0xFF0B3D2B),
        // #2E8B62 n'atteint que 4,2:1 avec du texte blanc : réservé aux
        // éléments sans texte (anneaux et barres de progression).
        secondary: AppColors.secondary,
        onSecondary: Colors.white,
        surface: palette.background,
        onSurface: AppColors.text,
        onSurfaceVariant: AppColors.textSecondary,
        surfaceContainerLowest: palette.card,
        surfaceContainerLow: palette.card,
        surfaceContainer: palette.muted,
        surfaceContainerHigh: const Color(0xFFE6EBE8),
        surfaceContainerHighest: const Color(0xFFDDE3E0),
        outline: const Color(0xFF7C8781),
        outlineVariant: palette.hairline,
        error: const Color(0xFFB3261E),
        inverseSurface: const Color(0xFF1C2420),
        onInverseSurface: const Color(0xFFF0F4F2),
        inversePrimary: const Color(0xFF7FD3AC),
      );
  return _buildTheme(scheme, palette, StatusColors.light);
}

ThemeData buildDarkTheme() {
  const palette = AppPalette.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.dark,
      ).copyWith(
        primary: const Color(0xFF6FCBA0),
        onPrimary: const Color(0xFF00301E),
        primaryContainer: const Color(0xFF1E3B2E),
        onPrimaryContainer: const Color(0xFFBDEBD3),
        secondary: const Color(0xFF4FB386),
        surface: palette.background,
        onSurface: const Color(0xFFE6ECE9),
        onSurfaceVariant: const Color(0xFFA4B0AA),
        surfaceContainerLowest: palette.card,
        surfaceContainerLow: palette.card,
        surfaceContainer: palette.muted,
        surfaceContainerHigh: const Color(0xFF26302B),
        surfaceContainerHighest: const Color(0xFF2E3833),
        outline: const Color(0xFF8A968F),
        outlineVariant: palette.hairline,
        error: const Color(0xFFF2B8B5),
        inverseSurface: const Color(0xFFE6ECE9),
        onInverseSurface: const Color(0xFF1C2420),
      );
  return _buildTheme(scheme, palette, StatusColors.dark);
}

TextTheme _textTheme(Color ink, Color muted) {
  TextStyle s(double size, FontWeight weight, {double? height, double? ls}) =>
      TextStyle(
        fontFamily: _fontFamily,
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: ls,
        color: ink,
      );
  return TextTheme(
    displayMedium: s(44, FontWeight.w800, height: 1.05, ls: -1.2),
    displaySmall: s(34, FontWeight.w800, height: 1.1, ls: -0.8),
    headlineLarge: s(30, FontWeight.w800, height: 1.15, ls: -0.6),
    headlineMedium: s(26, FontWeight.w800, height: 1.2, ls: -0.5),
    headlineSmall: s(22, FontWeight.w700, height: 1.25, ls: -0.3),
    titleLarge: s(19, FontWeight.w700, height: 1.3, ls: -0.2),
    titleMedium: s(16, FontWeight.w700, height: 1.35, ls: -0.1),
    titleSmall: s(14.5, FontWeight.w700, height: 1.35),
    bodyLarge: s(16, FontWeight.w500, height: 1.45, ls: -0.1),
    bodyMedium: s(14.5, FontWeight.w500, height: 1.45, ls: -0.05),
    bodySmall: s(13, FontWeight.w500, height: 1.4).copyWith(color: muted),
    labelLarge: s(15, FontWeight.w700, height: 1.2),
    labelMedium: s(12.5, FontWeight.w700, height: 1.2),
    labelSmall: s(11.5, FontWeight.w700, height: 1.2, ls: 0.2),
  );
}

ThemeData _buildTheme(
  ColorScheme scheme,
  AppPalette palette,
  StatusColors statusColors,
) {
  final text = _textTheme(scheme.onSurface, scheme.onSurfaceVariant);
  const pill = StadiumBorder();
  final fieldRadius = BorderRadius.circular(14);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: _fontFamily,
    textTheme: text,
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    extensions: [palette, statusColors],
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        // Geste « retour » prédictif d'Android 14+, fondu enchaîné sinon.
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 4,
      titleTextStyle: text.titleMedium?.copyWith(fontSize: 17),
    ),
    iconTheme: IconThemeData(color: scheme.onSurface, size: 22),
    dividerTheme: DividerThemeData(
      color: palette.hairline,
      thickness: 1,
      space: 1,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: palette.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      minVerticalPadding: 12,
      horizontalTitleGap: 14,
      titleTextStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      subtitleTextStyle: text.bodySmall,
      iconColor: scheme.onSurfaceVariant,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.muted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      floatingLabelStyle: text.bodyMedium?.copyWith(
        color: scheme.primary,
        fontWeight: FontWeight.w700,
      ),
      hintStyle: text.bodyMedium?.copyWith(color: palette.placeholder),
      helperStyle: text.bodySmall,
      helperMaxLines: 3,
      errorMaxLines: 3,
      prefixIconColor: scheme.onSurfaceVariant,
      suffixIconColor: scheme.onSurfaceVariant,
      border: OutlineInputBorder(
        borderRadius: fieldRadius,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: fieldRadius,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: fieldRadius,
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: fieldRadius,
        borderSide: BorderSide(color: scheme.error, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: fieldRadius,
        borderSide: BorderSide(color: scheme.error, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: pill,
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: pill,
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: palette.hairlineStrong),
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 44),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: pill,
        textStyle: text.labelLarge?.copyWith(fontSize: 14),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
      focusElevation: 2,
      hoverElevation: 3,
      highlightElevation: 3,
      shape: pill,
      extendedTextStyle: text.labelLarge,
      extendedPadding: const EdgeInsets.symmetric(horizontal: 22),
    ),
    chipTheme: ChipThemeData(
      shape: pill,
      side: BorderSide.none,
      backgroundColor: palette.muted,
      selectedColor: scheme.onSurface,
      labelStyle: text.labelMedium?.copyWith(fontSize: 13.5),
      secondaryLabelStyle: text.labelMedium?.copyWith(
        fontSize: 13.5,
        color: scheme.surface,
      ),
      checkmarkColor: scheme.surface,
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 70,
      elevation: 0,
      backgroundColor: palette.card,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primaryContainer,
      indicatorShape: pill,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => text.labelSmall?.copyWith(
          fontSize: 12,
          color: states.contains(WidgetState.selected)
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected)
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbIcon: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? const Icon(Icons.check_rounded, size: 16)
            : null,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      side: BorderSide(color: scheme.outline, width: 1.6),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.card,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: palette.hairlineStrong,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: palette.card,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: text.bodyMedium,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: text.bodyMedium?.copyWith(
        color: scheme.onInverseSurface,
        fontWeight: FontWeight.w600,
      ),
      actionTextColor: scheme.inversePrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: palette.muted,
      circularTrackColor: palette.muted,
    ),
    tabBarTheme: TabBarThemeData(
      labelStyle: text.labelLarge?.copyWith(fontSize: 14),
      unselectedLabelStyle: text.labelLarge?.copyWith(fontSize: 14),
      dividerColor: palette.hairline,
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: palette.card,
      surfaceTintColor: Colors.transparent,
      headerHeadlineStyle: text.headlineSmall,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
    ),
  );
}

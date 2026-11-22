import 'package:flutter/material.dart';

import 'package:immich_mobile/constants/locales.dart';
import 'package:immich_ui/immich_ui.dart';

class ImmichTheme {
  final ColorScheme light;
  final ColorScheme dark;

  const ImmichTheme({required this.light, required this.dark});
}

ThemeData getThemeData({required ColorScheme colorScheme, required Locale locale}) {
  final fontFamily = _getFontFamilyFromLocale(locale);
  final immichColors = ImmichColors.harmonized(colorScheme);

  return ThemeData(
    useMaterial3: true,
    brightness: colorScheme.brightness,
    colorScheme: colorScheme,
    extensions: [immichColors],
    primaryColor: colorScheme.primary,
    hintColor: colorScheme.onSurfaceVariant,
    focusColor: colorScheme.primary,
    scaffoldBackgroundColor: colorScheme.surface,
    splashColor: colorScheme.primary.withValues(alpha: 0.08),
    highlightColor: colorScheme.primary.withValues(alpha: 0.06),
    fontFamily: fontFamily,
    dividerTheme: DividerThemeData(color: colorScheme.outlineVariant, thickness: 1, space: 1),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colorScheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(ImmichRadius.xl)),
      ),
      dragHandleColor: colorScheme.outlineVariant,
      dragHandleSize: const Size(36, 4),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(ImmichRadius.sm))),
      contentTextStyle: TextStyle(
        fontFamily: fontFamily,
        color: colorScheme.onInverseSurface,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      actionTextColor: colorScheme.inversePrimary,
      backgroundColor: colorScheme.inverseSurface,
    ),
    appBarTheme: AppBarTheme(
      titleTextStyle: TextStyle(
        color: colorScheme.onSurface,
        fontFamily: fontFamily,
        fontWeight: FontWeight.w600,
        fontSize: 20,
        letterSpacing: -0.2,
      ),
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 1.0,
      centerTitle: false,
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(fontSize: 36, fontWeight: FontWeight.w700, height: 1.18, letterSpacing: -0.6),
      displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, height: 1.22, letterSpacing: -0.4),
      displaySmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, height: 1.25, letterSpacing: -0.3),
      headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, height: 1.25, letterSpacing: -0.3),
      headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, height: 1.30, letterSpacing: -0.2),
      titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, height: 1.30, letterSpacing: -0.2),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.38, letterSpacing: -0.1),
      titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.40),
      bodyLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, height: 1.45),
      bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: 1.45),
      bodySmall: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w400, height: 1.40, letterSpacing: 0.1),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.25, letterSpacing: 0.1),
      labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, height: 1.25, letterSpacing: 0.2),
      labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, height: 1.20, letterSpacing: 0.25),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        minimumSize: const Size(0, 48),
        shape: const StadiumBorder(),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 0,
        minimumSize: const Size(0, 48),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        side: BorderSide(color: colorScheme.outlineVariant),
        shape: const StadiumBorder(),
      ),
    ),
    cardTheme: CardThemeData(
      color: colorScheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(ImmichRadius.lg))),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colorScheme.surfaceContainerLow,
      selectedColor: colorScheme.primaryContainer,
      side: BorderSide(color: colorScheme.outlineVariant),
      shape: const StadiumBorder(),
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 12,
      // ignore: deprecated_member_use
      year2023: false,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(type: BottomNavigationBarType.fixed),
    popupMenuTheme: PopupMenuThemeData(
      color: colorScheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(ImmichRadius.md))),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: colorScheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      indicatorColor: colorScheme.primaryContainer,
      elevation: 0,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: colorScheme.onPrimaryContainer, size: 24);
        }
        return IconThemeData(color: colorScheme.onSurfaceVariant, size: 24);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontFamily: fontFamily,
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
          overflow: TextOverflow.ellipsis,
        );
      }),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: colorScheme.surfaceContainer,
      indicatorColor: colorScheme.primaryContainer,
      selectedIconTheme: IconThemeData(color: colorScheme.onPrimaryContainer),
      unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainerLow,
      border: OutlineInputBorder(
        borderSide: BorderSide(color: colorScheme.outlineVariant),
        borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.md)),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: colorScheme.outlineVariant),
        borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.md)),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.md)),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: colorScheme.error),
        borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.md)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: colorScheme.error, width: 1.5),
        borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.md)),
      ),
      labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      floatingLabelStyle: TextStyle(color: colorScheme.primary),
      hintStyle: TextStyle(fontSize: 14.0, fontWeight: FontWeight.normal, color: colorScheme.onSurfaceVariant),
    ),
    textSelectionTheme: TextSelectionThemeData(cursorColor: colorScheme.primary),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colorScheme.surfaceContainer),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: const WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(ImmichRadius.md))),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLow,
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
          borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.md)),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colorScheme.outlineVariant),
          borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.md)),
        ),
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        hintStyle: TextStyle(fontSize: 14.0, fontWeight: FontWeight.normal, color: colorScheme.onSurfaceVariant),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(ImmichRadius.xl))),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      // ignore: deprecated_member_use
      year2023: false,
      trackGap: 3,
    ),
  );
}

// Replaces all surface shades in ImmichTheme with the warm Sunlit Paper / Obsidian Alcove
// neutral surface scale so non-default primary accents stay calm around photography.
ImmichTheme decolorizeSurfaces({required ImmichTheme theme}) {
  return ImmichTheme(
    light: theme.light.copyWith(
      surface: const Color(0xFFFAF9F7),
      onSurface: const Color(0xFF181715),
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFF4F2EE),
      surfaceContainer: const Color(0xFFECE9E3),
      surfaceContainerHigh: const Color(0xFFE4E0D8),
      surfaceContainerHighest: const Color(0xFFDBD6CC),
      surfaceDim: const Color(0xFFEAE6DE),
      surfaceBright: const Color(0xFFFFFFFF),
      onSurfaceVariant: const Color(0xFF5E5952),
      outline: const Color(0xFF7B766E),
      outlineVariant: const Color(0xFFE2DDD5),
      inverseSurface: const Color(0xFF2B2926),
      onInverseSurface: const Color(0xFFF5F3EF),
    ),
    dark: theme.dark.copyWith(
      surface: const Color(0xFF0C0C0E),
      onSurface: const Color(0xFFF2F0EC),
      surfaceContainerLowest: const Color(0xFF060607),
      surfaceContainerLow: const Color(0xFF141417),
      surfaceContainer: const Color(0xFF1C1C20),
      surfaceContainerHigh: const Color(0xFF25252A),
      surfaceContainerHighest: const Color(0xFF2F2F36),
      surfaceDim: const Color(0xFF09090B),
      surfaceBright: const Color(0xFF232328),
      onSurfaceVariant: const Color(0xFFA4A098),
      outline: const Color(0xFF8E8A82),
      outlineVariant: const Color(0xFF2B2B31),
      inverseSurface: const Color(0xFFEBE8E2),
      onInverseSurface: const Color(0xFF1C1B19),
    ),
  );
}

String? _getFontFamilyFromLocale(Locale locale) {
  if (localesNotSupportedByAppFont.contains(locale)) {
    // Let Flutter use the default font
    return null;
  }
  return 'GoogleSans';
}

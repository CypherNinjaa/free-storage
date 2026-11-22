import 'package:flutter/material.dart';
import 'package:immich_ui/src/constants.dart';
import 'package:material_color_utilities/blend/blend.dart';
import 'package:material_color_utilities/hct/hct.dart';
import 'package:material_color_utilities/palettes/tonal_palette.dart';

class ImmichThemeProvider extends StatelessWidget {
  final ColorScheme colorScheme;
  final Widget child;

  const ImmichThemeProvider({super.key, required this.colorScheme, required this.child});

  @override
  Widget build(BuildContext context) {
    final existingColors = Theme.of(context).extension<ImmichColors>();
    return Theme(
      data: Theme.of(context).copyWith(
        extensions: [existingColors ?? ImmichColors.harmonized(colorScheme)],
        colorScheme: colorScheme,
        brightness: colorScheme.brightness,
        inputDecorationTheme: InputDecorationTheme(
          floatingLabelBehavior: FloatingLabelBehavior.auto,
          filled: true,
          fillColor: colorScheme.surfaceContainerLow,
          border: WidgetStateInputBorder.resolveWith((states) {
            final color = states.contains(WidgetState.error)
                ? colorScheme.error
                : states.contains(WidgetState.focused)
                ? colorScheme.primary
                : colorScheme.outlineVariant;
            final width = states.contains(WidgetState.focused) ? 1.5 : 1.0;
            return OutlineInputBorder(
              borderSide: BorderSide(color: color, width: width),
              borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.md)),
            );
          }),
          labelStyle: WidgetStateTextStyle.resolveWith((states) {
            final color = states.contains(WidgetState.error)
                ? colorScheme.error
                : states.contains(WidgetState.focused)
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant;
            return TextStyle(color: color, fontWeight: FontWeight.w500);
          }),
          hintStyle: TextStyle(fontSize: ImmichTextSize.body, color: colorScheme.onSurfaceVariant),
          errorStyle: TextStyle(color: colorScheme.error, fontWeight: FontWeight.w500),
        ),
      ),
      child: child,
    );
  }
}

/// Sunlit Alcove extended semantic & photography-overlay color tokens (04_design_system.md §1.2).
class ImmichColors extends ThemeExtension<ImmichColors> {
  final Color primaryText;

  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color onInfoContainer;

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;

  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;

  final Color error;
  final Color onError;

  final Color mediaCanvas;
  final Color scrimPill;

  const ImmichColors({
    required this.primaryText,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.error,
    required this.onError,
    this.mediaCanvas = const Color(0xFF000000),
    this.scrimPill = const Color(0x94000000), // rgba(0, 0, 0, 0.58) -> 5.33:1 AA over white
  });

  /// Exact WCAG AA-verified Sunlit Alcove semantic palette.
  factory ImmichColors.sunlitAlcove(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return const ImmichColors(
        primaryText: Color(0xFFFDB44B),
        info: Color(0xFF8FC5FF),
        onInfo: Color(0xFF0A2C52),
        infoContainer: Color(0xFF133254),
        onInfoContainer: Color(0xFFD6EAFF),
        success: Color(0xFF7AD89A),
        onSuccess: Color(0xFF0B3B1E),
        successContainer: Color(0xFF123B22),
        onSuccessContainer: Color(0xFFC4F5D3),
        warning: Color(0xFFFFCC80),
        onWarning: Color(0xFF3A1E00),
        warningContainer: Color(0xFF4A2C06),
        onWarningContainer: Color(0xFFFFE6BF),
        error: Color(0xFFFFB4AB),
        onError: Color(0xFF690005),
      );
    }
    return const ImmichColors(
      primaryText: Color(0xFF9E450A),
      info: Color(0xFF1C5B99),
      onInfo: Color(0xFFFFFFFF),
      infoContainer: Color(0xFFD8EAFC),
      onInfoContainer: Color(0xFF0A2C52),
      success: Color(0xFF1B6B3A),
      onSuccess: Color(0xFFFFFFFF),
      successContainer: Color(0xFFD5F2DF),
      onSuccessContainer: Color(0xFF0B3B1E),
      warning: Color(0xFF8F4D00),
      onWarning: Color(0xFFFFFFFF),
      warningContainer: Color(0xFFFCE5C4),
      onWarningContainer: Color(0xFF3A1E00),
      error: Color(0xFFBA1A1A),
      onError: Color(0xFFFFFFFF),
    );
  }

  /// Harmonized fallback when user selects a custom seed preset or Material You dynamic palette.
  factory ImmichColors.harmonized(ColorScheme scheme) {
    final isAmberDefault =
        scheme.primary.toARGB32() == 0xFFB8540F || scheme.primary.toARGB32() == 0xFFFDB44B;
    if (isAmberDefault) {
      return ImmichColors.sunlitAlcove(scheme.brightness);
    }
    final (infoCont, onInfoCont) = scheme.harmonized(const Color(0xFF1C5B99));
    final (successCont, onSuccessCont) = scheme.harmonized(const Color(0xFF1B6B3A));
    final (warningCont, onWarningCont) = scheme.harmonized(const Color(0xFF8F4D00));
    final (errorCont, onErrorCont) = scheme.harmonized(const Color(0xFFBA1A1A));
    final isDark = scheme.brightness == Brightness.dark;
    return ImmichColors(
      primaryText: isDark ? scheme.primary : scheme.primary,
      info: isDark ? const Color(0xFF8FC5FF) : const Color(0xFF1C5B99),
      onInfo: onInfoCont,
      infoContainer: infoCont,
      onInfoContainer: onInfoCont,
      success: isDark ? const Color(0xFF7AD89A) : const Color(0xFF1B6B3A),
      onSuccess: onSuccessCont,
      successContainer: successCont,
      onSuccessContainer: onSuccessCont,
      warning: isDark ? const Color(0xFFFFCC80) : const Color(0xFF8F4D00),
      onWarning: onWarningCont,
      warningContainer: warningCont,
      onWarningContainer: onWarningCont,
      error: errorCont,
      onError: onErrorCont,
    );
  }

  /// Bottom-only editorial cover scrim (04_design_system.md §1.2):
  /// leaves top ~55% of the photograph completely untouched while giving 7.81:1 AAA text contrast at bottom.
  static const LinearGradient scrimEditorial = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x00000000),
      Color(0x14000000), // 0.08
      Color(0x5C000000), // 0.36
      Color(0xAD000000), // 0.68
    ],
    stops: [0.0, 0.45, 0.72, 1.0],
  );

  /// 4-stop top edge viewer scrim (AA contrast over bright skies/snow).
  static const LinearGradient scrimViewerTop = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x9E000000), // 0.62
      Color(0x52000000), // 0.32
      Color(0x14000000), // 0.08
      Color(0x00000000),
    ],
    stops: [0.0, 0.45, 0.78, 1.0],
  );

  /// 4-stop bottom edge viewer scrim.
  static const LinearGradient scrimViewerBottom = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [
      Color(0x9E000000), // 0.62
      Color(0x52000000), // 0.32
      Color(0x14000000), // 0.08
      Color(0x00000000),
    ],
    stops: [0.0, 0.45, 0.78, 1.0],
  );

  @override
  ImmichColors copyWith({
    Color? primaryText,
    Color? info,
    Color? onInfo,
    Color? infoContainer,
    Color? onInfoContainer,
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? error,
    Color? onError,
    Color? mediaCanvas,
    Color? scrimPill,
  }) {
    return ImmichColors(
      primaryText: primaryText ?? this.primaryText,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      error: error ?? this.error,
      onError: onError ?? this.onError,
      mediaCanvas: mediaCanvas ?? this.mediaCanvas,
      scrimPill: scrimPill ?? this.scrimPill,
    );
  }

  @override
  ImmichColors lerp(ImmichColors? other, double t) {
    if (other == null) {
      return this;
    }
    return ImmichColors(
      primaryText: Color.lerp(primaryText, other.primaryText, t)!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      onInfoContainer: Color.lerp(onInfoContainer, other.onInfoContainer, t)!,
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer: Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer: Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
      error: Color.lerp(error, other.error, t)!,
      onError: Color.lerp(onError, other.onError, t)!,
      mediaCanvas: Color.lerp(mediaCanvas, other.mediaCanvas, t)!,
      scrimPill: Color.lerp(scrimPill, other.scrimPill, t)!,
    );
  }
}

extension on ColorScheme {
  (Color container, Color onContainer) harmonized(Color seed) {
    final hct = Hct.fromInt(Blend.harmonize(seed.toARGB32(), primary.toARGB32()));
    final tones = TonalPalette.of(hct.hue, hct.chroma);
    final isDark = brightness == Brightness.dark;
    return (Color(tones.get(isDark ? 30 : 90)), Color(tones.get(isDark ? 90 : 10)));
  }
}

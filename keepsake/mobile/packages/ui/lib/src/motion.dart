import 'package:flutter/widgets.dart';

/// M3 Expressive Standard motion tokens for Ambry (05_motion_spec.md §1).
/// Near-critically damped spatial springs (ζ = 0.9) and zero-overshoot effect curves
/// tuned for 60/120 Hz Impeller performance and full reduced-motion accessibility.
abstract final class AmbryMotion {
  // Spatial Springs (movement, scale, bounds — ζ = 0.9, crisp with zero rubbery bounce)
  static final SpringDescription fastSpatial = SpringDescription.withDampingRatio(
    mass: 1.0,
    stiffness: 1400.0,
    ratio: 0.9,
  );
  static final SpringDescription defaultSpatial = SpringDescription.withDampingRatio(
    mass: 1.0,
    stiffness: 700.0,
    ratio: 0.9,
  );
  static final SpringDescription slowSpatial = SpringDescription.withDampingRatio(
    mass: 1.0,
    stiffness: 300.0,
    ratio: 0.9,
  );

  // Durations
  static const Duration dFast = Duration(milliseconds: 140); // image reveal, micro-feedback
  static const Duration dStandard = Duration(milliseconds: 180); // tabs, chrome fades, multi-select
  static const Duration dModerate = Duration(milliseconds: 220); // onboarding steps, sheets, search expand
  static const Duration dRoute = Duration(milliseconds: 260); // viewer backdrop & Hero flight
  static const Duration dShimmer = Duration(milliseconds: 1200); // shared skeleton sweep

  // Curves
  static const Curve easeSpatial = Curves.easeOutCubic;
  static const Curve easeEffects = Curves.easeOut;
  static const Curve easeEmphasized = Curves.fastOutSlowIn;

  /// Returns [Duration.zero] when the user has enabled Android "Remove animations".
  static Duration durationOf(BuildContext context, Duration normal) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : normal;

  static bool isReduced(BuildContext context) => MediaQuery.disableAnimationsOf(context);
}

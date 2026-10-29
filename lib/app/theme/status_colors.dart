import 'package:flutter/material.dart';

/// Couleurs des statuts. Chaque couple fond/texte respecte un contraste
/// d'au moins 4,5:1. La couleur n'est jamais le seul indicateur : chaque
/// statut a aussi un libellé et une icône.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
    required this.danger,
    required this.onDanger,
    required this.info,
    required this.onInfo,
    required this.neutral,
    required this.onNeutral,
  });

  static const light = StatusColors(
    success: Color(0xFFDDF0E6),
    onSuccess: Color(0xFF0F5238),
    warning: Color(0xFFFFF0D4),
    onWarning: Color(0xFF7A4A00),
    danger: Color(0xFFFCE4E2),
    onDanger: Color(0xFF9A1F17),
    info: Color(0xFFE2ECF8),
    onInfo: Color(0xFF1D4A7A),
    neutral: Color(0xFFEAEFEC),
    onNeutral: Color(0xFF46524C),
  );

  static const dark = StatusColors(
    success: Color(0xFF1E4434),
    onSuccess: Color(0xFFB6E8CD),
    warning: Color(0xFF4A3510),
    onWarning: Color(0xFFFFD99A),
    danger: Color(0xFF5A1F1B),
    onDanger: Color(0xFFFFC2BC),
    info: Color(0xFF1C3450),
    onInfo: Color(0xFFC3DAF5),
    neutral: Color(0xFF2F3633),
    onNeutral: Color(0xFFCBD4CF),
  );

  final Color success;
  final Color onSuccess;
  final Color warning;
  final Color onWarning;
  final Color danger;
  final Color onDanger;
  final Color info;
  final Color onInfo;
  final Color neutral;
  final Color onNeutral;

  static StatusColors of(BuildContext context) =>
      Theme.of(context).extension<StatusColors>() ?? light;

  @override
  StatusColors copyWith() => this;

  @override
  StatusColors lerp(StatusColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return StatusColors(
      success: l(success, other.success),
      onSuccess: l(onSuccess, other.onSuccess),
      warning: l(warning, other.warning),
      onWarning: l(onWarning, other.onWarning),
      danger: l(danger, other.danger),
      onDanger: l(onDanger, other.onDanger),
      info: l(info, other.info),
      onInfo: l(onInfo, other.onInfo),
      neutral: l(neutral, other.neutral),
      onNeutral: l(onNeutral, other.onNeutral),
    );
  }
}

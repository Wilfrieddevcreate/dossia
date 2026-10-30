import 'package:flutter/material.dart';

/// Couleurs des statuts. Chaque couple fond/texte respecte un contraste
/// d'au moins 4,5:1 ; les teintes « icône » atteignent 3:1 sur les blocs.
/// La couleur n'est jamais le seul indicateur : chaque statut a aussi un
/// libellé et une icône.
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
    required this.successIcon,
    required this.warningIcon,
    required this.dangerIcon,
    required this.neutralIcon,
  });

  static const light = StatusColors(
    success: Color(0xFFE2F2E9),
    onSuccess: Color(0xFF125A3A),
    warning: Color(0xFFFCF0DA),
    onWarning: Color(0xFF7A4A00),
    danger: Color(0xFFFBE6E4),
    onDanger: Color(0xFF9C251C),
    info: Color(0xFFE5EDF8),
    onInfo: Color(0xFF22528C),
    neutral: Color(0xFFEDF1EF),
    onNeutral: Color(0xFF4A5650),
    successIcon: Color(0xFF1B7A52),
    warningIcon: Color(0xFFB06A00),
    dangerIcon: Color(0xFFC0392B),
    neutralIcon: Color(0xFF7C8781),
  );

  static const dark = StatusColors(
    success: Color(0xFF1B3428),
    onSuccess: Color(0xFFA9E5C7),
    warning: Color(0xFF3B2C12),
    onWarning: Color(0xFFF6D193),
    danger: Color(0xFF41201D),
    onDanger: Color(0xFFFFBCB4),
    info: Color(0xFF1B2B40),
    onInfo: Color(0xFFBBD4F3),
    neutral: Color(0xFF252D29),
    onNeutral: Color(0xFFC6CFCA),
    successIcon: Color(0xFF6FCBA0),
    warningIcon: Color(0xFFF0B455),
    dangerIcon: Color(0xFFFF8A7E),
    neutralIcon: Color(0xFF8A968F),
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

  /// Teintes pour les icônes de statut (pastilles des listes).
  final Color successIcon;
  final Color warningIcon;
  final Color dangerIcon;
  final Color neutralIcon;

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
      successIcon: l(successIcon, other.successIcon),
      warningIcon: l(warningIcon, other.warningIcon),
      dangerIcon: l(dangerIcon, other.dangerIcon),
      neutralIcon: l(neutralIcon, other.neutralIcon),
    );
  }
}

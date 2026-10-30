import 'package:flutter/material.dart';

import '../../core/models/document_category.dart';

/// Teintes de surface et couleurs par catégorie, en clair et en sombre.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.card,
    required this.muted,
    required this.hairline,
    required this.hairlineStrong,
    required this.placeholder,
    required this.shadow,
    required this.categoryTints,
  });

  static const light = AppPalette(
    background: Color(0xFFF3F5F4),
    card: Color(0xFFFFFFFF),
    muted: Color(0xFFEDF1EF),
    hairline: Color(0xFFE5EAE7),
    hairlineStrong: Color(0xFFD3DBD7),
    placeholder: Color(0xFF7C8781),
    shadow: Color(0x0F17251E),
    categoryTints: {
      DocumentCategory.identity: (Color(0xFFE5EDF9), Color(0xFF2A5DA8)),
      DocumentCategory.education: (Color(0xFFEFE9FA), Color(0xFF6743AE)),
      DocumentCategory.professional: (Color(0xFFFBEEDC), Color(0xFF8E5300)),
      DocumentCategory.finance: (Color(0xFFE0F2E8), Color(0xFF17603F)),
      DocumentCategory.housing: (Color(0xFFDFF1F3), Color(0xFF1B6670)),
      DocumentCategory.other: (Color(0xFFEBEFED), Color(0xFF4F5B55)),
    },
  );

  static const dark = AppPalette(
    background: Color(0xFF0E1311),
    card: Color(0xFF171E1B),
    muted: Color(0xFF212A26),
    hairline: Color(0xFF26302B),
    hairlineStrong: Color(0xFF36423C),
    placeholder: Color(0xFF8A968F),
    shadow: Color(0x00000000),
    categoryTints: {
      DocumentCategory.identity: (Color(0xFF1C2A3F), Color(0xFFA9C7F2)),
      DocumentCategory.education: (Color(0xFF2A2240), Color(0xFFCDB8F5)),
      DocumentCategory.professional: (Color(0xFF3A2C16), Color(0xFFF2C98A)),
      DocumentCategory.finance: (Color(0xFF1B3428), Color(0xFFA6E3C4)),
      DocumentCategory.housing: (Color(0xFF17333A), Color(0xFF9FDCE3)),
      DocumentCategory.other: (Color(0xFF252D29), Color(0xFFC3CCC7)),
    },
  );

  /// Fond des écrans.
  final Color background;

  /// Fond des blocs (listes groupées, cartes).
  final Color card;

  /// Fond discret : champs, puces, pistes de progression.
  final Color muted;

  /// Séparateurs.
  final Color hairline;
  final Color hairlineStrong;

  /// Texte d'exemple dans les champs (contraste ≥ 3:1, non essentiel).
  final Color placeholder;

  /// Ombre très légère des blocs (transparente en sombre).
  final Color shadow;

  /// Couple (fond, icône) par catégorie de document.
  final Map<DocumentCategory, (Color, Color)> categoryTints;

  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ?? light;

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(AppPalette? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      background: l(background, other.background),
      card: l(card, other.card),
      muted: l(muted, other.muted),
      hairline: l(hairline, other.hairline),
      hairlineStrong: l(hairlineStrong, other.hairlineStrong),
      placeholder: l(placeholder, other.placeholder),
      shadow: l(shadow, other.shadow),
      categoryTints: t < 0.5 ? categoryTints : other.categoryTints,
    );
  }
}

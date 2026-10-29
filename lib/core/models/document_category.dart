/// Catégories de documents proposées par l'application.
///
/// La valeur `name` de l'énumération est stockée en base : ne jamais renommer
/// une valeur existante sans migration.
enum DocumentCategory {
  identity('Identité'),
  education('Éducation'),
  professional('Professionnel'),
  finance('Finances'),
  housing('Domicile'),
  other('Autres');

  const DocumentCategory(this.label);

  final String label;
}

/// Catégories facultatives d'un dossier.
///
/// La valeur `name` de l'énumération est stockée en base : ne jamais renommer
/// une valeur existante sans migration.
enum DossierCategory {
  travel('Voyage et visa'),
  studies('Études'),
  scholarship('Bourse et concours'),
  employment('Emploi'),
  administrative('Démarche administrative'),
  finance('Finances'),
  housing('Logement'),
  personal('Personnel'),
  other('Autre');

  const DossierCategory(this.label);

  final String label;
}

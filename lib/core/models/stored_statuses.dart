/// Statut d'une pièce tel que déclaré par l'utilisateur (colonne
/// `required_items.status`).
///
/// Le statut affiché (Manquant, Disponible, À vérifier, À renouveler,
/// Facultatif) est toujours recalculé à partir des données métier ; seule
/// l'indication « une condition reste à confirmer » est saisie à la main.
enum ManualItemStatus {
  /// Aucun point à confirmer : le statut dépend uniquement des documents liés.
  auto,

  /// L'utilisateur a signalé une condition à confirmer (copie certifiée,
  /// traduction, légalisation…).
  toVerify,
}

/// Statut d'un dossier tel que déclaré par l'utilisateur (colonne
/// `dossiers.status`).
///
/// « En préparation » et « Prêt à vérifier » sont calculés ; « Terminé » est
/// une confirmation explicite de l'utilisateur. L'archivage est porté par
/// `archived_at`.
enum ManualDossierStatus { inProgress, completed }

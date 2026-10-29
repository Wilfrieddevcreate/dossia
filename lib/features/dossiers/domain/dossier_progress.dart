import '../../../core/models/stored_statuses.dart';
import '../../requirements/domain/item_status.dart';

/// Synthèse de l'avancement d'un dossier (§ 3.4 et 4.5).
class DossierProgress {
  const DossierProgress({
    this.mandatoryTotal = 0,
    this.mandatoryAvailable = 0,
    this.mandatoryMissing = 0,
    this.mandatoryToVerify = 0,
    this.mandatoryToRenew = 0,
    this.optionalTotal = 0,
    this.optionalAvailable = 0,
  });

  factory DossierProgress.fromEvaluations(Iterable<ItemEvaluation> items) {
    var total = 0, available = 0, missing = 0, toVerify = 0, toRenew = 0;
    var optTotal = 0, optAvailable = 0;
    for (final e in items) {
      if (e.isMandatory) {
        total++;
        switch (e.status) {
          case ItemStatus.available:
            available++;
          case ItemStatus.missing:
          case ItemStatus.optional:
            missing++;
          case ItemStatus.toVerify:
            toVerify++;
          case ItemStatus.toRenew:
            toRenew++;
        }
      } else {
        optTotal++;
        if (e.status == ItemStatus.available) optAvailable++;
      }
    }
    return DossierProgress(
      mandatoryTotal: total,
      mandatoryAvailable: available,
      mandatoryMissing: missing,
      mandatoryToVerify: toVerify,
      mandatoryToRenew: toRenew,
      optionalTotal: optTotal,
      optionalAvailable: optAvailable,
    );
  }

  final int mandatoryTotal;
  final int mandatoryAvailable;
  final int mandatoryMissing;
  final int mandatoryToVerify;
  final int mandatoryToRenew;
  final int optionalTotal;
  final int optionalAvailable;

  bool get hasMandatoryItems => mandatoryTotal > 0;

  /// Part des pièces obligatoires satisfaites, entre 0 et 1, ou `null` si le
  /// dossier ne comporte aucune pièce obligatoire.
  double? get ratio =>
      hasMandatoryItems ? mandatoryAvailable / mandatoryTotal : null;

  /// Pourcentage arrondi à l'entier inférieur : 100 % n'est affiché que si
  /// toutes les pièces obligatoires sont réellement disponibles.
  int? get percent =>
      hasMandatoryItems ? (mandatoryAvailable * 100) ~/ mandatoryTotal : null;

  bool get allMandatoryAvailable =>
      hasMandatoryItems && mandatoryAvailable == mandatoryTotal;

  /// Pièces obligatoires qui demandent encore une action.
  int get mandatoryPending => mandatoryTotal - mandatoryAvailable;

  /// Libellé de progression, conforme au § 4.5.
  String get label =>
      hasMandatoryItems ? '$percent %' : 'Aucune pièce obligatoire';
}

/// Statut général d'un dossier (§ 4.7).
enum DossierStatus {
  inProgress('En préparation'),
  readyToCheck('Prêt à vérifier'),
  completed('Terminé'),
  archived('Archivé');

  const DossierStatus(this.label);

  final String label;
}

DossierStatus computeDossierStatus({
  required bool archived,
  required ManualDossierStatus manualStatus,
  required DossierProgress progress,
}) {
  if (archived) return DossierStatus.archived;
  if (manualStatus == ManualDossierStatus.completed) {
    return DossierStatus.completed;
  }
  if (progress.allMandatoryAvailable) return DossierStatus.readyToCheck;
  return DossierStatus.inProgress;
}

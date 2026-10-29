import '../../../core/utils/dates.dart';

/// Statut affiché d'une pièce requise (§ 4.6 du cahier des charges).
enum ItemStatus {
  /// Aucun document n'est associé à une pièce obligatoire.
  missing('Manquant'),

  /// Les documents associés couvrent la pièce et rien ne reste à confirmer.
  available('Disponible'),

  /// Des documents sont associés mais une condition reste à confirmer.
  toVerify('À vérifier'),

  /// Au moins un document associé est expiré.
  toRenew('À renouveler'),

  /// Pièce facultative sans document associé.
  optional('Facultatif');

  const ItemStatus(this.label);

  final String label;
}

/// Raison pour laquelle une pièce est « À vérifier ».
enum VerifyReason {
  incompleteQuantity,
  archivedDocument,
  userFlagged,
  expiresBeforeDeadline,
}

/// Document associé à une pièce, réduit aux informations utiles au calcul.
class LinkedDocumentFacts {
  const LinkedDocumentFacts({
    required this.quantityAssigned,
    this.expiryDate,
    this.archived = false,
  });

  final int quantityAssigned;
  final DateTime? expiryDate;
  final bool archived;
}

/// Pièce requise, réduite aux informations utiles au calcul.
class ItemFacts {
  const ItemFacts({
    required this.isMandatory,
    required this.quantity,
    this.flaggedToVerify = false,
    this.links = const [],
  });

  final bool isMandatory;
  final int quantity;
  final bool flaggedToVerify;
  final List<LinkedDocumentFacts> links;
}

/// Résultat de l'évaluation d'une pièce.
class ItemEvaluation {
  const ItemEvaluation({
    required this.status,
    required this.isMandatory,
    required this.assignedQuantity,
    required this.requiredQuantity,
    this.reasons = const {},
  });

  final ItemStatus status;
  final bool isMandatory;
  final int assignedQuantity;
  final int requiredQuantity;

  /// Raisons de vérification. Renseignées pour [ItemStatus.toVerify], et
  /// conservées pour [ItemStatus.toRenew] lorsqu'elles existent aussi.
  final Set<VerifyReason> reasons;

  /// Une pièce est satisfaite lorsqu'elle est disponible : documents associés
  /// en quantité suffisante, non expirés, et aucune condition en attente.
  bool get isSatisfied => status == ItemStatus.available;
}

/// Calcule le statut d'une pièce.
///
/// Règles, dans l'ordre :
/// 1. aucun document associé → Manquant (ou Facultatif si la pièce n'est pas
///    obligatoire) ;
/// 2. un document associé est expiré (date d'expiration strictement
///    antérieure à [today]) → À renouveler ;
/// 3. quantité associée insuffisante, document archivé, condition signalée par
///    l'utilisateur, ou document qui expire avant la date limite du dossier →
///    À vérifier ;
/// 4. sinon → Disponible.
///
/// Aucune date d'expiration n'est jamais supposée : un document sans date
/// d'expiration n'est jamais considéré comme expiré.
ItemEvaluation evaluateItem(
  ItemFacts item, {
  required DateTime today,
  DateTime? dossierDeadline,
}) {
  final day = dateOnly(today);
  final assigned = item.links.fold<int>(0, (sum, l) => sum + l.quantityAssigned);

  if (item.links.isEmpty) {
    return ItemEvaluation(
      status: item.isMandatory ? ItemStatus.missing : ItemStatus.optional,
      isMandatory: item.isMandatory,
      assignedQuantity: 0,
      requiredQuantity: item.quantity,
    );
  }

  final reasons = <VerifyReason>{
    if (assigned < item.quantity) VerifyReason.incompleteQuantity,
    if (item.links.any((l) => l.archived)) VerifyReason.archivedDocument,
    if (item.flaggedToVerify) VerifyReason.userFlagged,
    if (dossierDeadline != null &&
        item.links.any(
          (l) =>
              l.expiryDate != null &&
              !dateOnly(l.expiryDate!).isBefore(day) &&
              dateOnly(l.expiryDate!).isBefore(dateOnly(dossierDeadline)),
        ))
      VerifyReason.expiresBeforeDeadline,
  };

  final expired = item.links.any(
    (l) => l.expiryDate != null && dateOnly(l.expiryDate!).isBefore(day),
  );

  final ItemStatus status;
  if (expired) {
    status = ItemStatus.toRenew;
  } else if (reasons.isNotEmpty) {
    status = ItemStatus.toVerify;
  } else {
    status = ItemStatus.available;
  }

  return ItemEvaluation(
    status: status,
    isMandatory: item.isMandatory,
    assignedQuantity: assigned,
    requiredQuantity: item.quantity,
    reasons: reasons,
  );
}

String verifyReasonLabel(
  VerifyReason reason, {
  required int assigned,
  required int required,
}) {
  switch (reason) {
    case VerifyReason.incompleteQuantity:
      return 'Quantité incomplète : $assigned sur $required';
    case VerifyReason.archivedDocument:
      return 'Un document associé est archivé';
    case VerifyReason.userFlagged:
      return 'Une condition reste à confirmer';
    case VerifyReason.expiresBeforeDeadline:
      return 'Un document expire avant la date limite du dossier';
  }
}

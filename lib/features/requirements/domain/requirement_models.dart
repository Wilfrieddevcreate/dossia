import '../../../core/database/app_database.dart';
import '../../../core/models/stored_statuses.dart';
import '../../documents/domain/document_models.dart';
import 'item_status.dart';

String requirementDisplayName(RequiredItemRow item, DocumentTypeRow? type) {
  final custom = item.customName?.trim();
  if (custom != null && custom.isNotEmpty) return custom;
  return type?.name ?? 'Pièce sans nom';
}

/// Document personnel associé à une pièce.
class LinkedDocument {
  const LinkedDocument({
    required this.link,
    required this.doc,
    required this.docType,
  });

  final ItemDocumentLinkRow link;
  final PersonalDocumentRow doc;
  final DocumentTypeRow docType;

  String get displayName => documentDisplayName(doc, docType);
  bool get isArchived => doc.archivedAt != null;
}

/// Pièce requise avec son type et ses associations.
class RequirementView {
  const RequirementView({
    required this.item,
    required this.type,
    required this.links,
  });

  final RequiredItemRow item;
  final DocumentTypeRow? type;
  final List<LinkedDocument> links;

  String get id => item.id;
  String get dossierId => item.dossierId;
  String get displayName => requirementDisplayName(item, type);
  bool get flaggedToVerify => item.status == ManualItemStatus.toVerify;

  ItemFacts get facts => ItemFacts(
    isMandatory: item.isMandatory,
    quantity: item.quantity,
    flaggedToVerify: flaggedToVerify,
    links: [
      for (final l in links)
        LinkedDocumentFacts(
          quantityAssigned: l.link.quantityAssigned,
          expiryDate: l.doc.expiryDate,
          archived: l.isArchived,
        ),
    ],
  );

  EvaluatedRequirement evaluate({
    required DateTime today,
    DateTime? dossierDeadline,
  }) => EvaluatedRequirement(
    this,
    evaluateItem(facts, today: today, dossierDeadline: dossierDeadline),
  );
}

class EvaluatedRequirement {
  const EvaluatedRequirement(this.view, this.evaluation);

  final RequirementView view;
  final ItemEvaluation evaluation;

  ItemStatus get status => evaluation.status;
}

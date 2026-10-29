import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/models/stored_statuses.dart';
import '../domain/requirement_models.dart';

/// Informations saisies dans le formulaire d'une pièce.
class RequirementInput {
  const RequirementInput({
    this.typeId,
    this.customName,
    this.isMandatory = true,
    this.quantity = 1,
    this.instructions,
    this.notes,
    this.dueDate,
  }) : assert(typeId != null || customName != null);

  final String? typeId;
  final String? customName;
  final bool isMandatory;
  final int quantity;
  final String? instructions;
  final String? notes;
  final DateTime? dueDate;
}

class RequirementsRepository {
  RequirementsRepository(this._db);

  final AppDatabase _db;

  Set<TableInfo> get _tables => {
    _db.requiredItems,
    _db.itemDocumentLinks,
    _db.personalDocuments,
    _db.documentTypes,
  };

  /// Pièces d'un dossier, ou de tous les dossiers si [dossierId] est nul,
  /// triées par position.
  Stream<List<RequirementView>> watchRequirements({String? dossierId}) =>
      _db.watchComputed(_tables, () => loadRequirements(dossierId: dossierId));

  Future<List<RequirementView>> loadRequirements({String? dossierId}) async {
    final itemQuery = _db.select(_db.requiredItems).join([
      leftOuterJoin(
        _db.documentTypes,
        _db.documentTypes.id.equalsExp(_db.requiredItems.typeId),
      ),
    ]);
    if (dossierId != null) {
      itemQuery.where(_db.requiredItems.dossierId.equals(dossierId));
    }
    itemQuery.orderBy([
      OrderingTerm.asc(_db.requiredItems.position),
      OrderingTerm.asc(_db.requiredItems.createdAt),
    ]);
    final itemRows = await itemQuery.get();

    final docType = _db.alias(_db.documentTypes, 'doc_type');
    final linkQuery = _db.select(_db.itemDocumentLinks).join([
      innerJoin(
        _db.requiredItems,
        _db.requiredItems.id.equalsExp(_db.itemDocumentLinks.requiredItemId),
        useColumns: false,
      ),
      innerJoin(
        _db.personalDocuments,
        _db.personalDocuments.id.equalsExp(
          _db.itemDocumentLinks.personalDocumentId,
        ),
      ),
      innerJoin(
        docType,
        docType.id.equalsExp(_db.personalDocuments.typeId),
      ),
    ]);
    if (dossierId != null) {
      linkQuery.where(_db.requiredItems.dossierId.equals(dossierId));
    }
    linkQuery.orderBy([OrderingTerm.asc(_db.itemDocumentLinks.linkedAt)]);
    final linksByItem = groupBy(
      [
        for (final row in await linkQuery.get())
          LinkedDocument(
            link: row.readTable(_db.itemDocumentLinks),
            doc: row.readTable(_db.personalDocuments),
            docType: row.readTable(docType),
          ),
      ],
      (LinkedDocument l) => l.link.requiredItemId,
    );

    return [
      for (final row in itemRows)
        RequirementView(
          item: row.readTable(_db.requiredItems),
          type: row.readTableOrNull(_db.documentTypes),
          links: linksByItem[row.readTable(_db.requiredItems).id] ?? const [],
        ),
    ];
  }

  Future<RequirementView?> loadRequirement(String itemId) async {
    final item = await (_db.select(
      _db.requiredItems,
    )..where((i) => i.id.equals(itemId))).getSingleOrNull();
    if (item == null) return null;
    final all = await loadRequirements(dossierId: item.dossierId);
    return all.firstWhereOrNull((r) => r.id == itemId);
  }

  Future<String> createRequirement(
    String dossierId,
    RequirementInput input,
  ) async {
    return _db.transaction(() async {
      final maxPosition = _db.requiredItems.position.max();
      final query = _db.selectOnly(_db.requiredItems)
        ..addColumns([maxPosition])
        ..where(_db.requiredItems.dossierId.equals(dossierId));
      final current = await query.map((r) => r.read(maxPosition)).getSingle();
      final now = DateTime.now();
      final id = newId();
      await _db
          .into(_db.requiredItems)
          .insert(
            RequiredItemsCompanion.insert(
              id: id,
              dossierId: dossierId,
              typeId: Value(input.typeId),
              customName: Value(cleanText(input.customName)),
              isMandatory: Value(input.isMandatory),
              quantity: Value(input.quantity),
              instructions: Value(cleanText(input.instructions)),
              notes: Value(cleanText(input.notes)),
              dueDate: Value(input.dueDate),
              position: (current ?? -1) + 1,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _touchDossier(dossierId);
      return id;
    });
  }

  Future<void> updateRequirement(String itemId, RequirementInput input) async {
    await _db.transaction(() async {
      await (_db.update(
        _db.requiredItems,
      )..where((i) => i.id.equals(itemId))).write(
        RequiredItemsCompanion(
          typeId: Value(input.typeId),
          customName: Value(cleanText(input.customName)),
          isMandatory: Value(input.isMandatory),
          quantity: Value(input.quantity),
          instructions: Value(cleanText(input.instructions)),
          notes: Value(cleanText(input.notes)),
          dueDate: Value(input.dueDate),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _touchDossierOfItem(itemId);
    });
  }

  Future<void> setFlaggedToVerify(String itemId, bool flagged) async {
    await (_db.update(
      _db.requiredItems,
    )..where((i) => i.id.equals(itemId))).write(
      RequiredItemsCompanion(
        status: Value(flagged ? ManualItemStatus.toVerify : ManualItemStatus.auto),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Supprime une pièce et ses associations. Les documents de la bibliothèque
  /// ne sont jamais supprimés.
  Future<void> deleteRequirement(String itemId) async {
    await _db.transaction(() async {
      await _touchDossierOfItem(itemId);
      await (_db.delete(
        _db.itemDocumentLinks,
      )..where((l) => l.requiredItemId.equals(itemId))).go();
      await (_db.delete(
        _db.requiredItems,
      )..where((i) => i.id.equals(itemId))).go();
    });
  }

  /// Enregistre le nouvel ordre des pièces d'un dossier.
  Future<void> reorder(String dossierId, List<String> orderedItemIds) async {
    await _db.batch((b) {
      for (var i = 0; i < orderedItemIds.length; i++) {
        b.update(
          _db.requiredItems,
          RequiredItemsCompanion(position: Value(i)),
          where: (t) =>
              t.id.equals(orderedItemIds[i]) & t.dossierId.equals(dossierId),
        );
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Associations document ↔ pièce

  /// Associe un document à une pièce. Si l'association existe déjà, sa
  /// quantité est mise à jour.
  Future<void> linkDocument({
    required String itemId,
    required String documentId,
    int quantity = 1,
  }) async {
    await _db.transaction(() async {
      await _db
          .into(_db.itemDocumentLinks)
          .insert(
            ItemDocumentLinksCompanion.insert(
              id: newId(),
              requiredItemId: itemId,
              personalDocumentId: documentId,
              quantityAssigned: Value(quantity),
              linkedAt: DateTime.now(),
            ),
            onConflict: DoUpdate(
              (_) => ItemDocumentLinksCompanion(
                quantityAssigned: Value(quantity),
              ),
              target: [
                _db.itemDocumentLinks.requiredItemId,
                _db.itemDocumentLinks.personalDocumentId,
              ],
            ),
          );
      await _touchDossierOfItem(itemId);
    });
  }

  Future<void> updateLinkQuantity(String linkId, int quantity) async {
    await (_db.update(_db.itemDocumentLinks)..where((l) => l.id.equals(linkId)))
        .write(ItemDocumentLinksCompanion(quantityAssigned: Value(quantity)));
  }

  /// Retire une association. Le document reste dans la bibliothèque et
  /// conserve ses autres associations.
  Future<void> unlink(String linkId) async {
    await _db.transaction(() async {
      final link = await (_db.select(
        _db.itemDocumentLinks,
      )..where((l) => l.id.equals(linkId))).getSingleOrNull();
      if (link == null) return;
      await (_db.delete(
        _db.itemDocumentLinks,
      )..where((l) => l.id.equals(linkId))).go();
      await _touchDossierOfItem(link.requiredItemId);
    });
  }

  Future<void> _touchDossierOfItem(String itemId) async {
    final item = await (_db.select(
      _db.requiredItems,
    )..where((i) => i.id.equals(itemId))).getSingleOrNull();
    if (item != null) await _touchDossier(item.dossierId);
  }

  Future<void> _touchDossier(String dossierId) async {
    await (_db.update(_db.dossiers)..where((d) => d.id.equals(dossierId)))
        .write(DossiersCompanion(updatedAt: Value(DateTime.now())));
  }
}

final requirementsRepositoryProvider = Provider<RequirementsRepository>(
  (ref) => RequirementsRepository(ref.watch(databaseProvider)),
);

/// Toutes les pièces de tous les dossiers (tableau de bord, liste des dossiers,
/// échéances).
final allRequirementsProvider = StreamProvider<List<RequirementView>>(
  (ref) => ref.watch(requirementsRepositoryProvider).watchRequirements(),
);

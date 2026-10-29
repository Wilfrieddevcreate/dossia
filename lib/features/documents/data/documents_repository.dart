import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/files/file_storage_service.dart';
import '../../../core/models/document_category.dart';
import '../../requirements/domain/requirement_models.dart';
import '../domain/document_models.dart';

/// Informations saisies dans le formulaire d'un document.
class DocumentInput {
  const DocumentInput({
    required this.typeId,
    this.customName,
    this.issueDate,
    this.expiryDate,
    this.issuer,
    this.notes,
  });

  final String typeId;
  final String? customName;
  final DateTime? issueDate;
  final DateTime? expiryDate;
  final String? issuer;
  final String? notes;
}

class DocumentsRepository {
  DocumentsRepository(this._db, this._files);

  final AppDatabase _db;
  final FileStorageService _files;

  // ---------------------------------------------------------------------------
  // Types de documents

  Stream<List<DocumentTypeRow>> watchTypes() {
    return (_db.select(_db.documentTypes)..orderBy([
          (t) => OrderingTerm.asc(t.category),
          (t) => OrderingTerm.asc(t.isCustom),
          (t) => OrderingTerm.asc(t.name),
        ]))
        .watch();
  }

  Future<DocumentTypeRow> createType({
    required String name,
    required DocumentCategory category,
    bool expiryApplicable = false,
  }) async {
    final row = DocumentTypesCompanion.insert(
      id: newId(),
      name: name.trim(),
      category: category,
      expiryApplicable: Value(expiryApplicable),
      isCustom: const Value(true),
      createdAt: DateTime.now(),
    );
    return _db.into(_db.documentTypes).insertReturning(row);
  }

  // ---------------------------------------------------------------------------
  // Documents personnels

  Stream<List<DocumentView>> watchDocuments() => _db.watchComputed({
    _db.personalDocuments,
    _db.documentTypes,
    _db.documentFiles,
    _db.itemDocumentLinks,
  }, _loadViews);

  Future<List<DocumentView>> _loadViews({String? onlyId}) async {
    final query = _db.select(_db.personalDocuments).join([
      innerJoin(
        _db.documentTypes,
        _db.documentTypes.id.equalsExp(_db.personalDocuments.typeId),
      ),
    ]);
    if (onlyId != null) query.where(_db.personalDocuments.id.equals(onlyId));

    final fileCount = _db.documentFiles.id.count();
    final files = _db.selectOnly(_db.documentFiles)
      ..addColumns([_db.documentFiles.documentId, fileCount])
      ..groupBy([_db.documentFiles.documentId]);
    final fileCounts = {
      for (final r in await files.get())
        r.read(_db.documentFiles.documentId)!: r.read(fileCount)!,
    };

    final linkCount = _db.itemDocumentLinks.id.count();
    final links = _db.selectOnly(_db.itemDocumentLinks)
      ..addColumns([_db.itemDocumentLinks.personalDocumentId, linkCount])
      ..groupBy([_db.itemDocumentLinks.personalDocumentId]);
    final usageCounts = {
      for (final r in await links.get())
        r.read(_db.itemDocumentLinks.personalDocumentId)!: r.read(linkCount)!,
    };

    final views = [
      for (final row in await query.get())
        DocumentView(
          doc: row.readTable(_db.personalDocuments),
          type: row.readTable(_db.documentTypes),
          fileCount: fileCounts[row.readTable(_db.personalDocuments).id] ?? 0,
          usageCount: usageCounts[row.readTable(_db.personalDocuments).id] ?? 0,
        ),
    ];
    views.sort(
      (a, b) => normalizeForSearch(
        a.displayName,
      ).compareTo(normalizeForSearch(b.displayName)),
    );
    return views;
  }

  Stream<DocumentDetail?> watchDocument(String id) => _db.watchComputed({
    _db.personalDocuments,
    _db.documentTypes,
    _db.documentFiles,
    _db.itemDocumentLinks,
    _db.requiredItems,
    _db.dossiers,
  }, () => loadDocument(id));

  Future<DocumentDetail?> loadDocument(String id) async {
    final views = await _loadViews(onlyId: id);
    if (views.isEmpty) return null;

    final files =
        await (_db.select(_db.documentFiles)
              ..where((f) => f.documentId.equals(id))
              ..orderBy([(f) => OrderingTerm.asc(f.createdAt)]))
            .get();

    final itemType = _db.alias(_db.documentTypes, 'item_type');
    final usageQuery =
        _db.select(_db.itemDocumentLinks).join([
            innerJoin(
              _db.requiredItems,
              _db.requiredItems.id.equalsExp(
                _db.itemDocumentLinks.requiredItemId,
              ),
            ),
            innerJoin(
              _db.dossiers,
              _db.dossiers.id.equalsExp(_db.requiredItems.dossierId),
            ),
            leftOuterJoin(
              itemType,
              itemType.id.equalsExp(_db.requiredItems.typeId),
            ),
          ])
          ..where(_db.itemDocumentLinks.personalDocumentId.equals(id))
          ..orderBy([OrderingTerm.asc(_db.dossiers.title)]);

    final usages = [
      for (final row in await usageQuery.get())
        DocumentUsage(
          linkId: row.readTable(_db.itemDocumentLinks).id,
          dossierId: row.readTable(_db.dossiers).id,
          dossierTitle: row.readTable(_db.dossiers).title,
          dossierArchived: row.readTable(_db.dossiers).archivedAt != null,
          itemId: row.readTable(_db.requiredItems).id,
          itemName: requirementDisplayName(
            row.readTable(_db.requiredItems),
            row.readTableOrNull(itemType),
          ),
        ),
    ];

    return DocumentDetail(view: views.single, files: files, usages: usages);
  }

  Future<String> createDocument(DocumentInput input) async {
    final now = DateTime.now();
    final id = newId();
    await _db
        .into(_db.personalDocuments)
        .insert(
          PersonalDocumentsCompanion.insert(
            id: id,
            typeId: input.typeId,
            customName: Value(cleanText(input.customName)),
            issueDate: Value(input.issueDate),
            expiryDate: Value(input.expiryDate),
            issuer: Value(cleanText(input.issuer)),
            notes: Value(cleanText(input.notes)),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  /// Crée un document sans fichier pour chaque type sélectionné lors de
  /// l'inventaire.
  Future<void> createFromInventory(Iterable<String> typeIds) async {
    final now = DateTime.now();
    await _db.batch((b) {
      b.insertAll(_db.personalDocuments, [
        for (final typeId in typeIds)
          PersonalDocumentsCompanion.insert(
            id: newId(),
            typeId: typeId,
            createdAt: now,
            updatedAt: now,
          ),
      ]);
    });
  }

  Future<void> updateDocument(String id, DocumentInput input) async {
    await (_db.update(
      _db.personalDocuments,
    )..where((d) => d.id.equals(id))).write(
      PersonalDocumentsCompanion(
        typeId: Value(input.typeId),
        customName: Value(cleanText(input.customName)),
        issueDate: Value(input.issueDate),
        expiryDate: Value(input.expiryDate),
        issuer: Value(cleanText(input.issuer)),
        notes: Value(cleanText(input.notes)),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> setArchived(String id, bool archived) async {
    final now = DateTime.now();
    await (_db.update(
      _db.personalDocuments,
    )..where((d) => d.id.equals(id))).write(
      PersonalDocumentsCompanion(
        archivedAt: Value(archived ? now : null),
        updatedAt: Value(now),
      ),
    );
  }

  /// Supprime définitivement un document, ses fichiers joints et ses
  /// associations. L'appelant doit avoir obtenu la confirmation de
  /// l'utilisateur en lui indiquant les dossiers concernés.
  Future<void> deleteDocument(String id) async {
    final files = await (_db.select(
      _db.documentFiles,
    )..where((f) => f.documentId.equals(id))).get();
    await _db.transaction(() async {
      await (_db.delete(
        _db.itemDocumentLinks,
      )..where((l) => l.personalDocumentId.equals(id))).go();
      await (_db.delete(
        _db.documentFiles,
      )..where((f) => f.documentId.equals(id))).go();
      await (_db.delete(
        _db.personalDocuments,
      )..where((d) => d.id.equals(id))).go();
    });
    // Les fichiers ne sont effacés qu'une fois la base à jour : en cas
    // d'interruption, il reste au pire un fichier orphelin, jamais une
    // référence vers un fichier absent.
    for (final f in files) {
      await _files.delete(f.relativePath);
    }
  }

  // ---------------------------------------------------------------------------
  // Fichiers joints

  Future<void> attachFile({
    required String documentId,
    required File source,
    required String originalName,
  }) async {
    final stored = await _files.importFile(
      source: source,
      originalName: originalName,
      documentId: documentId,
    );
    try {
      await _db
          .into(_db.documentFiles)
          .insert(
            DocumentFilesCompanion.insert(
              id: newId(),
              documentId: documentId,
              fileName: originalName,
              relativePath: stored.relativePath,
              mimeType: Value(stored.mimeType),
              sizeBytes: stored.sizeBytes,
              createdAt: DateTime.now(),
            ),
          );
      await _touch(documentId);
    } catch (_) {
      await _files.delete(stored.relativePath);
      rethrow;
    }
  }

  Future<void> removeFile(DocumentFileRow file) async {
    await (_db.delete(
      _db.documentFiles,
    )..where((f) => f.id.equals(file.id))).go();
    await _touch(file.documentId);
    await _files.delete(file.relativePath);
  }

  Future<void> _touch(String documentId) async {
    await (_db.update(_db.personalDocuments)
          ..where((d) => d.id.equals(documentId)))
        .write(PersonalDocumentsCompanion(updatedAt: Value(DateTime.now())));
  }
}

final documentsRepositoryProvider = Provider<DocumentsRepository>(
  (ref) => DocumentsRepository(
    ref.watch(databaseProvider),
    ref.watch(fileStorageProvider),
  ),
);

final documentTypesProvider = StreamProvider<List<DocumentTypeRow>>(
  (ref) => ref.watch(documentsRepositoryProvider).watchTypes(),
);

final documentsProvider = StreamProvider<List<DocumentView>>(
  (ref) => ref.watch(documentsRepositoryProvider).watchDocuments(),
);

final documentDetailProvider = StreamProvider.autoDispose
    .family<DocumentDetail?, String>(
      (ref, id) => ref.watch(documentsRepositoryProvider).watchDocument(id),
    );

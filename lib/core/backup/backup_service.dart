/// Sauvegarde et restauration locales (§ 4.10 du cahier des charges).
///
/// ## Format de sauvegarde, version 1
///
/// Archive ZIP contenant :
///
/// - `manifest.json` :
///   ```json
///   {
///     "format": "dossia-backup",
///     "formatVersion": 1,
///     "schemaVersion": 1,
///     "appVersion": "1.0.0",
///     "createdAt": "2026-10-29T14:03:00.000Z",
///     "includesFiles": true,
///     "counts": {"documentTypes": 30, "documents": 4, "documentFiles": 2,
///                "dossiers": 1, "requiredItems": 5, "links": 3, "tasks": 2,
///                "settings": 3, "includedFiles": 2},
///     "checksums": {"data.json": "<sha256>", "files/<chemin>": "<sha256>"}
///   }
///   ```
/// - `data.json` : une liste de lignes par table (`document_types`,
///   `personal_documents`, `document_files`, `dossiers`, `required_items`,
///   `item_document_links`, `tasks`, `settings`), sérialisées par le
///   `toJson()` généré par drift, dates au format ISO-8601 ;
/// - `files/<chemin relatif>` (facultatif) : les fichiers joints, au même
///   chemin relatif que `document_files.relative_path`.
///
/// Sans fichiers joints (`includesFiles = false`), les lignes de
/// `document_files` sont tout de même exportées pour conserver les
/// métadonnées ; l'application signale alors ces fichiers comme absents.
///
/// À la restauration, l'archive est entièrement vérifiée (format, versions,
/// empreintes SHA-256, cohérence des références, chemins) avant toute
/// modification. Le remplacement des données se fait dans une seule
/// transaction ; les fichiers joints ne sont remplacés qu'après sa validation.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../features/settings/data/settings_repository.dart';
import '../database/app_database.dart';
import '../database/database_provider.dart';
import '../database/seed_data.dart';
import '../files/file_storage_service.dart';
import '../utils/app_info.dart';
import '../utils/errors.dart';

const backupFormat = 'dossia-backup';
const backupFormatVersion = 1;

const _manifestEntry = 'manifest.json';
const _dataEntry = 'data.json';
const _filesPrefix = 'files/';

/// Les dates sont exportées en ISO-8601 plutôt qu'en millisecondes, pour
/// conserver la précision et l'indication UTC/locale.
const _serializer = ValueSerializer.defaults(
  serializeDateTimeValuesAsString: true,
);

class BackupException implements UserFacingError {
  const BackupException(this.message);

  @override
  final String message;

  @override
  String toString() => message;
}

/// Résumé d'une sauvegarde, affiché avant la restauration.
class BackupPreview {
  const BackupPreview({
    required this.createdAt,
    required this.formatVersion,
    required this.schemaVersion,
    required this.appVersion,
    required this.includesFiles,
    required this.documentCount,
    required this.dossierCount,
    required this.requiredItemCount,
    required this.taskCount,
    required this.fileCount,
    required this.missingFileCount,
  });

  final DateTime createdAt;
  final int formatVersion;
  final int schemaVersion;
  final String? appVersion;
  final bool includesFiles;
  final int documentCount;
  final int dossierCount;
  final int requiredItemCount;
  final int taskCount;

  /// Nombre de fichiers joints référencés par les documents.
  final int fileCount;

  /// Fichiers référencés mais absents de l'archive (sauvegarde sans
  /// fichiers, ou fichier déjà introuvable lors de la sauvegarde). Leurs
  /// métadonnées sont restaurées et l'application les signale comme absents.
  final int missingFileCount;
}

class BackupService {
  BackupService({
    required this._db,
    required this._files,
    Future<Directory> Function()? workDirectory,
    this._appVersion,
  }) : _workDirectory = workDirectory ?? getTemporaryDirectory;

  final AppDatabase _db;
  final FileStorageService _files;
  final Future<Directory> Function() _workDirectory;
  final String? _appVersion;

  static const _archivePrefix = 'dossia-sauvegarde-';

  // ---------------------------------------------------------------------------
  // Création

  /// Crée l'archive dans le répertoire de travail et renvoie le fichier.
  ///
  /// Les sauvegardes précédentes laissées dans ce répertoire sont supprimées,
  /// pour ne pas conserver de copies de données personnelles en cache.
  Future<File> createBackup({required bool includeFiles}) async {
    final work = await _workDirectory();
    await work.create(recursive: true);
    await for (final entity in work.list()) {
      final name = p.basename(entity.path);
      if (entity is File &&
          name.startsWith(_archivePrefix) &&
          name.endsWith('.zip')) {
        await entity.delete();
      }
    }

    final data = await _db.transaction(_exportData);
    final dataJson = jsonEncode(data.toJson());

    final attachments = <String, String>{};
    if (includeFiles) {
      for (final f in data.documentFiles) {
        final file = await _files.resolve(f.relativePath);
        if (file != null) attachments[f.relativePath] = file.path;
      }
    }

    final now = DateTime.now();
    final archivePath = p.join(work.path, '$_archivePrefix${_stamp(now)}.zip');
    final manifestBase = <String, Object?>{
      'format': backupFormat,
      'formatVersion': backupFormatVersion,
      'schemaVersion': _db.schemaVersion,
      'appVersion': _appVersion,
      'createdAt': now.toUtc().toIso8601String(),
      'includesFiles': includeFiles,
      'counts': {
        'documentTypes': data.documentTypes.length,
        'documents': data.personalDocuments.length,
        'documentFiles': data.documentFiles.length,
        'dossiers': data.dossiers.length,
        'requiredItems': data.requiredItems.length,
        'links': data.links.length,
        'tasks': data.tasks.length,
        'settings': data.settings.length,
      },
    };

    try {
      await _writeArchiveInIsolate(
        archivePath,
        manifestBase,
        dataJson,
        attachments,
      );
    } on FileSystemException {
      await _deleteQuietly(File(archivePath));
      throw const BackupException(
        "Impossible de créer la sauvegarde. Vérifiez l'espace de stockage disponible.",
      );
    }

    await _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: SettingKeys.lastBackupAt,
            value: now.toUtc().toIso8601String(),
          ),
        );
    return File(archivePath);
  }

  Future<_BackupData> _exportData() async => _BackupData(
    documentTypes: await _db.select(_db.documentTypes).get(),
    personalDocuments: await _db.select(_db.personalDocuments).get(),
    documentFiles: await _db.select(_db.documentFiles).get(),
    dossiers: await _db.select(_db.dossiers).get(),
    requiredItems: await _db.select(_db.requiredItems).get(),
    links: await _db.select(_db.itemDocumentLinks).get(),
    tasks: await _db.select(_db.tasks).get(),
    settings: await _db.select(_db.settings).get(),
  );

  // ---------------------------------------------------------------------------
  // Lecture et restauration

  /// Lit et valide une archive sans rien modifier.
  Future<BackupPreview> inspectBackup(File archive) async {
    final staging = await _createStaging();
    try {
      return (await _load(archive, staging)).preview;
    } finally {
      await _deleteQuietly(staging);
    }
  }

  /// Remplace toutes les données locales par le contenu de l'archive.
  ///
  /// L'archive est d'abord entièrement validée. Les données sont remplacées
  /// dans une seule transaction ; en cas d'échec, rien n'est modifié.
  Future<BackupPreview> restoreBackup(File archive) async {
    final staging = await _createStaging();
    try {
      final loaded = await _load(archive, staging);
      final data = loaded.data;
      final current = await (_db.select(_db.settings)).get();
      final currentSettings = {for (final s in current) s.key: s.value};

      try {
        await _db.transaction(() async {
          await _db.delete(_db.itemDocumentLinks).go();
          await _db.delete(_db.tasks).go();
          await _db.delete(_db.requiredItems).go();
          await _db.delete(_db.dossiers).go();
          await _db.delete(_db.documentFiles).go();
          await _db.delete(_db.personalDocuments).go();
          await (_db.delete(
            _db.documentTypes,
          )..where((t) => t.isCustom.equals(true))).go();
          await _db.delete(_db.settings).go();

          await _db.batch((b) {
            // Le catalogue intégré de cette version de l'application est
            // conservé tel quel ; seuls les types personnalisés sont repris.
            b.insertAll(
              _db.documentTypes,
              data.documentTypes.where((t) => !t.isCustom),
              mode: InsertMode.insertOrIgnore,
            );
            b.insertAll(
              _db.documentTypes,
              data.documentTypes.where((t) => t.isCustom),
            );
            b.insertAll(_db.personalDocuments, data.personalDocuments);
            b.insertAll(_db.documentFiles, data.documentFiles);
            b.insertAll(_db.dossiers, data.dossiers);
            b.insertAll(_db.requiredItems, data.requiredItems);
            b.insertAll(_db.itemDocumentLinks, data.links);
            b.insertAll(_db.tasks, data.tasks);
            b.insertAll(
              _db.settings,
              _mergeSettings(
                data.settings,
                currentSettings,
                loaded.preview.createdAt,
              ),
            );
          });
          await _db.seedBuiltinTypes();
        });
      } catch (_) {
        throw const BackupException(
          "La restauration a échoué. Vos données actuelles n'ont pas été modifiées.",
        );
      }

      await _replaceAttachments(
        Directory(p.join(staging.path, 'files')),
        keepFromCurrent: [
          for (final f in data.documentFiles)
            if (!loaded.archivedFiles.contains(f.relativePath)) f.relativePath,
        ],
      );
      return loaded.preview;
    } finally {
      await _deleteQuietly(staging);
    }
  }

  /// Préférences de la sauvegarde, en conservant l'onboarding terminé et la
  /// date de sauvegarde la plus récente.
  List<SettingRow> _mergeSettings(
    List<SettingRow> restored,
    Map<String, String> current,
    DateTime backupCreatedAt,
  ) {
    final merged = {for (final s in restored) s.key: s.value};
    if (current[SettingKeys.onboardingCompleted] == 'true') {
      merged[SettingKeys.onboardingCompleted] = 'true';
    }
    final candidates = [
      backupCreatedAt.toUtc(),
      DateTime.tryParse(current[SettingKeys.lastBackupAt] ?? '')?.toUtc(),
      DateTime.tryParse(merged[SettingKeys.lastBackupAt] ?? '')?.toUtc(),
    ].whereType<DateTime>().toList()..sort();
    merged[SettingKeys.lastBackupAt] = candidates.last.toIso8601String();
    return [
      for (final e in merged.entries) SettingRow(key: e.key, value: e.value),
    ];
  }

  /// Remplace le répertoire des fichiers joints par les fichiers restaurés.
  ///
  /// Les fichiers référencés mais absents de l'archive ([keepFromCurrent])
  /// sont conservés s'ils existent encore sur l'appareil : restaurer une
  /// sauvegarde sans fichiers sur le même téléphone ne les efface donc pas.
  Future<void> _replaceAttachments(
    Directory staged, {
    required List<String> keepFromCurrent,
  }) async {
    final root = await _files.attachmentsRoot();
    try {
      for (final relative in keepFromCurrent) {
        final current = File(p.join(root.path, relative));
        if (!await current.exists()) continue;
        final target = File(p.join(staged.path, relative));
        await target.parent.create(recursive: true);
        try {
          await current.rename(target.path);
        } on FileSystemException {
          await current.copy(target.path);
        }
      }
      await root.delete(recursive: true);
      if (!await staged.exists()) {
        await root.create(recursive: true);
        return;
      }
      try {
        await staged.rename(root.path);
      } on FileSystemException {
        // Répertoires sur des volumes différents : copie puis suppression.
        await _copyDirectory(staged, root);
      }
    } on FileSystemException {
      throw const BackupException(
        "Les données ont été restaurées, mais certains fichiers joints n'ont pas pu être copiés. Ils sont signalés comme introuvables.",
      );
    }
  }

  Future<Directory> _createStaging() async {
    final work = await _workDirectory();
    await work.create(recursive: true);
    return work.createTemp('dossia-restauration-');
  }

  Future<_LoadedBackup> _load(File archive, Directory staging) async {
    if (!await archive.exists()) {
      throw const BackupException('Fichier de sauvegarde introuvable.');
    }
    final raw = await _readArchiveInIsolate(archive.path, staging.path);
    if (raw.error != null) throw BackupException(raw.error!);

    final manifest = _decodeObject(raw.manifestJson!, _manifestEntry);
    if (manifest['format'] != backupFormat) {
      throw const BackupException(
        "Ce fichier n'est pas une sauvegarde Dossia.",
      );
    }
    final formatVersion = manifest['formatVersion'];
    final schemaVersion = manifest['schemaVersion'];
    if (formatVersion is! int || schemaVersion is! int) {
      throw const BackupException('Sauvegarde invalide : version absente.');
    }
    if (formatVersion > backupFormatVersion ||
        schemaVersion > _db.schemaVersion) {
      throw const BackupException(
        'Cette sauvegarde a été créée par une version plus récente de Dossia. '
        "Mettez l'application à jour avant de la restaurer.",
      );
    }
    final createdAt = DateTime.tryParse(
      manifest['createdAt']?.toString() ?? '',
    );
    final checksums = manifest['checksums'];
    if (createdAt == null || checksums is! Map) {
      throw const BackupException('Sauvegarde invalide : manifeste incomplet.');
    }

    // Empreintes : chaque élément de l'archive doit correspondre au
    // manifeste, et chaque élément annoncé doit être présent.
    final computed = raw.checksums;
    for (final entry in checksums.entries) {
      if (!computed.containsKey(entry.key)) {
        throw const BackupException(
          'Sauvegarde incomplète : des éléments annoncés sont absents de l’archive.',
        );
      }
    }
    for (final entry in computed.entries) {
      if (checksums[entry.key] != entry.value) {
        throw const BackupException(
          'Sauvegarde corrompue : le contrôle d’intégrité a échoué.',
        );
      }
    }

    final data = _parseData(_decodeObject(raw.dataJson!, _dataEntry));
    _validateReferences(data);

    // Fichiers extraits mais non référencés : ignorés.
    final referenced = {for (final f in data.documentFiles) f.relativePath};
    for (final path in raw.extractedFiles) {
      if (!referenced.contains(path)) {
        await _deleteQuietly(File(p.join(staging.path, 'files', path)));
      }
    }
    final present = raw.extractedFiles.toSet();

    return _LoadedBackup(
      data: data,
      archivedFiles: present,
      preview: BackupPreview(
        createdAt: createdAt,
        formatVersion: formatVersion,
        schemaVersion: schemaVersion,
        appVersion: manifest['appVersion']?.toString(),
        includesFiles: manifest['includesFiles'] == true,
        documentCount: data.personalDocuments.length,
        dossierCount: data.dossiers.length,
        requiredItemCount: data.requiredItems.length,
        taskCount: data.tasks.length,
        fileCount: data.documentFiles.length,
        missingFileCount: data.documentFiles
            .where((f) => !present.contains(f.relativePath))
            .length,
      ),
    );
  }

  Map<String, dynamic> _decodeObject(String json, String entry) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Signalé ci-dessous.
    }
    throw BackupException('Sauvegarde invalide : $entry est illisible.');
  }

  _BackupData _parseData(Map<String, dynamic> json) {
    List<T> rows<T>(String key, T Function(Map<String, dynamic>) parse) {
      final list = json[key];
      if (list is! List) {
        throw BackupException('Sauvegarde invalide : table « $key » absente.');
      }
      return [
        for (final item in list)
          if (item is Map<String, dynamic>)
            parse(item)
          else
            throw BackupException(
              'Sauvegarde invalide : ligne illisible dans « $key ».',
            ),
      ];
    }

    try {
      return _BackupData(
        documentTypes: rows(
          'document_types',
          (j) => DocumentTypeRow.fromJson(j, serializer: _serializer),
        ),
        personalDocuments: rows(
          'personal_documents',
          (j) => PersonalDocumentRow.fromJson(j, serializer: _serializer),
        ),
        documentFiles: rows(
          'document_files',
          (j) => DocumentFileRow.fromJson(j, serializer: _serializer),
        ),
        dossiers: rows(
          'dossiers',
          (j) => DossierRow.fromJson(j, serializer: _serializer),
        ),
        requiredItems: rows(
          'required_items',
          (j) => RequiredItemRow.fromJson(j, serializer: _serializer),
        ),
        links: rows(
          'item_document_links',
          (j) => ItemDocumentLinkRow.fromJson(j, serializer: _serializer),
        ),
        tasks: rows(
          'tasks',
          (j) => TaskRow.fromJson(j, serializer: _serializer),
        ),
        settings: rows(
          'settings',
          (j) => SettingRow.fromJson(j, serializer: _serializer),
        ),
      );
    } on BackupException {
      rethrow;
    } catch (_) {
      // Champ manquant, type inattendu, valeur d'énumération inconnue…
      throw const BackupException(
        'Sauvegarde invalide : certaines données sont illisibles.',
      );
    }
  }

  /// Vérifie l'unicité des identifiants et la cohérence de toutes les
  /// références, pour que la restauration ne puisse pas produire de données
  /// incohérentes.
  void _validateReferences(_BackupData data) {
    Set<String> uniqueIds(Iterable<String> ids) {
      final set = <String>{};
      for (final id in ids) {
        if (!set.add(id)) {
          throw const BackupException(
            'Sauvegarde invalide : identifiants en double.',
          );
        }
      }
      return set;
    }

    void check(bool condition) {
      if (!condition) {
        throw const BackupException(
          'Sauvegarde invalide : des références entre les données sont incohérentes.',
        );
      }
    }

    final typeIds = {
      ...uniqueIds(data.documentTypes.map((t) => t.id)),
      for (final t in builtinDocumentTypes) t.id,
    };
    final docIds = uniqueIds(data.personalDocuments.map((d) => d.id));
    uniqueIds(data.documentFiles.map((f) => f.id));
    final dossierIds = uniqueIds(data.dossiers.map((d) => d.id));
    final itemIds = uniqueIds(data.requiredItems.map((i) => i.id));
    uniqueIds(data.links.map((l) => l.id));
    uniqueIds(data.tasks.map((t) => t.id));
    uniqueIds(data.settings.map((s) => s.key));

    for (final d in data.personalDocuments) {
      check(typeIds.contains(d.typeId));
    }
    for (final f in data.documentFiles) {
      check(docIds.contains(f.documentId));
      if (!_isSafeRelativePath(f.relativePath)) {
        throw const BackupException(
          'Sauvegarde invalide : chemin de fichier non autorisé.',
        );
      }
    }
    for (final i in data.requiredItems) {
      check(dossierIds.contains(i.dossierId));
      check(i.typeId == null || typeIds.contains(i.typeId));
      check(i.typeId != null || i.customName != null);
      check(i.quantity >= 1);
    }
    final pairs = <String>{};
    for (final l in data.links) {
      check(itemIds.contains(l.requiredItemId));
      check(docIds.contains(l.personalDocumentId));
      check(l.quantityAssigned >= 1);
      check(pairs.add('${l.requiredItemId}|${l.personalDocumentId}'));
    }
    for (final t in data.tasks) {
      check(dossierIds.contains(t.dossierId));
    }
  }
}

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    db: ref.watch(databaseProvider),
    files: ref.watch(fileStorageProvider),
    appVersion: appVersion,
  ),
);

// -----------------------------------------------------------------------------
// Données et traitements hors du fil principal

class _BackupData {
  const _BackupData({
    required this.documentTypes,
    required this.personalDocuments,
    required this.documentFiles,
    required this.dossiers,
    required this.requiredItems,
    required this.links,
    required this.tasks,
    required this.settings,
  });

  final List<DocumentTypeRow> documentTypes;
  final List<PersonalDocumentRow> personalDocuments;
  final List<DocumentFileRow> documentFiles;
  final List<DossierRow> dossiers;
  final List<RequiredItemRow> requiredItems;
  final List<ItemDocumentLinkRow> links;
  final List<TaskRow> tasks;
  final List<SettingRow> settings;

  Map<String, Object?> toJson() {
    List<Map<String, dynamic>> encode(Iterable<DataClass> rows) => [
      for (final r in rows) r.toJson(serializer: _serializer),
    ];
    return {
      'document_types': encode(documentTypes),
      'personal_documents': encode(personalDocuments),
      'document_files': encode(documentFiles),
      'dossiers': encode(dossiers),
      'required_items': encode(requiredItems),
      'item_document_links': encode(links),
      'tasks': encode(tasks),
      'settings': encode(settings),
    };
  }
}

class _LoadedBackup {
  const _LoadedBackup({
    required this.data,
    required this.preview,
    required this.archivedFiles,
  });

  final _BackupData data;
  final BackupPreview preview;

  /// Chemins relatifs des fichiers joints fournis par l'archive.
  final Set<String> archivedFiles;
}

/// Contenu brut lu dans l'archive, transmis entre isolats.
class _RawArchive {
  const _RawArchive({
    this.error,
    this.manifestJson,
    this.dataJson,
    this.checksums = const {},
    this.extractedFiles = const [],
  });

  final String? error;
  final String? manifestJson;
  final String? dataJson;

  /// Empreintes calculées, par nom d'élément de l'archive.
  final Map<String, String> checksums;

  /// Chemins relatifs des fichiers joints extraits dans `staging/files/`.
  final List<String> extractedFiles;
}

// Les fonctions lancées dans un isolat sont définies au niveau supérieur, pour
// que leur fermeture ne capture que des valeurs transmissibles (jamais la
// base de données).

Future<void> _writeArchiveInIsolate(
  String archivePath,
  Map<String, Object?> manifestBase,
  String dataJson,
  Map<String, String> attachments,
) => Isolate.run(
  () => _writeArchive(archivePath, manifestBase, dataJson, attachments),
);

Future<_RawArchive> _readArchiveInIsolate(
  String archivePath,
  String stagingPath,
) => Isolate.run(() => _readArchive(archivePath, stagingPath));

Future<void> _writeArchive(
  String archivePath,
  Map<String, Object?> manifestBase,
  String dataJson,
  Map<String, String> attachments,
) async {
  final dataBytes = utf8.encode(dataJson);
  final checksums = <String, String>{
    _dataEntry: sha256.convert(dataBytes).toString(),
  };
  final encoder = ZipFileEncoder()..create(archivePath);
  try {
    encoder.addArchiveFile(ArchiveFile.bytes(_dataEntry, dataBytes));
    var included = 0;
    for (final MapEntry(key: relativePath, value: absolutePath)
        in attachments.entries) {
      final file = File(absolutePath);
      // Un fichier disparu entre-temps est simplement omis : il sera
      // signalé comme absent à la restauration.
      if (!await file.exists()) continue;
      final name = '$_filesPrefix$relativePath';
      checksums[name] = (await sha256.bind(file.openRead()).first).toString();
      await encoder.addFile(file, name);
      included++;
    }
    final manifest = {
      ...manifestBase,
      'counts': {
        ...(manifestBase['counts']! as Map<String, Object?>),
        'includedFiles': included,
      },
      'checksums': checksums,
    };
    encoder.addArchiveFile(
      ArchiveFile.bytes(
        _manifestEntry,
        utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest)),
      ),
    );
  } finally {
    await encoder.close();
  }
}

Future<_RawArchive> _readArchive(String archivePath, String stagingPath) async {
  InputFileStream? input;
  try {
    if (!await _hasZipSignature(archivePath)) {
      return const _RawArchive(
        error: "Ce fichier n'est pas une sauvegarde Dossia lisible.",
      );
    }
    input = InputFileStream(archivePath);
    final archive = ZipDecoder().decodeStream(input);
    String? manifestJson;
    String? dataJson;
    final checksums = <String, String>{};
    final extracted = <String>[];

    for (final entry in archive.files) {
      final name = entry.name;
      if (name.startsWith('/') ||
          name.contains('\\') ||
          name.split('/').any((part) => part == '..')) {
        return const _RawArchive(
          error: 'Sauvegarde invalide : chemin de fichier non autorisé.',
        );
      }
      if (!entry.isFile) continue;

      if (name == _manifestEntry) {
        manifestJson = utf8.decode(entry.readBytes() ?? const []);
      } else if (name == _dataEntry) {
        final bytes = entry.readBytes() ?? Uint8List(0);
        checksums[name] = sha256.convert(bytes).toString();
        dataJson = utf8.decode(bytes);
      } else if (name.startsWith(_filesPrefix)) {
        final relative = name.substring(_filesPrefix.length);
        if (!_isSafeRelativePath(relative)) {
          return const _RawArchive(
            error: 'Sauvegarde invalide : chemin de fichier non autorisé.',
          );
        }
        final target = File(p.join(stagingPath, 'files', relative));
        await target.parent.create(recursive: true);
        final output = OutputFileStream(target.path);
        try {
          entry.writeContent(output);
        } finally {
          await output.close();
        }
        checksums[name] = (await sha256.bind(target.openRead()).first)
            .toString();
        extracted.add(relative);
      }
      // Les autres éléments sont ignorés.
    }

    if (manifestJson == null || dataJson == null) {
      return const _RawArchive(
        error: 'Sauvegarde invalide : manifeste ou données absents.',
      );
    }
    return _RawArchive(
      manifestJson: manifestJson,
      dataJson: dataJson,
      checksums: checksums,
      extractedFiles: extracted,
    );
  } on FormatException {
    // Inclut ArchiveException et les erreurs de décodage UTF-8.
    return const _RawArchive(
      error: "Ce fichier n'est pas une sauvegarde Dossia lisible.",
    );
  } on FileSystemException {
    return const _RawArchive(
      error:
          "Impossible de lire la sauvegarde. Vérifiez l'espace de stockage disponible.",
    );
  } catch (_) {
    return const _RawArchive(
      error: "Ce fichier n'est pas une sauvegarde Dossia lisible.",
    );
  } finally {
    await input?.close();
  }
}

/// Les archives ZIP commencent par « PK\x03\x04 » (ou « PK\x05\x06 » si
/// elles sont vides). Le décodeur accepte sinon certains fichiers quelconques
/// comme des archives vides.
Future<bool> _hasZipSignature(String path) async {
  final file = await File(path).open();
  try {
    final header = await file.read(4);
    return header.length == 4 &&
        header[0] == 0x50 &&
        header[1] == 0x4b &&
        ((header[2] == 0x03 && header[3] == 0x04) ||
            (header[2] == 0x05 && header[3] == 0x06));
  } finally {
    await file.close();
  }
}

/// Chemin relatif sans remontée de répertoire ni chemin absolu.
bool _isSafeRelativePath(String path) {
  if (path.isEmpty || path.startsWith('/') || path.contains('\\')) {
    return false;
  }
  if (path.contains(':')) return false;
  return path
      .split('/')
      .every((part) => part.isNotEmpty && part != '.' && part != '..');
}

String _stamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)}-${two(t.hour)}${two(t.minute)}';
}

Future<void> _copyDirectory(Directory source, Directory target) async {
  await target.create(recursive: true);
  await for (final entity in source.list(recursive: true)) {
    final relative = p.relative(entity.path, from: source.path);
    if (entity is File) {
      final dest = File(p.join(target.path, relative));
      await dest.parent.create(recursive: true);
      await entity.copy(dest.path);
    }
  }
  await source.delete(recursive: true);
}

Future<void> _deleteQuietly(FileSystemEntity entity) async {
  try {
    if (await entity.exists()) await entity.delete(recursive: true);
  } on FileSystemException {
    // Nettoyage non critique.
  }
}

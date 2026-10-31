import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dossia/core/backup/backup_service.dart';
import 'package:dossia/core/database/app_database.dart';
import 'package:dossia/core/files/file_storage_service.dart';
import 'package:dossia/core/models/document_category.dart';
import 'package:dossia/core/models/dossier_category.dart';
import 'package:dossia/core/models/stored_statuses.dart';
import 'package:dossia/features/settings/data/settings_repository.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase db;
  late Directory base;
  late Directory work;
  late FileStorageService files;
  late BackupService service;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    base = await Directory.systemTemp.createTemp('dossia_base_');
    work = await Directory.systemTemp.createTemp('dossia_work_');
    files = FileStorageService(baseDirectory: () async => base);
    service = BackupService(
      db: db,
      files: files,
      workDirectory: () async => work,
      appVersion: 'test',
    );
  });

  tearDown(() async {
    await db.close();
    for (final dir in [base, work]) {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });

  /// Jeu de données couvrant toutes les tables, avec un fichier joint.
  Future<({String relativePath, Uint8List bytes})> seed() async {
    final now = DateTime.now();
    await db
        .into(db.documentTypes)
        .insert(
          DocumentTypesCompanion.insert(
            id: 'custom-type',
            name: 'Attestation de bourse',
            category: DocumentCategory.education,
            isCustom: const Value(true),
            createdAt: now,
          ),
        );
    for (final (id, typeId) in [
      ('doc-passport', 'builtin.passport'),
      ('doc-custom', 'custom-type'),
    ]) {
      await db
          .into(db.personalDocuments)
          .insert(
            PersonalDocumentsCompanion.insert(
              id: id,
              typeId: typeId,
              customName: const Value('Mon document'),
              issueDate: Value(DateTime(2020, 2, 29)),
              expiryDate: Value(DateTime(2030, 12, 31)),
              issuer: const Value('Préfecture'),
              notes: const Value('Notes « accentuées » éèà'),
              createdAt: now,
              updatedAt: now,
              archivedAt: id == 'doc-custom'
                  ? Value(now)
                  : const Value.absent(),
            ),
          );
    }

    final bytes = Uint8List.fromList(List.generate(70000, (i) => i % 251));
    final source = File(p.join(work.path, 'scan.pdf'));
    await source.writeAsBytes(bytes);
    final stored = await files.importFile(
      source: source,
      originalName: 'scan.pdf',
      documentId: 'doc-passport',
    );
    await source.delete();
    await db
        .into(db.documentFiles)
        .insert(
          DocumentFilesCompanion.insert(
            id: 'file-1',
            documentId: 'doc-passport',
            fileName: 'scan.pdf',
            relativePath: stored.relativePath,
            mimeType: Value(stored.mimeType),
            sizeBytes: stored.sizeBytes,
            createdAt: now,
          ),
        );

    await db
        .into(db.dossiers)
        .insert(
          DossiersCompanion.insert(
            id: 'dossier-1',
            title: 'Visa France',
            category: const Value(DossierCategory.travel),
            deadline: Value(DateTime(2026, 12, 1)),
            status: const Value(ManualDossierStatus.completed),
            createdAt: now,
            updatedAt: now,
            lastOpenedAt: Value(now),
          ),
        );
    await db
        .into(db.requiredItems)
        .insert(
          RequiredItemsCompanion.insert(
            id: 'item-1',
            dossierId: 'dossier-1',
            typeId: const Value('builtin.passport'),
            quantity: const Value(2),
            status: const Value(ManualItemStatus.toVerify),
            dueDate: Value(DateTime(2026, 11, 15)),
            position: 0,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.requiredItems)
        .insert(
          RequiredItemsCompanion.insert(
            id: 'item-2',
            dossierId: 'dossier-1',
            customName: const Value('Photo récente'),
            isMandatory: const Value(false),
            position: 1,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.itemDocumentLinks)
        .insert(
          ItemDocumentLinksCompanion.insert(
            id: 'link-1',
            requiredItemId: 'item-1',
            personalDocumentId: 'doc-passport',
            quantityAssigned: const Value(2),
            linkedAt: now,
          ),
        );
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: 'task-1',
            dossierId: 'dossier-1',
            title: 'Prendre rendez-vous',
            dueDate: Value(DateTime(2026, 11, 2)),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.settings)
        .insert(
          SettingsCompanion.insert(
            key: SettingKeys.onboardingCompleted,
            value: 'true',
          ),
        );
    await db
        .into(db.settings)
        .insert(
          SettingsCompanion.insert(
            key: SettingKeys.notificationsEnabled,
            value: 'true',
          ),
        );
    return (relativePath: stored.relativePath, bytes: bytes);
  }

  /// Contenu de toutes les tables, hors préférences.
  Future<Map<String, List<DataClass>>> snapshot() async {
    int byId(dynamic a, dynamic b) =>
        (a.id as String).compareTo(b.id as String);
    return {
      'types': (await db.select(db.documentTypes).get())..sort(byId),
      'documents': (await db.select(db.personalDocuments).get())..sort(byId),
      'files': (await db.select(db.documentFiles).get())..sort(byId),
      'dossiers': (await db.select(db.dossiers).get())..sort(byId),
      'items': (await db.select(db.requiredItems).get())..sort(byId),
      'links': (await db.select(db.itemDocumentLinks).get())..sort(byId),
      'tasks': (await db.select(db.tasks).get())..sort(byId),
    };
  }

  Future<Map<String, String>> settings() async => {
    for (final s in await db.select(db.settings).get()) s.key: s.value,
  };

  /// Modifie l'état local pour vérifier que la restauration le remplace.
  Future<void> alterLocalData() async {
    await db.delete(db.itemDocumentLinks).go();
    await db.delete(db.tasks).go();
    await db.delete(db.requiredItems).go();
    await db.delete(db.dossiers).go();
    await db.delete(db.documentFiles).go();
    await db.delete(db.personalDocuments).go();
    final now = DateTime.now();
    await db
        .into(db.dossiers)
        .insert(
          DossiersCompanion.insert(
            id: 'other',
            title: 'Dossier local',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await files.deleteAll();
  }

  /// Réécrit une archive en remplaçant ou ajoutant des éléments.
  Future<File> rewriteArchive(
    File source, {
    Map<String, List<int>> replace = const {},
    Map<String, Object?> Function(Map<String, Object?> manifest)? editManifest,
  }) async {
    final decoded = ZipDecoder().decodeBytes(await source.readAsBytes());
    final out = Archive();
    final contents = <String, List<int>>{
      for (final f in decoded.files)
        if (f.isFile) f.name: f.content,
    }..addAll(replace);
    if (editManifest != null) {
      final manifest =
          jsonDecode(utf8.decode(contents['manifest.json']!))
              as Map<String, Object?>;
      contents['manifest.json'] = utf8.encode(
        jsonEncode(editManifest(manifest)),
      );
    }
    for (final e in contents.entries) {
      out.add(ArchiveFile.bytes(e.key, e.value));
    }
    final target = File(p.join(work.path, 'modifiee.zip'));
    await target.writeAsBytes(ZipEncoder().encodeBytes(out));
    return target;
  }

  Map<String, Object?> Function(Map<String, Object?>) resignData(
    List<int> data,
  ) {
    return (manifest) {
      final checksums = Map<String, Object?>.from(
        manifest['checksums']! as Map,
      );
      checksums['data.json'] = sha256.convert(data).toString();
      return {...manifest, 'checksums': checksums};
    };
  }

  Future<List<int>> editData(
    File archive,
    void Function(Map<String, dynamic> data) edit,
  ) async {
    final decoded = ZipDecoder().decodeBytes(await archive.readAsBytes());
    final data =
        jsonDecode(utf8.decode(decoded.findFile('data.json')!.content))
            as Map<String, dynamic>;
    edit(data);
    return utf8.encode(jsonEncode(data));
  }

  group('sauvegarde complète', () {
    test('restaure toutes les tables et les fichiers joints', () async {
      final attachment = await seed();
      final before = await snapshot();

      final archive = await service.createBackup(includeFiles: true);
      expect(p.basename(archive.path), startsWith('dossia-sauvegarde-'));
      expect(p.extension(archive.path), '.zip');
      expect((await settings())[SettingKeys.lastBackupAt], isNotNull);

      final preview = await service.inspectBackup(archive);
      expect(preview.formatVersion, backupFormatVersion);
      expect(preview.schemaVersion, db.schemaVersion);
      expect(preview.appVersion, 'test');
      expect(preview.includesFiles, isTrue);
      expect(preview.documentCount, 2);
      expect(preview.dossierCount, 1);
      expect(preview.requiredItemCount, 2);
      expect(preview.taskCount, 1);
      expect(preview.fileCount, 1);
      expect(preview.missingFileCount, 0);

      await alterLocalData();
      expect((await snapshot())['dossiers'], hasLength(1));

      await service.restoreBackup(archive);

      final after = await snapshot();
      for (final table in before.keys) {
        expect(after[table], before[table], reason: table);
      }
      final restored = await files.resolve(attachment.relativePath);
      expect(restored, isNotNull);
      expect(await restored!.readAsBytes(), attachment.bytes);

      final restoredSettings = await settings();
      expect(restoredSettings[SettingKeys.onboardingCompleted], 'true');
      expect(restoredSettings[SettingKeys.notificationsEnabled], 'true');
      expect(restoredSettings[SettingKeys.lastBackupAt], isNotNull);
    });

    test('ne laisse pas de fichiers temporaires de restauration', () async {
      await seed();
      final archive = await service.createBackup(includeFiles: true);
      await service.inspectBackup(archive);
      await service.restoreBackup(archive);
      final leftovers = work.listSync().where(
        (e) => p.basename(e.path).startsWith('dossia-restauration-'),
      );
      expect(leftovers, isEmpty);
    });

    test(
      'remplace la sauvegarde précédente du répertoire de travail',
      () async {
        await seed();
        await service.createBackup(includeFiles: false);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await service.createBackup(includeFiles: true);
        final archives = work.listSync().where(
          (e) => p.basename(e.path).startsWith('dossia-sauvegarde-'),
        );
        expect(archives, hasLength(1));
      },
    );

    test("conserve l'onboarding terminé sur l'appareil", () async {
      final archive = await service.createBackup(includeFiles: false);
      await db
          .into(db.settings)
          .insert(
            SettingsCompanion.insert(
              key: SettingKeys.onboardingCompleted,
              value: 'true',
            ),
          );
      await service.restoreBackup(archive);
      expect((await settings())[SettingKeys.onboardingCompleted], 'true');
    });
  });

  group('sauvegarde sans fichiers', () {
    test('restaure les métadonnées et signale les fichiers absents', () async {
      final attachment = await seed();
      final before = await snapshot();
      final archive = await service.createBackup(includeFiles: false);

      final preview = await service.inspectBackup(archive);
      expect(preview.includesFiles, isFalse);
      expect(preview.fileCount, 1);
      expect(preview.missingFileCount, 1);

      // Restauration sur un autre appareil : le fichier n'existe pas.
      final otherBase = await Directory.systemTemp.createTemp('dossia_other_');
      final otherDb = AppDatabase(NativeDatabase.memory());
      final otherFiles = FileStorageService(
        baseDirectory: () async => otherBase,
      );
      final other = BackupService(
        db: otherDb,
        files: otherFiles,
        workDirectory: () async => work,
      );
      try {
        await other.restoreBackup(archive);
        final rows = await otherDb.select(otherDb.documentFiles).get();
        expect(rows, before['files']);
        expect(await otherFiles.resolve(attachment.relativePath), isNull);
      } finally {
        await otherDb.close();
        await otherBase.delete(recursive: true);
      }
    });

    test(
      'conserve les fichiers encore présents sur le même appareil',
      () async {
        final attachment = await seed();
        final archive = await service.createBackup(includeFiles: false);
        await service.restoreBackup(archive);
        final file = await files.resolve(attachment.relativePath);
        expect(file, isNotNull);
        expect(await file!.readAsBytes(), attachment.bytes);
      },
    );
  });

  group('validation', () {
    Future<void> expectRejected(
      File archive,
      Matcher message, {
      bool checkUntouched = true,
    }) async {
      final before = await snapshot();
      final beforeSettings = await settings();
      await expectLater(
        service.inspectBackup(archive),
        throwsA(
          isA<BackupException>().having((e) => e.message, 'message', message),
        ),
      );
      await expectLater(
        service.restoreBackup(archive),
        throwsA(
          isA<BackupException>().having((e) => e.message, 'message', message),
        ),
      );
      if (checkUntouched) {
        final after = await snapshot();
        for (final table in before.keys) {
          expect(after[table], before[table], reason: table);
        }
        expect(await settings(), beforeSettings);
      }
    }

    test("refuse un fichier qui n'est pas une archive", () async {
      await seed();
      final file = File(p.join(work.path, 'faux.zip'));
      await file.writeAsString('ceci n’est pas un zip');
      await expectRejected(file, contains("n'est pas une sauvegarde Dossia"));
    });

    test('refuse une archive sans manifeste', () async {
      final file = File(p.join(work.path, 'vide.zip'));
      final archive = Archive()..add(ArchiveFile.string('autre.txt', 'x'));
      await file.writeAsBytes(ZipEncoder().encodeBytes(archive));
      await expectRejected(file, contains('manifeste ou données absents'));
    });

    test('détecte des données modifiées (empreinte)', () async {
      await seed();
      final archive = await service.createBackup(includeFiles: true);
      final data = await editData(archive, (d) {
        (d['dossiers'] as List).first['title'] = 'Modifié';
      });
      final tampered = await rewriteArchive(
        archive,
        replace: {'data.json': data},
      );
      await expectRejected(tampered, contains('contrôle d’intégrité'));
    });

    test('détecte un fichier joint modifié (empreinte)', () async {
      final attachment = await seed();
      final archive = await service.createBackup(includeFiles: true);
      final tampered = await rewriteArchive(
        archive,
        replace: {
          'files/${attachment.relativePath}': [1, 2, 3],
        },
      );
      await expectRejected(tampered, contains('contrôle d’intégrité'));
    });

    test('refuse un autre format', () async {
      await seed();
      final archive = await service.createBackup(includeFiles: false);
      final other = await rewriteArchive(
        archive,
        editManifest: (m) => {...m, 'format': 'autre-application'},
      );
      await expectRejected(other, contains("n'est pas une sauvegarde Dossia"));
    });

    test('refuse un schéma plus récent', () async {
      await seed();
      final archive = await service.createBackup(includeFiles: false);
      final newer = await rewriteArchive(
        archive,
        editManifest: (m) => {...m, 'schemaVersion': db.schemaVersion + 1},
      );
      await expectRejected(newer, contains('version plus récente'));
    });

    test('refuse un format de sauvegarde plus récent', () async {
      await seed();
      final archive = await service.createBackup(includeFiles: false);
      final newer = await rewriteArchive(
        archive,
        editManifest: (m) => {...m, 'formatVersion': backupFormatVersion + 1},
      );
      await expectRejected(newer, contains('version plus récente'));
    });

    test(
      'refuse des références incohérentes sans toucher aux données',
      () async {
        await seed();
        final archive = await service.createBackup(includeFiles: true);
        final data = await editData(archive, (d) {
          (d['tasks'] as List).first['dossierId'] = 'dossier-inexistant';
        });
        final broken = await rewriteArchive(
          archive,
          replace: {'data.json': data},
          editManifest: resignData(data),
        );
        await expectRejected(broken, contains('incohérentes'));
      },
    );

    test('refuse une association vers un document inexistant', () async {
      await seed();
      final archive = await service.createBackup(includeFiles: false);
      final data = await editData(archive, (d) {
        (d['item_document_links'] as List).first['personalDocumentId'] = 'x';
      });
      final broken = await rewriteArchive(
        archive,
        replace: {'data.json': data},
        editManifest: resignData(data),
      );
      await expectRejected(broken, contains('incohérentes'));
    });

    test('refuse des données illisibles', () async {
      await seed();
      final archive = await service.createBackup(includeFiles: false);
      final data = await editData(archive, (d) {
        (d['dossiers'] as List).first['status'] = 'statut-inconnu';
      });
      final broken = await rewriteArchive(
        archive,
        replace: {'data.json': data},
        editManifest: resignData(data),
      );
      await expectRejected(broken, contains('illisibles'));
    });

    test('refuse un chemin qui sort du répertoire de restauration', () async {
      await seed();
      final archive = await service.createBackup(includeFiles: false);
      final evil = await rewriteArchive(
        archive,
        replace: {'files/../../evasion.txt': utf8.encode('x')},
      );
      await expectRejected(evil, contains('chemin de fichier non autorisé'));
      expect(
        File(p.join(work.parent.path, 'evasion.txt')).existsSync(),
        isFalse,
      );
      expect(File(p.join(work.path, 'evasion.txt')).existsSync(), isFalse);
    });

    test('refuse un chemin de fichier joint forgé dans les données', () async {
      await seed();
      final archive = await service.createBackup(includeFiles: false);
      final data = await editData(archive, (d) {
        (d['document_files'] as List).first['relativePath'] = '../../x.pdf';
      });
      final broken = await rewriteArchive(
        archive,
        replace: {'data.json': data},
        editManifest: resignData(data),
      );
      await expectRejected(broken, contains('chemin de fichier non autorisé'));
    });
  });

  group('sauvegarde protégée par mot de passe', () {
    const password = 'Cotonou-2026!';
    late BackupService secured;

    setUp(() {
      // Itérations réduites pour la vitesse des tests.
      secured = BackupService(
        db: db,
        files: files,
        workDirectory: () async => work,
        appVersion: 'test',
        kdfIterations: 1000,
      );
    });

    List<String> workEntries() =>
        work.listSync().map((e) => p.basename(e.path)).toList()..sort();

    test('aller-retour complet avec mot de passe', () async {
      final attachment = await seed();
      final before = await snapshot();

      final archive = await secured.createBackup(
        includeFiles: true,
        password: password,
      );
      expect(p.extension(archive.path), '.dossia');
      expect(await secured.isEncryptedBackup(archive), isTrue);
      expect((await settings())[SettingKeys.lastBackupAt], isNotNull);
      // Aucune archive en clair ne reste après le chiffrement.
      expect(workEntries(), [p.basename(archive.path)]);
      // Le contenu en clair n'apparaît pas dans le fichier chiffré.
      final raw = await archive.readAsBytes();
      expect(latin1.decode(raw).contains('Visa France'), isFalse);
      expect(latin1.decode(raw).contains('manifest.json'), isFalse);

      await expectLater(
        secured.inspectBackup(archive),
        throwsA(isA<BackupPasswordRequired>()),
      );
      await expectLater(
        secured.inspectBackup(archive, password: 'mauvais-mot-de-passe'),
        throwsA(
          isA<BackupWrongPassword>().having(
            (e) => e.message,
            'message',
            'Mot de passe incorrect.',
          ),
        ),
      );
      final preview = await secured.inspectBackup(archive, password: password);
      expect(preview.documentCount, 2);
      expect(preview.dossierCount, 1);
      expect(preview.fileCount, 1);
      expect(preview.missingFileCount, 0);
      expect(workEntries(), [p.basename(archive.path)]);

      await alterLocalData();
      await expectLater(
        secured.restoreBackup(archive),
        throwsA(isA<BackupPasswordRequired>()),
      );
      expect((await snapshot())['dossiers'], hasLength(1));

      await secured.restoreBackup(archive, password: password);
      final after = await snapshot();
      for (final table in before.keys) {
        expect(after[table], before[table], reason: table);
      }
      final restored = await files.resolve(attachment.relativePath);
      expect(await restored!.readAsBytes(), attachment.bytes);
      // Ni archive en clair ni répertoire temporaire après la restauration.
      expect(workEntries(), [p.basename(archive.path)]);
    });

    test('mot de passe trop court refusé', () async {
      await seed();
      await expectLater(
        secured.createBackup(includeFiles: false, password: '1234567'),
        throwsA(
          isA<BackupException>().having(
            (e) => e.message,
            'message',
            contains('8 caractères'),
          ),
        ),
      );
      expect(workEntries(), isEmpty);
    });

    test('sauvegarde chiffrée endommagée : données locales intactes', () async {
      await seed();
      final archive = await secured.createBackup(
        includeFiles: false,
        password: password,
      );
      final bytes = await archive.readAsBytes();
      bytes[bytes.length - 3] ^= 0x01;
      await archive.writeAsBytes(bytes);
      final before = await snapshot();
      await expectLater(
        secured.restoreBackup(archive, password: password),
        throwsA(
          isA<BackupException>().having(
            (e) => e.message,
            'message',
            contains('endommagée'),
          ),
        ),
      );
      final after = await snapshot();
      for (final table in before.keys) {
        expect(after[table], before[table], reason: table);
      }
      expect(workEntries(), [p.basename(archive.path)]);
    });

    test(
      'remplace aussi les sauvegardes précédentes, chiffrées ou non',
      () async {
        await seed();
        await secured.createBackup(includeFiles: false);
        await secured.createBackup(includeFiles: false, password: password);
        final archives = work.listSync().where(
          (e) => p.basename(e.path).startsWith('dossia-sauvegarde-'),
        );
        expect(archives, hasLength(1));
        expect(p.extension(archives.single.path), '.dossia');
      },
    );

    test(
      'une sauvegarde non chiffrée reste lisible sans mot de passe',
      () async {
        await seed();
        final archive = await secured.createBackup(includeFiles: false);
        expect(await secured.isEncryptedBackup(archive), isFalse);
        final preview = await secured.inspectBackup(
          archive,
          password: 'ignoré',
        );
        expect(preview.documentCount, 2);
      },
    );

    test('le plancher d’itérations réel refuse un fichier de test', () async {
      await seed();
      final archive = await secured.createBackup(
        includeFiles: false,
        password: password,
      );
      // Service de production : 1000 itérations sont sous le plancher.
      await expectLater(
        service.inspectBackup(archive, password: password),
        throwsA(
          isA<BackupException>().having(
            (e) => e.message,
            'message',
            contains('endommagée'),
          ),
        ),
      );
    });
  });
}

import 'dart:io';

import 'package:dossia/core/database/app_database.dart';
import 'package:dossia/core/database/seed_data.dart';
import 'package:dossia/core/files/file_storage_service.dart';
import 'package:dossia/core/models/document_category.dart';
import 'package:dossia/features/deadlines/domain/deadline_models.dart';
import 'package:dossia/features/documents/data/documents_repository.dart';
import 'package:dossia/features/dossiers/data/dossiers_repository.dart';
import 'package:dossia/features/dossiers/domain/dossier_models.dart';
import 'package:dossia/features/dossiers/domain/dossier_progress.dart';
import 'package:dossia/features/requirements/data/requirements_repository.dart';
import 'package:dossia/features/requirements/domain/item_status.dart';
import 'package:dossia/features/settings/data/settings_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const passport = 'builtin.passport';
const birthCertificate = 'builtin.birth_certificate';
const transcript = 'builtin.transcript';

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late FileStorageService files;
  late DocumentsRepository documents;
  late DossiersRepository dossiers;
  late RequirementsRepository requirements;
  final today = DateTime(2026, 10, 29);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('dossia_repo_test');
    files = FileStorageService(baseDirectory: () async => tempDir);
    documents = DocumentsRepository(db, files);
    dossiers = DossiersRepository(db);
    requirements = RequirementsRepository(db);
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<DossierOverview> overviewOf(String dossierId) async {
    final dossier = await dossiers.getDossier(dossierId);
    final reqs = await requirements.loadRequirements(dossierId: dossierId);
    final tasks = await (db.select(
      db.tasks,
    )..where((t) => t.dossierId.equals(dossierId))).get();
    return DossierOverview.build(
      dossier: dossier!,
      requirements: reqs,
      tasks: tasks,
      today: today,
    );
  }

  test('le catalogue de types est installé à la création', () async {
    final types = await db.select(db.documentTypes).get();
    expect(types.length, builtinDocumentTypes.length);
    expect(types.every((t) => !t.isCustom), isTrue);
  });

  test('un document peut être enregistré sans fichier numérique', () async {
    final id = await documents.createDocument(
      const DocumentInput(typeId: passport, customName: '  '),
    );
    final views = await documents.watchDocuments().first;
    expect(views.single.id, id);
    expect(views.single.fileCount, 0);
    expect(views.single.displayName, 'Passeport');
    expect(views.single.doc.expiryDate, isNull);
  });

  test('un dossier peut être créé sans date limite', () async {
    final id = await dossiers.createDossier(
      const DossierInput(title: 'Visa France'),
    );
    final overview = await overviewOf(id);
    expect(overview.dossier.deadline, isNull);
    expect(overview.progress.label, 'Aucune pièce obligatoire');
    expect(overview.status, DossierStatus.inProgress);
  });

  test('pièces obligatoires, facultatives, statuts et progression', () async {
    final dossierId = await dossiers.createDossier(
      const DossierInput(title: 'Visa France'),
    );
    final passportItem = await requirements.createRequirement(
      dossierId,
      const RequirementInput(typeId: passport),
    );
    final birthItem = await requirements.createRequirement(
      dossierId,
      const RequirementInput(typeId: birthCertificate),
    );
    await requirements.createRequirement(
      dossierId,
      const RequirementInput(customName: 'Lettre de soutien', isMandatory: false),
    );

    var o = await overviewOf(dossierId);
    expect(o.items.map((i) => i.status), [
      ItemStatus.missing,
      ItemStatus.missing,
      ItemStatus.optional,
    ]);
    expect(o.progress.percent, 0);

    // Association : la pièce devient disponible, la progression est recalculée.
    final docId = await documents.createDocument(
      const DocumentInput(typeId: passport),
    );
    await requirements.linkDocument(itemId: passportItem, documentId: docId);
    o = await overviewOf(dossierId);
    expect(o.items.first.status, ItemStatus.available);
    expect(o.progress.percent, 50);

    // Condition signalée : à vérifier, ne compte plus comme disponible.
    await requirements.setFlaggedToVerify(passportItem, true);
    o = await overviewOf(dossierId);
    expect(o.items.first.status, ItemStatus.toVerify);
    expect(o.progress.percent, 0);
    expect(o.progress.mandatoryToVerify, 1);

    await requirements.setFlaggedToVerify(passportItem, false);
    final birthDoc = await documents.createDocument(
      const DocumentInput(typeId: birthCertificate),
    );
    await requirements.linkDocument(itemId: birthItem, documentId: birthDoc);
    o = await overviewOf(dossierId);
    // La pièce facultative manquante ne bloque pas la progression.
    expect(o.progress.percent, 100);
    expect(o.status, DossierStatus.readyToCheck);
  });

  test('la progression est émise à nouveau après chaque modification', () async {
    final dossierId = await dossiers.createDossier(
      const DossierInput(title: 'Bourse'),
    );
    final itemId = await requirements.createRequirement(
      dossierId,
      const RequirementInput(typeId: transcript, quantity: 2),
    );
    final docA = await documents.createDocument(
      const DocumentInput(typeId: transcript, customName: 'Relevé L1'),
    );
    final docB = await documents.createDocument(
      const DocumentInput(typeId: transcript, customName: 'Relevé L2'),
    );

    final emitted = <ItemStatus>[];
    final sub = requirements
        .watchRequirements(dossierId: dossierId)
        .listen(
          (items) => emitted.add(items.single.evaluate(today: today).status),
        );
    await pumpEventQueue();
    await requirements.linkDocument(itemId: itemId, documentId: docA);
    await pumpEventQueue();
    await requirements.linkDocument(itemId: itemId, documentId: docB);
    await pumpEventQueue();
    await sub.cancel();

    expect(emitted.first, ItemStatus.missing);
    expect(emitted, contains(ItemStatus.toVerify)); // 1 exemplaire sur 2
    expect(emitted.last, ItemStatus.available);
  });

  test('un même document sert dans plusieurs dossiers ; retirer une '
      'association ne touche ni le document ni les autres dossiers', () async {
    final docId = await documents.createDocument(
      const DocumentInput(typeId: passport),
    );
    final visa = await dossiers.createDossier(const DossierInput(title: 'Visa'));
    final travel = await dossiers.createDossier(
      const DossierInput(title: 'Voyage'),
    );
    final visaItem = await requirements.createRequirement(
      visa,
      const RequirementInput(typeId: passport),
    );
    final travelItem = await requirements.createRequirement(
      travel,
      const RequirementInput(typeId: passport),
    );
    await requirements.linkDocument(itemId: visaItem, documentId: docId);
    await requirements.linkDocument(itemId: travelItem, documentId: docId);

    final detail = await documents.watchDocument(docId).first;
    expect(detail!.usages.map((u) => u.dossierTitle).toSet(), {
      'Visa',
      'Voyage',
    });
    expect(detail.view.usageCount, 2);

    final visaLink = (await overviewOf(visa)).items.single.view.links.single;
    await requirements.unlink(visaLink.link.id);

    expect((await overviewOf(visa)).items.single.status, ItemStatus.missing);
    expect(
      (await overviewOf(travel)).items.single.status,
      ItemStatus.available,
    );
    expect(await documents.watchDocuments().first, hasLength(1));
  });

  test('associer deux fois le même document ne crée pas de doublon', () async {
    final dossierId = await dossiers.createDossier(
      const DossierInput(title: 'Emploi'),
    );
    final item = await requirements.createRequirement(
      dossierId,
      const RequirementInput(customName: 'Photos', quantity: 4),
    );
    final photo = await documents.createDocument(
      const DocumentInput(typeId: 'builtin.id_photo'),
    );
    await requirements.linkDocument(itemId: item, documentId: photo);
    await requirements.linkDocument(
      itemId: item,
      documentId: photo,
      quantity: 4,
    );
    final view = (await overviewOf(dossierId)).items.single;
    expect(view.view.links, hasLength(1));
    expect(view.evaluation.assignedQuantity, 4);
    expect(view.status, ItemStatus.available);
  });

  test('supprimer un dossier conserve les documents de la bibliothèque',
      () async {
    final docId = await documents.createDocument(
      const DocumentInput(typeId: passport),
    );
    final a = await dossiers.createDossier(const DossierInput(title: 'A'));
    final b = await dossiers.createDossier(const DossierInput(title: 'B'));
    final itemA = await requirements.createRequirement(
      a,
      const RequirementInput(typeId: passport),
    );
    final itemB = await requirements.createRequirement(
      b,
      const RequirementInput(typeId: passport),
    );
    await requirements.linkDocument(itemId: itemA, documentId: docId);
    await requirements.linkDocument(itemId: itemB, documentId: docId);
    await dossiers.createTask(a, const TaskInput(title: 'Rendez-vous'));

    await dossiers.deleteDossier(a);

    expect(await dossiers.getDossier(a), isNull);
    expect(await db.select(db.tasks).get(), isEmpty);
    expect(await documents.watchDocuments().first, hasLength(1));
    expect((await overviewOf(b)).items.single.status, ItemStatus.available);
  });

  test('retirer une pièce conserve le document', () async {
    final docId = await documents.createDocument(
      const DocumentInput(typeId: passport),
    );
    final d = await dossiers.createDossier(const DossierInput(title: 'A'));
    final item = await requirements.createRequirement(
      d,
      const RequirementInput(typeId: passport),
    );
    await requirements.linkDocument(itemId: item, documentId: docId);
    await requirements.deleteRequirement(item);
    expect((await overviewOf(d)).items, isEmpty);
    expect(await documents.watchDocuments().first, hasLength(1));
  });

  test('supprimer un document retire ses associations et ses fichiers',
      () async {
    final docId = await documents.createDocument(
      const DocumentInput(typeId: passport),
    );
    final source = File('${tempDir.path}/scan.pdf')
      ..writeAsBytesSync([37, 80, 68, 70]);
    await documents.attachFile(
      documentId: docId,
      source: source,
      originalName: 'scan.pdf',
    );
    final stored = (await db.select(db.documentFiles).get()).single;
    expect(await files.resolve(stored.relativePath), isNotNull);

    final d = await dossiers.createDossier(const DossierInput(title: 'A'));
    final item = await requirements.createRequirement(
      d,
      const RequirementInput(typeId: passport),
    );
    await requirements.linkDocument(itemId: item, documentId: docId);

    await documents.deleteDocument(docId);

    expect(await documents.watchDocuments().first, isEmpty);
    expect(await db.select(db.itemDocumentLinks).get(), isEmpty);
    expect(await db.select(db.documentFiles).get(), isEmpty);
    expect(await files.resolve(stored.relativePath), isNull);
    expect((await overviewOf(d)).items.single.status, ItemStatus.missing);
  });

  test('la base refuse une suppression qui casserait une association',
      () async {
    final docId = await documents.createDocument(
      const DocumentInput(typeId: passport),
    );
    final d = await dossiers.createDossier(const DossierInput(title: 'A'));
    final item = await requirements.createRequirement(
      d,
      const RequirementInput(typeId: passport),
    );
    await requirements.linkDocument(itemId: item, documentId: docId);
    expect(
      () => (db.delete(
        db.personalDocuments,
      )..where((t) => t.id.equals(docId))).go(),
      throwsA(isA<SqliteException>()),
    );
  });

  test('une quantité inférieure à 1 est refusée par la base', () async {
    final d = await dossiers.createDossier(const DossierInput(title: 'A'));
    expect(
      () => requirements.createRequirement(
        d,
        const RequirementInput(customName: 'X', quantity: 0),
      ),
      throwsA(isA<SqliteException>()),
    );
  });

  test('un document archivé reste associé mais passe « À vérifier »', () async {
    final docId = await documents.createDocument(
      const DocumentInput(typeId: passport),
    );
    final d = await dossiers.createDossier(const DossierInput(title: 'A'));
    final item = await requirements.createRequirement(
      d,
      const RequirementInput(typeId: passport),
    );
    await requirements.linkDocument(itemId: item, documentId: docId);
    await documents.setArchived(docId, true);
    final o = await overviewOf(d);
    expect(o.items.single.status, ItemStatus.toVerify);
    expect(o.items.single.evaluation.reasons, {VerifyReason.archivedDocument});
  });

  test('un fichier joint non pris en charge est refusé proprement', () async {
    final docId = await documents.createDocument(
      const DocumentInput(typeId: passport),
    );
    final source = File('${tempDir.path}/notes.exe')..writeAsBytesSync([0]);
    expect(
      () => documents.attachFile(
        documentId: docId,
        source: source,
        originalName: 'notes.exe',
      ),
      throwsA(isA<AttachmentException>()),
    );
    expect(await db.select(db.documentFiles).get(), isEmpty);
  });

  test('réordonner les pièces', () async {
    final d = await dossiers.createDossier(const DossierInput(title: 'A'));
    final ids = [
      for (final name in ['Un', 'Deux', 'Trois'])
        await requirements.createRequirement(
          d,
          RequirementInput(customName: name),
        ),
    ];
    await requirements.reorder(d, ids.reversed.toList());
    final names = (await overviewOf(d)).items.map((i) => i.view.displayName);
    expect(names, ['Trois', 'Deux', 'Un']);
  });

  test('recherche locale insensible aux accents et à la casse', () async {
    await documents.createDocument(
      const DocumentInput(typeId: passport, issuer: 'Préfecture'),
    );
    await documents.createDocument(
      const DocumentInput(typeId: 'builtin.pass_certificate'),
    );
    final views = await documents.watchDocuments().first;
    expect(views.where((v) => v.matches('prefecture')), hasLength(1));
    expect(views.where((v) => v.matches('REUSSITE')), hasLength(1));
    expect(views.where((v) => v.matches('introuvable')), isEmpty);

    final id = await dossiers.createDossier(
      const DossierInput(title: "Inscription à l'université"),
    );
    final o = await overviewOf(id);
    expect(o.matches('universite'), isTrue);
    expect(o.matches('visa'), isFalse);
  });

  test('échéances : dates saisies uniquement, dossiers actifs uniquement',
      () async {
    final docWithExpiry = await documents.createDocument(
      DocumentInput(typeId: passport, expiryDate: DateTime(2026, 11, 20)),
    );
    await documents.createDocument(const DocumentInput(typeId: transcript));
    final active = await dossiers.createDossier(
      DossierInput(title: 'Actif', deadline: DateTime(2026, 12, 1)),
    );
    final archived = await dossiers.createDossier(
      DossierInput(title: 'Archivé', deadline: DateTime(2026, 11, 1)),
    );
    await dossiers.setArchived(archived, true);
    await dossiers.createTask(
      active,
      TaskInput(title: 'Rendez-vous', dueDate: DateTime(2026, 10, 1)),
    );

    final entries = collectDeadlines(
      dossiers: [await overviewOf(active), await overviewOf(archived)],
      documents: await documents.watchDocuments().first,
    );
    expect(entries.map((e) => e.key), [
      startsWith('task:'),
      'document:$docWithExpiry',
      'dossier:$active',
    ]);
    final split = splitDeadlines(entries, today);
    expect(split.overdue.single.kind, DeadlineKind.task);
    expect(split.upcoming, hasLength(2));
  });

  test('effacer toutes les données conserve le catalogue de types', () async {
    await documents.createType(
      name: 'Attestation de stage',
      category: DocumentCategory.other,
    );
    await documents.createDocument(const DocumentInput(typeId: passport));
    await dossiers.createDossier(const DossierInput(title: 'A'));
    final settings = SettingsRepository(db);
    await settings.setBool(SettingKeys.onboardingCompleted, true);

    await settings.wipeAllData();

    expect(await db.select(db.personalDocuments).get(), isEmpty);
    expect(await db.select(db.dossiers).get(), isEmpty);
    expect((await settings.load()).onboardingCompleted, isFalse);
    final types = await db.select(db.documentTypes).get();
    expect(types.length, builtinDocumentTypes.length);
  });

  test('les données persistent après fermeture et réouverture', () async {
    final file = File('${tempDir.path}/dossia.sqlite');
    var fileDb = AppDatabase(NativeDatabase(file));
    final docId = await DocumentsRepository(
      fileDb,
      files,
    ).createDocument(const DocumentInput(typeId: passport));
    final dossierId = await DossiersRepository(
      fileDb,
    ).createDossier(DossierInput(title: 'Visa', deadline: DateTime(2027, 2, 3)));
    await fileDb.close();

    fileDb = AppDatabase(NativeDatabase(file));
    final doc = await (fileDb.select(
      fileDb.personalDocuments,
    )..where((d) => d.id.equals(docId))).getSingle();
    final dossier = await DossiersRepository(fileDb).getDossier(dossierId);
    expect(doc.typeId, passport);
    expect(dossier!.deadline, DateTime(2027, 2, 3));
    // Le catalogue n'est pas dupliqué à la réouverture.
    expect(
      (await fileDb.select(fileDb.documentTypes).get()).length,
      builtinDocumentTypes.length,
    );
    await fileDb.close();
  });
}

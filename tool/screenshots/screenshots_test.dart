// Captures d'écran de l'application avec ses vraies polices, sans émulateur.
//
//   flutter test --update-goldens tool/screenshots/
//
// Les images sont écrites dans tool/screenshots/goldens/ (revue du design,
// fiche Google Play). Ce dossier n'est pas lancé par `flutter test`.
import 'dart:io';

import 'package:dossia/app/app.dart';
import 'package:dossia/app/router.dart';
import 'package:dossia/core/database/app_database.dart';
import 'package:dossia/core/database/database_provider.dart';
import 'package:dossia/core/files/file_storage_service.dart';
import 'package:dossia/core/models/dossier_category.dart';
import 'package:dossia/features/documents/data/documents_repository.dart';
import 'package:dossia/features/dossiers/data/dossiers_repository.dart';
import 'package:dossia/features/requirements/data/requirements_repository.dart';
import 'package:dossia/features/settings/data/settings_repository.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

Future<void> _loadFonts() async {
  final manrope = FontLoader('Manrope');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    manrope.addFont(rootBundle.load('assets/fonts/Manrope-$w.ttf'));
  }
  await manrope.load();
  final root = Platform.environment['FLUTTER_ROOT'] ?? '/home/bocal/flutter';
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      File(
        '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ).readAsBytes().then(ByteData.sublistView),
    );
  await icons.load();
}

class _Ids {
  late String visa, university, internship, passportItem, birthItem, passport;
}

Future<_Ids> _seed(ProviderContainer c) async {
  final ids = _Ids();
  final docs = c.read(documentsRepositoryProvider);
  final dossiers = c.read(dossiersRepositoryProvider);
  final reqs = c.read(requirementsRepositoryProvider);
  final now = DateTime.now();
  DateTime inDays(int d) => DateTime(now.year, now.month, now.day + d);

  ids.passport = await docs.createDocument(
    DocumentInput(
      typeId: 'builtin.passport',
      issueDate: inDays(-900),
      expiryDate: inDays(260),
      issuer: 'Direction de l’émigration et de l’immigration',
    ),
  );
  final idCard = await docs.createDocument(
    DocumentInput(typeId: 'builtin.id_card', expiryDate: inDays(21)),
  );
  final birth = await docs.createDocument(
    const DocumentInput(typeId: 'builtin.birth_certificate'),
  );
  final bac = await docs.createDocument(
    const DocumentInput(
      typeId: 'builtin.baccalaureate',
      customName: 'Baccalauréat série C',
    ),
  );
  final transcriptL1 = await docs.createDocument(
    const DocumentInput(typeId: 'builtin.transcript', customName: 'Relevé L1'),
  );
  final transcriptL2 = await docs.createDocument(
    const DocumentInput(typeId: 'builtin.transcript', customName: 'Relevé L2'),
  );
  final cv = await docs.createDocument(
    const DocumentInput(typeId: 'builtin.cv'),
  );
  await docs.createDocument(
    DocumentInput(typeId: 'builtin.proof_of_address', expiryDate: inDays(-12)),
  );
  await docs.createDocument(
    const DocumentInput(typeId: 'builtin.bank_statement'),
  );

  ids.visa = await dossiers.createDossier(
    DossierInput(
      title: 'Visa études France',
      category: DossierCategory.travel,
      deadline: inDays(34),
      description: 'Dépôt au centre de visas de Cotonou.',
    ),
  );
  ids.passportItem = await reqs.createRequirement(
    ids.visa,
    const RequirementInput(
      typeId: 'builtin.passport',
      instructions: 'Valide au moins 3 mois après le retour',
    ),
  );
  await reqs.linkDocument(itemId: ids.passportItem, documentId: ids.passport);
  ids.birthItem = await reqs.createRequirement(
    ids.visa,
    const RequirementInput(
      typeId: 'builtin.birth_certificate',
      customName: 'Acte de naissance (copie intégrale)',
    ),
  );
  await reqs.linkDocument(itemId: ids.birthItem, documentId: birth);
  await reqs.setFlaggedToVerify(ids.birthItem, true);
  final transcriptsItem = await reqs.createRequirement(
    ids.visa,
    const RequirementInput(typeId: 'builtin.transcript', quantity: 2),
  );
  await reqs.linkDocument(itemId: transcriptsItem, documentId: transcriptL1);
  await reqs.linkDocument(itemId: transcriptsItem, documentId: transcriptL2);
  final bacItem = await reqs.createRequirement(
    ids.visa,
    const RequirementInput(typeId: 'builtin.baccalaureate'),
  );
  await reqs.linkDocument(itemId: bacItem, documentId: bac);
  await reqs.createRequirement(
    ids.visa,
    const RequirementInput(typeId: 'builtin.financial_guarantee'),
  );
  await reqs.createRequirement(
    ids.visa,
    RequirementInput(typeId: 'builtin.travel_insurance', dueDate: inDays(20)),
  );
  await reqs.createRequirement(
    ids.visa,
    const RequirementInput(
      typeId: 'builtin.recommendation_letter',
      isMandatory: false,
    ),
  );
  await dossiers.createTask(
    ids.visa,
    TaskInput(title: 'Prendre rendez-vous au centre de visas', dueDate: inDays(6)),
  );
  await dossiers.createTask(
    ids.visa,
    const TaskInput(title: 'Faire traduire l’acte de naissance'),
  );

  ids.university = await dossiers.createDossier(
    DossierInput(
      title: 'Inscription Université d’Abomey-Calavi',
      category: DossierCategory.studies,
      deadline: inDays(9),
    ),
  );
  for (final (type, doc) in [
    ('builtin.id_card', idCard),
    ('builtin.baccalaureate', bac),
    ('builtin.birth_certificate', birth),
  ]) {
    final item = await reqs.createRequirement(
      ids.university,
      RequirementInput(typeId: type),
    );
    await reqs.linkDocument(itemId: item, documentId: doc);
  }
  await reqs.createRequirement(
    ids.university,
    const RequirementInput(typeId: 'builtin.id_photo', quantity: 4),
  );

  ids.internship = await dossiers.createDossier(
    const DossierInput(
      title: 'Candidature stage télécoms',
      category: DossierCategory.employment,
    ),
  );
  final cvItem = await reqs.createRequirement(
    ids.internship,
    const RequirementInput(typeId: 'builtin.cv'),
  );
  await reqs.linkDocument(itemId: cvItem, documentId: cv);

  final settings = c.read(settingsRepositoryProvider);
  await settings.setBool(SettingKeys.onboardingCompleted, true);
  return ids;
}

void main() {
  late _Ids ids;

  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    Intl.defaultLocale = 'fr_FR';
    await initializeDateFormatting('fr_FR');
    await _loadFonts();
  });

  Future<void> shoot(
    WidgetTester tester,
    String name,
    String Function() location, {
    Brightness brightness = Brightness.light,
    bool seed = true,
    Future<void> Function(WidgetTester)? before,
  }) async {
    debugDisableShadows = false;
    try {
      tester.view.physicalSize = const Size(412 * 2.5, 915 * 2.5);
      tester.view.devicePixelRatio = 2.5;
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      final db = AppDatabase(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          fileStorageProvider.overrideWithValue(
            FileStorageService(
              baseDirectory: () async =>
                  Directory.systemTemp.createTemp('dossia_shots'),
            ),
          ),
          initialLocationProvider.overrideWithValue(Routes.home),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 3));
        container.dispose();
        await tester.runAsync(db.close);
      });
      if (seed) {
        ids = (await tester.runAsync(() => _seed(container)))!;
      }
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const DossiaApp(),
        ),
      );
      // Laisse la base répondre (temps réel) jusqu'à la fin des chargements,
      // puis les animations se terminer.
      Future<void> settle() async {
        for (var i = 0; i < 60; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 50));
          if (i > 5 &&
              find.byType(CircularProgressIndicator).evaluate().isEmpty) {
            break;
          }
        }
        try {
          await tester.pumpAndSettle(
            const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 5),
          );
        } on FlutterError {
          // Animation infinie (indicateur) : on capture l'état courant.
        }
      }

      await settle();
      container.read(routerProvider).go(location());
      await settle();
      if (before != null) {
        await before(tester);
        await settle();
      }
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/$name.png'),
      );

    } finally {
      debugDisableShadows = true;
    }
  }

  final screens = <String, String Function()>{
    '01_accueil': () => Routes.home,
    '02_dossiers': () => Routes.dossiers,
    '03_dossier': () => Routes.dossier(ids.visa),
    '04_piece': () => Routes.item(ids.visa, ids.birthItem),
    '05_piece_formulaire': () => Routes.newItem(ids.visa),
    '06_documents': () => Routes.documents,
    '07_document': () => Routes.document(ids.passport),
    '08_document_formulaire': () => Routes.newDocument(),
    '09_echeances': () => Routes.deadlines,
    '10_reglages': () => Routes.settings,
    '11_sauvegarde': () => Routes.backup,
    '12_confidentialite': () => Routes.privacy,
    '13_dossier_formulaire': () => Routes.newDossier,
    '14_inventaire': () => '${Routes.inventory}?onboarding=1',
  };

  for (final MapEntry(key: name, value: location) in screens.entries) {
    testWidgets(name, (tester) => shoot(tester, name, location));
  }

  testWidgets('00_bienvenue', (tester) async {
    await shoot(tester, '00_bienvenue', () => Routes.welcome, seed: false);
  });
  testWidgets('20_accueil_vide', (tester) async {
    await shoot(tester, '20_accueil_vide', () => Routes.home, seed: false);
  });
  testWidgets('21_dossiers_vide', (tester) async {
    await shoot(tester, '21_dossiers_vide', () => Routes.dossiers, seed: false);
  });
  testWidgets('30_accueil_sombre', (tester) async {
    await shoot(
      tester,
      '30_accueil_sombre',
      () => Routes.home,
      brightness: Brightness.dark,
    );
  });
  testWidgets('31_dossier_sombre', (tester) async {
    await shoot(
      tester,
      '31_dossier_sombre',
      () => Routes.dossier(ids.visa),
      brightness: Brightness.dark,
    );
  });
  testWidgets('32_documents_sombre', (tester) async {
    await shoot(
      tester,
      '32_documents_sombre',
      () => Routes.documents,
      brightness: Brightness.dark,
    );
  });
}

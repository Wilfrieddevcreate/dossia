import 'dart:io';

import 'package:dossia/app/app.dart';
import 'package:dossia/app/router.dart';
import 'package:dossia/features/dashboard/presentation/dashboard_screen.dart';
import 'package:dossia/features/onboarding/presentation/welcome_screen.dart';
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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// Tailles d'écran testées : petit téléphone (avec texte agrandi) et grand
/// téléphone.
const _screens = <String, (Size, double)>{
  'petit écran 320×640, texte ×1,3': (Size(320, 640), 1.3),
  'grand écran 412×915': (Size(412, 915), 1.0),
};

class _Harness {
  _Harness(this.db, this.container);

  final AppDatabase db;
  final ProviderContainer container;

  DocumentsRepository get documents =>
      container.read(documentsRepositoryProvider);
  DossiersRepository get dossiers => container.read(dossiersRepositoryProvider);
  RequirementsRepository get requirements =>
      container.read(requirementsRepositoryProvider);
}

Future<_Harness> _pumpApp(
  WidgetTester tester, {
  required Size size,
  required double textScale,
  bool onboarded = true,
  Future<void> Function(_Harness h)? seed,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  final db = AppDatabase(NativeDatabase.memory());
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      fileStorageProvider.overrideWithValue(
        FileStorageService(
          baseDirectory: () async => Directory.systemTemp.createTemp('dossia'),
        ),
      ),
      initialLocationProvider.overrideWithValue(
        onboarded ? Routes.home : Routes.welcome,
      ),
    ],
  );
  final harness = _Harness(db, container);
  if (seed != null) await tester.runAsync(() => seed(harness));

  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const DossiaApp()),
  );
  await _settle(tester);

  addTearDown(() async {
    // Démonte l'application puis laisse expirer les minuteries de drift et du
    // regroupement des rappels avant de fermer la base.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    container.dispose();
    await tester.runAsync(db.close);
  });
  return harness;
}

/// Laisse la base répondre puis l'interface se stabiliser.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

/// Fait défiler l'écran jusqu'à [finder] : les listes ne construisent que les
/// éléments proches de la zone visible.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  bool found() {
    try {
      return finder.evaluate().isNotEmpty;
    } on StateError {
      return false;
    }
  }

  for (final delta in [-200.0, 200.0]) {
    for (var i = 0; i < 30 && !found(); i++) {
      final scrollable = find.byType(Scrollable).hitTestable();
      if (scrollable.evaluate().isEmpty) break;
      await tester.drag(scrollable.first, Offset(0, delta));
      await tester.pump();
    }
  }
  if (found()) {
    await tester.ensureVisible(finder.first);
    await tester.pumpAndSettle();
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _reveal(tester, finder);
  await tester.tap(finder);
  await _settle(tester);
}

/// Retour arrière via le bouton de l'AppBar (infobulle française « Retour »).
Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Retour').last);
  await _settle(tester);
}

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    Intl.defaultLocale = 'fr_FR';
    await initializeDateFormatting('fr_FR');
  });

  for (final MapEntry(key: label, value: (size, scale)) in _screens.entries) {
    group(label, () {
      testWidgets('premier lancement : sans compte, inventaire ignorable', (
        tester,
      ) async {
        final h = await _pumpApp(
          tester,
          size: size,
          textScale: scale,
          onboarded: false,
        );
        expect(find.byType(WelcomeScreen), findsOneWidget);
        await _tap(tester, find.text('Commencer'));
        expect(find.text('Vos documents'), findsOneWidget);

        await _tap(tester, find.text('Passer'));
        expect(find.byType(DashboardScreen), findsOneWidget);

        final settings = await tester.runAsync(
          () => SettingsRepository(h.db).load(),
        );
        expect(settings!.onboardingCompleted, isTrue);
        final docs = await tester.runAsync(
          () => h.db.select(h.db.personalDocuments).get(),
        );
        expect(docs, isEmpty);
      });

      testWidgets('inventaire initial : sélection de documents possédés', (
        tester,
      ) async {
        final h = await _pumpApp(
          tester,
          size: size,
          textScale: scale,
          onboarded: false,
        );
        await _tap(tester, find.text('Commencer'));
        await _tap(tester, find.text('Passeport'));
        await _tap(tester, find.text('Acte de naissance'));
        await _tap(tester, find.text('Ajouter 2 documents'));
        expect(find.byType(DashboardScreen), findsOneWidget);

        await _tap(tester, find.text('Documents').last);
        expect(find.text('Passeport'), findsOneWidget);
        expect(find.text('Acte de naissance'), findsOneWidget);
        final docs = await tester.runAsync(
          () => h.db.select(h.db.personalDocuments).get(),
        );
        expect(docs, hasLength(2));
      });

      testWidgets('créer un dossier et une pièce manquante', (tester) async {
        await _pumpApp(tester, size: size, textScale: scale);
        await _tap(tester, find.text('Dossiers').last);
        expect(find.text('Aucun dossier pour le moment'), findsOneWidget);

        await _tap(tester, find.text('Créer un dossier').first);
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Nom du dossier *'),
          'Visa France',
        );
        await _tap(tester, find.text('Créer le dossier'));
        expect(find.text('Aucune pièce obligatoire'), findsOneWidget);

        await _tap(tester, find.text('Ajouter une pièce'));
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Nom de la pièce'),
          'Formulaire de demande',
        );
        await _tap(tester, find.text('Ajouter la pièce'));
        // Détail de la pièce : aucun document associé.
        await _reveal(tester, find.text('Manquant'));
        expect(find.text('Manquant'), findsWidgets);

        await _back(tester);
        await _reveal(tester, find.text('0 %'));
        expect(find.text('0 %'), findsOneWidget);
        await _reveal(tester, find.text('En préparation'));
        expect(find.text('En préparation'), findsOneWidget);
      });

      testWidgets('un document existant est proposé puis associé', (
        tester,
      ) async {
        late String dossierId;
        await _pumpApp(
          tester,
          size: size,
          textScale: scale,
          seed: (h) async {
            await h.documents.createDocument(
              const DocumentInput(typeId: 'builtin.passport'),
            );
            dossierId = await h.dossiers.createDossier(
              const DossierInput(title: 'Voyage'),
            );
            await h.requirements.createRequirement(
              dossierId,
              const RequirementInput(typeId: 'builtin.passport'),
            );
            await h.requirements.createRequirement(
              dossierId,
              const RequirementInput(
                customName: 'Assurance',
                isMandatory: false,
              ),
            );
          },
        );
        await _tap(tester, find.text('Dossiers').last);
        await _tap(tester, find.text('Voyage'));
        await _reveal(tester, find.text('0 %'));
        expect(find.text('0 %'), findsOneWidget);

        await _tap(tester, find.text('Passeport').last);
        await _reveal(tester, find.text('Vous avez déjà ce document'));
        expect(find.text('Vous avez déjà ce document'), findsOneWidget);
        await _tap(tester, find.text('Associer'));
        await _reveal(tester, find.text('Disponible'));
        expect(find.text('Disponible'), findsWidgets);

        await _back(tester);
        // La pièce facultative manquante ne bloque pas la progression.
        await _reveal(tester, find.text('100 %'));
        expect(find.text('100 %'), findsOneWidget);
        await _reveal(tester, find.text('Prêt à vérifier'));
        expect(find.text('Prêt à vérifier'), findsOneWidget);
      });

      testWidgets('chaque écran s’affiche sans débordement', (tester) async {
        late String dossierId, itemId, docId;
        final soon = DateTime.now().add(const Duration(days: 10));
        final h = await _pumpApp(
          tester,
          size: size,
          textScale: scale,
          seed: (h) async {
            docId = await h.documents.createDocument(
              DocumentInput(
                typeId: 'builtin.passport',
                customName: 'Passeport biométrique renouvelé',
                issuer: 'Direction de l’émigration et de l’immigration',
                expiryDate: soon,
                notes: 'Original rangé dans la pochette bleue.',
              ),
            );
            dossierId = await h.dossiers.createDossier(
              DossierInput(
                title: 'Demande de visa long séjour études France',
                category: DossierCategory.administrative,
                deadline: soon.add(const Duration(days: 30)),
                description: 'Dépôt au centre de visas.',
                notes: 'Apporter les originaux.',
              ),
            );
            itemId = await h.requirements.createRequirement(
              dossierId,
              RequirementInput(
                typeId: 'builtin.passport',
                quantity: 2,
                instructions: 'Copie certifiée conforme de moins de 3 mois',
                dueDate: soon,
              ),
            );
            await h.requirements.linkDocument(itemId: itemId, documentId: docId);
            await h.requirements.createRequirement(
              dossierId,
              const RequirementInput(
                customName: 'Attestation de prise en charge financière',
                isMandatory: false,
              ),
            );
            await h.dossiers.createTask(
              dossierId,
              TaskInput(title: 'Prendre rendez-vous au consulat', dueDate: soon),
            );
          },
        );
        final router = h.container.read(routerProvider);
        for (final location in [
          Routes.home,
          Routes.dossiers,
          Routes.documents,
          Routes.settings,
          Routes.dossier(dossierId),
          Routes.item(dossierId, itemId),
          Routes.editItem(dossierId, itemId),
          Routes.newItem(dossierId),
          Routes.editDossier(dossierId),
          Routes.newDossier,
          Routes.document(docId),
          Routes.editDocument(docId),
          Routes.newDocument(),
          Routes.reorderItems(dossierId),
          Routes.deadlines,
          Routes.backup,
          Routes.privacy,
          Routes.inventory,
        ]) {
          router.go(location);
          await _settle(tester);
          // Parcourt l'écran de haut en bas pour construire tout son contenu.
          final scrollable = find.byType(Scrollable).hitTestable();
          if (scrollable.evaluate().isNotEmpty) {
            await tester.fling(scrollable.first, const Offset(0, -3000), 3000);
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull, reason: location);
        }
      });
    });
  }
}

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../models/document_category.dart';
import '../models/dossier_category.dart';
import '../models/stored_statuses.dart';
import 'converters.dart';
import 'seed_data.dart';
import 'tables.dart';

export 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    DocumentTypes,
    PersonalDocuments,
    DocumentFiles,
    Dossiers,
    RequiredItems,
    ItemDocumentLinks,
    Tasks,
    Settings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  /// Version du schéma. Toute modification de table doit incrémenter ce
  /// numéro, ajouter une étape dans [migration] et un instantané dans
  /// `drift_schemas/` (`dart run drift_dev make-migrations`).
  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'dossia',
      native: const DriftNativeOptions(
        // Répertoire privé de l'application, non visible des autres apps.
        databaseDirectory: getApplicationSupportDirectory,
      ),
    );
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await seedBuiltinTypes();
    },
    onUpgrade: (m, from, to) async {
      // Aucune migration pour l'instant (schéma v1). Les étapes futures
      // seront ajoutées ici, une par version, sans jamais supprimer de
      // données existantes.
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      if (details.hadUpgrade) {
        await seedBuiltinTypes();
      }
    },
  );

  /// Insère les types du catalogue manquants, sans toucher aux existants.
  Future<void> seedBuiltinTypes() async {
    final now = DateTime.now();
    await batch((b) {
      b.insertAll(documentTypes, [
        for (final t in builtinDocumentTypes)
          DocumentTypesCompanion.insert(
            id: t.id,
            name: t.name,
            category: t.category,
            description: Value(t.description),
            expiryApplicable: Value(t.expiryApplicable),
            isCustom: const Value(false),
            createdAt: now,
          ),
      ], mode: InsertMode.insertOrIgnore);
    });
  }
}

import 'package:dossia/core/database/app_database.dart';
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';

/// Vérifie le schéma de la base par rapport aux instantanés versionnés de
/// `drift_schemas/`. À chaque nouvelle version du schéma :
/// 1. incrémenter `schemaVersion` et écrire l'étape dans `onUpgrade` ;
/// 2. `dart run drift_dev make-migrations` (nouvel instantané + helpers) ;
/// 3. ajouter ici un test `migrateAndValidate` depuis chaque ancienne version
///    et un test vérifiant que les données existantes sont conservées.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('le schéma créé correspond à l’instantané v1', () async {
    final schema = await verifier.schemaAt(1);
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 1);
    await db.close();
  });

  test('ouvrir une base v1 existante conserve ses données', () async {
    final schema = await verifier.schemaAt(1);
    // Base v1 créée avec le schéma figé, contenant un document.
    final old = schema.newConnection();
    await old.ensureOpen(_NoMigrationUser());
    await old.runCustom(
      "INSERT INTO document_types (id, name, category, expiry_applicable, "
      "is_custom, created_at) VALUES ('t1', 'Type perso', 'other', 0, 1, "
      "'2026-01-01T00:00:00.000')",
    );
    await old.runCustom(
      "INSERT INTO personal_documents (id, type_id, created_at, updated_at) "
      "VALUES ('d1', 't1', '2026-01-01T00:00:00.000', "
      "'2026-01-01T00:00:00.000')",
    );

    final db = AppDatabase(old);
    final docs = await db.select(db.personalDocuments).get();
    expect(docs.single.id, 'd1');
    final types = await db.select(db.documentTypes).get();
    expect(types.where((t) => t.isCustom).single.name, 'Type perso');
    // Même version : aucune migration ni réinsertion du catalogue, les
    // données existantes sont lues telles quelles.
    expect(types, hasLength(1));
    await db.close();
  });
}

class _NoMigrationUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'app_database.dart';

/// Base de données de l'application. Remplacée par une base en mémoire dans
/// les tests via `ProviderScope(overrides: [...])`.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

const _uuid = Uuid();

String newId() => _uuid.v4();

extension WatchComputed on AppDatabase {
  /// Émet le résultat de [compute] puis le recalcule à chaque modification de
  /// l'une des [tables]. Le calcul est fait dans une transaction pour lire un
  /// état cohérent de la base.
  ///
  /// Le déclencheur est une requête surveillée par drift : elle émet à chaque
  /// modification des tables et gère proprement l'annulation de l'abonnement.
  Stream<T> watchComputed<T>(
    Set<TableInfo> tables,
    Future<T> Function() compute,
  ) {
    return customSelect(
      'SELECT 1',
      readsFrom: tables,
    ).watch().asyncMap((_) => transaction(compute));
  }
}

/// Transforme une chaîne saisie en valeur nullable : les champs vides sont
/// enregistrés comme absents.
String? cleanText(String? value) {
  final trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

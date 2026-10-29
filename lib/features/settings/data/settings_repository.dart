import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';

/// Clés de la table `settings`.
abstract final class SettingKeys {
  static const onboardingCompleted = 'onboarding_completed';
  static const notificationsEnabled = 'notifications_enabled';
  static const deadlineReminderDays = 'deadline_reminder_days';
  static const expiryReminderDays = 'expiry_reminder_days';
  static const lastBackupAt = 'last_backup_at';
}

/// Préférences de l'application, avec leurs valeurs par défaut.
class AppSettings {
  const AppSettings(this._values);

  final Map<String, String> _values;

  Map<String, String> get raw => Map.unmodifiable(_values);

  bool get onboardingCompleted =>
      _values[SettingKeys.onboardingCompleted] == 'true';

  /// Les rappels sont désactivés tant que l'utilisateur ne les a pas activés.
  bool get notificationsEnabled =>
      _values[SettingKeys.notificationsEnabled] == 'true';

  int get deadlineReminderDays =>
      int.tryParse(_values[SettingKeys.deadlineReminderDays] ?? '') ?? 3;

  int get expiryReminderDays =>
      int.tryParse(_values[SettingKeys.expiryReminderDays] ?? '') ?? 30;

  DateTime? get lastBackupAt =>
      DateTime.tryParse(_values[SettingKeys.lastBackupAt] ?? '');
}

class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  Stream<AppSettings> watch() => _db
      .select(_db.settings)
      .watch()
      .map((rows) => AppSettings({for (final r in rows) r.key: r.value}));

  Future<AppSettings> load() async {
    final rows = await _db.select(_db.settings).get();
    return AppSettings({for (final r in rows) r.key: r.value});
  }

  Future<void> set(String key, String value) async {
    await _db
        .into(_db.settings)
        .insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));
  }

  Future<void> setBool(String key, bool value) => set(key, value.toString());

  Future<void> setInt(String key, int value) => set(key, value.toString());

  /// Efface toutes les données (documents, dossiers, préférences) et remet le
  /// catalogue des types par défaut. Les fichiers joints sont supprimés par
  /// l'appelant.
  Future<void> wipeAllData() async {
    await _db.transaction(() async {
      await _db.delete(_db.itemDocumentLinks).go();
      await _db.delete(_db.tasks).go();
      await _db.delete(_db.requiredItems).go();
      await _db.delete(_db.dossiers).go();
      await _db.delete(_db.documentFiles).go();
      await _db.delete(_db.personalDocuments).go();
      await _db.delete(_db.documentTypes).go();
      await _db.delete(_db.settings).go();
      await _db.seedBuiltinTypes();
    });
  }
}

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(databaseProvider)),
);

final settingsProvider = StreamProvider<AppSettings>(
  (ref) => ref.watch(settingsRepositoryProvider).watch(),
);

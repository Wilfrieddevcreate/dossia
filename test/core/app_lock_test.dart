import 'package:dossia/core/database/app_database.dart';
import 'package:dossia/core/database/database_provider.dart';
import 'package:dossia/core/security/app_lock.dart';
import 'package:dossia/features/settings/data/settings_repository.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeDeviceAuth extends DeviceAuth {
  FakeDeviceAuth({this.available = true, this.outcome = AuthOutcome.success});

  bool available;
  AuthOutcome outcome;
  int prompts = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<AuthOutcome> authenticate(String reason) async {
    prompts++;
    return outcome;
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late ProviderContainer container;
  late FakeDeviceAuth auth;
  late DateTime now;

  Future<void> setUpWith({
    required bool lockEnabled,
    bool initiallyLocked = false,
  }) async {
    db = AppDatabase(NativeDatabase.memory());
    auth = FakeDeviceAuth();
    now = DateTime(2026, 10, 30, 10);
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        deviceAuthProvider.overrideWithValue(auth),
        initialAppLockProvider.overrideWithValue(initiallyLocked),
        appLockClockProvider.overrideWithValue(() => now),
      ],
    );
    await container
        .read(settingsRepositoryProvider)
        .setBool(SettingKeys.appLockEnabled, lockEnabled);
    // Le contrôleur lit les préférences déjà chargées, comme dans l'app.
    container.listen(settingsProvider, (_, _) {});
    await container.read(settingsProvider.future);
    await pumpEventQueue();
  }

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  AppLockController lock() => container.read(appLockProvider.notifier);
  bool locked() => container.read(appLockProvider);

  test('verrouillée au démarrage si l’option est active', () async {
    await setUpWith(lockEnabled: true, initiallyLocked: true);
    expect(locked(), isTrue);
    expect(await lock().unlock(), AuthOutcome.success);
    expect(locked(), isFalse);
  });

  test('se verrouille après 30 secondes hors de l’application', () async {
    await setUpWith(lockEnabled: true);
    lock().onBackground();
    now = now.add(const Duration(seconds: 29));
    lock().onForeground();
    expect(locked(), isFalse);

    lock().onBackground();
    now = now.add(appLockGracePeriod);
    lock().onForeground();
    expect(locked(), isTrue);
  });

  test('ne se verrouille pas si l’option est désactivée', () async {
    await setUpWith(lockEnabled: false);
    lock().onBackground();
    now = now.add(const Duration(minutes: 10));
    lock().onForeground();
    expect(locked(), isFalse);
  });

  test('pas de verrouillage au retour de l’appareil photo ou du sélecteur',
      () async {
    await setUpWith(lockEnabled: true);
    lock().onBackground();
    ExternalActivity.expect();
    now = now.add(const Duration(minutes: 2));
    lock().onForeground();
    expect(locked(), isFalse);

    // Le passe-droit ne sert qu'une fois.
    lock().onBackground();
    now = now.add(const Duration(minutes: 2));
    lock().onForeground();
    expect(locked(), isTrue);
  });

  test('un échec ou une annulation laisse l’application verrouillée',
      () async {
    await setUpWith(lockEnabled: true, initiallyLocked: true);
    auth.outcome = AuthOutcome.cancelled;
    expect(await lock().unlock(), AuthOutcome.cancelled);
    expect(locked(), isTrue);
    auth.outcome = AuthOutcome.lockedOut;
    expect(await lock().unlock(), AuthOutcome.lockedOut);
    expect(locked(), isTrue);
  });

  test('sans verrouillage du téléphone, Dossia se déverrouille et désactive '
      'l’option (jamais de blocage définitif)', () async {
    await setUpWith(lockEnabled: true, initiallyLocked: true);
    auth.available = false;
    expect(await lock().unlock(), AuthOutcome.unavailable);
    expect(locked(), isFalse);
    final settings = await container.read(settingsRepositoryProvider).load();
    expect(settings.appLockEnabled, isFalse);
  });

  test('activer ou désactiver demande une authentification', () async {
    await setUpWith(lockEnabled: false);
    auth.outcome = AuthOutcome.cancelled;
    expect(await lock().setEnabled(true), AuthOutcome.cancelled);
    expect(
      (await container.read(settingsRepositoryProvider).load()).appLockEnabled,
      isFalse,
    );

    auth.outcome = AuthOutcome.success;
    expect(await lock().setEnabled(true), AuthOutcome.success);
    expect(
      (await container.read(settingsRepositoryProvider).load()).appLockEnabled,
      isTrue,
    );
    expect(auth.prompts, 2);

    expect(await lock().setEnabled(false), AuthOutcome.success);
    expect(
      (await container.read(settingsRepositoryProvider).load()).appLockEnabled,
      isFalse,
    );
  });

  test('impossible d’activer sans verrouillage configuré sur le téléphone',
      () async {
    await setUpWith(lockEnabled: false);
    auth.available = false;
    expect(await lock().setEnabled(true), AuthOutcome.unavailable);
    expect(auth.prompts, 0);
  });
}

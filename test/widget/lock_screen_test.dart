import 'dart:io';

import 'package:dossia/app/app.dart';
import 'package:dossia/app/router.dart';
import 'package:dossia/core/database/app_database.dart';
import 'package:dossia/core/database/database_provider.dart';
import 'package:dossia/core/files/file_storage_service.dart';
import 'package:dossia/core/security/app_lock.dart';
import 'package:dossia/core/security/lock_screen.dart';
import 'package:dossia/features/dashboard/presentation/dashboard_screen.dart';
import 'package:dossia/features/settings/data/settings_repository.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import '../core/app_lock_test.dart' show FakeDeviceAuth;

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    Intl.defaultLocale = 'fr_FR';
    await initializeDateFormatting('fr_FR');
  });

  testWidgets('application verrouillée : contenu masqué jusqu’au '
      'déverrouillage', (tester) async {
    tester.view.physicalSize = const Size(412 * 3, 915 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final db = AppDatabase(NativeDatabase.memory());
    final auth = FakeDeviceAuth(outcome: AuthOutcome.cancelled);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        fileStorageProvider.overrideWithValue(
          FileStorageService(
            baseDirectory: () async => Directory.systemTemp.createTemp('lock'),
          ),
        ),
        initialLocationProvider.overrideWithValue(Routes.home),
        initialAppLockProvider.overrideWithValue(true),
        deviceAuthProvider.overrideWithValue(auth),
      ],
    );
    await tester.runAsync(
      () => container
          .read(settingsRepositoryProvider)
          .setBool(SettingKeys.appLockEnabled, true),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
      container.dispose();
      await tester.runAsync(db.close);
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const DossiaApp()),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 100));
    }

    // L'invite s'est ouverte d'elle-même ; annulée, l'écran reste verrouillé.
    expect(auth.prompts, 1);
    expect(find.byType(LockScreen), findsOneWidget);
    expect(find.text('Dossia est verrouillé'), findsOneWidget);
    // Le contenu de l'accueil n'est pas exposé aux lecteurs d'écran.
    expect(find.bySemanticsLabel(RegExp('Échéances')), findsNothing);

    auth.outcome = AuthOutcome.success;
    await tester.tap(find.text('Déverrouiller'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(find.byType(LockScreen), findsNothing);
    expect(find.byType(DashboardScreen), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'app/app.dart';
import 'app/router.dart';
import 'core/notifications/notification_service.dart';
import 'features/settings/data/settings_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Affichage bord à bord sur toutes les versions d'Android.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  Intl.defaultLocale = 'fr_FR';
  await initializeDateFormatting('fr_FR');

  // L'emplacement initial dépend de l'onboarding : il est lu avant la
  // création du routeur.
  var initialLocation = Routes.home;
  final container = ProviderContainer(
    overrides: [initialLocationProvider.overrideWith((ref) => initialLocation)],
  );
  final settings = await container.read(settingsRepositoryProvider).load();
  if (!settings.onboardingCompleted) initialLocation = Routes.welcome;

  // Les rappels ne doivent jamais empêcher l'ouverture de l'application.
  try {
    await container
        .read(notificationServiceProvider)
        .init(
          // Navigation différée : au lancement depuis une notification, le
          // navigateur n'est pas encore construit.
          onTap: (route) {
            WidgetsBinding.instance
              ..addPostFrameCallback(
                (_) => container.read(routerProvider).push(route),
              )
              ..scheduleFrame();
          },
        );
  } catch (_) {}

  runApp(
    UncontrolledProviderScope(container: container, child: const DossiaApp()),
  );
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notifications/notification_service.dart';
import '../core/security/app_lock.dart';
import '../core/security/lock_screen.dart';
import '../core/utils/today_provider.dart';
import '../features/deadlines/data/deadlines_provider.dart';
import '../features/deadlines/domain/reminder_planner.dart';
import '../features/settings/data/settings_repository.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class DossiaApp extends ConsumerStatefulWidget {
  const DossiaApp({super.key});

  @override
  ConsumerState<DossiaApp> createState() => _DossiaAppState();
}

class _DossiaAppState extends ConsumerState<DossiaApp>
    with WidgetsBindingObserver {
  Timer? _reminderDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reminderDebounce?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = ref.read(appLockProvider.notifier);
    if (state == AppLifecycleState.paused) lock.onBackground();
    if (state == AppLifecycleState.resumed) {
      lock.onForeground();
      ref.read(todayProvider.notifier).refresh();
    }
  }

  /// Reprogramme les rappels après chaque modification des échéances ou des
  /// préférences, avec un léger délai pour regrouper les saisies.
  void _scheduleReminderSync() {
    _reminderDebounce?.cancel();
    _reminderDebounce = Timer(const Duration(seconds: 2), () async {
      final settings = ref.read(settingsProvider).value;
      final deadlines = ref.read(deadlinesProvider).value;
      if (settings == null || deadlines == null) return;
      final service = ref.read(notificationServiceProvider);
      try {
        if (!settings.notificationsEnabled) {
          await service.cancelAll();
          return;
        }
        await service.replaceAll(
          planReminders(
            deadlines,
            now: DateTime.now(),
            deadlineLeadDays: settings.deadlineReminderDays,
            expiryLeadDays: settings.expiryReminderDays,
          ),
        );
      } catch (_) {
        // Un échec de programmation ne doit pas bloquer l'application ; il
        // sera retenté à la prochaine modification.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(deadlinesProvider, (_, _) => _scheduleReminderSync());
    ref.listen(settingsProvider, (_, _) => _scheduleReminderSync());

    return MaterialApp.router(
      title: 'Dossia',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      routerConfig: ref.watch(routerProvider),
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // Barres système transparentes, icônes assorties au thème.
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            statusBarBrightness: dark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarIconBrightness: dark
                ? Brightness.light
                : Brightness.dark,
            systemNavigationBarContrastEnforced: false,
          ),
          child: AppLockGate(child: child!),
        );
      },
    );
  }
}

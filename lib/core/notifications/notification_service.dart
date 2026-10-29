import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../features/deadlines/domain/reminder_planner.dart';

/// Rappels locaux (aucun serveur). Les notifications sont programmées par
/// Android avec `inexactAllowWhileIdle`, sans permission d'alarme exacte.
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  /// Chemin à ouvrir lorsque l'utilisateur touche une notification.
  static const tapRoute = '/deadlines';

  static const _channel = AndroidNotificationDetails(
    'dossia_reminders',
    'Rappels et échéances',
    channelDescription:
        'Rappels avant les dates limites et les dates d\'expiration.',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    // Le contenu (nom des documents) est masqué sur l'écran de verrouillage.
    visibility: NotificationVisibility.private,
  );

  Future<void> init({void Function(String route)? onTap}) async {
    if (_ready || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    tzdata.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (_) {
      // Fuseau inconnu : on garde UTC plutôt que d'échouer.
      tz.setLocalLocation(tz.UTC);
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) =>
          onTap?.call(response.payload ?? tapRoute),
    );
    _ready = true;

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      onTap?.call(launch!.notificationResponse?.payload ?? tapRoute);
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  /// Demande l'autorisation d'afficher des notifications (Android 13+).
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    return await _android?.requestNotificationsPermission() ?? false;
  }

  Future<bool> areEnabled() async {
    if (!_ready) return false;
    return await _android?.areNotificationsEnabled() ?? false;
  }

  /// Remplace tous les rappels programmés par [reminders].
  Future<void> replaceAll(List<PlannedReminder> reminders) async {
    if (!_ready) return;
    await _plugin.cancelAll();
    for (var i = 0; i < reminders.length; i++) {
      final r = reminders[i];
      await _plugin.zonedSchedule(
        id: i + 1,
        title: r.title,
        body: r.body,
        scheduledDate: tz.TZDateTime(
          tz.local,
          r.at.year,
          r.at.month,
          r.at.day,
          r.at.hour,
          r.at.minute,
        ),
        notificationDetails: const NotificationDetails(android: _channel),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: tapRoute,
      );
    }
  }

  Future<void> cancelAll() async {
    if (_ready) await _plugin.cancelAll();
  }
}

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);

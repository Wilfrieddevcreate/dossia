import '../../../core/utils/dates.dart';
import 'deadline_models.dart';

/// Heure locale à laquelle les rappels sont déclenchés.
const reminderHour = 9;

/// Nombre maximal de rappels programmés à la fois (Android limite le nombre
/// d'alarmes par application).
const maxScheduledReminders = 60;

class PlannedReminder {
  const PlannedReminder({
    required this.at,
    required this.title,
    required this.body,
    required this.entryKey,
  });

  /// Date et heure locales du rappel.
  final DateTime at;
  final String title;
  final String body;
  final String entryKey;
}

/// Calcule les rappels à programmer : un rappel [leadDays] jours avant
/// l'échéance et un rappel le jour même, à [reminderHour] heures. Seuls les
/// rappels futurs sont retenus, au plus [maxScheduledReminders].
List<PlannedReminder> planReminders(
  Iterable<DeadlineEntry> entries, {
  required DateTime now,
  required int deadlineLeadDays,
  required int expiryLeadDays,
}) {
  final reminders = <PlannedReminder>[];
  for (final entry in entries) {
    final lead = entry.kind == DeadlineKind.documentExpiry
        ? expiryLeadDays
        : deadlineLeadDays;
    final day = dateOnly(entry.date);
    final candidates = <(DateTime, int)>[
      if (lead > 0) (day.subtract(Duration(days: lead)), lead),
      (day, 0),
    ];
    for (final (date, daysBefore) in candidates) {
      final at = DateTime(date.year, date.month, date.day, reminderHour);
      if (!at.isAfter(now)) continue;
      reminders.add(
        PlannedReminder(
          at: at,
          title: _title(entry.kind),
          body: _body(entry, daysBefore),
          entryKey: entry.key,
        ),
      );
    }
  }
  reminders.sort((a, b) => a.at.compareTo(b.at));
  return reminders.take(maxScheduledReminders).toList();
}

String _title(DeadlineKind kind) => switch (kind) {
  DeadlineKind.documentExpiry => 'Document bientôt expiré',
  DeadlineKind.dossier => 'Date limite de dossier',
  DeadlineKind.task => 'Tâche à faire',
  DeadlineKind.item => 'Pièce à fournir',
};

String _body(DeadlineEntry entry, int daysBefore) {
  final when = daysBefore == 0
      ? "aujourd'hui"
      : daysBefore == 1
      ? 'demain'
      : 'dans $daysBefore jours';
  final verb = entry.kind == DeadlineKind.documentExpiry
      ? 'expire'
      : 'arrive à échéance';
  return '${entry.title} $verb $when.';
}

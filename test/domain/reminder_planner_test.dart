import 'package:dossia/features/deadlines/domain/deadline_models.dart';
import 'package:dossia/features/deadlines/domain/reminder_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 29, 14);

  DeadlineEntry entry(DeadlineKind kind, DateTime date, [String key = 'k']) =>
      DeadlineEntry(key: key, kind: kind, date: date, title: 'Passeport');

  test('un rappel avant l’échéance et un le jour même, à 9 h', () {
    final reminders = planReminders(
      [entry(DeadlineKind.dossier, DateTime(2026, 11, 10))],
      now: now,
      deadlineLeadDays: 3,
      expiryLeadDays: 30,
    );
    expect(reminders.map((r) => r.at), [
      DateTime(2026, 11, 7, 9),
      DateTime(2026, 11, 10, 9),
    ]);
    expect(reminders.last.body, contains("aujourd'hui"));
  });

  test('le délai d’expiration s’applique aux documents', () {
    final reminders = planReminders(
      [entry(DeadlineKind.documentExpiry, DateTime(2027, 1, 31))],
      now: now,
      deadlineLeadDays: 3,
      expiryLeadDays: 30,
    );
    expect(reminders.first.at, DateTime(2027, 1, 1, 9));
    expect(reminders.first.body, 'Passeport expire dans 30 jours.');
  });

  test('aucun rappel dans le passé', () {
    final reminders = planReminders(
      [
        entry(DeadlineKind.task, DateTime(2026, 10, 29)), // 9 h déjà passé
        entry(DeadlineKind.task, DateTime(2026, 10, 20)),
        entry(DeadlineKind.task, DateTime(2026, 10, 31)), // J-3 passé
      ],
      now: now,
      deadlineLeadDays: 3,
      expiryLeadDays: 30,
    );
    expect(reminders.map((r) => r.at), [DateTime(2026, 10, 31, 9)]);
  });

  test('nombre de rappels limité et trié', () {
    final entries = [
      for (var i = 100; i > 0; i--)
        entry(DeadlineKind.dossier, DateTime(2027, 1, 1).add(Duration(days: i))),
    ];
    final reminders = planReminders(
      entries,
      now: now,
      deadlineLeadDays: 1,
      expiryLeadDays: 30,
    );
    expect(reminders, hasLength(maxScheduledReminders));
    for (var i = 1; i < reminders.length; i++) {
      expect(reminders[i].at.isBefore(reminders[i - 1].at), isFalse);
    }
  });
}

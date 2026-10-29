import 'package:intl/intl.dart';

/// Ramène une date à minuit (heure locale), sans composante horaire.
DateTime dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);

/// Date du jour, sans heure.
DateTime today() => dateOnly(DateTime.now());

String formatIsoDate(DateTime value) {
  final y = value.year.toString().padLeft(4, '0');
  final m = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

DateTime parseIsoDate(String value) {
  final parsed = DateTime.parse(value);
  return DateTime(parsed.year, parsed.month, parsed.day);
}

/// Nombre de jours calendaires entre [from] et [to] (négatif si [to] est passé).
int daysBetween(DateTime from, DateTime to) {
  // Calcul en UTC pour ne pas être faussé par les changements d'heure.
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

final _longDate = DateFormat('d MMMM y', 'fr_FR');
final _shortDate = DateFormat('d MMM y', 'fr_FR');
final _dateTime = DateFormat("d MMM y 'à' HH:mm", 'fr_FR');

String formatLongDate(DateTime value) => _longDate.format(value);

String formatShortDate(DateTime value) => _shortDate.format(value);

String formatDateTime(DateTime value) => _dateTime.format(value.toLocal());

/// Formulation relative d'une échéance : « aujourd'hui », « dans 3 jours »,
/// « dépassée de 2 jours ».
String relativeDayLabel(DateTime date, {DateTime? reference}) {
  final days = daysBetween(reference ?? today(), date);
  if (days == 0) return "aujourd'hui";
  if (days == 1) return 'demain';
  if (days == -1) return 'hier';
  if (days > 1) return 'dans $days jours';
  return 'il y a ${-days} jours';
}

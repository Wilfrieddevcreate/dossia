import 'package:drift/drift.dart';

import '../utils/dates.dart';

/// Stocke une date calendaire (sans heure) au format ISO `AAAA-MM-JJ`.
///
/// Les dates de délivrance, d'expiration et les échéances n'ont pas d'heure :
/// les conserver sous forme de texte évite tout décalage de fuseau horaire.
class DateOnlyConverter extends TypeConverter<DateTime, String> {
  const DateOnlyConverter();

  @override
  DateTime fromSql(String fromDb) => parseIsoDate(fromDb);

  @override
  String toSql(DateTime value) => formatIsoDate(value);
}

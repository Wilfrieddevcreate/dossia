import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dates.dart';

/// Date du jour utilisée pour les statuts (expiration, échéances).
///
/// Rafraîchie au retour de l'application au premier plan, afin que les
/// statuts restent justes si l'application reste ouverte plusieurs jours.
class TodayNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => today();

  void refresh() {
    final now = today();
    if (now != state) state = now;
  }
}

final todayProvider = NotifierProvider<TodayNotifier, DateTime>(
  TodayNotifier.new,
);

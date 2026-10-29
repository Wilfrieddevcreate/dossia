import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/today_provider.dart';
import '../../documents/data/documents_repository.dart';
import '../../dossiers/data/dossiers_repository.dart';
import '../domain/deadline_models.dart';

/// Toutes les échéances connues, triées par date.
final deadlinesProvider = Provider<AsyncValue<List<DeadlineEntry>>>((ref) {
  final dossiers = ref.watch(dossierOverviewsProvider);
  final documents = ref.watch(documentsProvider);
  if (dossiers.hasError) {
    return AsyncValue.error(dossiers.error!, dossiers.stackTrace!);
  }
  if (documents.hasError) {
    return AsyncValue.error(documents.error!, documents.stackTrace!);
  }
  if (!dossiers.hasValue || !documents.hasValue) {
    return const AsyncValue.loading();
  }
  return AsyncValue.data(
    collectDeadlines(
      dossiers: dossiers.requireValue,
      documents: documents.requireValue,
    ),
  );
});

/// Échéances séparées entre « à venir » et « dépassées ».
final splitDeadlinesProvider =
    Provider<
      AsyncValue<({List<DeadlineEntry> upcoming, List<DeadlineEntry> overdue})>
    >((ref) {
      final today = ref.watch(todayProvider);
      return ref
          .watch(deadlinesProvider)
          .whenData((all) => splitDeadlines(all, today));
    });

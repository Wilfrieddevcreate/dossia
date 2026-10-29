import '../../../core/database/app_database.dart';
import '../../../core/utils/dates.dart';
import '../../documents/domain/document_models.dart';
import '../../requirements/domain/item_status.dart';
import '../../requirements/domain/requirement_models.dart';
import 'dossier_progress.dart';

/// Dossier avec ses pièces évaluées.
class DossierOverview {
  DossierOverview({
    required this.dossier,
    required this.items,
    required this.tasks,
  }) : progress = DossierProgress.fromEvaluations(
         items.map((i) => i.evaluation),
       );

  /// Évalue les pièces de [dossier] à la date [today].
  factory DossierOverview.build({
    required DossierRow dossier,
    required Iterable<RequirementView> requirements,
    required Iterable<TaskRow> tasks,
    required DateTime today,
  }) {
    return DossierOverview(
      dossier: dossier,
      items: [
        for (final r in requirements)
          r.evaluate(today: today, dossierDeadline: dossier.deadline),
      ],
      tasks: tasks.toList(),
    );
  }

  final DossierRow dossier;
  final List<EvaluatedRequirement> items;
  final List<TaskRow> tasks;
  final DossierProgress progress;

  String get id => dossier.id;
  bool get isArchived => dossier.archivedAt != null;

  DossierStatus get status => computeDossierStatus(
    archived: isArchived,
    manualStatus: dossier.status,
    progress: progress,
  );

  /// Un dossier actif n'est ni archivé ni terminé.
  bool get isActive =>
      status != DossierStatus.archived && status != DossierStatus.completed;

  List<EvaluatedRequirement> itemsWithStatus(ItemStatus status) =>
      items.where((i) => i.status == status).toList();

  int get openTaskCount => tasks.where((t) => !t.isCompleted).length;

  bool matches(String query) {
    final q = normalizeForSearch(query);
    if (q.isEmpty) return true;
    return [dossier.title, dossier.description, dossier.category?.label]
        .whereType<String>()
        .any((v) => normalizeForSearch(v).contains(q));
  }

  /// Prochaines actions à effectuer, par ordre d'importance : pièces
  /// obligatoires à renouveler, manquantes, à vérifier, puis tâches ouvertes.
  List<NextAction> nextActions({int limit = 5}) {
    final actions = <NextAction>[];
    for (final status in const [
      ItemStatus.toRenew,
      ItemStatus.missing,
      ItemStatus.toVerify,
    ]) {
      for (final item in items.where(
        (i) => i.evaluation.isMandatory && i.status == status,
      )) {
        actions.add(
          NextAction(
            kind: switch (status) {
              ItemStatus.toRenew => NextActionKind.renew,
              ItemStatus.missing => NextActionKind.obtain,
              _ => NextActionKind.verify,
            },
            label: item.view.displayName,
            itemId: item.view.id,
            dueDate: item.view.item.dueDate,
          ),
        );
      }
    }
    final openTasks = tasks.where((t) => !t.isCompleted).toList()
      ..sort((a, b) {
        if (a.dueDate == null && b.dueDate == null) return 0;
        if (a.dueDate == null) return 1;
        if (b.dueDate == null) return -1;
        return a.dueDate!.compareTo(b.dueDate!);
      });
    for (final t in openTasks) {
      actions.add(
        NextAction(
          kind: NextActionKind.task,
          label: t.title,
          taskId: t.id,
          dueDate: t.dueDate,
        ),
      );
    }
    return actions.take(limit).toList();
  }

  /// Nombre de jours avant la date limite (négatif si dépassée).
  int? daysUntilDeadline(DateTime today) => dossier.deadline == null
      ? null
      : daysBetween(today, dossier.deadline!);
}

enum NextActionKind {
  obtain('Obtenir'),
  renew('Renouveler'),
  verify('Vérifier'),
  task('Tâche');

  const NextActionKind(this.verb);

  final String verb;
}

class NextAction {
  const NextAction({
    required this.kind,
    required this.label,
    this.itemId,
    this.taskId,
    this.dueDate,
  });

  final NextActionKind kind;
  final String label;
  final String? itemId;
  final String? taskId;
  final DateTime? dueDate;
}

enum DossierSort {
  recent('Modifiés récemment'),
  deadline('Date limite'),
  title('Nom'),
  progress('Progression');

  const DossierSort(this.label);

  final String label;
}

int compareDossiers(DossierOverview a, DossierOverview b, DossierSort sort) {
  switch (sort) {
    case DossierSort.recent:
      return b.dossier.updatedAt.compareTo(a.dossier.updatedAt);
    case DossierSort.deadline:
      final da = a.dossier.deadline, db = b.dossier.deadline;
      if (da == null && db == null) {
        return compareDossiers(a, b, DossierSort.title);
      }
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    case DossierSort.title:
      return normalizeForSearch(
        a.dossier.title,
      ).compareTo(normalizeForSearch(b.dossier.title));
    case DossierSort.progress:
      // Les dossiers sans pièce obligatoire sont placés en dernier.
      final ra = a.progress.ratio ?? -1, rb = b.progress.ratio ?? -1;
      return rb.compareTo(ra);
  }
}

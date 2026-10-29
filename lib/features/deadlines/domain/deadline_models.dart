import '../../../core/utils/dates.dart';
import '../../documents/domain/document_models.dart';
import '../../dossiers/domain/dossier_models.dart';
import '../../requirements/domain/item_status.dart';

enum DeadlineKind {
  dossier('Date limite du dossier'),
  documentExpiry('Expiration du document'),
  task('Tâche'),
  item('Pièce à fournir');

  const DeadlineKind(this.label);

  final String label;
}

/// Échéance affichée dans la liste des échéances et utilisée pour les rappels.
class DeadlineEntry {
  const DeadlineEntry({
    required this.key,
    required this.kind,
    required this.date,
    required this.title,
    this.context,
    this.dossierId,
    this.documentId,
    this.itemId,
  });

  /// Identifiant stable (`kind:id`), utilisé pour les rappels.
  final String key;
  final DeadlineKind kind;
  final DateTime date;
  final String title;

  /// Dossier ou type de document concerné.
  final String? context;
  final String? dossierId;
  final String? documentId;
  final String? itemId;

  bool isOverdue(DateTime today) => date.isBefore(today);
}

/// Rassemble les échéances : dates limites des dossiers actifs, dates
/// d'expiration des documents non archivés, tâches ouvertes et pièces non
/// disponibles ayant une échéance. Aucune date n'est inventée : seules les
/// dates saisies par l'utilisateur sont prises en compte.
List<DeadlineEntry> collectDeadlines({
  required Iterable<DossierOverview> dossiers,
  required Iterable<DocumentView> documents,
}) {
  final entries = <DeadlineEntry>[];

  for (final d in dossiers.where((d) => d.isActive)) {
    final deadline = d.dossier.deadline;
    if (deadline != null) {
      entries.add(
        DeadlineEntry(
          key: 'dossier:${d.id}',
          kind: DeadlineKind.dossier,
          date: deadline,
          title: d.dossier.title,
          context: d.progress.label,
          dossierId: d.id,
        ),
      );
    }
    for (final t in d.tasks.where((t) => !t.isCompleted && t.dueDate != null)) {
      entries.add(
        DeadlineEntry(
          key: 'task:${t.id}',
          kind: DeadlineKind.task,
          date: t.dueDate!,
          title: t.title,
          context: d.dossier.title,
          dossierId: d.id,
        ),
      );
    }
    for (final i in d.items) {
      final due = i.view.item.dueDate;
      if (due == null || i.status == ItemStatus.available) continue;
      entries.add(
        DeadlineEntry(
          key: 'item:${i.view.id}',
          kind: DeadlineKind.item,
          date: due,
          title: i.view.displayName,
          context: d.dossier.title,
          dossierId: d.id,
          itemId: i.view.id,
        ),
      );
    }
  }

  for (final doc in documents.where((d) => !d.isArchived)) {
    final expiry = doc.doc.expiryDate;
    if (expiry == null) continue;
    entries.add(
      DeadlineEntry(
        key: 'document:${doc.id}',
        kind: DeadlineKind.documentExpiry,
        date: expiry,
        title: doc.displayName,
        context: doc.type.name,
        documentId: doc.id,
      ),
    );
  }

  entries.sort((a, b) => a.date.compareTo(b.date));
  return entries;
}

/// Sépare les échéances à venir (dont aujourd'hui) des échéances dépassées.
({List<DeadlineEntry> upcoming, List<DeadlineEntry> overdue}) splitDeadlines(
  List<DeadlineEntry> entries,
  DateTime today,
) {
  final day = dateOnly(today);
  return (
    upcoming: entries.where((e) => !e.isOverdue(day)).toList(),
    overdue: entries.where((e) => e.isOverdue(day)).toList().reversed.toList(),
  );
}

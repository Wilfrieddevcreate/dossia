import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../core/utils/dates.dart';
import '../domain/deadline_models.dart';

/// Ligne d'échéance avec date, nature et délai restant.
class DeadlineTile extends StatelessWidget {
  const DeadlineTile({super.key, required this.entry, required this.today});

  final DeadlineEntry entry;
  final DateTime today;

  void _open(BuildContext context) {
    if (entry.itemId != null && entry.dossierId != null) {
      context.push(Routes.item(entry.dossierId!, entry.itemId!));
    } else if (entry.dossierId != null) {
      context.push(Routes.dossier(entry.dossierId!));
    } else if (entry.documentId != null) {
      context.push(Routes.document(entry.documentId!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overdue = entry.isOverdue(today);
    final days = daysBetween(today, entry.date);
    final accent = overdue
        ? theme.colorScheme.error
        : days <= 7
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    final relative = overdue
        ? 'Dépassée ${relativeDayLabel(entry.date, reference: today)}'
        : relativeDayLabel(entry.date, reference: today);
    return ListTile(
      onTap: () => _open(context),
      leading: Semantics(
        excludeSemantics: true,
        child: Container(
          width: 52,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent),
          ),
          // Réduit le contenu plutôt que de déborder avec un grand texte.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${entry.date.day}',
                  style: theme.textTheme.titleMedium?.copyWith(color: accent),
                ),
                Text(
                  DateFormat('MMM', 'fr_FR').format(entry.date),
                  style: theme.textTheme.labelSmall?.copyWith(color: accent),
                ),
              ],
            ),
          ),
        ),
      ),
      title: Text(entry.title),
      subtitle: Text(
        [
          entry.kind.label,
          ?entry.context,
          '${formatShortDate(entry.date)} · $relative',
        ].join('\n'),
      ),
      isThreeLine: true,
      trailing: overdue
          ? Icon(
              Icons.warning_amber_rounded,
              color: theme.colorScheme.error,
              semanticLabel: 'Échéance dépassée',
            )
          : null,
    );
  }
}

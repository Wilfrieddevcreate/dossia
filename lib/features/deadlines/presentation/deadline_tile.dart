import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../domain/deadline_models.dart';

/// Ligne d'échéance : date, objet, contexte et délai restant.
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

  String get _context {
    final ctx = entry.context;
    return switch (entry.kind) {
      DeadlineKind.dossier => 'Date limite du dossier',
      DeadlineKind.documentExpiry =>
        ctx == null || ctx == entry.title ? 'Expiration' : 'Expiration · $ctx',
      DeadlineKind.task => ctx == null ? 'Tâche' : 'Tâche · $ctx',
      DeadlineKind.item => ctx == null ? 'Pièce' : 'Pièce · $ctx',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = StatusColors.of(context);
    final days = daysBetween(today, entry.date);
    final overdue = days < 0;
    final soon = !overdue && days <= 7;
    final relative = overdue
        ? 'en retard'
        : days == 0
        ? "aujourd'hui"
        : days == 1
        ? 'demain'
        : 'dans $days j';
    final relativeColor = overdue
        ? status.dangerIcon
        : soon
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Semantics(
      button: true,
      label:
          '${entry.title}, $_context, ${formatLongDate(entry.date)}, '
          '${overdue ? 'en retard de ${-days} jours' : relativeDayLabel(entry.date, reference: today)}',
      excludeSemantics: true,
      child: AppRow(
        onTap: () => _open(context),
        chevron: false,
        leading: _DateBadge(date: entry.date, overdue: overdue),
        title: entry.title,
        subtitle: _context,
        trailing: Text(
          relative,
          style: theme.textTheme.labelMedium?.copyWith(
            color: relativeColor,
            fontWeight: overdue || soon ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _DateBadge extends StatelessWidget {
  const _DateBadge({required this.date, required this.overdue});

  final DateTime date;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = StatusColors.of(context);
    final palette = AppPalette.of(context);
    final fg = overdue ? status.onDanger : theme.colorScheme.onSurface;
    return Container(
      width: 46,
      height: 50,
      decoration: BoxDecoration(
        color: overdue ? status.danger : palette.muted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DateFormat('MMM', 'fr_FR').format(date).replaceAll('.', ''),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: overdue ? fg : theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
              Text(
                '${date.day}',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

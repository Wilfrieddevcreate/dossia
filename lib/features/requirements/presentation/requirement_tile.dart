import 'package:flutter/material.dart';

import '../../../core/utils/dates.dart';
import '../../../core/widgets/status_badges.dart';
import '../domain/item_status.dart';
import '../domain/requirement_models.dart';

/// Ligne d'une pièce dans le détail d'un dossier.
class RequirementTile extends StatelessWidget {
  const RequirementTile({
    super.key,
    required this.item,
    required this.onTap,
    this.trailing,
  });

  final EvaluatedRequirement item;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final view = item.view;
    final e = item.evaluation;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    final lines = <String>[
      if (view.links.isEmpty)
        'Aucun document associé'
      else
        view.links.map((l) => l.displayName).join(', '),
      if (e.requiredQuantity > 1)
        '${e.assignedQuantity} sur ${e.requiredQuantity} exemplaires',
      if (view.item.dueDate != null)
        'À fournir avant le ${formatShortDate(view.item.dueDate!)}',
    ];

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: ExcludeSemantics(
                child: Icon(
                  itemStatusIcon(e.status),
                  color: e.status == ItemStatus.available
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(view.displayName, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  for (final line in lines) Text(line, style: muted),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      ItemStatusChip(e.status, dense: true),
                      if (!e.isMandatory && e.status != ItemStatus.optional)
                        const OptionalChip(),
                    ],
                  ),
                ],
              ),
            ),
            trailing ??
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

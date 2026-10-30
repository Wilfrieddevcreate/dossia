import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_badges.dart';
import '../domain/item_status.dart';
import '../domain/requirement_models.dart';

/// Couleur du libellé de statut dans les textes.
Color itemStatusTextColor(BuildContext context, ItemStatus status) {
  final c = StatusColors.of(context);
  return switch (status) {
    ItemStatus.available => c.onSuccess,
    ItemStatus.toVerify => c.onWarning,
    ItemStatus.toRenew => c.onDanger,
    ItemStatus.missing ||
    ItemStatus.optional => Theme.of(context).colorScheme.onSurfaceVariant,
  };
}

String shortVerifyReason(VerifyReason r, ItemEvaluation e) => switch (r) {
  VerifyReason.incompleteQuantity =>
    '${e.assignedQuantity} sur ${e.requiredQuantity}',
  VerifyReason.archivedDocument => 'document archivé',
  VerifyReason.userFlagged => 'condition à confirmer',
  VerifyReason.expiresBeforeDeadline => 'expire avant l’échéance',
};

/// Précision qui suit le statut : documents associés, raison, échéance.
String requirementDetail(EvaluatedRequirement item) {
  final view = item.view;
  final e = item.evaluation;
  final parts = <String>[];
  switch (e.status) {
    case ItemStatus.available:
      final names = view.links
          .map((l) => l.displayName)
          .where((n) => n != view.displayName)
          .toList();
      if (names.isNotEmpty) parts.add(names.join(', '));
      if (e.requiredQuantity > 1) {
        parts.add('${e.assignedQuantity} sur ${e.requiredQuantity}');
      }
    case ItemStatus.toVerify:
      parts.addAll(e.reasons.map((r) => shortVerifyReason(r, e)));
    case ItemStatus.toRenew:
      final expired = view.links
          .where((l) => l.doc.expiryDate != null)
          .map((l) => l.doc.expiryDate!)
          .toList();
      if (expired.isNotEmpty) {
        expired.sort();
        parts.add('expiré le ${formatCompactDate(expired.first)}');
      }
    case ItemStatus.missing:
    case ItemStatus.optional:
      if (e.requiredQuantity > 1) {
        parts.add('${e.requiredQuantity} exemplaires');
      }
  }
  if (!e.isMandatory && e.status != ItemStatus.optional) {
    parts.add('facultative');
  }
  if (view.item.dueDate != null && e.status != ItemStatus.available) {
    parts.add('avant le ${formatCompactDate(view.item.dueDate!)}');
  }
  return parts.join(' · ');
}

/// Ligne d'une pièce dans la liste de contrôle du dossier.
class RequirementTile extends StatelessWidget {
  const RequirementTile({super.key, required this.item, required this.onTap});

  final EvaluatedRequirement item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = item.status;
    final detail = requirementDetail(item);
    return AppRow(
      onTap: onTap,
      leading: StatusIcon(status, size: 26),
      title: item.view.displayName,
      subtitleWidget: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: status.label,
              style: TextStyle(
                color: itemStatusTextColor(context, status),
                fontWeight: FontWeight.w700,
              ),
            ),
            if (detail.isNotEmpty) TextSpan(text: ' · $detail'),
          ],
        ),
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}

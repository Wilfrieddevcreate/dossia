import 'package:flutter/material.dart';

import '../../app/theme/status_colors.dart';
import '../../features/documents/domain/document_models.dart';
import '../../features/dossiers/domain/dossier_progress.dart';
import '../../features/requirements/domain/item_status.dart';

/// Pastille de statut : icône + libellé + couleur. La couleur n'est jamais le
/// seul indicateur (§ 4.6).
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
    this.dense = false,
  });

  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: foreground,
      fontWeight: FontWeight.w600,
    );
    return Semantics(
      label: 'Statut : $label',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: dense ? 2 : 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: dense ? 14 : 16, color: foreground),
            const SizedBox(width: 4),
            Flexible(
              child: Text(label, style: style, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

class ItemStatusChip extends StatelessWidget {
  const ItemStatusChip(this.status, {super.key, this.dense = false});

  final ItemStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = StatusColors.of(context);
    final (bg, fg) = switch (status) {
      ItemStatus.missing => (c.danger, c.onDanger),
      ItemStatus.available => (c.success, c.onSuccess),
      ItemStatus.toVerify => (c.warning, c.onWarning),
      ItemStatus.toRenew => (c.danger, c.onDanger),
      ItemStatus.optional => (c.neutral, c.onNeutral),
    };
    return StatusChip(
      label: status.label,
      icon: itemStatusIcon(status),
      background: bg,
      foreground: fg,
      dense: dense,
    );
  }
}

IconData itemStatusIcon(ItemStatus status) => switch (status) {
  ItemStatus.missing => Icons.radio_button_unchecked,
  ItemStatus.available => Icons.check_circle,
  ItemStatus.toVerify => Icons.help_outline,
  ItemStatus.toRenew => Icons.autorenew,
  ItemStatus.optional => Icons.remove_circle_outline,
};

class DossierStatusChip extends StatelessWidget {
  const DossierStatusChip(this.status, {super.key, this.dense = false});

  final DossierStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = StatusColors.of(context);
    final (bg, fg, icon) = switch (status) {
      DossierStatus.inProgress => (c.info, c.onInfo, Icons.pending_outlined),
      DossierStatus.readyToCheck => (
        c.warning,
        c.onWarning,
        Icons.fact_check_outlined,
      ),
      DossierStatus.completed => (c.success, c.onSuccess, Icons.task_alt),
      DossierStatus.archived => (c.neutral, c.onNeutral, Icons.inventory_2_outlined),
    };
    return StatusChip(
      label: status.label,
      icon: icon,
      background: bg,
      foreground: fg,
      dense: dense,
    );
  }
}

/// Indication d'expiration d'un document ; rien n'est affiché si aucune date
/// d'expiration n'a été renseignée.
class ExpiryChip extends StatelessWidget {
  const ExpiryChip(this.state, {super.key, this.dense = true});

  final ExpiryState state;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = StatusColors.of(context);
    return switch (state) {
      ExpiryState.none || ExpiryState.valid => const SizedBox.shrink(),
      ExpiryState.expiringSoon => StatusChip(
        label: 'Expire bientôt',
        icon: Icons.schedule,
        background: c.warning,
        foreground: c.onWarning,
        dense: dense,
      ),
      ExpiryState.expired => StatusChip(
        label: 'Expiré',
        icon: Icons.error_outline,
        background: c.danger,
        foreground: c.onDanger,
        dense: dense,
      ),
    };
  }
}

class ArchivedChip extends StatelessWidget {
  const ArchivedChip({super.key});

  @override
  Widget build(BuildContext context) {
    final c = StatusColors.of(context);
    return StatusChip(
      label: 'Archivé',
      icon: Icons.inventory_2_outlined,
      background: c.neutral,
      foreground: c.onNeutral,
      dense: true,
    );
  }
}

class OptionalChip extends StatelessWidget {
  const OptionalChip({super.key});

  @override
  Widget build(BuildContext context) {
    final c = StatusColors.of(context);
    return StatusChip(
      label: 'Facultatif',
      icon: Icons.remove_circle_outline,
      background: c.neutral,
      foreground: c.onNeutral,
      dense: true,
    );
  }
}

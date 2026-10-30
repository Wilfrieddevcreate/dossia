import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../features/documents/domain/document_models.dart';
import '../../features/dossiers/domain/dossier_progress.dart';
import '../../features/requirements/domain/item_status.dart';

/// Pastille de statut : icône + libellé sur fond teinté. La couleur n'est
/// jamais le seul indicateur (§ 4.6).
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
  final IconData? icon;
  final Color background;
  final Color foreground;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: foreground,
      fontSize: dense ? 12 : 12.5,
    );
    return Semantics(
      label: 'Statut : $label',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          icon == null ? 10 : 7,
          dense ? 3 : 5,
          10,
          dense ? 3 : 5,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: dense ? 14 : 15, color: foreground),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(label, style: style, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

(Color, Color) _itemColors(StatusColors c, ItemStatus status) =>
    switch (status) {
      ItemStatus.missing => (c.neutral, c.onNeutral),
      ItemStatus.available => (c.success, c.onSuccess),
      ItemStatus.toVerify => (c.warning, c.onWarning),
      ItemStatus.toRenew => (c.danger, c.onDanger),
      ItemStatus.optional => (c.neutral, c.onNeutral),
    };

class ItemStatusChip extends StatelessWidget {
  const ItemStatusChip(this.status, {super.key, this.dense = false});

  final ItemStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _itemColors(StatusColors.of(context), status);
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
  ItemStatus.missing => Icons.radio_button_unchecked_rounded,
  ItemStatus.available => Icons.check_rounded,
  ItemStatus.toVerify => Icons.priority_high_rounded,
  ItemStatus.toRenew => Icons.autorenew_rounded,
  ItemStatus.optional => Icons.remove_rounded,
};

/// Pastille ronde de la liste de pièces, façon liste de contrôle : cercle
/// vide à réunir, coche verte quand c'est prêt. Animée au changement.
class StatusIcon extends StatelessWidget {
  const StatusIcon(this.status, {super.key, this.size = 28});

  final ItemStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = StatusColors.of(context);
    final palette = AppPalette.of(context);
    final Widget icon = switch (status) {
      ItemStatus.missing => _Ring(color: c.neutralIcon, size: size),
      ItemStatus.optional => _Ring(
        color: palette.hairlineStrong,
        size: size,
        dashed: true,
      ),
      ItemStatus.available => _Disc(
        color: c.successIcon,
        icon: Icons.check_rounded,
        size: size,
      ),
      ItemStatus.toVerify => _Disc(
        color: c.warningIcon,
        icon: Icons.priority_high_rounded,
        size: size,
      ),
      ItemStatus.toRenew => _Disc(
        color: c.dangerIcon,
        icon: Icons.autorenew_rounded,
        size: size,
      ),
    };
    return Semantics(
      label: status.label,
      excludeSemantics: true,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutBack,
        transitionBuilder: (child, animation) =>
            ScaleTransition(scale: animation, child: child),
        child: KeyedSubtree(key: ValueKey(status), child: icon),
      ),
    );
  }
}

class _Disc extends StatelessWidget {
  const _Disc({required this.color, required this.icon, required this.size});

  final Color color;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final onColor = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF0E1311)
        : Colors.white;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, size: size * 0.62, color: onColor),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.color, required this.size, this.dashed = false});

  final Color color;
  final double size;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _RingIconPainter(color, dashed)),
    );
  }
}

class _RingIconPainter extends CustomPainter {
  _RingIconPainter(this.color, this.dashed);

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rect = (Offset.zero & size).deflate(2);
    if (!dashed) {
      canvas.drawOval(rect, paint);
      return;
    }
    const segments = 12;
    const sweep = 6.283185307179586 / segments;
    for (var i = 0; i < segments; i++) {
      canvas.drawArc(rect, i * sweep, sweep * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(_RingIconPainter old) =>
      old.color != color || old.dashed != dashed;
}

class DossierStatusChip extends StatelessWidget {
  const DossierStatusChip(this.status, {super.key, this.dense = false});

  final DossierStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = StatusColors.of(context);
    final (bg, fg, icon) = switch (status) {
      DossierStatus.inProgress => (c.info, c.onInfo, Icons.timelapse_rounded),
      DossierStatus.readyToCheck => (
        c.warning,
        c.onWarning,
        Icons.fact_check_outlined,
      ),
      DossierStatus.completed => (c.success, c.onSuccess, Icons.check_rounded),
      DossierStatus.archived => (
        c.neutral,
        c.onNeutral,
        Icons.inventory_2_outlined,
      ),
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
/// d'expiration n'a été renseignée ou si elle est lointaine.
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
        icon: Icons.schedule_rounded,
        background: c.warning,
        foreground: c.onWarning,
        dense: dense,
      ),
      ExpiryState.expired => StatusChip(
        label: 'Expiré',
        icon: Icons.error_outline_rounded,
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
      icon: null,
      background: c.neutral,
      foreground: c.onNeutral,
      dense: true,
    );
  }
}

/// Case ronde animée (tâches, inventaire). Avec [onChanged], elle est
/// cliquable seule ; sinon c'est la ligne entière qui gère le geste.
class RoundCheck extends StatelessWidget {
  const RoundCheck({
    super.key,
    required this.checked,
    this.onChanged,
    this.semanticLabel,
  });

  final bool checked;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = StatusColors.of(context);
    final box = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: checked ? c.successIcon : Colors.transparent,
        border: Border.all(
          color: checked ? c.successIcon : theme.colorScheme.outline,
          width: 2,
        ),
      ),
      child: AnimatedScale(
        scale: checked ? 1 : 0.4,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        child: AnimatedOpacity(
          opacity: checked ? 1 : 0,
          duration: const Duration(milliseconds: 150),
          child: Icon(
            Icons.check_rounded,
            size: 17,
            color: theme.colorScheme.surface,
          ),
        ),
      ),
    );
    if (onChanged == null) return ExcludeSemantics(child: box);
    return Semantics(
      checked: checked,
      label: semanticLabel,
      button: true,
      excludeSemantics: true,
      child: InkResponse(
        onTap: () => onChanged!(!checked),
        radius: 22,
        child: box,
      ),
    );
  }
}

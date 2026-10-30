import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/database/app_database.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/today_provider.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_badges.dart';
import '../../requirements/presentation/requirement_tile.dart';
import '../data/dossiers_repository.dart';
import '../domain/dossier_models.dart';
import '../domain/dossier_progress.dart';
import 'pdf_export.dart';
import 'task_sheet.dart';

/// Détail et suivi d'un dossier (§ 3.4).
class DossierDetailScreen extends ConsumerStatefulWidget {
  const DossierDetailScreen({super.key, required this.dossierId});

  final String dossierId;

  @override
  ConsumerState<DossierDetailScreen> createState() =>
      _DossierDetailScreenState();
}

class _DossierDetailScreenState extends ConsumerState<DossierDetailScreen> {
  @override
  void initState() {
    super.initState();
    // Pour la section « En cours » de l'accueil.
    ref.read(dossiersRepositoryProvider).markOpened(widget.dossierId).ignore();
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(dossierOverviewProvider(widget.dossierId));
    return AsyncView(
      value: overview,
      builder: (overview) {
        if (overview == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
              icon: Icons.folder_off_outlined,
              title: 'Dossier introuvable',
              message: "Ce dossier a été supprimé ou n'existe plus.",
            ),
          );
        }
        return _DossierDetailView(overview: overview);
      },
    );
  }
}

enum _MenuAction { edit, reorder, complete, archive, delete }

class _DossierDetailView extends ConsumerWidget {
  const _DossierDetailView({required this.overview});

  final DossierOverview overview;

  Future<void> _onMenu(
    BuildContext context,
    WidgetRef ref,
    _MenuAction action,
  ) async {
    final repo = ref.read(dossiersRepositoryProvider);
    final d = overview.dossier;
    switch (action) {
      case _MenuAction.edit:
        context.push(Routes.editDossier(d.id));
      case _MenuAction.reorder:
        context.push(Routes.reorderItems(d.id));
      case _MenuAction.complete:
        final completing = overview.status != DossierStatus.completed;
        if (completing) {
          final pending = overview.progress.mandatoryPending;
          final confirmed = await showConfirmDialog(
            context,
            title: 'Marquer comme terminé ?',
            message:
                '${pending > 0 ? '$pending pièce${pending > 1 ? 's' : ''} obligatoire${pending > 1 ? 's ne sont' : ' n’est'} pas encore disponible${pending > 1 ? 's' : ''}.\n\n' : ''}'
                'Vous indiquez avoir fini de préparer ce dossier. Cela ne '
                "garantit pas son acceptation par l'organisme destinataire.",
            confirmLabel: 'Terminer',
          );
          if (!confirmed || !context.mounted) return;
          HapticFeedback.mediumImpact();
        }
        await runGuarded(
          context,
          () => repo.setCompleted(d.id, completing),
          success: completing ? 'Dossier terminé' : 'Préparation reprise',
        );
      case _MenuAction.archive:
        final archiving = !overview.isArchived;
        await runGuarded(
          context,
          () => repo.setArchived(d.id, archiving),
          success: archiving ? 'Dossier archivé' : 'Dossier réactivé',
          onUndo: () => repo.setArchived(d.id, !archiving),
        );
      case _MenuAction.delete:
        final confirmed = await showConfirmDialog(
          context,
          title: 'Supprimer ce dossier ?',
          message:
              '« ${d.title} », ses ${overview.items.length} pièce(s) et '
              'ses ${overview.tasks.length} tâche(s) seront supprimés '
              'définitivement.\n\nVos documents restent dans la '
              'bibliothèque. Pour simplement le ranger, archivez-le.',
          confirmLabel: 'Supprimer',
          destructive: true,
        );
        if (!confirmed || !context.mounted) return;
        final ok = await runGuarded(context, () => repo.deleteDossier(d.id));
        if (ok && context.mounted) {
          showMessage(context, 'Dossier supprimé');
          context.pop();
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final d = overview.dossier;
    final actions = overview.isActive
        ? overview.nextActions(limit: 3)
        : const <NextAction>[];

    PopupMenuItem<_MenuAction> item(
      _MenuAction value,
      IconData icon,
      String label, {
      bool danger = false,
    }) => PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: danger
                ? theme.colorScheme.error
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 14),
          Text(
            label,
            style: danger ? TextStyle(color: theme.colorScheme.error) : null,
          ),
        ],
      ),
    );

    return DetailScaffold(
      title: d.title,
      actions: [
        IconButton(
          tooltip: 'Exporter le récapitulatif PDF',
          icon: const Icon(Icons.ios_share_rounded),
          onPressed: () => exportDossierPdf(context, ref, overview),
        ),
        PopupMenuButton<_MenuAction>(
          tooltip: "Plus d'actions",
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (a) => _onMenu(context, ref, a),
          itemBuilder: (_) => [
            item(_MenuAction.edit, Icons.edit_outlined, 'Modifier'),
            if (overview.items.length > 1)
              item(
                _MenuAction.reorder,
                Icons.reorder_rounded,
                'Réorganiser les pièces',
              ),
            if (!overview.isArchived)
              item(
                _MenuAction.complete,
                overview.status == DossierStatus.completed
                    ? Icons.replay_rounded
                    : Icons.task_alt_rounded,
                overview.status == DossierStatus.completed
                    ? 'Reprendre la préparation'
                    : 'Marquer comme terminé',
              ),
            item(
              _MenuAction.archive,
              overview.isArchived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined,
              overview.isArchived ? 'Réactiver' : 'Archiver',
            ),
            item(
              _MenuAction.delete,
              Icons.delete_outline_rounded,
              'Supprimer',
              danger: true,
            ),
          ],
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'dossier-fab',
        onPressed: () => context.push(Routes.newItem(d.id)),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Ajouter une pièce'),
      ),
      slivers: [
        SliverToBoxAdapter(child: _Header(overview: overview)),
        SliverBox(child: _ProgressPanel(overview: overview)),
        if (actions.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SectionTitle('À faire ensuite')),
          SliverBox(
            child: ListGroup(
              dividerIndent: 68,
              children: [
                for (final a in actions)
                  _NextActionRow(action: a, overview: overview),
              ],
            ),
          ),
        ],
        SliverToBoxAdapter(
          child: SectionTitle(
            overview.items.isEmpty
                ? 'Pièces'
                : 'Pièces · ${overview.items.length}',
            action: overview.items.length > 1
                ? SectionAction(
                    label: 'Réorganiser',
                    icon: Icons.reorder_rounded,
                    onPressed: () => context.push(Routes.reorderItems(d.id)),
                  )
                : null,
          ),
        ),
        SliverBox(
          child: overview.items.isEmpty
              ? const InfoBanner(
                  icon: Icons.checklist_rounded,
                  message:
                      'Ajoutez les pièces demandées. Pour chacune, Dossia '
                      'vous propose les documents de votre bibliothèque qui '
                      'correspondent.',
                )
              : ListGroup(
                  dividerIndent: 56,
                  children: [
                    for (final i in overview.items)
                      RequirementTile(
                        item: i,
                        onTap: () => context.push(Routes.item(d.id, i.view.id)),
                      ),
                  ],
                ),
        ),
        const SliverToBoxAdapter(child: SectionTitle('Tâches')),
        SliverBox(
          child: ListGroup(
            dividerIndent: 56,
            children: [
              for (final t in overview.tasks)
                _TaskRow(task: t, dossierId: d.id),
              AppRow(
                dense: true,
                leading: Icon(
                  Icons.add_rounded,
                  color: theme.colorScheme.primary,
                ),
                title: 'Ajouter une tâche',
                titleStyle: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
                chevron: false,
                onTap: () => showTaskSheet(context, dossierId: d.id),
              ),
            ],
          ),
        ),
        if (d.description != null || d.notes != null) ...[
          const SliverToBoxAdapter(child: SectionTitle('Notes')),
          SliverBox(
            child: Panel(
              padding: const EdgeInsets.all(18),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (d.description != null)
                      Text(d.description!, style: theme.textTheme.bodyMedium),
                    if (d.description != null && d.notes != null)
                      const SizedBox(height: 10),
                    if (d.notes != null)
                      Text(
                        d.notes!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.overview});

  final DossierOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = StatusColors.of(context);
    final today = ref.watch(todayProvider);
    final d = overview.dossier;
    final days = overview.daysUntilDeadline(today);
    final overdue = days != null && days < 0 && overview.isActive;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                dossierCategoryIcon(d.category),
                size: 17,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  d.category?.label ?? 'Dossier',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(d.title, style: theme.textTheme.headlineMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              DossierStatusChip(overview.status),
              if (d.deadline != null)
                StatusChip(
                  icon: Icons.event_rounded,
                  label: overdue
                      ? 'Échéance dépassée · ${formatCompactDate(d.deadline!)}'
                      : '${formatCompactDate(d.deadline!)} · ${relativeDayLabel(d.deadline!, reference: today)}',
                  background: overdue ? c.danger : c.neutral,
                  foreground: overdue ? c.onDanger : c.onNeutral,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressPanel extends StatelessWidget {
  const _ProgressPanel({required this.overview});

  final DossierOverview overview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = StatusColors.of(context);
    final p = overview.progress;
    final status = overview.status;

    final note = switch (status) {
      DossierStatus.readyToCheck => (
        Icons.fact_check_outlined,
        'Toutes les pièces obligatoires sont là. Vérifiez leur conformité '
            'auprès de l’organisme avant le dépôt.',
      ),
      DossierStatus.completed => (
        Icons.task_alt_rounded,
        'Préparation terminée. Ce statut ne garantit pas l’acceptation du '
            'dossier.',
      ),
      _ => null,
    };

    return Panel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProgressRing(
                ratio: p.ratio,
                size: 96,
                stroke: 9,
                semanticLabel: p.hasMandatoryItems
                    ? 'Progression : ${p.percent} pour cent, '
                          '${p.mandatoryAvailable} pièces obligatoires '
                          'disponibles sur ${p.mandatoryTotal}'
                    : 'Aucune pièce obligatoire',
                child: p.hasMandatoryItems
                    ? Text(
                        p.label,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      )
                    : Icon(
                        Icons.checklist_rounded,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: p.hasMandatoryItems
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${p.mandatoryTotal} pièce${p.mandatoryTotal > 1 ? 's' : ''} obligatoire${p.mandatoryTotal > 1 ? 's' : ''}',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _Legend(
                            color: c.successIcon,
                            count: p.mandatoryAvailable,
                            label: 'disponible',
                          ),
                          _Legend(
                            color: c.warningIcon,
                            count: p.mandatoryToVerify,
                            label: 'à vérifier',
                            invariable: true,
                          ),
                          _Legend(
                            color: c.neutralIcon,
                            count: p.mandatoryMissing,
                            label: 'manquante',
                          ),
                          if (p.mandatoryToRenew > 0)
                            _Legend(
                              color: c.dangerIcon,
                              count: p.mandatoryToRenew,
                              label: 'à renouveler',
                              invariable: true,
                            ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.label, style: theme.textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text(
                            p.optionalTotal > 0
                                ? 'Seules des pièces facultatives sont listées.'
                                : 'Ajoutez les pièces demandées pour suivre '
                                      'l’avancement.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
              ),
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: 18),
            InfoBanner(
              icon: note.$1,
              message: note.$2,
              background: status == DossierStatus.completed
                  ? c.success
                  : c.warning,
              foreground: status == DossierStatus.completed
                  ? c.onSuccess
                  : c.onWarning,
            ),
          ],
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.color,
    required this.count,
    required this.label,
    this.invariable = false,
  });

  final Color color;
  final int count;
  final String label;

  /// Libellé sans marque du pluriel (« à vérifier »).
  final bool invariable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = invariable || count < 2 ? label : '${label}s';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Text(
            '$count',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NextActionRow extends StatelessWidget {
  const _NextActionRow({required this.action, required this.overview});

  final NextAction action;
  final DossierOverview overview;

  @override
  Widget build(BuildContext context) {
    final c = StatusColors.of(context);
    final (icon, bg, fg, verb) = switch (action.kind) {
      NextActionKind.obtain => (
        Icons.add_task_rounded,
        c.neutral,
        c.onNeutral,
        'À obtenir',
      ),
      NextActionKind.renew => (
        Icons.autorenew_rounded,
        c.danger,
        c.onDanger,
        'À renouveler',
      ),
      NextActionKind.verify => (
        Icons.priority_high_rounded,
        c.warning,
        c.onWarning,
        'À vérifier',
      ),
      NextActionKind.task => (Icons.check_rounded, c.info, c.onInfo, 'Tâche'),
    };
    return AppRow(
      leading: IconTile(icon, size: 38, background: bg, foreground: fg),
      title: action.label,
      subtitle: action.dueDate == null
          ? verb
          : '$verb · avant le ${formatCompactDate(action.dueDate!)}',
      onTap: () {
        final id = overview.dossier.id;
        if (action.itemId != null) {
          context.push(Routes.item(id, action.itemId!));
        } else {
          final task = overview.tasks.firstWhere((t) => t.id == action.taskId);
          showTaskSheet(context, dossierId: id, task: task);
        }
      },
    );
  }
}

class _TaskRow extends ConsumerWidget {
  const _TaskRow({required this.task, required this.dossierId});

  final TaskRow task;
  final String dossierId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final done = task.isCompleted;
    return AppRow(
      dense: true,
      leading: RoundCheck(
        checked: done,
        semanticLabel: done ? 'Tâche terminée' : 'Tâche à faire',
        onChanged: (v) {
          HapticFeedback.selectionClick();
          runGuarded(
            context,
            () => ref
                .read(dossiersRepositoryProvider)
                .setTaskCompleted(task.id, v),
          );
        },
      ),
      title: task.title,
      titleStyle: theme.textTheme.bodyLarge?.copyWith(
        fontWeight: FontWeight.w600,
        decoration: done ? TextDecoration.lineThrough : null,
        color: done ? theme.colorScheme.onSurfaceVariant : null,
      ),
      subtitle: task.dueDate == null
          ? null
          : 'Avant le ${formatCompactDate(task.dueDate!)}',
      chevron: false,
      onTap: () => showTaskSheet(context, dossierId: dossierId, task: task),
    );
  }
}

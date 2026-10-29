import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/status_colors.dart';
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
    // Pour la section « Récemment consultés » de l'accueil.
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
                '${pending > 0 ? 'Attention : $pending pièce(s) obligatoire(s) ne sont pas encore disponibles.\n\n' : ''}'
                '« Terminé » indique que vous avez fini de préparer ce dossier. '
                "Ce statut ne vaut pas acceptation par l'administration ou "
                "l'organisme destinataire.",
            confirmLabel: 'Marquer terminé',
          );
          if (!confirmed || !context.mounted) return;
        }
        await runGuarded(
          context,
          () => repo.setCompleted(d.id, completing),
          success: completing ? 'Dossier marqué terminé.' : 'Préparation reprise.',
        );
      case _MenuAction.archive:
        final archiving = !overview.isArchived;
        await runGuarded(
          context,
          () => repo.setArchived(d.id, archiving),
          success: archiving
              ? 'Dossier archivé. Il reste consultable dans « Archivés ».'
              : 'Dossier réactivé.',
        );
      case _MenuAction.delete:
        final confirmed = await showConfirmDialog(
          context,
          title: 'Supprimer ce dossier ?',
          message:
              '« ${d.title} » sera supprimé définitivement avec ses '
              '${overview.items.length} pièce(s) et ${overview.tasks.length} '
              'tâche(s).\n\nLes documents de votre bibliothèque ne sont pas '
              'supprimés et restent associés à vos autres dossiers.\n\n'
              'Pour le conserver sans l’afficher, archivez-le.',
          confirmLabel: 'Supprimer',
          destructive: true,
        );
        if (!confirmed || !context.mounted) return;
        final ok = await runGuarded(context, () => repo.deleteDossier(d.id));
        if (ok && context.mounted) {
          showMessage(context, 'Dossier supprimé.');
          context.pop();
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final d = overview.dossier;
    final actions = overview.nextActions();

    return Scaffold(
      appBar: AppBar(
        title: Text(d.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Exporter le récapitulatif PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => exportDossierPdf(context, ref, overview),
          ),
          PopupMenuButton<_MenuAction>(
            tooltip: "Plus d'actions",
            onSelected: (a) => _onMenu(context, ref, a),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _MenuAction.edit,
                child: Text('Modifier le dossier'),
              ),
              if (overview.items.length > 1)
                const PopupMenuItem(
                  value: _MenuAction.reorder,
                  child: Text('Réorganiser les pièces'),
                ),
              if (!overview.isArchived)
                PopupMenuItem(
                  value: _MenuAction.complete,
                  child: Text(
                    overview.status == DossierStatus.completed
                        ? 'Reprendre la préparation'
                        : 'Marquer comme terminé',
                  ),
                ),
              PopupMenuItem(
                value: _MenuAction.archive,
                child: Text(overview.isArchived ? 'Réactiver' : 'Archiver'),
              ),
              const PopupMenuItem(
                value: _MenuAction.delete,
                child: Text('Supprimer'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'dossier-fab',
        onPressed: () => context.push(Routes.newItem(d.id)),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter une pièce'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          _Header(overview: overview),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _ProgressCard(overview: overview),
          ),
          if (actions.isNotEmpty && !overview.isArchived) ...[
            const SectionHeader('Prochaines actions'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: Column(
                  children: [
                    for (final a in actions)
                      ListTile(
                        leading: Icon(_actionIcon(a.kind)),
                        title: Text('${a.kind.verb} : ${a.label}'),
                        subtitle: a.dueDate == null
                            ? null
                            : Text('Avant le ${formatShortDate(a.dueDate!)}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          if (a.itemId != null) {
                            context.push(Routes.item(d.id, a.itemId!));
                          } else {
                            final task = overview.tasks.firstWhere(
                              (t) => t.id == a.taskId,
                            );
                            showTaskSheet(context, dossierId: d.id, task: task);
                          }
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
          SectionHeader(
            'Pièces (${overview.items.length})',
            trailing: TextButton.icon(
              onPressed: () => context.push(Routes.newItem(d.id)),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter'),
            ),
          ),
          if (overview.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: InfoBanner(
                icon: Icons.checklist,
                message:
                    'Ajoutez les pièces demandées pour ce dossier. Pour '
                    'chacune, Dossia vous proposera les documents de votre '
                    'bibliothèque qui correspondent.',
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < overview.items.length; i++) ...[
                      if (i > 0) const Divider(indent: 16, endIndent: 16),
                      RequirementTile(
                        item: overview.items[i],
                        onTap: () => context.push(
                          Routes.item(d.id, overview.items[i].view.id),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          SectionHeader(
            'Tâches',
            trailing: TextButton.icon(
              onPressed: () => showTaskSheet(context, dossierId: d.id),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter'),
            ),
          ),
          if (overview.tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Aucune tâche. Ajoutez par exemple « Prendre rendez-vous » '
                'ou « Faire légaliser les diplômes ».',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final t in overview.tasks)
                      _TaskTile(
                        title: t.title,
                        dueDate: t.dueDate,
                        done: t.isCompleted,
                        onToggle: (v) => runGuarded(
                          context,
                          () => ref
                              .read(dossiersRepositoryProvider)
                              .setTaskCompleted(t.id, v),
                        ),
                        onTap: () =>
                            showTaskSheet(context, dossierId: d.id, task: t),
                      ),
                  ],
                ),
              ),
            ),
          if (d.description != null || d.notes != null) ...[
            const SectionHeader('Description et notes'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (d.description != null)
                        Text(d.description!, style: theme.textTheme.bodyMedium),
                      if (d.description != null && d.notes != null)
                        const SizedBox(height: 12),
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
        ],
      ),
    );
  }

  IconData _actionIcon(NextActionKind kind) => switch (kind) {
    NextActionKind.obtain => Icons.add_task,
    NextActionKind.renew => Icons.autorenew,
    NextActionKind.verify => Icons.help_outline,
    NextActionKind.task => Icons.check_box_outline_blank,
  };
}

class _Header extends ConsumerWidget {
  const _Header({required this.overview});

  final DossierOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = ref.watch(todayProvider);
    final d = overview.dossier;
    final days = overview.daysUntilDeadline(today);
    final overdue = days != null && days < 0 && overview.isActive;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                dossierCategoryIcon(d.category),
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  d.category?.label ?? 'Sans catégorie',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(d.title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          DossierStatusChip(overview.status),
          if (d.deadline != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  overdue ? Icons.event_busy : Icons.event,
                  size: 18,
                  color: overdue
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Date limite : ${formatLongDate(d.deadline!)} '
                    '(${overdue ? 'dépassée, ' : ''}${relativeDayLabel(d.deadline!, reference: today)})',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: overdue ? theme.colorScheme.error : null,
                      fontWeight: overdue ? FontWeight.w600 : null,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.overview});

  final DossierOverview overview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = StatusColors.of(context);
    final p = overview.progress;
    final status = overview.status;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Progression', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Semantics(
              label: p.hasMandatoryItems
                  ? 'Progression : ${p.percent} pour cent, '
                        '${p.mandatoryAvailable} pièces obligatoires disponibles sur ${p.mandatoryTotal}'
                  : 'Aucune pièce obligatoire',
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.label,
                    style: p.hasMandatoryItems
                        ? theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          )
                        : theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                  ),
                  if (p.hasMandatoryItems) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: p.ratio,
                        minHeight: 10,
                        color: theme.colorScheme.secondary,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Count('Obligatoires', p.mandatoryTotal, null, null),
                _Count(
                  'Disponibles',
                  p.mandatoryAvailable,
                  colors.success,
                  colors.onSuccess,
                ),
                _Count(
                  'Manquantes',
                  p.mandatoryMissing,
                  colors.danger,
                  colors.onDanger,
                ),
                _Count(
                  'À vérifier',
                  p.mandatoryToVerify,
                  colors.warning,
                  colors.onWarning,
                ),
                if (p.mandatoryToRenew > 0)
                  _Count(
                    'À renouveler',
                    p.mandatoryToRenew,
                    colors.danger,
                    colors.onDanger,
                  ),
                if (p.optionalTotal > 0)
                  _Count(
                    'Facultatives',
                    p.optionalTotal,
                    colors.neutral,
                    colors.onNeutral,
                  ),
              ],
            ),
            if (status == DossierStatus.readyToCheck) ...[
              const SizedBox(height: 16),
              InfoBanner(
                icon: Icons.fact_check_outlined,
                background: colors.warning,
                foreground: colors.onWarning,
                message:
                    'Toutes les pièces obligatoires sont déclarées '
                    'disponibles. Vérifiez leur conformité auprès de '
                    "l'organisme concerné avant le dépôt.",
              ),
            ],
            if (status == DossierStatus.completed) ...[
              const SizedBox(height: 16),
              InfoBanner(
                icon: Icons.task_alt,
                background: colors.success,
                foreground: colors.onSuccess,
                message:
                    'Vous avez indiqué avoir terminé la préparation. Ce '
                    "statut ne vaut pas acceptation par l'organisme "
                    'destinataire.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.label, this.value, this.background, this.foreground);

  final String label;
  final int value;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = foreground ?? theme.colorScheme.onSurface;
    return Semantics(
      label: '$label : $value',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 92),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: background ?? theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$value',
              style: theme.textTheme.titleLarge?.copyWith(color: fg),
            ),
            Text(label, style: theme.textTheme.labelMedium?.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.title,
    required this.dueDate,
    required this.done,
    required this.onToggle,
    required this.onTap,
  });

  final String title;
  final DateTime? dueDate;
  final bool done;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Checkbox(
        value: done,
        onChanged: (v) => onToggle(v ?? false),
        semanticLabel: done ? 'Tâche terminée' : 'Tâche à faire',
      ),
      title: Text(
        title,
        style: done
            ? TextStyle(
                decoration: TextDecoration.lineThrough,
                color: theme.colorScheme.onSurfaceVariant,
              )
            : null,
      ),
      subtitle: dueDate == null
          ? null
          : Text('Avant le ${formatShortDate(dueDate!)}'),
      onTap: onTap,
    );
  }
}

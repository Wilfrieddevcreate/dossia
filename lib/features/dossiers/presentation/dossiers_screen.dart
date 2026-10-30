import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/today_provider.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_badges.dart';
import '../data/dossiers_repository.dart';
import '../domain/dossier_models.dart';
import '../domain/dossier_progress.dart';

enum _Filter {
  active('En cours'),
  completed('Terminés'),
  archived('Archivés');

  const _Filter(this.label);

  final String label;

  bool includes(DossierOverview d) => switch (this) {
    _Filter.active => d.isActive,
    _Filter.completed => d.status == DossierStatus.completed,
    _Filter.archived => d.status == DossierStatus.archived,
  };
}

/// Liste des dossiers, avec recherche, filtre et tri (§ 4.3).
class DossiersScreen extends ConsumerStatefulWidget {
  const DossiersScreen({super.key});

  @override
  ConsumerState<DossiersScreen> createState() => _DossiersScreenState();
}

class _DossiersScreenState extends ConsumerState<DossiersScreen> {
  final _search = TextEditingController();
  _Filter _filter = _Filter.active;
  DossierSort _sort = DossierSort.recent;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dossiers = ref.watch(dossierOverviewsProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'dossiers-fab',
        onPressed: () => context.push(Routes.newDossier),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nouveau dossier'),
      ),
      body: AsyncView(
        value: dossiers,
        builder: (all) {
          final visible =
              all
                  .where(_filter.includes)
                  .where((d) => d.matches(_search.text))
                  .toList()
                ..sort((a, b) => compareDossiers(a, b, _sort));
          return CustomScrollView(
            slivers: [
              LargeTitleAppBar(
                title: 'Dossiers',
                actions: [
                  if (all.isNotEmpty)
                    PopupMenuButton<DossierSort>(
                      tooltip: 'Trier',
                      icon: const Icon(Icons.swap_vert_rounded),
                      initialValue: _sort,
                      onSelected: (s) => setState(() => _sort = s),
                      itemBuilder: (_) => [
                        for (final s in DossierSort.values)
                          CheckedPopupMenuItem(
                            value: s,
                            checked: s == _sort,
                            child: Text(s.label),
                          ),
                      ],
                    ),
                ],
              ),
              if (all.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.folder_open_rounded,
                    title: 'Aucun dossier pour le moment',
                    message:
                        'Visa, inscription, candidature… Créez un dossier, '
                        'listez les pièces demandées, et voyez ce qu’il vous '
                        'reste à réunir.',
                    action: FilledButton(
                      onPressed: () => context.push(Routes.newDossier),
                      child: const Text('Créer un dossier'),
                    ),
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: SearchField(
                      controller: _search,
                      hint: 'Rechercher',
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: PillTabs<_Filter>(
                    options: _Filter.values,
                    selected: _filter,
                    labelOf: (f) {
                      final n = all.where(f.includes).length;
                      return n == 0 ? f.label : '${f.label} · $n';
                    },
                    onSelected: (f) => setState(() => _filter = f),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                if (visible.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: _search.text.isEmpty
                          ? Icons.inbox_outlined
                          : Icons.search_off_rounded,
                      title: _search.text.isNotEmpty
                          ? 'Aucun résultat'
                          : switch (_filter) {
                              _Filter.active => 'Rien en cours',
                              _Filter.completed => 'Aucun dossier terminé',
                              _Filter.archived => 'Aucun dossier archivé',
                            },
                      message: _search.text.isNotEmpty
                          ? 'Aucun dossier ne correspond à « ${_search.text} ».'
                          : switch (_filter) {
                              _Filter.active =>
                                'Tous vos dossiers sont terminés ou archivés.',
                              _Filter.completed =>
                                'Marquez un dossier comme terminé depuis son '
                                    'menu.',
                              _Filter.archived =>
                                'Archivez un dossier pour le ranger sans le '
                                    'supprimer.',
                            },
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 104),
                    sliver: SliverList.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) =>
                          DossierCard(overview: visible[i]),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Anneau de progression d'un dossier, avec le pourcentage au centre.
class DossierRing extends StatelessWidget {
  const DossierRing({
    super.key,
    required this.progress,
    this.size = 54,
    this.stroke = 5,
  });

  final DossierProgress progress;
  final double size;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = progress;
    return ProgressRing(
      ratio: p.ratio,
      size: size,
      stroke: stroke,
      semanticLabel: 'Progression : ${p.label}',
      child: p.allMandatoryAvailable
          ? Icon(
              Icons.check_rounded,
              color: theme.colorScheme.primary,
              size: size * 0.42,
            )
          : Text(
              p.hasMandatoryItems ? '${p.percent}%' : '–',
              style: theme.textTheme.labelMedium?.copyWith(
                fontSize: size * 0.24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
    );
  }
}

/// Résumé court d'un dossier : « 4/6 pièces · 1 à vérifier ».
String dossierFacts(DossierProgress p) {
  if (!p.hasMandatoryItems) {
    return p.optionalTotal > 0
        ? '${p.optionalTotal} pièce${p.optionalTotal > 1 ? 's' : ''} facultative${p.optionalTotal > 1 ? 's' : ''}'
        : 'Aucune pièce pour l’instant';
  }
  final parts = [
    '${p.mandatoryAvailable}/${p.mandatoryTotal} pièces',
    if (p.mandatoryToVerify > 0) '${p.mandatoryToVerify} à vérifier',
    if (p.mandatoryToRenew > 0) '${p.mandatoryToRenew} à renouveler',
  ];
  return parts.join(' · ');
}

class DossierCard extends ConsumerWidget {
  const DossierCard({super.key, required this.overview});

  final DossierOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = StatusColors.of(context);
    final today = ref.watch(todayProvider);
    final d = overview.dossier;
    final days = overview.daysUntilDeadline(today);
    final overdue = days != null && days < 0 && overview.isActive;
    final showStatus = overview.status != DossierStatus.inProgress;

    return Panel(
      onTap: () => context.push(Routes.dossier(d.id)),
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
      child: Row(
        children: [
          DossierRing(progress: overview.progress),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.title,
                  style: theme.textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  dossierFacts(overview.progress),
                  style: theme.textTheme.bodySmall,
                ),
                if (d.deadline != null || showStatus) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (showStatus)
                        DossierStatusChip(overview.status, dense: true),
                      if (d.deadline != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.event_rounded,
                              size: 15,
                              color: overdue
                                  ? status.dangerIcon
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                overdue
                                    ? 'Échéance dépassée'
                                    : '${formatCompactDate(d.deadline!)} · ${relativeDayLabel(d.deadline!, reference: today)}',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: overdue
                                      ? status.dangerIcon
                                      : theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

/// Ligne compacte d'un dossier (accueil).
class DossierListRow extends ConsumerWidget {
  const DossierListRow({super.key, required this.overview});

  final DossierOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    final d = overview.dossier;
    final facts = dossierFacts(overview.progress);
    return AppRow(
      onTap: () => context.push(Routes.dossier(d.id)),
      leading: DossierRing(progress: overview.progress, size: 44, stroke: 4),
      title: d.title,
      subtitle: d.deadline == null
          ? facts
          : '$facts · ${relativeDayLabel(d.deadline!, reference: today)}',
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
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

  bool _inFilter(DossierOverview d) => switch (_filter) {
    _Filter.active => d.isActive,
    _Filter.completed => d.status == DossierStatus.completed,
    _Filter.archived => d.status == DossierStatus.archived,
  };

  @override
  Widget build(BuildContext context) {
    final dossiers = ref.watch(dossierOverviewsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes dossiers'),
        actions: [
          PopupMenuButton<DossierSort>(
            tooltip: 'Trier',
            icon: const Icon(Icons.sort),
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
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'dossiers-fab',
        onPressed: () => context.push(Routes.newDossier),
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('Créer un dossier'),
      ),
      body: AsyncView(
        value: dossiers,
        builder: (all) {
          if (all.isEmpty) {
            return EmptyState(
              icon: Icons.folder_open_outlined,
              title: 'Aucun dossier pour le moment',
              message:
                  'Créez un dossier (visa, inscription, candidature…) puis '
                  'ajoutez les pièces demandées : Dossia vous montre ce qui '
                  'manque.',
              action: FilledButton.icon(
                onPressed: () => context.push(Routes.newDossier),
                icon: const Icon(Icons.add),
                label: const Text('Créer un dossier'),
              ),
            );
          }
          final visible =
              all
                  .where(_inFilter)
                  .where((d) => d.matches(_search.text))
                  .toList()
                ..sort((a, b) => compareDossiers(a, b, _sort));
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Rechercher un dossier',
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Effacer la recherche',
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(_search.clear),
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<_Filter>(
                    showSelectedIcon: false,
                    segments: [
                      for (final f in _Filter.values)
                        ButtonSegment(
                          value: f,
                          label: Text(
                            '${f.label} (${all.where((d) => switch (f) {
                              _Filter.active => d.isActive,
                              _Filter.completed => d.status == DossierStatus.completed,
                              _Filter.archived => d.status == DossierStatus.archived,
                            }).length})',
                          ),
                        ),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (s) => setState(() => _filter = s.first),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: visible.isEmpty
                    ? EmptyState(
                        icon: Icons.search_off,
                        title: _search.text.isEmpty
                            ? 'Aucun dossier ${_filter.label.toLowerCase()}'
                            : 'Aucun résultat',
                        message: switch (_filter) {
                          _ when _search.text.isNotEmpty =>
                            'Aucun dossier ne correspond à « ${_search.text} ».',
                          _Filter.active =>
                            'Tous vos dossiers sont terminés ou archivés.',
                          _Filter.completed =>
                            'Marquez un dossier comme terminé depuis son menu.',
                          _Filter.archived =>
                            'Les dossiers archivés sont conservés ici sans '
                                'encombrer la liste.',
                        },
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) =>
                            DossierCard(overview: visible[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class DossierCard extends ConsumerWidget {
  const DossierCard({super.key, required this.overview});

  final DossierOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = ref.watch(todayProvider);
    final d = overview.dossier;
    final p = overview.progress;
    final days = overview.daysUntilDeadline(today);
    final deadlineOverdue = days != null && days < 0 && overview.isActive;

    final counts = <String>[
      if (p.hasMandatoryItems)
        '${p.mandatoryAvailable}/${p.mandatoryTotal} obligatoires',
      if (p.mandatoryMissing > 0)
        '${p.mandatoryMissing} manquante${p.mandatoryMissing > 1 ? 's' : ''}',
      if (p.mandatoryToVerify > 0) '${p.mandatoryToVerify} à vérifier',
      if (p.mandatoryToRenew > 0) '${p.mandatoryToRenew} à renouveler',
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(Routes.dossier(d.id)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    dossierCategoryIcon(d.category),
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.title, style: theme.textTheme.titleMedium),
                        if (d.category != null)
                          Text(
                            d.category!.label,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        const SizedBox(height: 6),
                        DossierStatusChip(overview.status, dense: true),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ProgressLine(ratio: p.ratio, label: p.label),
              if (counts.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  counts.join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (d.deadline != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      deadlineOverdue ? Icons.event_busy : Icons.event,
                      size: 16,
                      color: deadlineOverdue
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Date limite : ${formatShortDate(d.deadline!)} '
                        '(${relativeDayLabel(d.deadline!, reference: today)})',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: deadlineOverdue
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: deadlineOverdue ? FontWeight.w600 : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/models/document_category.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/today_provider.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_badges.dart';
import '../data/documents_repository.dart';
import '../domain/document_models.dart';

/// Bibliothèque personnelle de documents (§ 4.2).
class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  final _search = TextEditingController();
  DocumentCategory? _category;
  bool _showArchived = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _resetFilters() => setState(() {
    _search.clear();
    _category = null;
  });

  @override
  Widget build(BuildContext context) {
    final documents = ref.watch(documentsProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'documents-fab',
        onPressed: () => context.push(Routes.newDocument()),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Ajouter'),
      ),
      body: AsyncView(
        value: documents,
        builder: (all) {
          final archivedCount = all.where((d) => d.isArchived).length;
          final inMode = all.where((d) => d.isArchived == _showArchived);
          final presentCategories = {for (final d in inMode) d.category};
          final visible = inMode
              .where((d) => _category == null || d.category == _category)
              .where((d) => d.matches(_search.text))
              .toList();
          final filtered = _search.text.isNotEmpty || _category != null;

          return CustomScrollView(
            slivers: [
              LargeTitleAppBar(
                title: _showArchived ? 'Archivés' : 'Documents',
                actions: [
                  if (_showArchived)
                    IconButton(
                      tooltip: 'Revenir aux documents',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() => _showArchived = false),
                    )
                  else
                    IconButton(
                      tooltip: 'Compléter mon inventaire',
                      icon: const Icon(Icons.playlist_add_check_rounded),
                      onPressed: () => context.push(Routes.inventory),
                    ),
                ],
              ),
              if (all.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'Votre bibliothèque est vide',
                    message:
                        'Enregistrez les documents que vous possédez, même '
                        'sans scan. Vous pourrez ensuite les utiliser dans '
                        'tous vos dossiers.',
                    action: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilledButton(
                          onPressed: () => context.push(Routes.newDocument()),
                          child: const Text('Ajouter un document'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => context.push(Routes.inventory),
                          child: const Text("Faire l'inventaire"),
                        ),
                      ],
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
                if (presentCategories.length > 1 || _category != null)
                  SliverToBoxAdapter(
                    child: PillTabs<DocumentCategory?>(
                      options: [
                        null,
                        for (final c in DocumentCategory.values)
                          if (presentCategories.contains(c) || c == _category)
                            c,
                      ],
                      selected: _category,
                      labelOf: (c) => c?.label ?? 'Tous',
                      onSelected: (c) => setState(() => _category = c),
                    ),
                  ),
                if (visible.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: filtered
                          ? Icons.search_off_rounded
                          : Icons.inventory_2_outlined,
                      title: filtered
                          ? 'Aucun résultat'
                          : 'Aucun document archivé',
                      message: filtered
                          ? 'Aucun document ne correspond à votre recherche.'
                          : 'Les documents archivés restent conservés '
                                "jusqu'à leur suppression.",
                      action: filtered
                          ? OutlinedButton(
                              onPressed: _resetFilters,
                              child: const Text('Effacer les filtres'),
                            )
                          : null,
                    ),
                  )
                else if (_category != null || _search.text.isNotEmpty)
                  ..._group(null, visible)
                else
                  for (final category in DocumentCategory.values)
                    if (visible.any((d) => d.category == category))
                      ..._group(
                        category,
                        visible.where((d) => d.category == category).toList(),
                      ),
                if (!_showArchived && archivedCount > 0)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: Panel(
                        child: AppRow(
                          dense: true,
                          leading: const IconTile(
                            Icons.inventory_2_outlined,
                            size: 36,
                          ),
                          title: 'Documents archivés · $archivedCount',
                          onTap: () => setState(() {
                            _showArchived = true;
                            _category = null;
                          }),
                        ),
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 112)),
              ],
            ],
          );
        },
      ),
    );
  }

  List<Widget> _group(DocumentCategory? category, List<DocumentView> docs) => [
    if (category != null)
      SliverToBoxAdapter(
        child: SectionTitle(
          '${category.label} · ${docs.length}',
          padding: const EdgeInsets.fromLTRB(20, 20, 12, 10),
        ),
      )
    else
      const SliverToBoxAdapter(child: SizedBox(height: 16)),
    SliverBox(
      child: ListGroup(
        children: [for (final d in docs) DocumentRow(document: d)],
      ),
    ),
  ];
}

/// Ligne d'un document dans la bibliothèque.
class DocumentRow extends ConsumerWidget {
  const DocumentRow({super.key, required this.document});

  final DocumentView document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = ref.watch(todayProvider);
    final expiry = document.expiryState(today);
    final date = document.doc.expiryDate;
    final details = <String>[
      if (document.displayName != document.type.name) document.type.name,
      if (date != null && expiry == ExpiryState.valid)
        'Expire le ${formatCompactDate(date)}',
    ];
    final flagged =
        expiry == ExpiryState.expired || expiry == ExpiryState.expiringSoon;
    return AppRow(
      onTap: () => context.push(Routes.document(document.id)),
      chevron: true,
      leading: CategoryAvatar(document.category),
      title: document.displayName,
      subtitle: details.isEmpty ? null : details.join(' · '),
      // Sous le titre : le badge ne doit jamais réduire le nom du document.
      subtitleWidget: flagged ? ExpiryChip(expiry) : null,
      trailing: document.fileCount > 0
          ? Icon(
              Icons.attach_file_rounded,
              size: 19,
              color: theme.colorScheme.onSurfaceVariant,
              semanticLabel: document.fileCount > 1
                  ? '${document.fileCount} fichiers joints'
                  : 'Fichier joint',
            )
          : null,
    );
  }
}


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

  @override
  Widget build(BuildContext context) {
    final documents = ref.watch(documentsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Documents'),
        actions: [
          IconButton(
            tooltip: 'Compléter mon inventaire',
            icon: const Icon(Icons.playlist_add_check),
            onPressed: () => context.push(Routes.inventory),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'documents-fab',
        onPressed: () => context.push(Routes.newDocument()),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
      ),
      body: AsyncView(
        value: documents,
        builder: (all) {
          if (all.isEmpty) {
            return EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'Votre bibliothèque est vide',
              message:
                  'Enregistrez les documents que vous possédez, même sans '
                  'fichier numérique. Vous pourrez ensuite les associer à vos '
                  'dossiers.',
              action: Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () => context.push(Routes.newDocument()),
                    icon: const Icon(Icons.add),
                    label: const Text('Ajouter un document'),
                  ),
                  OutlinedButton(
                    onPressed: () => context.push(Routes.inventory),
                    child: const Text("Faire l'inventaire"),
                  ),
                ],
              ),
            );
          }
          final archivedCount = all.where((d) => d.isArchived).length;
          final visible = all
              .where((d) => d.isArchived == _showArchived)
              .where((d) => _category == null || d.category == _category)
              .where((d) => d.matches(_search.text))
              .toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Rechercher un document',
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
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _chip('Toutes', _category == null, () {
                      setState(() => _category = null);
                    }),
                    for (final c in DocumentCategory.values)
                      _chip(c.label, _category == c, () {
                        setState(() => _category = _category == c ? null : c);
                      }),
                  ],
                ),
              ),
              if (archivedCount > 0 || _showArchived)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () =>
                          setState(() => _showArchived = !_showArchived),
                      icon: Icon(
                        _showArchived
                            ? Icons.arrow_back
                            : Icons.inventory_2_outlined,
                      ),
                      label: Text(
                        _showArchived
                            ? 'Revenir aux documents actifs'
                            : 'Voir les documents archivés ($archivedCount)',
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: visible.isEmpty
                    ? EmptyState(
                        icon: Icons.search_off,
                        title: _showArchived
                            ? 'Aucun document archivé'
                            : 'Aucun résultat',
                        message: _showArchived
                            ? 'Les documents archivés restent conservés '
                                  "jusqu'à leur suppression."
                            : 'Aucun document ne correspond à votre recherche '
                                  'ou au filtre choisi.',
                        action: (_search.text.isNotEmpty || _category != null)
                            ? OutlinedButton(
                                onPressed: () => setState(() {
                                  _search.clear();
                                  _category = null;
                                }),
                                child: const Text('Réinitialiser les filtres'),
                              )
                            : null,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) =>
                            DocumentCard(document: visible[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    ),
  );
}

class DocumentCard extends ConsumerWidget {
  const DocumentCard({super.key, required this.document, this.onTap});

  final DocumentView document;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = ref.watch(todayProvider);
    final expiry = document.doc.expiryDate;
    final details = <String>[
      if (document.displayName != document.type.name) document.type.name,
      if (expiry != null) 'Expire le ${formatShortDate(expiry)}',
      if (document.usageCount > 0)
        'Utilisé dans ${document.usageCount} pièce${document.usageCount > 1 ? 's' : ''}',
    ];
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap ?? () => context.push(Routes.document(document.id)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
                child: Icon(documentCategoryIcon(document.category), size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.displayName,
                      style: theme.textTheme.titleSmall,
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        details.join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (document.isArchived ||
                        document.expiryState(today) == ExpiryState.expired ||
                        document.expiryState(today) ==
                            ExpiryState.expiringSoon) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (document.isArchived) const ArchivedChip(),
                          ExpiryChip(document.expiryState(today)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (document.fileCount > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.attach_file,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                    semanticLabel: 'Fichier joint',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/status_colors.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/today_provider.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/status_badges.dart';
import '../../documents/data/documents_repository.dart';
import '../../documents/domain/document_models.dart';
import '../../dossiers/data/dossiers_repository.dart';
import '../../dossiers/domain/dossier_models.dart';
import '../data/requirements_repository.dart';
import '../domain/item_status.dart';
import '../domain/requirement_models.dart';

/// Détail d'une pièce : statut, documents associés, suggestions (§ 3.3).
class RequirementDetailScreen extends ConsumerWidget {
  const RequirementDetailScreen({
    super.key,
    required this.dossierId,
    required this.itemId,
  });

  final String dossierId;
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(dossierOverviewProvider(dossierId));
    return AsyncView(
      value: overview,
      builder: (overview) {
        final item = overview?.items.firstWhereOrNull(
          (i) => i.view.id == itemId,
        );
        if (overview == null || item == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
              icon: Icons.find_in_page_outlined,
              title: 'Pièce introuvable',
              message: "Cette pièce a été supprimée ou n'existe plus.",
            ),
          );
        }
        return _RequirementDetailView(overview: overview, item: item);
      },
    );
  }
}

class _RequirementDetailView extends ConsumerWidget {
  const _RequirementDetailView({required this.overview, required this.item});

  final DossierOverview overview;
  final EvaluatedRequirement item;

  RequirementView get view => item.view;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Retirer cette pièce ?',
      message:
          '« ${view.displayName} » sera retirée du dossier '
          '« ${overview.dossier.title} ».\n\nLes documents associés restent '
          'dans votre bibliothèque et dans vos autres dossiers.',
      confirmLabel: 'Retirer la pièce',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await runGuarded(
      context,
      () => ref.read(requirementsRepositoryProvider).deleteRequirement(view.id),
    );
    if (ok && context.mounted) {
      showMessage(context, 'Pièce retirée du dossier.');
      context.pop();
    }
  }

  Future<void> _link(
    BuildContext context,
    WidgetRef ref,
    DocumentView document,
  ) async {
    await runGuarded(
      context,
      () => ref
          .read(requirementsRepositoryProvider)
          .linkDocument(itemId: view.id, documentId: document.id),
      success: '« ${document.displayName} » associé à la pièce.',
    );
  }

  Future<void> _unlink(
    BuildContext context,
    WidgetRef ref,
    LinkedDocument linked,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Retirer l’association ?',
      message:
          '« ${linked.displayName} » ne sera plus associé à cette pièce. '
          'Le document reste dans votre bibliothèque et dans vos autres '
          'dossiers.',
      confirmLabel: 'Retirer',
    );
    if (!confirmed || !context.mounted) return;
    await runGuarded(
      context,
      () => ref.read(requirementsRepositoryProvider).unlink(linked.link.id),
      success: 'Association retirée.',
    );
  }

  Future<void> _chooseDocument(
    BuildContext context,
    WidgetRef ref,
    List<DocumentView> documents,
  ) async {
    final linkedIds = {for (final l in view.links) l.doc.id};
    final candidates =
        documents
            .where((d) => !d.isArchived && !linkedIds.contains(d.id))
            .toList()
          ..sort((a, b) {
            // Les documents du même type que la pièce viennent en premier.
            final am = a.type.id == view.item.typeId ? 0 : 1;
            final bm = b.type.id == view.item.typeId ? 0 : 1;
            return am.compareTo(bm);
          });
    final chosen = await showModalBottomSheet<DocumentView>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.85,
        child: _DocumentChooser(
          candidates: candidates,
          matchingTypeId: view.item.typeId,
        ),
      ),
    );
    if (chosen != null && context.mounted) await _link(context, ref, chosen);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = ref.watch(todayProvider);
    final documents = ref.watch(documentsProvider).value ?? const [];
    final e = item.evaluation;
    final linkedIds = {for (final l in view.links) l.doc.id};
    final suggestions = view.item.typeId == null
        ? const <DocumentView>[]
        : documents
              .where(
                (d) =>
                    !d.isArchived &&
                    d.type.id == view.item.typeId &&
                    !linkedIds.contains(d.id),
              )
              .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(view.displayName, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Modifier la pièce',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () =>
                context.push(Routes.editItem(view.dossierId, view.id)),
          ),
          IconButton(
            tooltip: 'Retirer la pièce du dossier',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text(
            overview.dossier.title,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(view.displayName, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          _StatusCard(item: item),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  _Line(
                    icon: Icons.rule,
                    text: e.isMandatory
                        ? 'Pièce obligatoire'
                        : 'Pièce facultative',
                  ),
                  _Line(
                    icon: Icons.content_copy_outlined,
                    text: e.requiredQuantity > 1
                        ? '${e.requiredQuantity} exemplaires attendus · ${e.assignedQuantity} associé(s)'
                        : '1 exemplaire attendu',
                  ),
                  if (view.type != null && view.item.customName != null)
                    _Line(
                      icon: Icons.category_outlined,
                      text: 'Type : ${view.type!.name}',
                    ),
                  if (view.item.dueDate != null)
                    _Line(
                      icon: Icons.event,
                      text:
                          'À fournir avant le ${formatLongDate(view.item.dueDate!)} '
                          '(${relativeDayLabel(view.item.dueDate!, reference: today)})',
                    ),
                  if (view.item.instructions != null)
                    _Line(
                      icon: Icons.info_outline,
                      text: view.item.instructions!,
                    ),
                  if (view.item.notes != null)
                    _Line(icon: Icons.notes, text: view.item.notes!),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Une condition reste à confirmer'),
            subtitle: const Text(
              'ex. copie certifiée, traduction, légalisation. La pièce reste '
              '« À vérifier » tant que cette option est active.',
            ),
            value: view.flaggedToVerify,
            onChanged: (v) => runGuarded(
              context,
              () => ref
                  .read(requirementsRepositoryProvider)
                  .setFlaggedToVerify(view.id, v),
            ),
          ),
          SectionHeader(
            'Documents associés',
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
          ),
          if (view.links.isEmpty)
            Text(
              'Aucun document associé pour le moment.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final l in view.links)
                    _LinkedDocumentTile(
                      linked: l,
                      showQuantity: view.item.quantity > 1,
                      onOpen: () => context.push(Routes.document(l.doc.id)),
                      onUnlink: () => _unlink(context, ref, l),
                      onQuantity: (q) => runGuarded(
                        context,
                        () => ref
                            .read(requirementsRepositoryProvider)
                            .updateLinkQuantity(l.link.id, q),
                      ),
                    ),
                ],
              ),
            ),
          if (suggestions.isNotEmpty) ...[
            SectionHeader(
              view.links.isEmpty
                  ? 'Vous avez déjà ce document'
                  : 'Autres documents correspondants',
              padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
            ),
            Card(
              child: Column(
                children: [
                  for (final s in suggestions)
                    ListTile(
                      leading: Icon(documentCategoryIcon(s.category)),
                      title: Text(s.displayName),
                      subtitle: s.doc.expiryDate == null
                          ? null
                          : Text(
                              'Expire le ${formatShortDate(s.doc.expiryDate!)}',
                            ),
                      trailing: FilledButton.tonal(
                        onPressed: () => _link(context, ref, s),
                        child: const Text('Associer'),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Vérifiez que le document convient avant de l’associer.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ] else if (view.links.isEmpty && view.item.typeId != null) ...[
            const SizedBox(height: 12),
            InfoBanner(
              message:
                  'Aucun document de ce type dans votre bibliothèque. '
                  'Ajoutez-le si vous le possédez ; sinon la pièce reste '
                  'manquante.',
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: () => context.push(
                  Routes.newDocument(
                    typeId: view.item.typeId,
                    linkItemId: view.id,
                  ),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Ajouter un nouveau document'),
              ),
              OutlinedButton.icon(
                onPressed: () => _chooseDocument(context, ref, documents),
                icon: const Icon(Icons.link),
                label: const Text('Associer un document existant'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.item});

  final EvaluatedRequirement item;

  @override
  Widget build(BuildContext context) {
    final colors = StatusColors.of(context);
    final e = item.evaluation;
    final (bg, fg) = switch (e.status) {
      ItemStatus.available => (colors.success, colors.onSuccess),
      ItemStatus.toVerify => (colors.warning, colors.onWarning),
      ItemStatus.missing || ItemStatus.toRenew => (colors.danger, colors.onDanger),
      ItemStatus.optional => (colors.neutral, colors.onNeutral),
    };
    final explanation = switch (e.status) {
      ItemStatus.missing =>
        'Aucun document n’est associé à cette pièce obligatoire.',
      ItemStatus.optional =>
        'Pièce facultative sans document associé : elle ne réduit pas la '
            'progression.',
      ItemStatus.available =>
        'Document associé et déclaré disponible. Dossia ne certifie pas sa '
            'conformité.',
      ItemStatus.toRenew =>
        'Un document associé est expiré. Renouvelez-le ou associez-en un '
            'autre.',
      ItemStatus.toVerify => 'Un point reste à confirmer :',
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExcludeSemantics(child: Icon(itemStatusIcon(e.status), color: fg)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  e.status.label,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: fg),
                ),
              ),
            ],
          ),
          if (!e.isMandatory && e.status != ItemStatus.optional) ...[
            const SizedBox(height: 6),
            const OptionalChip(),
          ],
          const SizedBox(height: 6),
          Text(explanation, style: TextStyle(color: fg)),
          for (final r in e.reasons)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '• ${verifyReasonLabel(r, assigned: e.assignedQuantity, required: e.requiredQuantity)}',
                style: TextStyle(color: fg),
              ),
            ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(
              icon,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _LinkedDocumentTile extends ConsumerWidget {
  const _LinkedDocumentTile({
    required this.linked,
    required this.showQuantity,
    required this.onOpen,
    required this.onUnlink,
    required this.onQuantity,
  });

  final LinkedDocument linked;
  final bool showQuantity;
  final VoidCallback onOpen;
  final VoidCallback onUnlink;
  final ValueChanged<int> onQuantity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = ref.watch(todayProvider);
    final expiry = expiryStateOf(linked.doc.expiryDate, today);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onOpen,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        linked.displayName,
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        [
                          linked.docType.name,
                          if (linked.doc.expiryDate != null)
                            'expire le ${formatShortDate(linked.doc.expiryDate!)}',
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Retirer l’association avec ${linked.displayName}',
                icon: const Icon(Icons.link_off),
                onPressed: onUnlink,
              ),
            ],
          ),
          if (linked.isArchived ||
              expiry == ExpiryState.expired ||
              expiry == ExpiryState.expiringSoon)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                children: [
                  if (linked.isArchived) const ArchivedChip(),
                  ExpiryChip(expiry),
                ],
              ),
            ),
          if (showQuantity)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 12),
              child: QuantityStepper(
                label: 'Exemplaires fournis',
                value: linked.link.quantityAssigned,
                onChanged: onQuantity,
              ),
            ),
        ],
      ),
    );
  }
}

class _DocumentChooser extends StatefulWidget {
  const _DocumentChooser({required this.candidates, this.matchingTypeId});

  final List<DocumentView> candidates;
  final String? matchingTypeId;

  @override
  State<_DocumentChooser> createState() => _DocumentChooserState();
}

class _DocumentChooserState extends State<_DocumentChooser> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = widget.candidates.where((d) => d.matches(_query)).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Associer un document',
              style: theme.textTheme.titleLarge,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Rechercher dans la bibliothèque',
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: visible.isEmpty
              ? const EmptyState(
                  icon: Icons.search_off,
                  title: 'Aucun document disponible',
                  message:
                      'Tous vos documents actifs sont déjà associés, ou aucun '
                      'ne correspond à la recherche.',
                )
              : ListView.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, i) {
                    final d = visible[i];
                    final match = d.type.id == widget.matchingTypeId;
                    return ListTile(
                      leading: Icon(documentCategoryIcon(d.category)),
                      title: Text(d.displayName),
                      subtitle: Text(
                        match ? '${d.type.name} · même type' : d.type.name,
                      ),
                      onTap: () => Navigator.of(context).pop(d),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

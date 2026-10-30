import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_theme.dart';
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
          '« ${view.displayName} » sera retirée de « ${overview.dossier.title} ». '
          'Les documents associés restent dans votre bibliothèque.',
      confirmLabel: 'Retirer',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await runGuarded(
      context,
      () => ref.read(requirementsRepositoryProvider).deleteRequirement(view.id),
    );
    if (ok && context.mounted) {
      showMessage(context, 'Pièce retirée');
      context.pop();
    }
  }

  Future<void> _link(
    BuildContext context,
    WidgetRef ref,
    DocumentView document,
  ) async {
    HapticFeedback.lightImpact();
    await runGuarded(
      context,
      () => ref
          .read(requirementsRepositoryProvider)
          .linkDocument(itemId: view.id, documentId: document.id),
      success: '« ${document.displayName} » associé',
    );
  }

  Future<void> _unlink(
    BuildContext context,
    WidgetRef ref,
    LinkedDocument linked,
  ) async {
    final repo = ref.read(requirementsRepositoryProvider);
    final quantity = linked.link.quantityAssigned;
    await runGuarded(
      context,
      () => repo.unlink(linked.link.id),
      success: 'Association retirée',
      onUndo: () => repo
          .linkDocument(
            itemId: view.id,
            documentId: linked.doc.id,
            quantity: quantity,
          )
          .ignore(),
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
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.88,
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
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    final details = <(String, String)>[
      ('Exigence', e.isMandatory ? 'Obligatoire' : 'Facultative'),
      (
        'Quantité',
        e.requiredQuantity == 1
            ? '1 exemplaire'
            : e.assignedQuantity == 0
            ? '${e.requiredQuantity} exemplaires attendus'
            : '${e.requiredQuantity} exemplaires · ${e.assignedQuantity} fourni${e.assignedQuantity > 1 ? 's' : ''}',
      ),
      if (view.type != null && view.item.customName != null)
        ('Type de document', view.type!.name),
      if (view.item.dueDate != null)
        (
          'À fournir avant le',
          '${formatLongDate(view.item.dueDate!)} · '
              '${relativeDayLabel(view.item.dueDate!, reference: today)}',
        ),
      if (view.item.instructions != null)
        ('Instructions', view.item.instructions!),
      if (view.item.notes != null) ('Note', view.item.notes!),
    ];

    return DetailScaffold(
      title: view.displayName,
      actions: [
        IconButton(
          tooltip: 'Modifier la pièce',
          icon: const Icon(Icons.edit_outlined),
          onPressed: () =>
              context.push(Routes.editItem(view.dossierId, view.id)),
        ),
        IconButton(
          tooltip: 'Retirer la pièce du dossier',
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: () => _delete(context, ref),
        ),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  overview.dossier.title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(view.displayName, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ItemStatusChip(e.status),
                    if (!e.isMandatory && e.status != ItemStatus.optional)
                      const OptionalChip(),
                  ],
                ),
              ],
            ),
          ),
        ),
        // « Manquant » se suffit : la pastille et la liste ci-dessous le disent.
        if (e.status != ItemStatus.missing)
          SliverBox(child: _StatusNote(item: item)),
        if (suggestions.isNotEmpty && view.links.isEmpty)
          SliverBox(
            padding: EdgeInsets.fromLTRB(
              16,
              e.status == ItemStatus.missing ? 0 : 16,
              16,
              0,
            ),
            child: _SuggestionPanel(
              title: 'Vous avez déjà ce document',
              suggestions: suggestions,
              onLink: (d) => _link(context, ref, d),
            ),
          ),
        const SliverToBoxAdapter(child: SectionTitle('Documents associés')),
        if (view.links.isEmpty &&
            suggestions.isEmpty &&
            view.item.typeId != null)
          SliverBox(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'Aucun document de ce type dans votre bibliothèque.',
              style: muted,
            ),
          ),
        SliverBox(
          child: ListGroup(
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
              _ActionRow(
                icon: Icons.link_rounded,
                label: 'Associer un document',
                onTap: () => _chooseDocument(context, ref, documents),
              ),
              _ActionRow(
                icon: Icons.add_rounded,
                label: 'Nouveau document',
                onTap: () => context.push(
                  Routes.newDocument(
                    typeId: view.item.typeId,
                    linkItemId: view.id,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (suggestions.isNotEmpty && view.links.isNotEmpty) ...[
          const SliverToBoxAdapter(
            child: SectionTitle('Autres documents correspondants'),
          ),
          SliverBox(
            child: _SuggestionPanel(
              suggestions: suggestions,
              onLink: (d) => _link(context, ref, d),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SectionTitle('Détails')),
        SliverBox(
          child: ListGroup(
            dividerIndent: 16,
            children: [
              for (final (label, value) in details)
                _InfoRow(label: label, value: value),
            ],
          ),
        ),
        SliverBox(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          child: Panel(
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              title: const Text('Une condition reste à confirmer'),
              subtitle: const Text('Copie certifiée, traduction, légalisation…'),
              value: view.flaggedToVerify,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                runGuarded(
                  context,
                  () => ref
                      .read(requirementsRepositoryProvider)
                      .setFlaggedToVerify(view.id, v),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Explication du statut, teintée comme lui, avec les raisons éventuelles.
class _StatusNote extends StatelessWidget {
  const _StatusNote({required this.item});

  final EvaluatedRequirement item;

  @override
  Widget build(BuildContext context) {
    final c = StatusColors.of(context);
    final e = item.evaluation;
    final (bg, fg) = switch (e.status) {
      ItemStatus.available => (c.success, c.onSuccess),
      ItemStatus.toVerify => (c.warning, c.onWarning),
      ItemStatus.toRenew => (c.danger, c.onDanger),
      ItemStatus.missing || ItemStatus.optional => (c.neutral, c.onNeutral),
    };
    final explanation = switch (e.status) {
      ItemStatus.missing => 'Aucun document n’est encore associé.',
      ItemStatus.optional =>
        'Pièce facultative : elle ne compte pas dans la progression.',
      ItemStatus.available =>
        'Document associé et déclaré disponible. Dossia ne certifie pas sa '
            'conformité.',
      ItemStatus.toRenew =>
        'Un document associé a expiré : renouvelez-le ou associez-en un '
            'autre.',
      ItemStatus.toVerify => 'Plusieurs points restent à confirmer :',
    };
    final reasons = [
      for (final r in e.reasons)
        verifyReasonLabel(
          r,
          assigned: e.assignedQuantity,
          required: e.requiredQuantity,
        ),
    ];
    // Une seule raison : elle suffit comme explication.
    final message = e.status == ItemStatus.toVerify && reasons.length == 1
        ? '${reasons.single}.'
        : [explanation, for (final r in reasons) '• $r'].join('\n');
    return InfoBanner(
      icon: itemStatusIcon(e.status),
      background: bg,
      foreground: fg,
      message: message,
    );
  }
}

/// Documents de la bibliothèque qui correspondent au type de la pièce.
class _SuggestionPanel extends StatelessWidget {
  const _SuggestionPanel({
    required this.suggestions,
    required this.onLink,
    this.title,
  });

  final List<DocumentView> suggestions;
  final ValueChanged<DocumentView> onLink;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
              child: Row(
                children: [
                  IconTile(
                    Icons.inventory_2_outlined,
                    size: 36,
                    background: theme.colorScheme.primaryContainer,
                    foreground: theme.colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title!, style: theme.textTheme.titleMedium),
                        Text(
                          'Vérifiez qu’il convient, puis associez-le.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          for (var i = 0; i < suggestions.length; i++) ...[
            if (i > 0) const Divider(indent: 70, endIndent: 16),
            AppRow(
              leading: CategoryAvatar(suggestions[i].category),
              title: suggestions[i].displayName,
              subtitle: suggestions[i].doc.expiryDate == null
                  ? suggestions[i].type.name
                  : 'Expire le ${formatCompactDate(suggestions[i].doc.expiryDate!)}',
              chevron: false,
              trailing: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(48, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onPressed: () => onLink(suggestions[i]),
                child: const Text('Associer'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Ligne d'action en couleur d'accent, en fin de liste.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppRow(
      dense: true,
      leading: IconTile(
        icon,
        size: 42,
        background: theme.colorScheme.primaryContainer,
        foreground: theme.colorScheme.onPrimaryContainer,
      ),
      title: label,
      titleStyle: theme.textTheme.bodyLarge?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
      chevron: false,
      onTap: onTap,
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$label : $value',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodySmall),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
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
    final today = ref.watch(todayProvider);
    final expiry = expiryStateOf(linked.doc.expiryDate, today);
    final flagged =
        linked.isArchived ||
        expiry == ExpiryState.expired ||
        expiry == ExpiryState.expiringSoon;
    final subtitle = [
      if (linked.displayName != linked.docType.name) linked.docType.name,
      if (linked.doc.expiryDate != null && !flagged)
        'Expire le ${formatCompactDate(linked.doc.expiryDate!)}',
    ].join(' · ');
    return Column(
      children: [
        AppRow(
          onTap: onOpen,
          chevron: false,
          leading: CategoryAvatar(linked.docType.category),
          title: linked.displayName,
          subtitle: subtitle.isEmpty ? null : subtitle,
          subtitleWidget: flagged
              ? Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (linked.isArchived) const ArchivedChip(),
                    ExpiryChip(expiry),
                  ],
                )
              : null,
          trailing: IconButton(
            tooltip: 'Retirer l’association avec ${linked.displayName}',
            icon: const Icon(Icons.link_off_rounded),
            onPressed: onUnlink,
          ),
        ),
        if (showQuantity)
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 12, 12),
            child: QuantityStepper(
              label: 'Exemplaires',
              value: linked.link.quantityAssigned,
              onChanged: onQuantity,
            ),
          ),
      ],
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
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = widget.candidates
        .where((d) => d.matches(_search.text))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
            'Associer un document',
            style: theme.textTheme.titleLarge,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SearchField(
            controller: _search,
            hint: 'Rechercher dans la bibliothèque',
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: visible.isEmpty
              ? const EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'Aucun document disponible',
                  message:
                      'Vos documents actifs sont déjà associés, ou aucun ne '
                      'correspond à la recherche.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: visible.length,
                  itemBuilder: (context, i) {
                    final d = visible[i];
                    final match = d.type.id == widget.matchingTypeId;
                    return AppRow(
                      dense: true,
                      leading: CategoryAvatar(d.category, size: 38),
                      title: d.displayName,
                      subtitle: match
                          ? '${d.type.name} · même type'
                          : d.type.name,
                      chevron: false,
                      onTap: () => Navigator.of(context).pop(d),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

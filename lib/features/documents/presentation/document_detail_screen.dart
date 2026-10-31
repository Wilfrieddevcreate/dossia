import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/database/app_database.dart';
import '../../../core/files/file_storage_service.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/today_provider.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_badges.dart';
import '../data/documents_repository.dart';
import '../domain/document_models.dart';
import 'attachment_actions.dart';

class DocumentDetailScreen extends ConsumerWidget {
  const DocumentDetailScreen({super.key, required this.documentId});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(documentDetailProvider(documentId));
    return AsyncView(
      value: detail,
      builder: (detail) {
        if (detail == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
              icon: Icons.description_outlined,
              title: 'Document introuvable',
              message: "Ce document a été supprimé ou n'existe plus.",
            ),
          );
        }
        return _DocumentDetailView(detail: detail);
      },
    );
  }
}

enum _MenuAction { archive, delete }

class _DocumentDetailView extends ConsumerWidget {
  const _DocumentDetailView({required this.detail});

  final DocumentDetail detail;

  DocumentView get view => detail.view;

  Future<void> _onMenu(
    BuildContext context,
    WidgetRef ref,
    _MenuAction action,
  ) async {
    final repo = ref.read(documentsRepositoryProvider);
    switch (action) {
      case _MenuAction.archive:
        final archive = !view.isArchived;
        await runGuarded(
          context,
          () => repo.setArchived(view.id, archive),
          success: archive ? 'Document archivé' : 'Document réactivé',
          onUndo: () => repo.setArchived(view.id, !archive).ignore(),
        );
      case _MenuAction.delete:
        final usages = detail.usages;
        final files = detail.files.length;
        final buffer = StringBuffer(
          '« ${view.displayName} » sera supprimé définitivement',
        );
        buffer.write(
          files == 0
              ? '.'
              : files == 1
              ? ', avec son fichier joint.'
              : ', avec ses $files fichiers joints.',
        );
        if (usages.isNotEmpty) {
          buffer.write(
            '\n\n${usages.length == 1 ? 'Cette pièce redeviendra manquante' : 'Ces ${usages.length} pièces redeviendront manquantes'} :\n'
            '${usages.map((u) => '• ${u.itemName} — ${u.dossierTitle}').join('\n')}',
          );
        }
        buffer.write('\n\nPour simplement le ranger, archivez-le.');
        final confirmed = await showConfirmDialog(
          context,
          title: 'Supprimer ce document ?',
          message: buffer.toString(),
          confirmLabel: 'Supprimer',
          destructive: true,
        );
        if (!confirmed || !context.mounted) return;
        final ok = await runGuarded(
          context,
          () => repo.deleteDocument(view.id),
        );
        if (ok && context.mounted) {
          showMessage(context, 'Document supprimé');
          context.pop();
        }
    }
  }

  Future<void> _addFile(BuildContext context, WidgetRef ref) async {
    final picked = await pickAttachment(context);
    if (picked == null || !context.mounted) return;
    await runGuarded(
      context,
      () => ref
          .read(documentsRepositoryProvider)
          .attachFile(
            documentId: view.id,
            source: picked.file,
            originalName: picked.name,
          ),
      success: 'Fichier joint',
    );
  }

  Future<void> _removeFile(
    BuildContext context,
    WidgetRef ref,
    DocumentFileRow file,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Retirer ce fichier ?',
      message:
          '« ${file.fileName} » sera effacé de Dossia. Le document reste '
          'dans votre bibliothèque.',
      confirmLabel: 'Retirer',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await runGuarded(
      context,
      () => ref.read(documentsRepositoryProvider).removeFile(file),
      success: 'Fichier retiré',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = ref.watch(todayProvider);
    final doc = view.doc;
    final expiryState = view.expiryState(today);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    final info = <(String, String)>[
      if (doc.issueDate != null)
        ('Délivré le', formatLongDate(doc.issueDate!)),
      if (doc.expiryDate != null)
        (
          'Expire le',
          '${formatLongDate(doc.expiryDate!)} · '
              '${relativeDayLabel(doc.expiryDate!, reference: today)}',
        ),
      if (doc.issuer != null) ('Autorité émettrice', doc.issuer!),
      if (doc.notes != null) ('Notes', doc.notes!),
    ];
    final incomplete =
        doc.issueDate == null ||
        doc.expiryDate == null ||
        doc.issuer == null ||
        doc.notes == null;

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
      title: view.displayName,
      actions: [
        IconButton(
          tooltip: 'Modifier',
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => context.push(Routes.editDocument(view.id)),
        ),
        PopupMenuButton<_MenuAction>(
          tooltip: "Plus d'actions",
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (a) => _onMenu(context, ref, a),
          itemBuilder: (_) => [
            item(
              _MenuAction.archive,
              view.isArchived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined,
              view.isArchived ? 'Réactiver' : 'Archiver',
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
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CategoryAvatar(view.category, size: 56),
                const SizedBox(height: 16),
                Text(view.displayName, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  view.displayName == view.type.name
                      ? view.category.label
                      : '${view.type.name} · ${view.category.label}',
                  style: muted,
                ),
                if (view.isArchived ||
                    expiryState == ExpiryState.expired ||
                    expiryState == ExpiryState.expiringSoon) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (view.isArchived) const ArchivedChip(),
                      ExpiryChip(expiryState, dense: false),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        SliverBox(
          child: ListGroup(
            dividerIndent: 16,
            children: [
              for (final (label, value) in info)
                _InfoRow(label: label, value: value),
              if (incomplete)
                AppRow(
                  dense: true,
                  leading: Icon(
                    Icons.add_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  title: info.isEmpty
                      ? 'Ajouter des dates ou des précisions'
                      : 'Compléter',
                  titleStyle: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                  chevron: false,
                  onTap: () => context.push(Routes.editDocument(view.id)),
                ),
            ],
          ),
        ),
        const SliverToBoxAdapter(child: SectionTitle('Fichiers')),
        SliverBox(
          child: ListGroup(
            children: [
              for (final f in detail.files)
                _FileRow(
                  file: f,
                  onOpen: () => openAttachment(context, ref, f),
                  onRemove: () => _removeFile(context, ref, f),
                ),
              AppRow(
                dense: detail.files.isNotEmpty,
                leading: IconTile(
                  Icons.add_a_photo_outlined,
                  size: 44,
                  background: theme.colorScheme.primaryContainer,
                  foreground: theme.colorScheme.onPrimaryContainer,
                ),
                title: 'Ajouter une photo ou un fichier',
                titleStyle: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
                subtitle: detail.files.isEmpty
                    ? 'Appareil photo, galerie ou PDF'
                    : null,
                chevron: false,
                onTap: () => _addFile(context, ref),
              ),
            ],
          ),
        ),
        const SliverToBoxAdapter(child: SectionTitle('Utilisé dans')),
        SliverBox(
          child: detail.usages.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Pas encore associé à un dossier.',
                    style: muted,
                  ),
                )
              : ListGroup(
                  children: [
                    for (final u in detail.usages)
                      AppRow(
                        leading: const IconTile(Icons.folder_outlined),
                        title: u.dossierTitle,
                        subtitle: u.dossierArchived
                            ? '${u.itemName} · dossier archivé'
                            : u.itemName,
                        onTap: () =>
                            context.push(Routes.item(u.dossierId, u.itemId)),
                      ),
                  ],
                ),
        ),
        SliverBox(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
          child: Text(
            doc.updatedAt.difference(doc.createdAt).inMinutes < 1
                ? 'Ajouté le ${formatDateTime(doc.createdAt)}'
                : 'Ajouté le ${formatDateTime(doc.createdAt)}\n'
                      'Modifié le ${formatDateTime(doc.updatedAt)}',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// Information du document : libellé discret au-dessus de la valeur.
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

/// Fichier joint, avec vignette pour les images ; un fichier absent du
/// stockage est signalé (§ 9.2).
class _FileRow extends ConsumerStatefulWidget {
  const _FileRow({
    required this.file,
    required this.onOpen,
    required this.onRemove,
  });

  final DocumentFileRow file;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  ConsumerState<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends ConsumerState<_FileRow> {
  late Future<File?> _resolved;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(_FileRow old) {
    super.didUpdateWidget(old);
    if (old.file.relativePath != widget.file.relativePath) _resolve();
  }

  void _resolve() {
    _resolved = ref.read(fileStorageProvider).resolve(widget.file.relativePath);
  }

  @override
  Widget build(BuildContext context) {
    final status = StatusColors.of(context);
    final file = widget.file;
    return FutureBuilder<File?>(
      future: _resolved,
      builder: (context, snapshot) {
        final done = snapshot.connectionState == ConnectionState.done;
        final resolved = snapshot.data;
        final missing = done && resolved == null;
        final Widget thumb;
        if (missing) {
          thumb = IconTile(
            Icons.report_problem_outlined,
            size: 44,
            background: status.danger,
            foreground: status.onDanger,
          );
        } else if (resolved != null && isImageMime(file.mimeType)) {
          thumb = ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.file(
              resolved,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              cacheWidth: 132,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) =>
                  const IconTile(Icons.image_outlined, size: 44),
            ),
          );
        } else {
          thumb = IconTile(attachmentIcon(file.mimeType), size: 44);
        }
        return AppRow(
          leading: thumb,
          title: file.fileName,
          subtitleWidget: Text(
            missing
                ? 'Fichier introuvable sur ce téléphone'
                : formatFileSize(file.sizeBytes),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: missing ? status.onDanger : null,
            ),
          ),
          onTap: widget.onOpen,
          trailing: IconButton(
            tooltip: 'Retirer ${file.fileName}',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: widget.onRemove,
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
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
          success: archive
              ? 'Document archivé. Il reste associé à ses dossiers.'
              : 'Document réactivé.',
        );
      case _MenuAction.delete:
        final usages = detail.usages;
        final buffer = StringBuffer(
          '« ${view.displayName} » sera supprimé définitivement de votre '
          'bibliothèque.',
        );
        if (detail.files.isNotEmpty) {
          buffer.write(
            ' Ses ${detail.files.length} fichier(s) joint(s) seront effacés.',
          );
        }
        if (usages.isNotEmpty) {
          buffer.write(
            '\n\nIl est utilisé dans ${usages.length} pièce(s) :\n'
            '${usages.map((u) => '• ${u.itemName} — ${u.dossierTitle}').join('\n')}'
            '\n\nCes associations seront retirées et les pièces concernées '
            'redeviendront manquantes.',
          );
        }
        buffer.write('\n\nPour le conserver sans l’afficher, archivez-le.');
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
          showMessage(context, 'Document supprimé.');
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
      success: 'Fichier joint.',
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
          '« ${file.fileName} » sera effacé de l’espace privé de Dossia. '
          'Le document reste dans votre bibliothèque.',
      confirmLabel: 'Retirer',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await runGuarded(
      context,
      () => ref.read(documentsRepositoryProvider).removeFile(file),
      success: 'Fichier retiré.',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = ref.watch(todayProvider);
    final doc = view.doc;
    final expiryState = view.expiryState(today);

    return Scaffold(
      appBar: AppBar(
        title: Text(view.displayName, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Modifier',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.push(Routes.editDocument(view.id)),
          ),
          PopupMenuButton<_MenuAction>(
            tooltip: "Plus d'actions",
            onSelected: (a) => _onMenu(context, ref, a),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _MenuAction.archive,
                child: Text(view.isArchived ? 'Réactiver' : 'Archiver'),
              ),
              const PopupMenuItem(
                value: _MenuAction.delete,
                child: Text('Supprimer'),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
                child: Icon(documentCategoryIcon(view.category)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(view.displayName, style: theme.textTheme.titleLarge),
                    Text(
                      '${view.type.name} · ${view.category.label}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (view.isArchived ||
              expiryState == ExpiryState.expired ||
              expiryState == ExpiryState.expiringSoon) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                if (view.isArchived) const ArchivedChip(),
                ExpiryChip(expiryState, dense: false),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                _InfoRow(
                  label: 'Date de délivrance',
                  value: doc.issueDate == null
                      ? null
                      : formatLongDate(doc.issueDate!),
                ),
                _InfoRow(
                  label: "Date d'expiration",
                  value: doc.expiryDate == null
                      ? null
                      : '${formatLongDate(doc.expiryDate!)} '
                            '(${relativeDayLabel(doc.expiryDate!, reference: today)})',
                ),
                _InfoRow(label: 'Autorité émettrice', value: doc.issuer),
                _InfoRow(label: 'Notes', value: doc.notes, last: true),
              ],
            ),
          ),
          SectionHeader(
            'Fichiers joints',
            padding: const EdgeInsets.fromLTRB(0, 24, 0, 8),
            trailing: TextButton.icon(
              onPressed: () => _addFile(context, ref),
              icon: const Icon(Icons.attach_file),
              label: const Text('Joindre'),
            ),
          ),
          if (detail.files.isEmpty)
            Text(
              'Aucun fichier. Le fichier numérique est facultatif.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final f in detail.files)
                    _FileTile(
                      file: f,
                      onOpen: () => openAttachment(context, ref, f),
                      onRemove: () => _removeFile(context, ref, f),
                    ),
                ],
              ),
            ),
          SectionHeader(
            'Utilisé dans',
            padding: const EdgeInsets.fromLTRB(0, 24, 0, 8),
          ),
          if (detail.usages.isEmpty)
            Text(
              "Ce document n'est associé à aucune pièce de dossier.",
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final u in detail.usages)
                    ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(u.dossierTitle),
                      subtitle: Text(
                        u.dossierArchived
                            ? '${u.itemName} · dossier archivé'
                            : u.itemName,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          context.push(Routes.item(u.dossierId, u.itemId)),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          Text(
            'Ajouté le ${formatDateTime(doc.createdAt)} · '
            'modifié le ${formatDateTime(doc.updatedAt)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, this.value, this.last = false});

  final String label;
  final String? value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Text(
                  value ?? 'Non renseigné',
                  style: value == null
                      ? theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        )
                      : theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        if (!last) const Divider(indent: 16, endIndent: 16),
      ],
    );
  }
}

/// Fichier joint ; un fichier absent du stockage est signalé (§ 9.2).
class _FileTile extends ConsumerWidget {
  const _FileTile({
    required this.file,
    required this.onOpen,
    required this.onRemove,
  });

  final DocumentFileRow file;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return FutureBuilder(
      future: ref.read(fileStorageProvider).resolve(file.relativePath),
      builder: (context, snapshot) {
        final missing =
            snapshot.connectionState == ConnectionState.done &&
            snapshot.data == null;
        return ListTile(
          leading: Icon(
            missing ? Icons.report_problem_outlined : attachmentIcon(file.mimeType),
            color: missing ? theme.colorScheme.error : null,
          ),
          title: Text(file.fileName, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            missing
                ? 'Fichier introuvable sur cet appareil'
                : formatFileSize(file.sizeBytes),
            style: missing ? TextStyle(color: theme.colorScheme.error) : null,
          ),
          onTap: onOpen,
          trailing: IconButton(
            tooltip: 'Retirer ${file.fileName}',
            icon: const Icon(Icons.delete_outline),
            onPressed: onRemove,
          ),
        );
      },
    );
  }
}

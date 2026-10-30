import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../app/theme/app_theme.dart';
import '../../../core/backup/backup_service.dart';
import '../../../core/files/export_actions.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../data/settings_repository.dart';

enum _Destination { share, save }

String _plural(int n, String singular, [String? plural]) =>
    '$n ${n > 1 ? (plural ?? '${singular}s') : singular}';

/// Sauvegarde manuelle et restauration (§ 4.10).
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _includeFiles = true;

  Future<void> _create(_Destination destination) async {
    final service = ref.read(backupServiceProvider);
    try {
      final file = await runWithProgress(
        context,
        'Création de la sauvegarde…',
        () => service.createBackup(includeFiles: _includeFiles),
      );
      if (!mounted) return;
      switch (destination) {
        case _Destination.share:
          await shareExportedFile(
            context,
            file: file,
            mimeType: 'application/zip',
            subject: 'Sauvegarde Dossia',
          );
        case _Destination.save:
          final bytes = await file.readAsBytes();
          if (!mounted) return;
          await saveExportToDevice(
            context,
            fileName: p.basename(file.path),
            bytes: bytes,
            mimeType: 'application/zip',
          );
      }
    } on BackupException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } catch (_) {
      if (mounted) {
        showMessage(
          context,
          "La sauvegarde n'a pas pu être créée. Vérifiez l'espace de "
          'stockage disponible.',
          error: true,
        );
      }
    }
  }

  Future<void> _restore() async {
    final service = ref.read(backupServiceProvider);
    PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(
        dialogTitle: 'Choisir une sauvegarde Dossia (.zip)',
      );
    } catch (_) {
      if (mounted) {
        showMessage(
          context,
          "Le sélecteur de fichiers n'a pas pu s'ouvrir.",
          error: true,
        );
      }
      return;
    }
    if (picked == null || !mounted) return;
    final path = picked.path;
    if (path == null) {
      showMessage(context, "Ce fichier n'est pas accessible.", error: true);
      return;
    }
    final archive = File(path);

    try {
      final preview = await runWithProgress(
        context,
        'Vérification de la sauvegarde…',
        () => service.inspectBackup(archive),
      );
      if (!mounted) return;
      final confirmed = await _confirmRestore(preview);
      if (!confirmed || !mounted) return;
      await runWithProgress(
        context,
        'Restauration en cours…',
        () => service.restoreBackup(archive),
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      final missing = preview.missingFileCount;
      showMessage(
        context,
        missing > 0
            ? 'Données restaurées. ${_plural(missing, 'fichier joint', 'fichiers joints')} '
                  '${missing > 1 ? 'manquent' : 'manque'} : ils seront '
                  'signalés comme introuvables.'
            : 'Données restaurées',
      );
    } on BackupException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } catch (_) {
      if (mounted) {
        showMessage(
          context,
          "La restauration n'a pas pu aboutir. Vos données actuelles n'ont "
          'pas été modifiées.',
          error: true,
        );
      }
    } finally {
      FilePicker.clearTemporaryFiles().ignore();
    }
  }

  Future<bool> _confirmRestore(BackupPreview preview) {
    final included = preview.fileCount - preview.missingFileCount;
    final details = [
      'Créée le ${formatDateTime(preview.createdAt)}',
      '${_plural(preview.documentCount, 'document')}, '
          '${_plural(preview.dossierCount, 'dossier')}',
      '${_plural(preview.requiredItemCount, 'pièce')}, '
          '${_plural(preview.taskCount, 'tâche')}',
      if (preview.fileCount > 0)
        preview.includesFiles
            ? '${_plural(included, 'fichier joint', 'fichiers joints')} inclus'
            : 'Fichiers joints non inclus',
    ];
    return showConfirmDialog(
      context,
      title: 'Restaurer cette sauvegarde ?',
      message:
          '${details.map((d) => '• $d').join('\n')}\n\n'
          'Toutes les données actuelles de Dossia sur ce téléphone seront '
          'remplacées. C’est irréversible.',
      confirmLabel: 'Remplacer mes données',
      destructive: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = StatusColors.of(context);
    final lastBackup = ref.watch(settingsProvider).value?.lastBackupAt;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return DetailScaffold(
      title: 'Sauvegarde',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Sauvegarde',
                    style: theme.textTheme.headlineMedium,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Une copie de vos données, à garder hors du téléphone.',
                  style: muted,
                ),
              ],
            ),
          ),
        ),
        SliverBox(
          child: Panel(
            child: AppRow(
              leading: IconTile(
                lastBackup == null
                    ? Icons.cloud_off_outlined
                    : Icons.cloud_done_outlined,
                background: lastBackup == null
                    ? status.warning
                    : status.success,
                foreground: lastBackup == null
                    ? status.onWarning
                    : status.onSuccess,
              ),
              title: lastBackup == null
                  ? 'Aucune sauvegarde'
                  : 'Dernière sauvegarde',
              subtitle: lastBackup == null
                  ? 'Créez-en une ci-dessous.'
                  : 'Le ${formatDateTime(lastBackup)}',
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        SliverBox(
          child: InfoBanner(
            icon: Icons.warning_amber_rounded,
            background: status.warning,
            foreground: status.onWarning,
            message:
                'Perte, vol, panne ou désinstallation : sans sauvegarde '
                'gardée ailleurs, vos données seraient perdues.',
          ),
        ),
        const SliverToBoxAdapter(child: SectionTitle('Créer une sauvegarde')),
        SliverBox(
          child: Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MergeSemantics(
                  child: AppRow(
                    leading: const IconTile(Icons.attach_file_rounded),
                    title: 'Inclure les fichiers joints',
                    subtitle: 'PDF et photos · fichier plus lourd',
                    chevron: false,
                    onTap: () => setState(() => _includeFiles = !_includeFiles),
                    trailing: Switch(
                      value: _includeFiles,
                      onChanged: (v) {
                        HapticFeedback.selectionClick();
                        setState(() => _includeFiles = v);
                      },
                    ),
                  ),
                ),
                const Divider(indent: 16, endIndent: 16),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Icon(
                              Icons.lock_open_rounded,
                              size: 17,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Le fichier .zip n’est pas chiffré : rangez-le '
                              'en lieu sûr et ne le partagez pas.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _create(_Destination.save),
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Enregistrer sur le téléphone'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => _create(_Destination.share),
                        icon: const Icon(Icons.ios_share_rounded),
                        label: const Text('Envoyer vers une application'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SectionTitle('Restaurer')),
        SliverBox(
          child: Panel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Remplace vos données actuelles par celles d’une '
                  'sauvegarde Dossia. Le fichier est vérifié avant toute '
                  'modification.',
                  style: muted,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _restore,
                  icon: const Icon(Icons.restore_rounded),
                  label: const Text('Choisir une sauvegarde'),
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }
}

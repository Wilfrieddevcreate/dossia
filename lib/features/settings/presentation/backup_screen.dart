import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../app/theme/status_colors.dart';
import '../../../core/backup/backup_service.dart';
import '../../../core/files/export_actions.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../data/settings_repository.dart';

enum _Destination { share, save }

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
      showMessage(
        context,
        preview.missingFileCount > 0
            ? 'Données restaurées. ${preview.missingFileCount} fichier(s) '
                  'joint(s) non inclus dans la sauvegarde sont signalés comme '
                  'absents.'
            : 'Données restaurées avec succès.',
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
    final details = [
      'Créée le ${formatDateTime(preview.createdAt)}',
      '${preview.documentCount} document(s), ${preview.dossierCount} dossier(s)',
      '${preview.requiredItemCount} pièce(s), ${preview.taskCount} tâche(s)',
      if (preview.fileCount > 0)
        preview.includesFiles
            ? '${preview.fileCount - preview.missingFileCount} fichier(s) joint(s) inclus'
            : 'Fichiers joints non inclus',
    ];
    return showConfirmDialog(
      context,
      title: 'Restaurer cette sauvegarde ?',
      message:
          '${details.map((d) => '• $d').join('\n')}\n\n'
          'Toutes les données actuelles de Dossia sur ce téléphone seront '
          'remplacées par celles de la sauvegarde. Cette action est '
          'irréversible.',
      confirmLabel: 'Remplacer mes données',
      destructive: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = StatusColors.of(context);
    final lastBackup = ref.watch(settingsProvider).value?.lastBackupAt;
    return Scaffold(
      appBar: AppBar(title: const Text('Sauvegarde et restauration')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          InfoBanner(
            icon: Icons.warning_amber_rounded,
            background: colors.warning,
            foreground: colors.onWarning,
            title: 'Vos données sont uniquement sur ce téléphone',
            message:
                'Sans sauvegarde, elles seront perdues en cas de '
                'désinstallation, de perte, de vol ou de panne du téléphone. '
                'Conservez une sauvegarde récente hors du téléphone '
                '(ordinateur, clé USB, messagerie personnelle…).',
          ),
          const SizedBox(height: 12),
          Text(
            lastBackup == null
                ? 'Aucune sauvegarde effectuée pour le moment.'
                : 'Dernière sauvegarde : ${formatDateTime(lastBackup)}.',
            style: theme.textTheme.bodyMedium,
          ),
          const SectionHeader(
            'Créer une sauvegarde',
            padding: EdgeInsets.fromLTRB(0, 24, 0, 8),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Inclure les fichiers joints'),
                    subtitle: const Text(
                      'PDF et images associés aux documents. La sauvegarde '
                      'sera plus volumineuse.',
                    ),
                    value: _includeFiles,
                    onChanged: (v) => setState(() => _includeFiles = v),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'La sauvegarde est un fichier .zip non chiffré : elle '
                    'contient vos informations personnelles. Rangez-la dans '
                    'un endroit sûr et ne la partagez pas.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _create(_Destination.save),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text("Enregistrer sur l'appareil"),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _create(_Destination.share),
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Envoyer vers une autre application'),
                  ),
                ],
              ),
            ),
          ),
          const SectionHeader(
            'Restaurer une sauvegarde',
            padding: EdgeInsets.fromLTRB(0, 24, 0, 8),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Choisissez un fichier de sauvegarde Dossia. Son contenu '
                    'est vérifié avant toute modification ; vous devrez '
                    'ensuite confirmer le remplacement de vos données.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _restore,
                    icon: const Icon(Icons.restore),
                    label: const Text('Choisir une sauvegarde'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

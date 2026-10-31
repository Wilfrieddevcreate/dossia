import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../app/theme/app_theme.dart';
import '../../../core/backup/backup_crypto.dart';
import '../../../core/backup/backup_service.dart';
import '../../../core/files/export_actions.dart';
import '../../../core/security/app_lock.dart';
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
  bool _protect = false;
  bool _showPassword = false;
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _create(_Destination destination) async {
    if (_protect && !(_formKey.currentState?.validate() ?? false)) return;
    final service = ref.read(backupServiceProvider);
    final password = _protect ? _password.text : null;
    try {
      final file = await runWithProgress(
        context,
        password == null
            ? 'Création de la sauvegarde…'
            : 'Chiffrement de la sauvegarde…',
        () => service.createBackup(
          includeFiles: _includeFiles,
          password: password,
        ),
      );
      // Le mot de passe n'est plus conservé une fois la sauvegarde créée.
      _password.clear();
      _confirm.clear();
      if (!mounted) return;
      final mimeType = password == null
          ? 'application/zip'
          : 'application/octet-stream';
      switch (destination) {
        case _Destination.share:
          await shareExportedFile(
            context,
            file: file,
            mimeType: mimeType,
            subject: 'Sauvegarde Dossia',
          );
        case _Destination.save:
          final bytes = await file.readAsBytes();
          if (!mounted) return;
          await saveExportToDevice(
            context,
            fileName: p.basename(file.path),
            bytes: bytes,
            mimeType: mimeType,
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
      // Le retour du sélecteur ne doit pas verrouiller l'application.
      ExternalActivity.expect();
      picked = await FilePicker.pickFile(
        dialogTitle: 'Choisir une sauvegarde Dossia (.zip ou .dossia)',
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

    String? password;
    try {
      final BackupPreview preview;
      final encrypted = await service.isEncryptedBackup(archive);
      if (!mounted) return;
      if (encrypted) {
        final unlocked = await showDialog<(String, BackupPreview)>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _PasswordDialog(service: service, archive: archive),
        );
        if (unlocked == null || !mounted) return;
        (password, preview) = unlocked;
      } else {
        preview = await runWithProgress(
          context,
          'Vérification de la sauvegarde…',
          () => service.inspectBackup(archive),
        );
      }
      if (!mounted) return;
      final confirmed = await _confirmRestore(preview);
      if (!confirmed || !mounted) return;
      await runWithProgress(
        context,
        'Restauration en cours…',
        () => service.restoreBackup(archive, password: password),
      );
      password = null;
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

  void _setProtect(bool value) {
    setState(() {
      _protect = value;
      if (!value) {
        _password.clear();
        _confirm.clear();
        _showPassword = false;
      }
    });
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
                const Divider(indent: 70, endIndent: 16),
                MergeSemantics(
                  child: AppRow(
                    leading: const IconTile(Icons.lock_outline_rounded),
                    title: 'Protéger par un mot de passe',
                    subtitle: 'Chiffre la sauvegarde',
                    chevron: false,
                    onTap: () => _setProtect(!_protect),
                    trailing: Switch(
                      value: _protect,
                      onChanged: (v) {
                        HapticFeedback.selectionClick();
                        _setProtect(v);
                      },
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _protect
                      ? _PasswordFields(
                          formKey: _formKey,
                          password: _password,
                          confirm: _confirm,
                          visible: _showPassword,
                          onToggleVisibility: () =>
                              setState(() => _showPassword = !_showPassword),
                        )
                      : const SizedBox(width: double.infinity),
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
                              _protect
                                  ? Icons.lock_rounded
                                  : Icons.lock_open_rounded,
                              size: 17,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _protect
                                  ? 'Le fichier .dossia sera chiffré : seul ce '
                                        'mot de passe permettra de l’ouvrir.'
                                  : 'Le fichier .zip n’est pas chiffré : '
                                        'rangez-le en lieu sûr et ne le '
                                        'partagez pas.',
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

/// Mot de passe et confirmation, avec avertissement.
class _PasswordFields extends StatelessWidget {
  const _PasswordFields({
    required this.formKey,
    required this.password,
    required this.confirm,
    required this.visible,
    required this.onToggleVisibility,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController password;
  final TextEditingController confirm;
  final bool visible;
  final VoidCallback onToggleVisibility;

  @override
  Widget build(BuildContext context) {
    final status = StatusColors.of(context);
    final toggle = IconButton(
      tooltip: visible ? 'Masquer le mot de passe' : 'Afficher le mot de passe',
      icon: Icon(
        visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
      ),
      onPressed: onToggleVisibility,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: password,
              obscureText: !visible,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'Mot de passe',
                helperText: 'Au moins $minBackupPasswordLength caractères',
                suffixIcon: toggle,
              ),
              validator: (v) =>
                  (v == null || v.runes.length < minBackupPasswordLength)
                  ? 'Au moins $minBackupPasswordLength caractères.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: confirm,
              obscureText: !visible,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              decoration: InputDecoration(
                labelText: 'Confirmer le mot de passe',
                suffixIcon: toggle,
              ),
              validator: (v) => v != password.text
                  ? 'Les deux mots de passe sont différents.'
                  : null,
            ),
            const SizedBox(height: 12),
            InfoBanner(
              icon: Icons.key_rounded,
              background: status.warning,
              foreground: status.onWarning,
              message:
                  'Sans ce mot de passe, la sauvegarde ne pourra pas être '
                  'restaurée. Dossia ne peut pas le retrouver.',
            ),
          ],
        ),
      ),
    );
  }
}

/// Demande le mot de passe d'une sauvegarde chiffrée et la vérifie, en
/// laissant réessayer en cas d'erreur. Renvoie le mot de passe et le résumé.
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.service, required this.archive});

  final BackupService service;
  final File archive;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();
  bool _visible = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _controller.text;
    if (password.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preview = await widget.service.inspectBackup(
        widget.archive,
        password: password,
      );
      _controller.clear();
      if (mounted) Navigator.of(context).pop((password, preview));
    } on BackupWrongPassword catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } on BackupException catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      showMessage(context, e.message, error: true);
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop();
      showMessage(context, "La sauvegarde n'a pas pu être lue.", error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.lock_outline_rounded),
      title: const Text('Sauvegarde protégée'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Saisissez le mot de passe choisi lors de la sauvegarde.'),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_busy,
            obscureText: !_visible,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
            onSubmitted: (_) => _submit(),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              labelText: 'Mot de passe',
              errorText: _error,
              suffixIcon: IconButton(
                tooltip: _visible
                    ? 'Masquer le mot de passe'
                    : 'Afficher le mot de passe',
                icon: Icon(
                  _visible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () => setState(() => _visible = !_visible),
              ),
            ),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Text('Ouvrir'),
        ),
      ],
    );
  }
}

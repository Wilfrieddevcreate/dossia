import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/files/file_storage_service.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/utils/app_info.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../data/settings_repository.dart';

const _deadlineLeadOptions = [1, 3, 7, 14];
const _expiryLeadOptions = [7, 14, 30, 60, 90];

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _toggleNotifications(
    BuildContext context,
    WidgetRef ref,
    bool enable,
  ) async {
    final repo = ref.read(settingsRepositoryProvider);
    if (!enable) {
      await runGuarded(
        context,
        () => repo.setBool(SettingKeys.notificationsEnabled, false),
      );
      return;
    }
    final granted = await ref
        .read(notificationServiceProvider)
        .requestPermission();
    if (!context.mounted) return;
    if (!granted) {
      showMessage(
        context,
        'Autorisation refusée. Activez les notifications de Dossia dans les '
        'réglages Android pour recevoir les rappels.',
        error: true,
      );
      return;
    }
    await runGuarded(
      context,
      () => repo.setBool(SettingKeys.notificationsEnabled, true),
      success: 'Rappels activés.',
    );
  }

  Future<void> _wipe(BuildContext context, WidgetRef ref) async {
    final first = await showConfirmDialog(
      context,
      title: 'Supprimer toutes les données ?',
      message:
          'Tous vos documents, fichiers joints, dossiers, pièces, tâches et '
          'préférences seront effacés de ce téléphone. Cette action est '
          'irréversible.\n\nSi vous souhaitez les conserver, créez d’abord '
          'une sauvegarde.',
      confirmLabel: 'Continuer',
      destructive: true,
    );
    if (!first || !context.mounted) return;
    final second = await showConfirmDialog(
      context,
      title: 'Confirmer la suppression',
      message:
          'Dernière confirmation : toutes les données de Dossia vont être '
          'supprimées définitivement.',
      confirmLabel: 'Tout supprimer',
      destructive: true,
    );
    if (!second || !context.mounted) return;
    final ok = await runGuarded(context, () async {
      await ref.read(notificationServiceProvider).cancelAll();
      await ref.read(settingsRepositoryProvider).wipeAllData();
      await ref.read(fileStorageProvider).deleteAll();
    });
    if (ok && context.mounted) {
      showMessage(context, 'Toutes les données ont été supprimées.');
      context.go(Routes.welcome);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: AsyncView(
        value: settings,
        builder: (s) => ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const SectionHeader('Rappels'),
            SwitchListTile(
              secondary: const Icon(Icons.notifications_outlined),
              title: const Text('Activer les rappels'),
              subtitle: const Text(
                'Notifications locales avant les dates limites et les dates '
                "d'expiration. Le contenu est masqué sur l'écran de "
                'verrouillage.',
              ),
              value: s.notificationsEnabled,
              onChanged: (v) => _toggleNotifications(context, ref, v),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _LeadDaysField(
                label: 'Rappel avant une date limite',
                enabled: s.notificationsEnabled,
                value: _deadlineLeadOptions.contains(s.deadlineReminderDays)
                    ? s.deadlineReminderDays
                    : 3,
                options: _deadlineLeadOptions,
                onChanged: (v) => ref
                    .read(settingsRepositoryProvider)
                    .setInt(SettingKeys.deadlineReminderDays, v),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: _LeadDaysField(
                label: "Rappel avant l'expiration d'un document",
                enabled: s.notificationsEnabled,
                value: _expiryLeadOptions.contains(s.expiryReminderDays)
                    ? s.expiryReminderDays
                    : 30,
                options: _expiryLeadOptions,
                onChanged: (v) => ref
                    .read(settingsRepositoryProvider)
                    .setInt(SettingKeys.expiryReminderDays, v),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Un second rappel est envoyé le jour même, à 9 h. Android '
                'peut décaler légèrement l’heure pour économiser la batterie.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SectionHeader('Données'),
            ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: const Text('Sauvegarde et restauration'),
              subtitle: Text(
                s.lastBackupAt == null
                    ? 'Aucune sauvegarde effectuée'
                    : 'Dernière sauvegarde : ${formatDateTime(s.lastBackupAt!)}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.backup),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_check),
              title: const Text('Compléter mon inventaire'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.inventory),
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Confidentialité et stockage'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.privacy),
            ),
            const SectionHeader('Zone sensible'),
            ListTile(
              leading: Icon(
                Icons.delete_forever_outlined,
                color: theme.colorScheme.error,
              ),
              title: Text(
                'Supprimer toutes les données',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              subtitle: const Text('Efface tout le contenu de Dossia'),
              onTap: () => _wipe(context, ref),
            ),
            const SectionHeader('À propos'),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Dossia'),
              subtitle: const Text(
                'Version $appVersion · Fonctionne hors ligne, sans compte',
              ),
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'Dossia',
                applicationVersion: appVersion,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Choix du délai de rappel, sur toute la largeur pour rester lisible avec
/// une grande taille de texte.
class _LeadDaysField extends StatelessWidget {
  const _LeadDaysField({
    required this.label,
    required this.enabled,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final bool enabled;
  final int value;
  final List<int> options;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      isExpanded: true,
      initialValue: value,
      decoration: InputDecoration(labelText: label, enabled: enabled),
      onChanged: enabled ? (v) => onChanged(v!) : null,
      items: [
        for (final d in options)
          DropdownMenuItem(
            value: d,
            child: Text('$d jour${d > 1 ? 's' : ''} avant'),
          ),
      ],
    );
  }
}

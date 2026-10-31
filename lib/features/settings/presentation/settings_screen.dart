import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/files/file_storage_service.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/security/app_lock.dart';
import '../../../core/utils/app_info.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../data/settings_repository.dart';

const _deadlineLeadOptions = [1, 3, 7, 14];
const _expiryLeadOptions = [7, 14, 30, 60, 90];

String _daysBefore(int d) => d == 1 ? '1 jour avant' : '$d jours avant';

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
        'Notifications refusées. Autorisez-les pour Dossia dans les '
        'réglages Android.',
        error: true,
      );
      return;
    }
    await runGuarded(
      context,
      () => repo.setBool(SettingKeys.notificationsEnabled, true),
      success: 'Rappels activés',
    );
  }

  Future<void> _toggleLock(
    BuildContext context,
    WidgetRef ref,
    bool enable,
  ) async {
    final outcome = await ref.read(appLockProvider.notifier).setEnabled(enable);
    if (!context.mounted) return;
    switch (outcome) {
      case AuthOutcome.success:
        HapticFeedback.lightImpact();
        showMessage(
          context,
          enable ? 'Verrouillage activé' : 'Verrouillage désactivé',
        );
      case AuthOutcome.unavailable:
        showMessage(
          context,
          'Configurez d’abord un code, un schéma ou une empreinte dans les '
          'réglages du téléphone.',
          error: true,
        );
      case AuthOutcome.lockedOut:
        showMessage(
          context,
          'Trop de tentatives. Réessayez dans quelques instants.',
          error: true,
        );
      case AuthOutcome.failed:
        showMessage(context, 'Authentification impossible.', error: true);
      case AuthOutcome.cancelled:
        break;
    }
  }

  Future<void> _pickLeadDays(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String key,
    required List<int> options,
    required int current,
  }) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      builder: (context) =>
          _LeadDaysSheet(title: title, options: options, current: current),
    );
    if (picked == null || picked == current || !context.mounted) return;
    await runGuarded(
      context,
      () => ref.read(settingsRepositoryProvider).setInt(key, picked),
    );
  }

  Future<void> _wipe(BuildContext context, WidgetRef ref) async {
    final first = await showConfirmDialog(
      context,
      title: 'Supprimer toutes les données ?',
      message:
          'Documents, fichiers joints, dossiers, tâches et préférences '
          'seront effacés de ce téléphone. C’est irréversible.\n\n'
          'Pour les garder, faites d’abord une sauvegarde.',
      confirmLabel: 'Continuer',
      destructive: true,
    );
    if (!first || !context.mounted) return;
    final second = await showConfirmDialog(
      context,
      title: 'Dernière confirmation',
      message: 'Tout le contenu de Dossia va être supprimé définitivement.',
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
      showMessage(context, 'Toutes les données ont été supprimées');
      context.go(Routes.welcome);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final status = StatusColors.of(context);
    return Scaffold(
      body: AsyncView(
        value: settings,
        builder: (s) {
          final deadlineDays =
              _deadlineLeadOptions.contains(s.deadlineReminderDays)
              ? s.deadlineReminderDays
              : 3;
          final expiryDays = _expiryLeadOptions.contains(s.expiryReminderDays)
              ? s.expiryReminderDays
              : 30;
          final enabled = s.notificationsEnabled;
          final valueStyle = theme.textTheme.labelLarge?.copyWith(
            color: enabled
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          );
          final dimmed = theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: enabled ? null : theme.colorScheme.onSurfaceVariant,
          );

          return CustomScrollView(
            slivers: [
              const LargeTitleAppBar(title: 'Réglages'),
              const SliverToBoxAdapter(
                child: SectionTitle(
                  'Notifications',
                  padding: EdgeInsets.fromLTRB(20, 8, 12, 10),
                ),
              ),
              SliverBox(
                child: ListGroup(
                  children: [
                    MergeSemantics(
                      child: AppRow(
                        leading: const IconTile(Icons.notifications_outlined),
                        title: 'Rappels',
                        subtitle: 'Avant les dates limites et les expirations',
                        chevron: false,
                        onTap: () =>
                            _toggleNotifications(context, ref, !enabled),
                        trailing: Switch(
                          value: enabled,
                          onChanged: (v) {
                            HapticFeedback.selectionClick();
                            _toggleNotifications(context, ref, v);
                          },
                        ),
                      ),
                    ),
                    AppRow(
                      leading: const IconTile(Icons.event_outlined),
                      title: 'Avant une date limite',
                      titleStyle: dimmed,
                      trailing: Text(
                        _daysBefore(deadlineDays),
                        style: valueStyle,
                      ),
                      chevron: enabled,
                      onTap: enabled
                          ? () => _pickLeadDays(
                              context,
                              ref,
                              title: 'Rappel avant une date limite',
                              key: SettingKeys.deadlineReminderDays,
                              options: _deadlineLeadOptions,
                              current: deadlineDays,
                            )
                          : null,
                    ),
                    AppRow(
                      leading: const IconTile(Icons.update_rounded),
                      title: 'Avant une expiration',
                      titleStyle: dimmed,
                      trailing: Text(
                        _daysBefore(expiryDays),
                        style: valueStyle,
                      ),
                      chevron: enabled,
                      onTap: enabled
                          ? () => _pickLeadDays(
                              context,
                              ref,
                              title: 'Rappel avant une expiration',
                              key: SettingKeys.expiryReminderDays,
                              options: _expiryLeadOptions,
                              current: expiryDays,
                            )
                          : null,
                    ),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: Text(
                    'Un second rappel arrive le jour même, vers 9 h.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SectionTitle('Sécurité')),
              SliverBox(
                child: ListGroup(
                  children: [
                    MergeSemantics(
                      child: AppRow(
                        leading: const IconTile(Icons.lock_outline_rounded),
                        title: 'Verrouiller Dossia',
                        subtitle: 'Empreinte, visage ou code du téléphone',
                        chevron: false,
                        onTap: () =>
                            _toggleLock(context, ref, !s.appLockEnabled),
                        trailing: Switch(
                          value: s.appLockEnabled,
                          onChanged: (v) {
                            HapticFeedback.selectionClick();
                            _toggleLock(context, ref, v);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (s.appLockEnabled)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: Text(
                      'Dossia se verrouille à l’ouverture et après 30 secondes '
                      'hors de l’application.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SectionTitle('Données')),
              SliverBox(
                child: ListGroup(
                  children: [
                    AppRow(
                      leading: const IconTile(Icons.cloud_upload_outlined),
                      title: 'Sauvegarde et restauration',
                      subtitle: s.lastBackupAt == null
                          ? 'Aucune sauvegarde pour l’instant'
                          : 'Dernière le ${formatCompactDate(s.lastBackupAt!.toLocal())}',
                      onTap: () => context.push(Routes.backup),
                    ),
                    AppRow(
                      leading: const IconTile(Icons.playlist_add_check_rounded),
                      title: 'Compléter mon inventaire',
                      onTap: () => context.push(Routes.inventory),
                    ),
                    AppRow(
                      leading: const IconTile(Icons.shield_outlined),
                      title: 'Confidentialité et stockage',
                      onTap: () => context.push(Routes.privacy),
                    ),
                  ],
                ),
              ),
              const SliverToBoxAdapter(child: SectionTitle('Zone sensible')),
              SliverBox(
                child: Panel(
                  child: AppRow(
                    leading: IconTile(
                      Icons.delete_outline_rounded,
                      background: status.danger,
                      foreground: status.onDanger,
                    ),
                    title: 'Supprimer toutes les données',
                    titleStyle: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: status.onDanger,
                    ),
                    subtitle: 'Efface tout le contenu de Dossia',
                    chevron: false,
                    onTap: () => _wipe(context, ref),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SectionTitle('À propos')),
              SliverBox(
                child: Panel(
                  child: AppRow(
                    leading: const IconTile(Icons.info_outline_rounded),
                    title: 'Dossia $appVersion',
                    subtitle: 'Hors ligne, sans compte · Licences',
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: 'Dossia',
                      applicationVersion: appVersion,
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          );
        },
      ),
    );
  }
}

class _LeadDaysSheet extends StatelessWidget {
  const _LeadDaysSheet({
    required this.title,
    required this.options,
    required this.current,
  });

  final String title;
  final List<int> options;
  final int current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(title, style: theme.textTheme.titleLarge),
          ),
          RadioGroup<int>(
            groupValue: current,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              Navigator.of(context).pop(v);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final d in options)
                  RadioListTile<int>(
                    value: d,
                    title: Text(_daysBefore(d)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

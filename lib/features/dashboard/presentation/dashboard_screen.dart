import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/status_colors.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/today_provider.dart';
import '../../../core/widgets/common.dart';
import '../../deadlines/data/deadlines_provider.dart';
import '../../deadlines/presentation/deadline_tile.dart';
import '../../documents/data/documents_repository.dart';
import '../../dossiers/data/dossiers_repository.dart';
import '../../dossiers/presentation/dossiers_screen.dart';
import '../../settings/data/settings_repository.dart';

/// Délai au-delà duquel l'accueil suggère une nouvelle sauvegarde.
const _backupReminderDays = 30;

/// Tableau de bord (§ 4.1).
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dossiers = ref.watch(dossierOverviewsProvider);
    final deadlines = ref.watch(splitDeadlinesProvider);
    final documentCount = ref.watch(documentsProvider).value?.length ?? 0;
    final settings = ref.watch(settingsProvider).value;
    final today = ref.watch(todayProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dossia'),
        actions: [
          IconButton(
            tooltip: 'Échéances',
            icon: const Icon(Icons.event_note_outlined),
            onPressed: () => context.push(Routes.deadlines),
          ),
        ],
      ),
      body: AsyncView(
        value: dossiers,
        builder: (all) {
          final active = all.where((d) => d.isActive).toList();
          final missing = active.fold<int>(
            0,
            (sum, d) => sum + d.progress.mandatoryMissing,
          );
          final toCheck = active.fold<int>(
            0,
            (sum, d) =>
                sum + d.progress.mandatoryToVerify + d.progress.mandatoryToRenew,
          );
          final recent =
              all
                  .where((d) => !d.isArchived && d.dossier.lastOpenedAt != null)
                  .toList()
                ..sort(
                  (a, b) => b.dossier.lastOpenedAt!.compareTo(
                    a.dossier.lastOpenedAt!,
                  ),
                );
          final split = deadlines.value;
          final nextDeadlines = [
            ...?split?.overdue.take(2),
            ...?split?.upcoming.take(3),
          ];
          final lastBackup = settings?.lastBackupAt;
          final needsBackup =
              (all.isNotEmpty || documentCount > 0) &&
              (lastBackup == null ||
                  daysBetween(lastBackup.toLocal(), DateTime.now()) >
                      _backupReminderDays);

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bonjour', style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text(
                      active.isEmpty
                          ? 'Préparez vos dossiers sans oublier une seule pièce.'
                          : 'Voici où en sont vos dossiers.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        label: 'Dossiers actifs',
                        value: active.length,
                        icon: Icons.folder_outlined,
                        onTap: () => context.go(Routes.dossiers),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        label: 'Pièces manquantes',
                        value: missing,
                        icon: Icons.radio_button_unchecked,
                        highlight: missing > 0,
                        onTap: () => context.go(Routes.dossiers),
                      ),
                    ),
                  ],
                ),
              ),
              if (toCheck > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    '$toCheck pièce(s) obligatoire(s) à vérifier ou à '
                    'renouveler.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (needsBackup)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: InfoBanner(
                    icon: Icons.backup_outlined,
                    background: StatusColors.of(context).warning,
                    foreground: StatusColors.of(context).onWarning,
                    title: lastBackup == null
                        ? 'Aucune sauvegarde'
                        : 'Dernière sauvegarde il y a plus de $_backupReminderDays jours',
                    message:
                        'Vos données restent sur ce téléphone. Sans '
                        'sauvegarde, elles seraient perdues en cas de perte, '
                        'de panne ou de désinstallation.',
                    action: TextButton(
                      onPressed: () => context.push(Routes.backup),
                      child: const Text('Sauvegarder maintenant'),
                    ),
                  ),
                ),
              SectionHeader(
                'Prochaines échéances',
                trailing: TextButton(
                  onPressed: () => context.push(Routes.deadlines),
                  child: const Text('Tout voir'),
                ),
              ),
              if (nextDeadlines.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Aucune échéance. Les dates limites des dossiers et les '
                    "dates d'expiration des documents apparaîtront ici.",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final e in nextDeadlines)
                          DeadlineTile(entry: e, today: today),
                      ],
                    ),
                  ),
                ),
              SectionHeader(
                'Récemment consultés',
                trailing: recent.isEmpty
                    ? null
                    : TextButton(
                        onPressed: () => context.go(Routes.dossiers),
                        child: const Text('Tous les dossiers'),
                      ),
              ),
              if (recent.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: InfoBanner(
                    icon: Icons.create_new_folder_outlined,
                    message:
                        'Créez votre premier dossier : visa, inscription, '
                        'candidature… puis listez les pièces demandées.',
                  ),
                )
              else
                for (final d in recent.take(3))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: DossierCard(overview: d),
                  ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: () => context.push(Routes.newDossier),
                      icon: const Icon(Icons.create_new_folder_outlined),
                      label: const Text('Créer un dossier'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => context.go(Routes.documents),
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: Text('Ma bibliothèque ($documentCount)'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.highlight = false,
  });

  final String label;
  final int value;
  final IconData icon;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = StatusColors.of(context);
    final fg = highlight ? colors.onDanger : theme.colorScheme.onSurface;
    return Semantics(
      button: true,
      label: '$label : $value',
      excludeSemantics: true,
      child: Card(
        color: highlight ? colors.danger : null,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: highlight ? fg : theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text(
                  '$value',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

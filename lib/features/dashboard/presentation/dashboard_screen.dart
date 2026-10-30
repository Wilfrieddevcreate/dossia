import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/today_provider.dart';
import '../../../core/widgets/common.dart';
import '../../deadlines/data/deadlines_provider.dart';
import '../../deadlines/domain/deadline_models.dart';
import '../../deadlines/presentation/deadline_tile.dart';
import '../../documents/data/documents_repository.dart';
import '../../dossiers/data/dossiers_repository.dart';
import '../../dossiers/domain/dossier_models.dart';
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
    final deadlines = ref.watch(splitDeadlinesProvider).value;
    final documentCount = ref.watch(documentsProvider).value?.length ?? 0;
    final settings = ref.watch(settingsProvider).value;
    final today = ref.watch(todayProvider);

    return Scaffold(
      body: AsyncView(
        value: dossiers,
        builder: (all) {
          final active = all.where((d) => d.isActive).toList();
          final recent = all.where((d) => d.isActive).toList()
            ..sort((a, b) {
              final la = a.dossier.lastOpenedAt ?? a.dossier.updatedAt;
              final lb = b.dossier.lastOpenedAt ?? b.dossier.updatedAt;
              return lb.compareTo(la);
            });
          final upcoming = [
            ...?deadlines?.overdue.take(2),
            ...?deadlines?.upcoming.take(3),
          ];
          final lastBackup = settings?.lastBackupAt;
          final needsBackup =
              (all.isNotEmpty || documentCount > 0) &&
              (lastBackup == null ||
                  daysBetween(lastBackup.toLocal(), DateTime.now()) >
                      _backupReminderDays);

          return CustomScrollView(
            slivers: [
              SliverSafeArea(
                bottom: false,
                sliver: SliverToBoxAdapter(
                  child: _Header(
                    today: today,
                    overdueCount: deadlines?.overdue.length ?? 0,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: _SummaryPanel(
                    active: active,
                    hasAny: all.isNotEmpty,
                    next: deadlines?.upcoming.firstOrNull,
                    today: today,
                  ),
                ),
              ),
              if (recent.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: SectionTitle(
                    'En cours',
                    action: SectionAction(
                      label: 'Tout voir',
                      onPressed: () => context.go(Routes.dossiers),
                    ),
                  ),
                ),
                _padded(
                  ListGroup(
                    children: [
                      for (final d in recent.take(3))
                        DossierListRow(overview: d),
                    ],
                  ),
                ),
              ],
              if (upcoming.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: SectionTitle(
                    'À venir',
                    action: SectionAction(
                      label: 'Échéances',
                      onPressed: () => context.push(Routes.deadlines),
                    ),
                  ),
                ),
                _padded(
                  ListGroup(
                    children: [
                      for (final e in upcoming)
                        DeadlineTile(entry: e, today: today),
                    ],
                  ),
                ),
              ],
              if (all.isEmpty) ...[
                const SliverToBoxAdapter(
                  child: SectionTitle('Pour bien démarrer'),
                ),
                _padded(
                  ListGroup(
                    children: [
                      AppRow(
                        leading: const IconTile(
                          Icons.playlist_add_check_rounded,
                        ),
                        title: documentCount == 0
                            ? 'Enregistrez vos documents'
                            : 'Complétez votre inventaire',
                        subtitle:
                            'Identité, diplômes, attestations… même sans '
                            'scan.',
                        onTap: () => context.push(Routes.inventory),
                      ),
                      AppRow(
                        leading: const IconTile(Icons.restore_rounded),
                        title: 'Restaurer une sauvegarde',
                        subtitle:
                            'Vous changez de téléphone ? Récupérez vos '
                            'données.',
                        onTap: () => context.push(Routes.backup),
                      ),
                    ],
                  ),
                ),
              ],
              if (needsBackup) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 28)),
                _padded(_BackupReminder(lastBackup: lastBackup)),
              ],
              if (all.isNotEmpty || documentCount > 0) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                _padded(
                  Panel(
                    child: AppRow(
                      leading: const IconTile(Icons.inventory_2_outlined),
                      title: 'Ma bibliothèque',
                      subtitle:
                          '$documentCount document${documentCount > 1 ? 's' : ''} enregistré${documentCount > 1 ? 's' : ''}',
                      onTap: () => context.go(Routes.documents),
                    ),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          );
        },
      ),
    );
  }

  Widget _padded(Widget child) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    sliver: SliverToBoxAdapter(child: child),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.today, required this.overdueCount});

  final DateTime today;
  final int overdueCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = DateFormat('EEEE d MMMM', 'fr_FR').format(today);
    final greeting = DateTime.now().hour >= 18 ? 'Bonsoir' : 'Bonjour';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 8, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date[0].toUpperCase() + date.substring(1),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Semantics(
                  header: true,
                  child: Text(greeting, style: theme.textTheme.headlineLarge),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: overdueCount > 0
                ? 'Échéances, $overdueCount en retard'
                : 'Échéances',
            onPressed: () => context.push(Routes.deadlines),
            icon: Badge(
              isLabelVisible: overdueCount > 0,
              smallSize: 9,
              backgroundColor: StatusColors.of(context).dangerIcon,
              child: const Icon(Icons.calendar_month_outlined),
            ),
          ),
        ],
      ),
    );
  }
}

/// Synthèse en tête d'accueil : ce qu'il reste à réunir.
class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({
    required this.active,
    required this.hasAny,
    required this.next,
    required this.today,
  });

  final List<DossierOverview> active;
  final bool hasAny;
  final DeadlineEntry? next;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final bg = dark ? scheme.primaryContainer : scheme.primary;
    final fg = dark ? scheme.onPrimaryContainer : scheme.onPrimary;
    final soft = fg.withValues(alpha: 0.78);

    final missing = active.fold<int>(
      0,
      (s, d) => s + d.progress.mandatoryMissing,
    );
    final toCheck = active.fold<int>(
      0,
      (s, d) => s + d.progress.mandatoryToVerify + d.progress.mandatoryToRenew,
    );

    final Widget body;
    if (active.isEmpty) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasAny ? 'Aucun dossier en cours' : 'Votre premier dossier',
            style: theme.textTheme.headlineSmall?.copyWith(color: fg),
          ),
          const SizedBox(height: 6),
          Text(
            hasAny
                ? 'Vos dossiers sont terminés ou archivés.'
                : 'Listez les pièces demandées, Dossia vous montre ce qu’il '
                      'manque.',
            style: theme.textTheme.bodyMedium?.copyWith(color: soft),
          ),
          const SizedBox(height: 18),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: fg,
              foregroundColor: bg,
              minimumSize: const Size(64, 46),
            ),
            onPressed: () => context.push(Routes.newDossier),
            child: const Text('Créer un dossier'),
          ),
        ],
      );
    } else {
      final dossierWord = active.length > 1 ? 'dossiers' : 'dossier';
      final headline = missing == 0
          ? (toCheck == 0 ? 'Tout est réuni' : '$toCheck à vérifier')
          : '$missing pièce${missing > 1 ? 's' : ''} à réunir';
      final sub = missing == 0 && toCheck == 0
          ? 'Vos ${active.length} $dossierWord en cours sont complets.'
          : [
              'Dans ${active.length} $dossierWord en cours',
              if (missing > 0 && toCheck > 0) '$toCheck à vérifier',
            ].join(' · ');
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headline,
            style: theme.textTheme.headlineMedium?.copyWith(color: fg),
          ),
          const SizedBox(height: 4),
          Text(sub, style: theme.textTheme.bodyMedium?.copyWith(color: soft)),
          if (next != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Divider(color: fg.withValues(alpha: 0.18), height: 1),
            ),
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 18, color: soft),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: next!.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text:
                              ' · ${relativeDayLabel(next!.date, reference: today)}',
                        ),
                      ],
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      );
    }

    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(26),
        ),
        child: body,
      ),
    );
  }
}

class _BackupReminder extends StatelessWidget {
  const _BackupReminder({required this.lastBackup});

  final DateTime? lastBackup;

  @override
  Widget build(BuildContext context) {
    final status = StatusColors.of(context);
    return Panel(
      child: AppRow(
        leading: IconTile(
          Icons.cloud_upload_outlined,
          background: status.warning,
          foreground: status.onWarning,
        ),
        title: lastBackup == null
            ? 'Faites une première sauvegarde'
            : 'Sauvegarde à refaire',
        subtitle: lastBackup == null
            ? 'Pour ne rien perdre si le téléphone est perdu ou en panne.'
            : 'Dernière le ${formatCompactDate(lastBackup!.toLocal())}.',
        onTap: () => context.push(Routes.backup),
      ),
    );
  }
}

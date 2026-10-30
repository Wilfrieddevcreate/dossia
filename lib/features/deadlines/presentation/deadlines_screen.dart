import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/dates.dart';
import '../../../core/utils/today_provider.dart';
import '../../../core/widgets/common.dart';
import '../data/deadlines_provider.dart';
import '../domain/deadline_models.dart';
import 'deadline_tile.dart';

/// Échéances regroupées par période ; les dépassées en premier (§ 4.8).
class DeadlinesScreen extends ConsumerWidget {
  const DeadlinesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final split = ref.watch(splitDeadlinesProvider);
    final today = ref.watch(todayProvider);
    return Scaffold(
      body: AsyncView(
        value: split,
        builder: (split) {
          List<DeadlineEntry> within(int from, int to) => split.upcoming.where((
            e,
          ) {
            final d = daysBetween(today, e.date);
            return d >= from && d <= to;
          }).toList();
          final groups = <(String, List<DeadlineEntry>)>[
            ('En retard', split.overdue),
            ('Cette semaine', within(0, 7)),
            ('Ce mois-ci', within(8, 31)),
            ('Plus tard', within(32, 1 << 30)),
          ].where((g) => g.$2.isNotEmpty).toList();

          return CustomScrollView(
            slivers: [
              const LargeTitleAppBar(title: 'Échéances'),
              if (groups.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.event_available_rounded,
                    title: 'Rien à l’horizon',
                    message:
                        'Les dates limites de vos dossiers et les dates '
                        "d'expiration de vos documents apparaîtront ici.",
                  ),
                )
              else
                for (final (title, entries) in groups) ...[
                  SliverToBoxAdapter(
                    child: SectionTitle(
                      '$title · ${entries.length}',
                      padding: const EdgeInsets.fromLTRB(20, 8, 12, 10),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    sliver: SliverToBoxAdapter(
                      child: ListGroup(
                        children: [
                          for (final e in entries)
                            DeadlineTile(entry: e, today: today),
                        ],
                      ),
                    ),
                  ),
                ],
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }
}

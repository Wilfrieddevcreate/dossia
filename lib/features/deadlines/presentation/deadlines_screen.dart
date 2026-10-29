import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/today_provider.dart';
import '../../../core/widgets/common.dart';
import '../data/deadlines_provider.dart';
import '../domain/deadline_models.dart';
import 'deadline_tile.dart';

/// Échéances à venir et dépassées (§ 4.8).
class DeadlinesScreen extends ConsumerWidget {
  const DeadlinesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final split = ref.watch(splitDeadlinesProvider);
    final today = ref.watch(todayProvider);
    return AsyncView(
      value: split,
      builder: (split) => DefaultTabController(
        length: 2,
        initialIndex: split.upcoming.isEmpty && split.overdue.isNotEmpty
            ? 1
            : 0,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Échéances'),
            bottom: TabBar(
              tabs: [
                Tab(text: 'À venir (${split.upcoming.length})'),
                Tab(text: 'Dépassées (${split.overdue.length})'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _List(
                entries: split.upcoming,
                today: today,
                empty: const EmptyState(
                  icon: Icons.event_available,
                  title: 'Aucune échéance à venir',
                  message:
                      'Ajoutez une date limite à vos dossiers ou une date '
                      "d'expiration à vos documents pour les suivre ici.",
                ),
              ),
              _List(
                entries: split.overdue,
                today: today,
                empty: const EmptyState(
                  icon: Icons.task_alt,
                  title: 'Aucune échéance dépassée',
                  message: 'Tout est à jour.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({
    required this.entries,
    required this.today,
    required this.empty,
  });

  final List<DeadlineEntry> entries;
  final DateTime today;
  final Widget empty;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return empty;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(indent: 84),
      itemBuilder: (context, i) =>
          DeadlineTile(entry: entries[i], today: today),
    );
  }
}

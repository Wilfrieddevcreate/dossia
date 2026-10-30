import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_badges.dart';
import '../../dossiers/data/dossiers_repository.dart';
import '../data/requirements_repository.dart';
import '../domain/requirement_models.dart';

/// Modification de l'ordre des pièces d'un dossier (§ 4.4).
class ReorderRequirementsScreen extends ConsumerStatefulWidget {
  const ReorderRequirementsScreen({super.key, required this.dossierId});

  final String dossierId;

  @override
  ConsumerState<ReorderRequirementsScreen> createState() =>
      _ReorderRequirementsScreenState();
}

class _ReorderRequirementsScreenState
    extends ConsumerState<ReorderRequirementsScreen> {
  List<EvaluatedRequirement>? _items;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await runGuarded(
      context,
      () => ref
          .read(requirementsRepositoryProvider)
          .reorder(widget.dossierId, [for (final i in _items!) i.view.id]),
      success: 'Ordre enregistré',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) context.pop();
  }

  void _move(int from, int to) {
    HapticFeedback.selectionClick();
    setState(() => _items!.insert(to, _items!.removeAt(from)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overview = ref.watch(dossierOverviewProvider(widget.dossierId));
    _items ??= overview.value?.items.toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Réorganiser les pièces'),
        actions: [
          TextButton(
            onPressed: (_items == null || _saving) ? null : _save,
            child: const Text('Enregistrer'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _items == null
          ? const Center(child: CircularProgressIndicator())
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              buildDefaultDragHandles: false,
              header: Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
                child: Text(
                  'Faites glisser une pièce par sa poignée, ou utilisez les '
                  'flèches.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              proxyDecorator: (child, index, animation) => AnimatedBuilder(
                animation: animation,
                builder: (context, child) => Transform.scale(
                  scale: 1 + 0.02 * Curves.easeOut.transform(animation.value),
                  child: child,
                ),
                child: Material(
                  color: Colors.transparent,
                  elevation: 6,
                  shadowColor: Colors.black26,
                  borderRadius: BorderRadius.circular(18),
                  child: child,
                ),
              ),
              itemCount: _items!.length,
              onReorderItem: _move,
              itemBuilder: (context, i) {
                final item = _items![i];
                return Padding(
                  key: ValueKey(item.view.id),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ReorderableDelayedDragStartListener(
                    index: i,
                    child: Panel(
                      radius: 18,
                      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                      child: Row(
                        children: [
                          StatusIcon(item.status, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.view.displayName,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  item.status.label,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Monter ${item.view.displayName}',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.keyboard_arrow_up_rounded),
                            onPressed: i == 0 ? null : () => _move(i, i - 1),
                          ),
                          IconButton(
                            tooltip: 'Descendre ${item.view.displayName}',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded),
                            onPressed: i == _items!.length - 1
                                ? null
                                : () => _move(i, i + 1),
                          ),
                          ReorderableDragStartListener(
                            index: i,
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Icon(
                                Icons.drag_indicator_rounded,
                                color: theme.colorScheme.onSurfaceVariant,
                                semanticLabel: 'Déplacer',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

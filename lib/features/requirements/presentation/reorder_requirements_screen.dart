import 'package:flutter/material.dart';
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
      success: 'Ordre des pièces enregistré.',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) context.pop();
  }

  @override
  Widget build(BuildContext context) {
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
        ],
      ),
      body: _items == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    'Maintenez une pièce puis faites-la glisser, ou utilisez '
                    'les flèches.',
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: _items!.length,
                    onReorderItem: (from, to) => setState(() {
                      _items!.insert(to, _items!.removeAt(from));
                    }),
                    itemBuilder: (context, i) {
                      final item = _items![i];
                      return ListTile(
                        key: ValueKey(item.view.id),
                        title: Text(item.view.displayName),
                        subtitle: Align(
                          alignment: Alignment.centerLeft,
                          child: ItemStatusChip(item.status, dense: true),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Monter ${item.view.displayName}',
                              icon: const Icon(Icons.arrow_upward),
                              onPressed: i == 0
                                  ? null
                                  : () => setState(() {
                                      _items!.insert(i - 1, _items!.removeAt(i));
                                    }),
                            ),
                            IconButton(
                              tooltip: 'Descendre ${item.view.displayName}',
                              icon: const Icon(Icons.arrow_downward),
                              onPressed: i == _items!.length - 1
                                  ? null
                                  : () => setState(() {
                                      _items!.insert(i + 1, _items!.removeAt(i));
                                    }),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

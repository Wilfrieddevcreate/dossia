import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/database/app_database.dart';
import '../../../core/models/document_category.dart';
import '../../../core/widgets/common.dart';
import '../../documents/data/documents_repository.dart';
import '../../documents/presentation/type_picker.dart';
import '../../settings/data/settings_repository.dart';

/// Inventaire des documents possédés (§ 3.1). Facultatif à l'onboarding,
/// accessible ensuite depuis la bibliothèque pour le compléter.
class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key, required this.fromOnboarding});

  final bool fromOnboarding;

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  final _selected = <String>{};
  bool _saving = false;

  Future<void> _finish({required bool save}) async {
    setState(() => _saving = true);
    final ok = await runGuarded(context, () async {
      if (save && _selected.isNotEmpty) {
        await ref
            .read(documentsRepositoryProvider)
            .createFromInventory(_selected);
      }
      if (widget.fromOnboarding) {
        await ref
            .read(settingsRepositoryProvider)
            .setBool(SettingKeys.onboardingCompleted, true);
      }
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    if (save && _selected.isNotEmpty) {
      final n = _selected.length;
      showMessage(
        context,
        n == 1
            ? '1 document ajouté à votre bibliothèque.'
            : '$n documents ajoutés à votre bibliothèque.',
      );
    }
    if (widget.fromOnboarding) {
      context.go(Routes.home);
    } else {
      context.pop();
    }
  }

  Future<void> _addCustom() async {
    final created = await showCreateTypeDialog(context, ref);
    if (created != null && mounted) {
      setState(() => _selected.add(created.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final types = ref.watch(documentTypesProvider);
    final documents = ref.watch(documentsProvider);
    final ownedTypeIds = {
      for (final d in documents.value ?? const [])
        if (!d.isArchived) d.type.id,
    };
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.fromOnboarding ? 'Vos documents' : 'Compléter mon inventaire',
        ),
        actions: [
          if (widget.fromOnboarding)
            TextButton(
              onPressed: _saving ? null : () => _finish(save: false),
              child: const Text('Passer'),
            ),
        ],
      ),
      body: AsyncView(
        value: types,
        builder: (types) {
          final byCategory = groupBy(types, (DocumentTypeRow t) => t.category);
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  'Cochez les documents que vous possédez réellement. '
                  "Inutile d'avoir leur version numérique : vous pourrez "
                  'ajouter un fichier, des dates ou des notes plus tard.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final category in DocumentCategory.values)
                if (byCategory[category]?.isNotEmpty ?? false) ...[
                  SectionHeader(
                    category.label,
                    trailing: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                        documentCategoryIcon(category),
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  for (final type in byCategory[category]!)
                    _TypeTile(
                      type: type,
                      owned: ownedTypeIds.contains(type.id),
                      selected: _selected.contains(type.id),
                      onChanged: (value) => setState(() {
                        value
                            ? _selected.add(type.id)
                            : _selected.remove(type.id);
                      }),
                    ),
                ],
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: OutlinedButton.icon(
                  onPressed: _addCustom,
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter un document personnalisé'),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton(
          onPressed: _saving
              ? null
              : (_selected.isEmpty && !widget.fromOnboarding)
              ? null
              : () => _finish(save: true),
          child: Text(
            _selected.isEmpty
                ? (widget.fromOnboarding
                      ? 'Continuer sans document'
                      : 'Sélectionnez des documents')
                : 'Ajouter ${_selected.length} document${_selected.length > 1 ? 's' : ''}',
          ),
        ),
      ),
    );
  }
}

class _TypeTile extends StatelessWidget {
  const _TypeTile({
    required this.type,
    required this.owned,
    required this.selected,
    required this.onChanged,
  });

  final DocumentTypeRow type;
  final bool owned;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: selected,
      onChanged: (v) => onChanged(v ?? false),
      title: Text(type.name),
      subtitle: owned
          ? const Text(
              'Déjà dans votre bibliothèque — cochez pour en ajouter un autre',
            )
          : null,
      controlAffinity: ListTileControlAffinity.leading,
    );
  }
}

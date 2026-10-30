import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/database/app_database.dart';
import '../../../core/models/document_category.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_badges.dart';
import '../../../core/widgets/form_fields.dart';
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
            ? '1 document ajouté à votre bibliothèque'
            : '$n documents ajoutés à votre bibliothèque',
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

  void _toggle(String typeId) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selected.remove(typeId)) _selected.add(typeId);
    });
  }

  String get _buttonLabel {
    final n = _selected.length;
    if (n == 0) {
      return widget.fromOnboarding
          ? 'Continuer sans document'
          : 'Sélectionnez des documents';
    }
    return n == 1 ? 'Ajouter 1 document' : 'Ajouter $n documents';
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
      bottomNavigationBar: FormSaveBar(
        label: _buttonLabel,
        busy: _saving,
        onPressed: (_selected.isEmpty && !widget.fromOnboarding)
            ? null
            : () => _finish(save: true),
      ),
      body: AsyncView(
        value: types,
        builder: (types) {
          final byCategory = groupBy(types, (DocumentTypeRow t) => t.category);
          return CustomScrollView(
            slivers: [
              LargeTitleAppBar(
                title: widget.fromOnboarding
                    ? 'Vos documents'
                    : 'Compléter mon inventaire',
                actions: [
                  if (widget.fromOnboarding)
                    TextButton(
                      onPressed: _saving ? null : () => _finish(save: false),
                      child: const Text('Passer'),
                    ),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Text(
                    'Cochez ce que vous avez déjà, même sans version '
                    'numérique.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              for (final category in DocumentCategory.values)
                if (byCategory[category]?.isNotEmpty ?? false) ...[
                  SliverToBoxAdapter(child: SectionTitle(category.label)),
                  SliverBox(
                    child: ListGroup(
                      dividerIndent: 58,
                      children: [
                        for (final type in byCategory[category]!)
                          _TypeRow(
                            type: type,
                            owned: ownedTypeIds.contains(type.id),
                            selected: _selected.contains(type.id),
                            onTap: () => _toggle(type.id),
                          ),
                      ],
                    ),
                  ),
                ],
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              SliverBox(
                child: Panel(
                  child: AppRow(
                    leading: IconTile(
                      Icons.add_rounded,
                      background: theme.colorScheme.primaryContainer,
                      foreground: theme.colorScheme.onPrimaryContainer,
                    ),
                    title: 'Ajouter un document personnalisé',
                    subtitle: 'Un document absent de la liste',
                    onTap: _addCustom,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }
}

class _TypeRow extends StatelessWidget {
  const _TypeRow({
    required this.type,
    required this.owned,
    required this.selected,
    required this.onTap,
  });

  final DocumentTypeRow type;
  final bool owned;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: selected,
      button: true,
      label: owned ? '${type.name}, déjà enregistré' : type.name,
      excludeSemantics: true,
      child: AppRow(
        dense: true,
        chevron: false,
        onTap: onTap,
        leading: RoundCheck(checked: selected),
        title: type.name,
        subtitle: owned ? 'Déjà enregistré' : null,
      ),
    );
  }
}

/// Case ronde animée, cochée en vert.

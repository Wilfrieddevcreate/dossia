import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/document_category.dart';
import '../../../core/widgets/common.dart';
import '../data/documents_repository.dart';
import '../domain/document_models.dart';

/// Ouvre la liste des types de documents avec recherche. Permet aussi de
/// créer un nouveau type. Renvoie le type choisi, ou `null`.
Future<DocumentTypeRow?> showDocumentTypePicker(
  BuildContext context,
  WidgetRef ref, {
  String? selectedId,
}) {
  return showModalBottomSheet<DocumentTypeRow>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.92,
      child: _TypePickerSheet(selectedId: selectedId),
    ),
  );
}

class _TypePickerSheet extends ConsumerStatefulWidget {
  const _TypePickerSheet({this.selectedId});

  final String? selectedId;

  @override
  ConsumerState<_TypePickerSheet> createState() => _TypePickerSheetState();
}

class _TypePickerSheetState extends ConsumerState<_TypePickerSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final created = await showCreateTypeDialog(
      context,
      ref,
      initialName: _search.text.trim(),
    );
    if (created != null && mounted) Navigator.of(context).pop(created);
  }

  @override
  Widget build(BuildContext context) {
    final types = ref.watch(documentTypesProvider);
    final theme = Theme.of(context);
    final query = _search.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text('Type de document', style: theme.textTheme.titleLarge),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SearchField(
            controller: _search,
            hint: 'Rechercher un type',
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: AsyncView(
            value: types,
            builder: (types) {
              final q = normalizeForSearch(query);
              final filtered = types
                  .where((t) => normalizeForSearch(t.name).contains(q))
                  .toList();
              final byCategory = groupBy(filtered, (t) => t.category);
              return ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  AppRow(
                    dense: true,
                    leading: IconTile(
                      Icons.add_rounded,
                      size: 36,
                      background: theme.colorScheme.primaryContainer,
                      foreground: theme.colorScheme.onPrimaryContainer,
                    ),
                    title: query.isEmpty
                        ? 'Créer un nouveau type'
                        : 'Créer « $query »',
                    titleStyle: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                    chevron: false,
                    onTap: _create,
                  ),
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                      child: Text(
                        'Aucun type ne correspond. Créez-le pour l’utiliser '
                        'tout de suite.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  for (final category in DocumentCategory.values)
                    if (byCategory[category] != null) ...[
                      SectionTitle(
                        category.label,
                        padding: const EdgeInsets.fromLTRB(20, 18, 12, 2),
                      ),
                      for (final t in byCategory[category]!)
                        AppRow(
                          dense: true,
                          leading: CategoryAvatar(t.category, size: 36),
                          title: t.name,
                          subtitle: t.isCustom ? 'Type personnalisé' : null,
                          chevron: false,
                          trailing: t.id == widget.selectedId
                              ? Icon(
                                  Icons.check_rounded,
                                  color: theme.colorScheme.primary,
                                  semanticLabel: 'Sélectionné',
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(t),
                        ),
                    ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Crée un type de document personnalisé (§ 3.3 et 4.2).
Future<DocumentTypeRow?> showCreateTypeDialog(
  BuildContext context,
  WidgetRef ref, {
  String? initialName,
}) {
  return showDialog<DocumentTypeRow>(
    context: context,
    builder: (context) => _CreateTypeDialog(initialName: initialName),
  );
}

class _CreateTypeDialog extends ConsumerStatefulWidget {
  const _CreateTypeDialog({this.initialName});

  final String? initialName;

  @override
  ConsumerState<_CreateTypeDialog> createState() => _CreateTypeDialogState();
}

class _CreateTypeDialogState extends ConsumerState<_CreateTypeDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initialName);
  DocumentCategory _category = DocumentCategory.other;
  bool _expiry = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    DocumentTypeRow? created;
    await runGuarded(context, () async {
      created = await ref
          .read(documentsRepositoryProvider)
          .createType(
            name: _name.text,
            category: _category,
            expiryApplicable: _expiry,
          );
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (created != null) Navigator.of(context).pop(created);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouveau type'),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 120,
                decoration: const InputDecoration(
                  counterText: '',
                  labelText: 'Nom',
                  hintText: 'ex. Attestation de stage',
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Indiquez un nom.'
                    : null,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<DocumentCategory>(
                isExpanded: true,
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Catégorie'),
                items: [
                  for (final c in DocumentCategory.values)
                    DropdownMenuItem(value: c, child: Text(c.label)),
                ],
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('A une date d’expiration'),
                value: _expiry,
                onChanged: (v) => setState(() => _expiry = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
          onPressed: _saving ? null : _save,
          child: const Text('Créer'),
        ),
      ],
    );
  }
}

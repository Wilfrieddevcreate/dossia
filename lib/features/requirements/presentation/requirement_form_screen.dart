import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/database/app_database.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/form_fields.dart';
import '../../documents/presentation/type_picker.dart';
import '../data/requirements_repository.dart';

/// Ajout ou modification d'une pièce requise (§ 3.3).
class RequirementFormScreen extends ConsumerStatefulWidget {
  const RequirementFormScreen({super.key, required this.dossierId, this.itemId});

  final String dossierId;
  final String? itemId;

  bool get isEditing => itemId != null;

  @override
  ConsumerState<RequirementFormScreen> createState() =>
      _RequirementFormScreenState();
}

class _RequirementFormScreenState extends ConsumerState<RequirementFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _customName = TextEditingController();
  final _instructions = TextEditingController();
  final _notes = TextEditingController();
  DocumentTypeRow? _type;
  bool _mandatory = true;
  int _quantity = 1;
  DateTime? _dueDate;
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.isEditing) {
      final view = await ref
          .read(requirementsRepositoryProvider)
          .loadRequirement(widget.itemId!);
      if (view != null) {
        _type = view.type;
        _customName.text = view.item.customName ?? '';
        _instructions.text = view.item.instructions ?? '';
        _notes.text = view.item.notes ?? '';
        _mandatory = view.item.isMandatory;
        _quantity = view.item.quantity;
        _dueDate = view.item.dueDate;
      }
    }
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _customName.dispose();
    _instructions.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickType() async {
    final picked = await showDocumentTypePicker(
      context,
      ref,
      selectedId: _type?.id,
    );
    if (picked != null) {
      setState(() => _type = picked);
      _formKey.currentState?.validate();
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final input = RequirementInput(
      typeId: _type?.id,
      customName: _customName.text.trim().isEmpty ? null : _customName.text,
      isMandatory: _mandatory,
      quantity: _quantity,
      instructions: _instructions.text,
      notes: _notes.text,
      dueDate: _dueDate,
    );
    final repo = ref.read(requirementsRepositoryProvider);
    String? createdId;
    final ok = await runGuarded(context, () async {
      if (widget.isEditing) {
        await repo.updateRequirement(widget.itemId!, input);
      } else {
        createdId = await repo.createRequirement(widget.dossierId, input);
      }
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    if (createdId != null) {
      // Le détail de la pièce propose les documents correspondants.
      context.pushReplacement(Routes.item(widget.dossierId, createdId!));
    } else {
      showMessage(context, 'Pièce mise à jour');
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Modifier la pièce' : 'Nouvelle pièce'),
      ),
      bottomNavigationBar: FormSaveBar(
        label: widget.isEditing ? 'Enregistrer' : 'Ajouter la pièce',
        busy: _saving,
        onPressed: _loaded ? _save : null,
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  FormSection(
                    title: 'Pièce',
                    children: [
                      FormField<DocumentTypeRow>(
                        validator: (_) =>
                            (_type == null && _customName.text.trim().isEmpty)
                            ? 'Choisissez un type ou saisissez un nom.'
                            : null,
                        builder: (state) => Semantics(
                          button: true,
                          label: 'Type de document',
                          value: _type?.name ?? 'Non choisi',
                          excludeSemantics: true,
                          child: InkWell(
                            onTap: _pickType,
                            borderRadius: BorderRadius.circular(14),
                            child: InputDecorator(
                              isEmpty: _type == null,
                              decoration: InputDecoration(
                                labelText: 'Type de document',
                                helperText: _type == null
                                    ? 'Dossia retrouvera vos documents de ce type.'
                                    : null,
                                errorText: state.errorText,
                                prefixIcon: _type == null
                                    ? const Icon(Icons.category_outlined)
                                    : Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        child: CategoryAvatar(
                                          _type!.category,
                                          size: 30,
                                        ),
                                      ),
                                suffixIcon: _type == null
                                    ? const Icon(Icons.expand_more_rounded)
                                    : IconButton(
                                        tooltip: 'Retirer le type',
                                        icon: const Icon(Icons.close_rounded),
                                        onPressed: () =>
                                            setState(() => _type = null),
                                      ),
                              ),
                              child: Text(_type?.name ?? ''),
                            ),
                          ),
                        ),
                      ),
                      TextFormField(
                        controller: _customName,
                        textCapitalization: TextCapitalization.sentences,
                        maxLength: 160,
                        decoration: InputDecoration(
                          counterText: '',
                          labelText: _type == null
                              ? 'Nom de la pièce'
                              : 'Nom personnalisé (facultatif)',
                          hintText: _type == null
                              ? 'ex. Formulaire de demande signé'
                              : 'ex. ${_type!.name} (copie certifiée)',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                  FormSection(
                    title: 'Exigence',
                    children: [
                      Material(
                        color: palette.muted,
                        borderRadius: BorderRadius.circular(14),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            SwitchListTile(
                              contentPadding: const EdgeInsets.fromLTRB(
                                16,
                                4,
                                12,
                                4,
                              ),
                              title: const Text('Pièce obligatoire'),
                              subtitle: Text(
                                _mandatory
                                    ? 'Compte dans la progression'
                                    : 'Ne réduit pas la progression',
                              ),
                              value: _mandatory,
                              onChanged: (v) => setState(() => _mandatory = v),
                            ),
                            Divider(
                              indent: 16,
                              endIndent: 16,
                              color: palette.hairlineStrong,
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                              child: QuantityStepper(
                                label: 'Quantité attendue',
                                value: _quantity,
                                onChanged: (v) => setState(() => _quantity = v),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  FormSection(
                    title: 'Précisions',
                    children: [
                      TextFormField(
                        controller: _instructions,
                        textCapitalization: TextCapitalization.sentences,
                        minLines: 2,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'Instructions',
                          hintText: 'ex. Copie légalisée de moins de 3 mois',
                          alignLabelWithHint: true,
                        ),
                      ),
                      TextFormField(
                        controller: _notes,
                        textCapitalization: TextCapitalization.sentences,
                        minLines: 2,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'Note',
                          alignLabelWithHint: true,
                        ),
                      ),
                      DateField(
                        label: 'À fournir avant le',
                        initialValue: _dueDate,
                        onChanged: (d) => setState(() => _dueDate = d),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

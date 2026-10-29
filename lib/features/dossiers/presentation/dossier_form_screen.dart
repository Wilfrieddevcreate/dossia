import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/models/dossier_category.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/form_fields.dart';
import '../data/dossiers_repository.dart';

/// Création ou modification d'un dossier (§ 3.2).
class DossierFormScreen extends ConsumerStatefulWidget {
  const DossierFormScreen({super.key, this.dossierId});

  final String? dossierId;

  bool get isEditing => dossierId != null;

  @override
  ConsumerState<DossierFormScreen> createState() => _DossierFormScreenState();
}

class _DossierFormScreenState extends ConsumerState<DossierFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _notes = TextEditingController();
  DossierCategory? _category;
  DateTime? _deadline;
  bool _loaded = false;
  bool _saving = false;

  static const _examples = [
    'Visa France',
    "Inscription à l'université",
    'Demande de bourse',
    'Candidature à un emploi',
    'Dossier de voyage',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.isEditing) {
      final d = await ref
          .read(dossiersRepositoryProvider)
          .getDossier(widget.dossierId!);
      if (d != null) {
        _title.text = d.title;
        _description.text = d.description ?? '';
        _notes.text = d.notes ?? '';
        _category = d.category;
        _deadline = d.deadline;
      }
    }
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final input = DossierInput(
      title: _title.text,
      category: _category,
      description: _description.text,
      deadline: _deadline,
      notes: _notes.text,
    );
    final repo = ref.read(dossiersRepositoryProvider);
    String? createdId;
    final ok = await runGuarded(context, () async {
      if (widget.isEditing) {
        await repo.updateDossier(widget.dossierId!, input);
      } else {
        createdId = await repo.createDossier(input);
      }
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    if (createdId != null) {
      showMessage(context, 'Dossier créé. Ajoutez maintenant les pièces.');
      context.pushReplacement(Routes.dossier(createdId!));
    } else {
      showMessage(context, 'Dossier mis à jour.');
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Modifier le dossier' : 'Nouveau dossier'),
      ),
      bottomNavigationBar: FormSaveBar(
        label: widget.isEditing ? 'Enregistrer' : 'Créer le dossier',
        busy: _saving,
        onPressed: _loaded ? _save : null,
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _title,
                    autofocus: !widget.isEditing,
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: 160,
                    decoration: const InputDecoration(
                      labelText: 'Nom du dossier *',
                      hintText: 'ex. Visa France',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Donnez un nom à votre dossier.'
                        : null,
                  ),
                  if (!widget.isEditing) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final e in _examples)
                          ActionChip(
                            label: Text(e),
                            onPressed: () => setState(() => _title.text = e),
                          ),
                      ],
                    ),
                  ],
                  formGap,
                  DropdownButtonFormField<DossierCategory?>(
                    isExpanded: true,
                    initialValue: _category,
                    decoration: const InputDecoration(
                      labelText: 'Catégorie (facultative)',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Aucune'),
                      ),
                      for (final c in DossierCategory.values)
                        DropdownMenuItem(value: c, child: Text(c.label)),
                    ],
                    onChanged: (v) => setState(() => _category = v),
                  ),
                  formGap,
                  DateField(
                    label: 'Date limite (facultative)',
                    initialValue: _deadline,
                    helperText:
                        'Date de dépôt ou de rendez-vous. Vous recevrez un '
                        'rappel si les notifications sont activées.',
                    onChanged: (d) => setState(() => _deadline = d),
                  ),
                  formGap,
                  TextFormField(
                    controller: _description,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Description (facultative)',
                      alignLabelWithHint: true,
                    ),
                  ),
                  formGap,
                  TextFormField(
                    controller: _notes,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: 'Notes personnelles (facultatives)',
                      hintText: 'Adresse du dépôt, contact, références…',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_theme.dart';
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
      showMessage(context, 'Dossier créé · ajoutez maintenant les pièces');
      context.pushReplacement(Routes.dossier(createdId!));
    } else {
      showMessage(context, 'Dossier mis à jour');
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = widget.isEditing ? 'Modifier le dossier' : 'Nouveau dossier';
    return Form(
      key: _formKey,
      child: DetailScaffold(
        title: heading,
        bottomBar: FormSaveBar(
          label: widget.isEditing ? 'Enregistrer' : 'Créer le dossier',
          busy: _saving,
          onPressed: _loaded ? _save : null,
        ),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Semantics(
                header: true,
                child: Text(heading, style: theme.textTheme.headlineMedium),
              ),
            ),
          ),
          if (!_loaded)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              sliver: SliverList.list(
                children: [
                  FormSection(
                    title: 'Dossier',
                    children: [
                      TextFormField(
                        controller: _title,
                        autofocus: !widget.isEditing,
                        textCapitalization: TextCapitalization.sentences,
                        maxLength: 160,
                        decoration: const InputDecoration(
                          labelText: 'Nom du dossier *',
                          hintText: 'ex. Visa France',
                          counterText: '',
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Donnez un nom à votre dossier.'
                            : null,
                      ),
                      if (!widget.isEditing)
                        // Suggestions sur une ligne, défilant sous le champ.
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.none,
                          child: Row(
                            children: [
                              for (final e in _examples)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ActionChip(
                                    label: Text(e),
                                    onPressed: () {
                                      HapticFeedback.selectionClick();
                                      setState(() => _title.text = e);
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  FormSection(
                    title: 'Catégorie',
                    children: [
                      _CategoryPicker(
                        value: _category,
                        onChanged: (c) => setState(() => _category = c),
                      ),
                    ],
                  ),
                  FormSection(
                    title: 'Échéance',
                    children: [
                      DateField(
                        label: 'Date limite',
                        initialValue: _deadline,
                        helperText: 'Dépôt ou rendez-vous. Facultatif.',
                        onChanged: (d) => setState(() => _deadline = d),
                      ),
                    ],
                  ),
                  FormSection(
                    title: 'Notes',
                    children: [
                      TextFormField(
                        controller: _description,
                        textCapitalization: TextCapitalization.sentences,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          alignLabelWithHint: true,
                        ),
                      ),
                      TextFormField(
                        controller: _notes,
                        textCapitalization: TextCapitalization.sentences,
                        minLines: 3,
                        maxLines: 8,
                        decoration: const InputDecoration(
                          labelText: 'Notes personnelles',
                          hintText: 'Adresse du dépôt, contact, références…',
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Catégories en puces ; toucher la puce choisie la désélectionne.
class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({required this.value, required this.onChanged});

  final DossierCategory? value;
  final ValueChanged<DossierCategory?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    // Pas d'espacement vertical supplémentaire : chaque puce garde déjà une
    // zone tactile de 48 dp qui sépare les lignes.
    return Wrap(
      spacing: 8,
      children: [
        for (final c in DossierCategory.values)
          ChoiceChip(
            selected: c == value,
            avatar: Icon(
              dossierCategoryIcon(c),
              size: 18,
              color: c == value
                  ? theme.colorScheme.surface
                  : theme.colorScheme.onSurfaceVariant,
            ),
            label: Text(c.label),
            labelStyle: theme.textTheme.labelMedium?.copyWith(
              fontSize: 13.5,
              color: c == value
                  ? theme.colorScheme.surface
                  : theme.colorScheme.onSurface,
            ),
            backgroundColor: palette.muted,
            onSelected: (_) {
              HapticFeedback.selectionClick();
              onChanged(c == value ? null : c);
            },
          ),
      ],
    );
  }
}

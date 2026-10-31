import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../data/dossiers_repository.dart';
import '../domain/dossier_models.dart';
import '../domain/dossier_progress.dart';
import 'dossiers_screen.dart';

/// Crée un nouveau dossier à partir de [source], après avoir demandé son nom
/// et ce qu'il faut reprendre. Avec [replaceCurrent], l'écran courant (le
/// formulaire de création) est remplacé par le nouveau dossier.
Future<void> duplicateDossier(
  BuildContext context,
  WidgetRef ref,
  DossierOverview source, {
  bool replaceCurrent = false,
}) async {
  final choice = await showModalBottomSheet<_DuplicateChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _DuplicateSheet(source: source),
    ),
  );
  if (choice == null || !context.mounted) return;
  String? newId;
  final ok = await runGuarded(context, () async {
    newId = await ref
        .read(dossiersRepositoryProvider)
        .duplicateDossier(
          source.id,
          title: choice.title,
          keepDocuments: choice.keepDocuments,
          copyTasks: choice.copyTasks,
        );
  });
  if (!ok || newId == null || !context.mounted) return;
  HapticFeedback.lightImpact();
  showMessage(context, 'Dossier créé à partir de « ${source.dossier.title} »');
  if (replaceCurrent) {
    context.pushReplacement(Routes.dossier(newId!));
  } else {
    context.push(Routes.dossier(newId!));
  }
}

/// Choisit un dossier existant (en cours, terminé ou archivé) comme point de
/// départ d'un nouveau dossier.
Future<void> startFromExistingDossier(
  BuildContext context,
  WidgetRef ref,
) async {
  final all = ref.read(dossierOverviewsProvider).value ?? const [];
  final sorted = [...all]
    ..sort((a, b) => compareDossiers(a, b, DossierSort.recent));
  final source = await showModalBottomSheet<DossierOverview>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Partir d’un dossier',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Ses pièces seront reprises dans le nouveau dossier.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          for (final d in sorted)
            AppRow(
              leading: DossierRing(progress: d.progress, size: 40, stroke: 4),
              title: d.dossier.title,
              subtitle: [
                '${d.items.length} pièce${d.items.length > 1 ? 's' : ''}',
                if (d.status == DossierStatus.archived) 'archivé',
                if (d.status == DossierStatus.completed) 'terminé',
              ].join(' · '),
              onTap: () => Navigator.of(context).pop(d),
            ),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return;
  await duplicateDossier(context, ref, source, replaceCurrent: true);
}

class _DuplicateChoice {
  const _DuplicateChoice(this.title, this.keepDocuments, this.copyTasks);

  final String title;
  final bool keepDocuments;
  final bool copyTasks;
}

class _DuplicateSheet extends StatefulWidget {
  const _DuplicateSheet({required this.source});

  final DossierOverview source;

  @override
  State<_DuplicateSheet> createState() => _DuplicateSheetState();
}

class _DuplicateSheetState extends State<_DuplicateSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(
    text: '${widget.source.dossier.title} (copie)',
  );
  bool _keepDocuments = false;
  bool _copyTasks = true;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(
      context,
    ).pop(_DuplicateChoice(_title.text, _keepDocuments, _copyTasks));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final source = widget.source;
    final linked = source.items.where((i) => i.view.links.isNotEmpty).length;
    return Form(
      key: _formKey,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          Text('Nouveau dossier', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '${switch (source.items.length) {
              0 => 'Le dossier « ${source.dossier.title} » n’a pas encore de pièce.',
              1 => 'La pièce de « ${source.dossier.title} » est reprise.',
              final n => 'Les $n pièces de « ${source.dossier.title} » sont reprises.',
            }} La date limite et les échéances ne le sont pas.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Nom du dossier'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Indiquez un nom.' : null,
          ),
          const SizedBox(height: 14),
          Panel(
            color: palette.muted,
            radius: 16,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Reprendre les documents associés'),
                  subtitle: Text(
                    linked == 0
                        ? 'Aucun document associé pour l’instant'
                        : 'Pour $linked pièce${linked > 1 ? 's' : ''}',
                  ),
                  value: _keepDocuments,
                  onChanged: linked == 0
                      ? null
                      : (v) => setState(() => _keepDocuments = v),
                ),
                if (source.tasks.isNotEmpty)
                  SwitchListTile(
                    title: const Text('Reprendre les tâches'),
                    subtitle: const Text('Décochées et sans date'),
                    value: _copyTasks,
                    onChanged: (v) => setState(() => _copyTasks = v),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _submit,
            child: const Text('Créer le dossier'),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/form_fields.dart';
import '../data/dossiers_repository.dart';

/// Ajout ou modification d'une tâche de préparation.
Future<void> showTaskSheet(
  BuildContext context, {
  required String dossierId,
  TaskRow? task,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _TaskForm(dossierId: dossierId, task: task),
    ),
  );
}

class _TaskForm extends ConsumerStatefulWidget {
  const _TaskForm({required this.dossierId, this.task});

  final String dossierId;
  final TaskRow? task;

  @override
  ConsumerState<_TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends ConsumerState<_TaskForm> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.task?.title);
  late final _notes = TextEditingController(text: widget.task?.notes);
  late DateTime? _due = widget.task?.dueDate;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(dossiersRepositoryProvider);
    final input = TaskInput(
      title: _title.text,
      dueDate: _due,
      notes: _notes.text,
    );
    final ok = await runGuarded(
      context,
      () => widget.task == null
          ? repo.createTask(widget.dossierId, input)
          : repo.updateTask(widget.task!.id, input),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Supprimer cette tâche ?',
      message: '« ${widget.task!.title} » sera supprimée définitivement.',
      confirmLabel: 'Supprimer',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final ok = await runGuarded(
      context,
      () => ref.read(dossiersRepositoryProvider).deleteTask(widget.task!.id),
    );
    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editing = widget.task != null;
    return Form(
      key: _formKey,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          Text(
            editing ? 'Modifier la tâche' : 'Nouvelle tâche',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 18),
          TextFormField(
            controller: _title,
            autofocus: !editing,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: 'Tâche *',
              hintText: 'ex. Prendre rendez-vous au consulat',
              counterText: '',
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Décrivez la tâche.' : null,
          ),
          formGap,
          DateField(
            label: 'À faire avant le',
            initialValue: _due,
            onChanged: (d) => setState(() => _due = d),
          ),
          formGap,
          TextFormField(
            controller: _notes,
            textCapitalization: TextCapitalization.sentences,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Notes',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              if (editing)
                TextButton.icon(
                  onPressed: _saving ? null : _delete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Supprimer'),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                ),
              const Spacer(),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(minimumSize: const Size(132, 52)),
                child: Text(editing ? 'Enregistrer' : 'Ajouter'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

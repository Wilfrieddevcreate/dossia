import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/files/file_storage_service.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/form_fields.dart';
import '../../requirements/data/requirements_repository.dart';
import '../data/documents_repository.dart';
import 'attachment_actions.dart';
import 'type_picker.dart';

/// Ajout ou modification d'un document personnel.
///
/// Avec [linkToItemId], le document créé est associé à cette pièce (ajout
/// depuis le détail d'un dossier, § 3.3). L'écran renvoie l'identifiant du
/// document enregistré.
class DocumentFormScreen extends ConsumerStatefulWidget {
  const DocumentFormScreen({
    super.key,
    this.documentId,
    this.initialTypeId,
    this.linkToItemId,
  });

  final String? documentId;
  final String? initialTypeId;
  final String? linkToItemId;

  bool get isEditing => documentId != null;

  @override
  ConsumerState<DocumentFormScreen> createState() => _DocumentFormScreenState();
}

class _DocumentFormScreenState extends ConsumerState<DocumentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _customName = TextEditingController();
  final _issuer = TextEditingController();
  final _notes = TextEditingController();
  DocumentTypeRow? _type;
  String? _typeError;
  DateTime? _issueDate;
  DateTime? _expiryDate;
  final _pendingFiles = <PickedAttachment>[];
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.isEditing) {
      final detail = await ref
          .read(documentsRepositoryProvider)
          .loadDocument(widget.documentId!);
      if (detail != null) {
        final doc = detail.view.doc;
        _type = detail.view.type;
        _customName.text = doc.customName ?? '';
        _issuer.text = doc.issuer ?? '';
        _notes.text = doc.notes ?? '';
        _issueDate = doc.issueDate;
        _expiryDate = doc.expiryDate;
      }
    } else if (widget.initialTypeId != null) {
      final types = await ref.read(documentTypesProvider.future);
      _type = types.firstWhereOrNull((t) => t.id == widget.initialTypeId);
    }
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _customName.dispose();
    _issuer.dispose();
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
      setState(() {
        _type = picked;
        _typeError = null;
      });
    }
  }

  Future<void> _addFile() async {
    final picked = await pickAttachment(context);
    if (picked == null) return;
    final size = await picked.file.length();
    if (!mounted) return;
    if (size > maxAttachmentBytes) {
      showMessage(
        context,
        'Ce fichier dépasse 25 Mo. Choisissez un fichier plus léger.',
        error: true,
      );
      return;
    }
    setState(() => _pendingFiles.add(picked));
  }

  Future<void> _save() async {
    final typeOk = _type != null;
    setState(() => _typeError = typeOk ? null : 'Choisissez un type.');
    if (!_formKey.currentState!.validate() || !typeOk) return;

    setState(() => _saving = true);
    final input = DocumentInput(
      typeId: _type!.id,
      customName: _customName.text,
      issueDate: _issueDate,
      expiryDate: _expiryDate,
      issuer: _issuer.text,
      notes: _notes.text,
    );
    final repo = ref.read(documentsRepositoryProvider);
    String? savedId;
    final failedFiles = <String>[];
    final ok = await runGuarded(context, () async {
      if (widget.isEditing) {
        await repo.updateDocument(widget.documentId!, input);
        savedId = widget.documentId;
      } else {
        savedId = await repo.createDocument(input);
        if (widget.linkToItemId != null) {
          await ref
              .read(requirementsRepositoryProvider)
              .linkDocument(itemId: widget.linkToItemId!, documentId: savedId!);
        }
      }
      for (final f in _pendingFiles) {
        try {
          await repo.attachFile(
            documentId: savedId!,
            source: f.file,
            originalName: f.name,
          );
        } catch (_) {
          failedFiles.add(f.name);
        }
      }
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    if (failedFiles.isNotEmpty) {
      showMessage(
        context,
        'Document enregistré, mais ${failedFiles.length} fichier(s) '
        "n'ont pas pu être copiés : ${failedFiles.join(', ')}.",
        error: true,
      );
    } else {
      showMessage(
        context,
        widget.isEditing
            ? 'Document mis à jour.'
            : widget.linkToItemId != null
            ? 'Document ajouté et associé à la pièce.'
            : 'Document ajouté à votre bibliothèque.',
      );
    }
    context.pop(savedId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isEditing ? 'Modifier le document' : 'Nouveau document',
        ),
      ),
      bottomNavigationBar: FormSaveBar(
        label: 'Enregistrer',
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
                  _TypeField(
                    type: _type,
                    errorText: _typeError,
                    onTap: _pickType,
                  ),
                  formGap,
                  TextFormField(
                    controller: _customName,
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: 120,
                    decoration: InputDecoration(
                      labelText: 'Nom personnalisé (facultatif)',
                      hintText: _type == null
                          ? 'ex. Passeport renouvelé en 2025'
                          : 'Par défaut : ${_type!.name}',
                      helperText:
                          'Utile pour distinguer deux documents du même type.',
                    ),
                  ),
                  formGap,
                  DateField(
                    label: 'Date de délivrance (facultative)',
                    initialValue: _issueDate,
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                    onChanged: (d) => setState(() => _issueDate = d),
                  ),
                  formGap,
                  DateField(
                    label: "Date d'expiration (facultative)",
                    initialValue: _expiryDate,
                    helperText: (_type?.expiryApplicable ?? false)
                        ? "Ce type de document expire généralement : indiquez la date pour recevoir un rappel."
                        : null,
                    onChanged: (d) => setState(() => _expiryDate = d),
                    validator: (d) {
                      if (d != null &&
                          _issueDate != null &&
                          d.isBefore(_issueDate!)) {
                        return "La date d'expiration doit suivre la date de délivrance.";
                      }
                      return null;
                    },
                  ),
                  formGap,
                  TextFormField(
                    controller: _issuer,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Autorité émettrice (facultative)',
                      hintText: 'ex. Mairie de Cotonou',
                    ),
                  ),
                  formGap,
                  TextFormField(
                    controller: _notes,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Notes personnelles (facultatives)',
                      alignLabelWithHint: true,
                    ),
                  ),
                  if (!widget.isEditing) ...[
                    SectionHeader(
                      'Fichier joint (facultatif)',
                      padding: const EdgeInsets.fromLTRB(0, 24, 0, 4),
                    ),
                    Text(
                      'Vous pouvez enregistrer ce document sans fichier '
                      'numérique. Les fichiers restent dans l’espace privé '
                      'de l’application.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final f in _pendingFiles)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.insert_drive_file_outlined),
                        title: Text(f.name, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          tooltip: 'Retirer ${f.name}',
                          icon: const Icon(Icons.close),
                          onPressed: () =>
                              setState(() => _pendingFiles.remove(f)),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _addFile,
                        icon: const Icon(Icons.attach_file),
                        label: const Text('Joindre un PDF ou une image'),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 16),
                    Text(
                      'Les fichiers joints se gèrent depuis la fiche du document.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

class _TypeField extends StatelessWidget {
  const _TypeField({required this.type, required this.onTap, this.errorText});

  final DocumentTypeRow? type;
  final VoidCallback onTap;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Type de document',
      value: type?.name ?? 'Non choisi',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          isEmpty: type == null,
          decoration: InputDecoration(
            labelText: 'Type de document *',
            errorText: errorText,
            prefixIcon: type == null
                ? null
                : Icon(documentCategoryIcon(type!.category)),
            suffixIcon: const Icon(Icons.arrow_drop_down),
            helperText: type?.category.label,
          ),
          child: Text(type?.name ?? ''),
        ),
      ),
    );
  }
}

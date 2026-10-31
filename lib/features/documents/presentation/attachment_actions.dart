import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/database/app_database.dart';
import '../../../core/files/file_storage_service.dart';
import '../../../core/security/app_lock.dart';
import '../../../core/widgets/common.dart';

/// Fichier choisi par l'utilisateur, pas encore copié dans l'espace privé.
class PickedAttachment {
  const PickedAttachment({required this.file, required this.name});

  final File file;
  final String name;
}

enum _Source { camera, gallery, file }

/// Propose de prendre une photo, d'en choisir une ou de choisir un fichier
/// (PDF ou image). Aucune permission n'est demandée : l'appareil photo et
/// les sélecteurs du système fournissent une copie temporaire.
Future<PickedAttachment?> pickAttachment(BuildContext context) async {
  final source = await showModalBottomSheet<_Source>(
    context: context,
    useSafeArea: true,
    builder: (context) => const _SourceSheet(),
  );
  if (source == null || !context.mounted) return null;
  // Le retour depuis l'appareil photo ou le sélecteur ne verrouille pas.
  ExternalActivity.expect();
  return switch (source) {
    _Source.camera => _pickImage(context, ImageSource.camera),
    _Source.gallery => _pickImage(context, ImageSource.gallery),
    _Source.file => _pickFile(context),
  };
}

Future<PickedAttachment?> _pickImage(
  BuildContext context,
  ImageSource source,
) async {
  try {
    final image = await ImagePicker().pickImage(
      source: source,
      // Assez net pour être lu, assez léger pour les sauvegardes.
      maxWidth: 2400,
      maxHeight: 2400,
      imageQuality: 85,
      requestFullMetadata: false,
    );
    if (image == null) return null;
    final extension = p.extension(image.name).toLowerCase();
    final name = source == ImageSource.camera
        ? 'Photo du ${DateFormat("d MMM y 'à' HH'h'mm", 'fr_FR').format(DateTime.now())}'
              '${extension.isEmpty ? '.jpg' : extension}'
        : image.name;
    return PickedAttachment(file: File(image.path), name: name);
  } on PlatformException catch (e) {
    if (context.mounted) {
      showMessage(
        context,
        e.code == 'camera_access_denied'
            ? 'Dossia n’a pas accès à l’appareil photo. Autorisez-le dans les '
                  'réglages du téléphone.'
            : source == ImageSource.camera
            ? 'L’appareil photo n’a pas pu s’ouvrir.'
            : 'Vos photos n’ont pas pu s’ouvrir.',
        error: true,
      );
    }
    return null;
  }
}

Future<PickedAttachment?> _pickFile(BuildContext context) async {
  try {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Choisir un PDF ou une image',
      type: FileType.custom,
      allowedExtensions: allowedAttachmentExtensions,
    );
    if (picked == null) return null;
    final path = picked.path;
    if (path == null) {
      if (context.mounted) {
        showMessage(
          context,
          "Ce fichier n'est pas accessible. Essayez de l'enregistrer d'abord "
          'sur le téléphone.',
          error: true,
        );
      }
      return null;
    }
    return PickedAttachment(file: File(path), name: picked.name);
  } catch (_) {
    if (context.mounted) {
      showMessage(
        context,
        "Le sélecteur de fichiers n'a pas pu s'ouvrir.",
        error: true,
      );
    }
    return null;
  }
}

class _SourceSheet extends StatelessWidget {
  const _SourceSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    void pop(_Source s) => Navigator.of(context).pop(s);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Joindre', style: theme.textTheme.titleLarge),
          ),
          AppRow(
            leading: const IconTile(Icons.photo_camera_outlined),
            title: 'Prendre une photo',
            subtitle: 'Photographiez le document',
            chevron: false,
            onTap: () => pop(_Source.camera),
          ),
          AppRow(
            leading: const IconTile(Icons.photo_library_outlined),
            title: 'Choisir une photo',
            subtitle: 'Depuis la galerie',
            chevron: false,
            onTap: () => pop(_Source.gallery),
          ),
          AppRow(
            leading: const IconTile(Icons.folder_open_outlined),
            title: 'Choisir un fichier',
            subtitle: 'PDF ou image',
            chevron: false,
            onTap: () => pop(_Source.file),
          ),
        ],
      ),
    );
  }
}

/// Ouvre un fichier joint : aperçu intégré pour les images, application
/// externe pour les PDF. Un fichier manquant est signalé sans plantage.
Future<void> openAttachment(
  BuildContext context,
  WidgetRef ref,
  DocumentFileRow fileRow,
) async {
  final file = await ref
      .read(fileStorageProvider)
      .resolve(fileRow.relativePath);
  if (!context.mounted) return;
  if (file == null) {
    showMessage(
      context,
      'Fichier introuvable. Il a peut-être été supprimé ou non inclus dans '
      'la sauvegarde restaurée. Vous pouvez le retirer puis le joindre à '
      'nouveau.',
      error: true,
    );
    return;
  }
  if (isImageMime(fileRow.mimeType)) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ImageViewer(file: file, title: fileRow.fileName),
      ),
    );
    return;
  }
  await _openExternally(context, file, fileRow.mimeType);
}

Future<void> _openExternally(
  BuildContext context,
  File file,
  String? mimeType,
) async {
  try {
    ExternalActivity.expect();
    final result = await OpenFilex.open(file.path, type: mimeType);
    if (!context.mounted) return;
    switch (result.type) {
      case ResultType.done:
        break;
      case ResultType.noAppToOpen:
        showMessage(
          context,
          'Aucune application ne permet d’ouvrir ce fichier sur ce téléphone.',
          error: true,
        );
      case ResultType.fileNotFound:
        showMessage(context, 'Fichier introuvable.', error: true);
      case ResultType.permissionDenied:
      case ResultType.error:
        showMessage(context, "Le fichier n'a pas pu être ouvert.", error: true);
    }
  } catch (_) {
    if (context.mounted) {
      showMessage(context, "Le fichier n'a pas pu être ouvert.", error: true);
    }
  }
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.file, required this.title});

  final File file;
  final String title;

  @override
  Widget build(BuildContext context) {
    // Fond sombre quel que soit le thème, comme une visionneuse de photos.
    return Theme(
      data: buildDarkTheme(),
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.black.withValues(alpha: 0.4),
            foregroundColor: Colors.white,
            title: Text(title, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                tooltip: 'Ouvrir avec une autre application',
                icon: const Icon(Icons.open_in_new_rounded),
                onPressed: () => _openExternally(context, file, null),
              ),
            ],
          ),
          body: InteractiveViewer(
            maxScale: 5,
            child: Center(
              child: Image.file(
                file,
                semanticLabel: title,
                errorBuilder: (context, _, _) => const EmptyState(
                  icon: Icons.broken_image_outlined,
                  title: 'Aperçu indisponible',
                  message:
                      "Ce format d'image ne s'affiche pas ici. Ouvrez-le avec "
                      'une autre application (bouton en haut à droite).',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Icône d'un fichier joint selon son type.
IconData attachmentIcon(String? mimeType) => isImageMime(mimeType)
    ? Icons.image_outlined
    : Icons.picture_as_pdf_outlined;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../../core/database/app_database.dart';
import '../../../core/files/file_storage_service.dart';
import '../../../core/widgets/common.dart';

/// Fichier choisi par l'utilisateur, pas encore copié dans l'espace privé.
class PickedAttachment {
  const PickedAttachment({required this.file, required this.name});

  final File file;
  final String name;
}

/// Ouvre le sélecteur de fichiers Android (PDF ou image). Aucune permission
/// de stockage n'est nécessaire : le système fournit une copie temporaire.
Future<PickedAttachment?> pickAttachment(BuildContext context) async {
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

/// Ouvre un fichier joint : aperçu intégré pour les images, application
/// externe pour les PDF. Un fichier manquant est signalé sans plantage.
Future<void> openAttachment(
  BuildContext context,
  WidgetRef ref,
  DocumentFileRow fileRow,
) async {
  final file = await ref.read(fileStorageProvider).resolve(fileRow.relativePath);
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
    return Scaffold(
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Ouvrir avec une autre application',
            icon: const Icon(Icons.open_in_new),
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
                  "Ce format d'image ne peut pas être affiché ici. Utilisez "
                  'le bouton en haut à droite pour l’ouvrir avec une autre '
                  'application.',
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

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/database_provider.dart';
import '../utils/errors.dart';

/// Taille maximale d'un fichier joint, pour rester raisonnable sur les
/// appareils d'entrée de gamme et dans les sauvegardes.
const maxAttachmentBytes = 25 * 1024 * 1024;

const allowedAttachmentExtensions = [
  'pdf',
  'jpg',
  'jpeg',
  'png',
  'webp',
  'heic',
  'heif',
];

class StoredFile {
  const StoredFile({
    required this.relativePath,
    required this.sizeBytes,
    required this.mimeType,
  });

  final String relativePath;
  final int sizeBytes;
  final String? mimeType;
}

class AttachmentException implements UserFacingError {
  const AttachmentException(this.message);

  @override
  final String message;

  @override
  String toString() => message;
}

/// Gère les fichiers joints dans l'espace privé de l'application
/// (`getApplicationSupportDirectory()/attachments`). Aucun fichier n'est
/// écrit dans un répertoire public.
class FileStorageService {
  FileStorageService({Future<Directory> Function()? baseDirectory})
    : _baseDirectory = baseDirectory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _baseDirectory;

  static const attachmentsFolder = 'attachments';

  Future<Directory> attachmentsRoot() async {
    final base = await _baseDirectory();
    final dir = Directory(p.join(base.path, attachmentsFolder));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Copie [source] dans l'espace privé, sous un nom généré.
  Future<StoredFile> importFile({
    required File source,
    required String originalName,
    required String documentId,
  }) async {
    final extension = p.extension(originalName).replaceFirst('.', '').toLowerCase();
    if (!allowedAttachmentExtensions.contains(extension)) {
      throw const AttachmentException(
        'Format non pris en charge. Choisissez un PDF ou une image (JPG, PNG, WEBP, HEIC).',
      );
    }
    final size = await source.length();
    if (size > maxAttachmentBytes) {
      throw const AttachmentException(
        'Ce fichier dépasse 25 Mo. Choisissez un fichier plus léger ou compressez-le.',
      );
    }
    final relativePath = p.posix.join(documentId, '${newId()}.$extension');
    final target = await resolveUnchecked(relativePath);
    await target.parent.create(recursive: true);
    try {
      await source.copy(target.path);
    } on FileSystemException {
      throw const AttachmentException(
        "Impossible d'enregistrer ce fichier. Vérifiez l'espace de stockage disponible.",
      );
    }
    return StoredFile(
      relativePath: relativePath,
      sizeBytes: size,
      mimeType: mimeTypeForExtension(extension),
    );
  }

  Future<File> resolveUnchecked(String relativePath) async {
    final root = await attachmentsRoot();
    final full = p.normalize(p.join(root.path, relativePath));
    // Empêche toute sortie du répertoire privé via un chemin relatif forgé.
    if (!p.isWithin(root.path, full)) {
      throw const AttachmentException('Chemin de fichier invalide.');
    }
    return File(full);
  }

  /// Renvoie le fichier s'il existe encore, `null` sinon.
  Future<File?> resolve(String relativePath) async {
    try {
      final file = await resolveUnchecked(relativePath);
      return await file.exists() ? file : null;
    } on AttachmentException {
      return null;
    }
  }

  Future<void> delete(String relativePath) async {
    final file = await resolve(relativePath);
    if (file == null) return;
    await file.delete();
    final parent = file.parent;
    if (await parent.exists() && await parent.list().isEmpty) {
      await parent.delete();
    }
  }

  Future<void> deleteAll() async {
    final root = await attachmentsRoot();
    if (await root.exists()) await root.delete(recursive: true);
  }
}

String? mimeTypeForExtension(String extension) {
  switch (extension.toLowerCase()) {
    case 'pdf':
      return 'application/pdf';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'heic':
      return 'image/heic';
    case 'heif':
      return 'image/heif';
  }
  return null;
}

bool isImageMime(String? mimeType) => mimeType?.startsWith('image/') ?? false;

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes o';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} Ko';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} Mo';
}

final fileStorageProvider = Provider<FileStorageService>(
  (ref) => FileStorageService(),
);

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../security/app_lock.dart';
import '../widgets/common.dart';

/// Écrit [bytes] dans un sous-dossier du cache de l'application, après avoir
/// effacé les exports précédents (aucune copie de données personnelles ne
/// s'accumule dans le cache).
Future<File> writeExportFile(String fileName, Uint8List bytes) async {
  final temp = await getTemporaryDirectory();
  final dir = Directory(p.join(temp.path, 'exports'));
  if (await dir.exists()) await dir.delete(recursive: true);
  await dir.create(recursive: true);
  final file = File(p.join(dir.path, fileName));
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

/// Ouvre la feuille de partage Android pour [file].
Future<void> shareExportedFile(
  BuildContext context, {
  required File file,
  required String mimeType,
  String? subject,
}) async {
  try {
    ExternalActivity.expect();
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType)],
        subject: subject,
        title: subject,
      ),
    );
  } catch (_) {
    if (context.mounted) {
      showMessage(
        context,
        "Le partage n'a pas pu s'ouvrir sur cet appareil.",
        error: true,
      );
    }
  }
}

/// Demande à l'utilisateur où enregistrer le fichier (sélecteur Android).
/// Renvoie `true` si le fichier a été enregistré.
Future<bool> saveExportToDevice(
  BuildContext context, {
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
}) async {
  try {
    ExternalActivity.expect();
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Enregistrer sous',
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeType,
    );
    if (uri == null) return false;
    if (context.mounted) showMessage(context, 'Fichier enregistré.');
    return true;
  } catch (_) {
    if (context.mounted) {
      showMessage(
        context,
        "Le fichier n'a pas pu être enregistré à cet emplacement.",
        error: true,
      );
    }
    return false;
  }
}

/// Affiche un indicateur bloquant pendant [task].
Future<T> runWithProgress<T>(
  BuildContext context,
  String message,
  Future<T> Function() task,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  );
  try {
    return await task();
  } finally {
    navigator.pop();
  }
}

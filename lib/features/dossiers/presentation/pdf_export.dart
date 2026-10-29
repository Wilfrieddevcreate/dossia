import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/export_actions.dart';
import '../../../core/pdf/dossier_pdf_service.dart';
import '../../../core/widgets/common.dart';
import '../domain/dossier_models.dart';

enum _Destination { share, save }

/// Génère le récapitulatif PDF d'un dossier, hors ligne, puis le partage ou
/// l'enregistre (§ 4.9).
Future<void> exportDossierPdf(
  BuildContext context,
  WidgetRef ref,
  DossierOverview overview,
) async {
  final choice = await showDialog<(_Destination, bool)>(
    context: context,
    builder: (context) => const _ExportDialog(),
  );
  if (choice == null || !context.mounted) return;
  final (destination, includeNotes) = choice;

  final service = ref.read(dossierPdfServiceProvider);
  final fileName = service.suggestedFileName(overview);
  try {
    final bytes = await runWithProgress(
      context,
      'Génération du récapitulatif…',
      () => service.buildSummary(
        overview,
        options: PdfExportOptions(includeNotes: includeNotes),
      ),
    );
    if (!context.mounted) return;
    switch (destination) {
      case _Destination.share:
        final file = await writeExportFile(fileName, bytes);
        if (!context.mounted) return;
        await shareExportedFile(
          context,
          file: file,
          mimeType: 'application/pdf',
          subject: 'Récapitulatif — ${overview.dossier.title}',
        );
      case _Destination.save:
        await saveExportToDevice(
          context,
          fileName: fileName,
          bytes: bytes,
          mimeType: 'application/pdf',
        );
    }
  } catch (_) {
    if (context.mounted) {
      showMessage(
        context,
        "Le récapitulatif n'a pas pu être généré. Réessayez.",
        error: true,
      );
    }
  }
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog();

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  bool _includeNotes = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Récapitulatif PDF'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Le PDF liste les pièces, leur statut et la progression. Il '
              "n'inclut pas les scans de vos documents.",
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Inclure les notes'),
              subtitle: const Text(
                'Description, notes du dossier et des pièces, tâches en cours.',
              ),
              value: _includeNotes,
              onChanged: (v) => setState(() => _includeNotes = v),
            ),
          ],
        ),
      ),
      actionsOverflowButtonSpacing: 8,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        OutlinedButton.icon(
          onPressed: () =>
              Navigator.of(context).pop((_Destination.save, _includeNotes)),
          icon: const Icon(Icons.download_outlined),
          label: const Text('Enregistrer'),
        ),
        FilledButton.icon(
          onPressed: () =>
              Navigator.of(context).pop((_Destination.share, _includeNotes)),
          icon: const Icon(Icons.share_outlined),
          label: const Text('Partager'),
        ),
      ],
    );
  }
}

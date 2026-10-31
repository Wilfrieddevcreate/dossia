import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
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
  final choice = await showModalBottomSheet<(_Destination, bool)>(
    context: context,
    useSafeArea: true,
    builder: (context) => _ExportSheet(title: overview.dossier.title),
  );
  if (choice == null || !context.mounted) return;
  final (destination, includeNotes) = choice;

  final service = ref.read(dossierPdfServiceProvider);
  final fileName = service.suggestedFileName(overview);
  try {
    final bytes = await runWithProgress(
      context,
      'Préparation du PDF…',
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

class _ExportSheet extends StatefulWidget {
  const _ExportSheet({required this.title});

  final String title;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  bool _includeNotes = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Récapitulatif PDF', style: theme.textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Les pièces de « ${widget.title} », leur statut et la '
            'progression. Vos scans ne sont pas inclus.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Panel(
            color: AppPalette.of(context).muted,
            radius: 16,
            child: SwitchListTile(
              title: const Text('Inclure les notes'),
              subtitle: const Text('Notes du dossier, des pièces et tâches'),
              value: _includeNotes,
              onChanged: (v) => setState(() => _includeNotes = v),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () =>
                Navigator.of(context).pop((_Destination.share, _includeNotes)),
            icon: const Icon(Icons.ios_share_rounded),
            label: const Text('Partager'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () =>
                Navigator.of(context).pop((_Destination.save, _includeNotes)),
            icon: const Icon(Icons.download_rounded),
            label: const Text('Enregistrer sur le téléphone'),
          ),
        ],
      ),
    );
  }
}

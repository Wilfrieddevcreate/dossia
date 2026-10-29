import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../features/dossiers/domain/dossier_models.dart';
import '../../features/requirements/domain/item_status.dart';
import '../../features/requirements/domain/requirement_models.dart';
import '../utils/dates.dart';

/// Options choisies par l'utilisateur avant l'export.
class PdfExportOptions {
  const PdfExportOptions({this.includeNotes = false});

  /// Inclut la description, les notes du dossier et des pièces, ainsi que les
  /// tâches ouvertes. Désactivé par défaut : les notes peuvent contenir des
  /// informations personnelles.
  final bool includeNotes;
}

const _regularFontAsset = 'assets/fonts/NotoSans-Regular.ttf';
const _boldFontAsset = 'assets/fonts/NotoSans-Bold.ttf';

const pdfDisclaimer =
    "Ce récapitulatif reflète les déclarations de l'utilisateur dans Dossia. "
    "Il ne certifie ni l'authenticité ni la conformité des documents.";

/// Génère le récapitulatif PDF d'un dossier, entièrement hors ligne.
///
/// Le PDF est un récapitulatif : il n'intègre jamais les fichiers joints aux
/// documents personnels.
class DossierPdfService {
  DossierPdfService({Future<ByteData> Function(String key)? loadAsset})
    : _loadAsset = loadAsset ?? rootBundle.load;

  final Future<ByteData> Function(String key) _loadAsset;

  /// Génère le récapitulatif PDF. Ne contient jamais les scans des documents.
  Future<Uint8List> buildSummary(
    DossierOverview overview, {
    PdfExportOptions options = const PdfExportOptions(),
    DateTime? generatedAt,
  }) async {
    // Les dates sont formatées ici (isolat principal, où les données de
    // localisation sont initialisées) ; l'isolat de rendu ne reçoit que du
    // texte.
    final report = buildDossierReport(
      overview,
      options: options,
      generatedAt: generatedAt ?? DateTime.now(),
    );
    final fonts = PdfFonts(
      regular: _bytesOf(await _loadAsset(_regularFontAsset)),
      bold: _bytesOf(await _loadAsset(_boldFontAsset)),
    );
    return _renderInIsolate(report, fonts);
  }

  /// Nom de fichier proposé : `dossia-<titre>-AAAA-MM-JJ.pdf`, en ASCII.
  String suggestedFileName(DossierOverview overview, {DateTime? generatedAt}) {
    final date = formatIsoDate(generatedAt ?? DateTime.now());
    return 'dossia-${slugify(overview.dossier.title)}-$date.pdf';
  }

  // Méthode statique : la fermeture envoyée à l'isolat ne capture que les
  // paramètres, jamais le service.
  static Future<Uint8List> _renderInIsolate(PdfReport report, PdfFonts fonts) =>
      Isolate.run(() => renderDossierReport(report, fonts));

  static Uint8List _bytesOf(ByteData data) => Uint8List.fromList(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
}

final dossierPdfServiceProvider = Provider<DossierPdfService>(
  (ref) => DossierPdfService(),
);

// -----------------------------------------------------------------------------
// Modèle du rapport (données simples, transmissibles à un isolat)

class PdfFonts {
  const PdfFonts({required this.regular, required this.bold});

  final Uint8List regular;
  final Uint8List bold;
}

class PdfCount {
  const PdfCount(this.label, this.value);

  final String label;
  final int value;
}

class PdfItemRow {
  const PdfItemRow({
    required this.number,
    required this.name,
    required this.mandatory,
    required this.quantity,
    required this.status,
    required this.documents,
    this.instructions,
    this.dueDate,
  });

  final int number;
  final String name;
  final bool mandatory;

  /// Quantité associée / attendue, par exemple « 1 / 2 ».
  final String quantity;
  final ItemStatus status;
  final List<String> documents;
  final String? instructions;
  final String? dueDate;
}

class PdfListEntry {
  const PdfListEntry(this.title, [this.details = const []]);

  final String title;
  final List<String> details;
}

class PdfListSection {
  const PdfListSection(this.title, this.entries);

  final String title;
  final List<PdfListEntry> entries;
}

class PdfNotes {
  const PdfNotes({
    this.description,
    this.notes,
    this.itemNotes = const [],
    this.openTasks = const [],
  });

  final String? description;
  final String? notes;
  final List<PdfListEntry> itemNotes;
  final List<PdfListEntry> openTasks;

  bool get isEmpty =>
      description == null &&
      notes == null &&
      itemNotes.isEmpty &&
      openTasks.isEmpty;
}

/// Contenu complet du récapitulatif, sous forme de texte déjà mis en forme.
class PdfReport {
  const PdfReport({
    required this.title,
    required this.generatedOn,
    required this.statusLabel,
    required this.progressLabel,
    required this.counts,
    required this.items,
    required this.sections,
    this.category,
    this.deadline,
    this.progressDetail,
    this.progressRatio,
    this.notes,
  });

  final String title;
  final String? category;
  final String generatedOn;
  final String? deadline;
  final String statusLabel;

  /// « 60 % » ou « Aucune pièce obligatoire ».
  final String progressLabel;

  /// « 3 sur 5 pièces obligatoires disponibles ».
  final String? progressDetail;
  final double? progressRatio;
  final List<PdfCount> counts;
  final List<PdfItemRow> items;
  final List<PdfListSection> sections;

  /// Renseigné uniquement si l'utilisateur a choisi d'inclure les notes.
  final PdfNotes? notes;
}

/// Construit le contenu du récapitulatif à partir d'un dossier évalué.
///
/// Fonction pure : elle ne lit ni la base ni les fichiers, ce qui permet de
/// tester précisément ce qui figurera dans le PDF.
PdfReport buildDossierReport(
  DossierOverview overview, {
  required PdfExportOptions options,
  required DateTime generatedAt,
}) {
  final dossier = overview.dossier;
  final progress = overview.progress;
  final reference = dateOnly(generatedAt);

  final deadline = dossier.deadline;
  final items = <PdfItemRow>[];
  for (var i = 0; i < overview.items.length; i++) {
    final item = overview.items[i];
    final row = item.view.item;
    items.add(
      PdfItemRow(
        number: i + 1,
        name: item.view.displayName,
        mandatory: row.isMandatory,
        quantity:
            '${item.evaluation.assignedQuantity} / '
            '${item.evaluation.requiredQuantity}',
        status: item.status,
        documents: [
          for (final l in item.view.links)
            [
              l.displayName,
              if (l.link.quantityAssigned > 1) '×${l.link.quantityAssigned}',
              if (l.isArchived) '(archivé)',
            ].join(' '),
        ],
        instructions: _clean(row.instructions),
        dueDate: row.dueDate == null ? null : formatShortDate(row.dueDate!),
      ),
    );
  }

  String suffix(EvaluatedRequirement item) =>
      item.evaluation.isMandatory ? '' : ' (facultative)';

  final missing = [
    for (final item in overview.items.where(
      (i) => i.evaluation.isMandatory && i.status == ItemStatus.missing,
    ))
      PdfListEntry(item.view.displayName, [
        ?_clean(item.view.item.instructions),
      ]),
  ];

  final toVerify = [
    for (final item in overview.items.where(
      (i) => i.status == ItemStatus.toVerify,
    ))
      PdfListEntry('${item.view.displayName}${suffix(item)}', [
        for (final reason in item.evaluation.reasons)
          verifyReasonLabel(
            reason,
            assigned: item.evaluation.assignedQuantity,
            required: item.evaluation.requiredQuantity,
          ),
      ]),
  ];

  final toRenew = [
    for (final item in overview.items.where(
      (i) => i.status == ItemStatus.toRenew,
    ))
      PdfListEntry('${item.view.displayName}${suffix(item)}', [
        for (final l in item.view.links)
          if (l.doc.expiryDate != null &&
              dateOnly(l.doc.expiryDate!).isBefore(reference))
            '${l.displayName} : expiré le ${formatLongDate(l.doc.expiryDate!)}',
      ]),
  ];

  PdfNotes? notes;
  if (options.includeNotes) {
    final openTasks = overview.tasks.where((t) => !t.isCompleted).toList()
      ..sort((a, b) {
        if (a.dueDate == null && b.dueDate == null) return 0;
        if (a.dueDate == null) return 1;
        if (b.dueDate == null) return -1;
        return a.dueDate!.compareTo(b.dueDate!);
      });
    notes = PdfNotes(
      description: _clean(dossier.description),
      notes: _clean(dossier.notes),
      itemNotes: [
        for (final item in overview.items)
          if (_clean(item.view.item.notes) case final note?)
            PdfListEntry(item.view.displayName, [note]),
      ],
      openTasks: [
        for (final t in openTasks)
          PdfListEntry(t.title, [
            if (t.dueDate != null) 'Échéance : ${formatLongDate(t.dueDate!)}',
            ?_clean(t.notes),
          ]),
      ],
    );
  }

  return PdfReport(
    title: dossier.title,
    category: dossier.category?.label,
    generatedOn: _formatGeneratedOn(generatedAt),
    deadline: deadline == null
        ? null
        : '${formatLongDate(deadline)} '
              '(${relativeDayLabel(deadline, reference: reference)})',
    statusLabel: overview.status.label,
    progressLabel: progress.label,
    progressDetail: progress.hasMandatoryItems
        ? '${progress.mandatoryAvailable} sur ${progress.mandatoryTotal} '
              '${progress.mandatoryTotal > 1 ? 'pièces obligatoires disponibles' : 'pièce obligatoire disponible'}'
        : null,
    progressRatio: progress.ratio,
    counts: [
      PdfCount('Obligatoires', progress.mandatoryTotal),
      PdfCount('Disponibles', progress.mandatoryAvailable),
      PdfCount('Manquantes', progress.mandatoryMissing),
      PdfCount('À vérifier', progress.mandatoryToVerify),
      PdfCount('À renouveler', progress.mandatoryToRenew),
      PdfCount('Facultatives', progress.optionalTotal),
    ],
    items: items,
    sections: [
      PdfListSection('Pièces manquantes', missing),
      PdfListSection('Pièces à vérifier', toVerify),
      if (toRenew.isNotEmpty) PdfListSection('Pièces à renouveler', toRenew),
    ],
    notes: notes,
  );
}

String? _clean(String? value) {
  final trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

String _formatGeneratedOn(DateTime value) {
  final local = value.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${formatLongDate(local)} à $hh:$mm';
}

/// Transforme un titre en segment de nom de fichier ASCII : minuscules, sans
/// accents, mots séparés par des tirets.
String slugify(String value, {int maxLength = 50}) {
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyy';
  final buffer = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    final index = from.indexOf(char);
    if (index >= 0) {
      buffer.write(to[index]);
    } else if (char == 'œ') {
      buffer.write('oe');
    } else if (char == 'æ') {
      buffer.write('ae');
    } else if (RegExp(r'[a-z0-9]').hasMatch(char)) {
      buffer.write(char);
    } else {
      buffer.write('-');
    }
  }
  var slug = buffer
      .toString()
      .replaceAll(RegExp('-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  if (slug.length > maxLength) {
    slug = slug.substring(0, maxLength).replaceAll(RegExp(r'-$'), '');
  }
  return slug.isEmpty ? 'dossier' : slug;
}

// -----------------------------------------------------------------------------
// Rendu

final _primary = PdfColor.fromHex('#176B4D');
final _ink = PdfColor.fromHex('#18211D');
final _muted = PdfColor.fromHex('#66736C');
final _line = PdfColor.fromHex('#D5DDD9');
final _tint = PdfColor.fromHex('#EEF4F1');

PdfColor _statusColor(ItemStatus status) => switch (status) {
  ItemStatus.available => _primary,
  ItemStatus.missing => PdfColor.fromHex('#B3261E'),
  ItemStatus.toVerify => PdfColor.fromHex('#8A5A00'),
  ItemStatus.toRenew => PdfColor.fromHex('#A04100'),
  ItemStatus.optional => _muted,
};

/// Produit les octets du PDF. Fonction de premier niveau : elle s'exécute dans
/// un isolat séparé pour ne pas bloquer l'interface.
Future<Uint8List> renderDossierReport(
  PdfReport report,
  PdfFonts fonts, {
  bool compress = true,
}) {
  final regular = pw.Font.ttf(ByteData.sublistView(fonts.regular));
  final bold = pw.Font.ttf(ByteData.sublistView(fonts.bold));
  final theme = pw.ThemeData.withFont(base: regular, bold: bold);

  final doc = pw.Document(
    compress: compress,
    title: 'Récapitulatif — ${report.title}',
    author: 'Dossia',
    creator: 'Dossia',
    subject: 'Récapitulatif de dossier',
  );

  doc.addPage(
    pw.MultiPage(
      theme: theme,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 32),
      maxPages: 200,
      header: (context) => context.pageNumber == 1
          ? pw.SizedBox()
          : pw.Container(
              alignment: pw.Alignment.centerLeft,
              margin: const pw.EdgeInsets.only(bottom: 12),
              padding: const pw.EdgeInsets.only(bottom: 4),
              decoration: pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: _line)),
              ),
              child: pw.Text(
                'Dossia — ${report.title}',
                style: pw.TextStyle(fontSize: 9, color: _muted),
              ),
            ),
      footer: (context) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 12),
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _line)),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Text(
                pdfDisclaimer,
                style: pw.TextStyle(fontSize: 8, color: _muted),
              ),
            ),
            pw.SizedBox(width: 16),
            pw.Text(
              'Page ${context.pageNumber} / ${context.pagesCount}',
              style: pw.TextStyle(fontSize: 8, color: _muted),
            ),
          ],
        ),
      ),
      build: (context) => [
        _header(report),
        pw.SizedBox(height: 16),
        _progress(report),
        pw.SizedBox(height: 12),
        _counts(report),
        pw.SizedBox(height: 20),
        _sectionTitle('Liste des pièces'),
        if (report.items.isEmpty)
          _emptyLine("Aucune pièce n'a été ajoutée à ce dossier.")
        else
          _itemsTable(report.items),
        for (final section in report.sections) ...[
          pw.SizedBox(height: 18),
          ..._keepWithFirst(_sectionTitle(section.title), [
            if (section.entries.isEmpty)
              _emptyLine('Aucune')
            else
              ...section.entries.map(_listEntry),
          ]),
        ],
        if (report.notes case final notes?) ..._notes(notes),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _header(PdfReport report) {
  pw.Widget field(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 3),
    child: pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '$label : ',
            style: pw.TextStyle(fontSize: 10, color: _muted),
          ),
          pw.TextSpan(
            text: value,
            style: pw.TextStyle(fontSize: 10, color: _ink),
          ),
        ],
      ),
    ),
  );

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        'Dossia — Récapitulatif de dossier',
        style: pw.TextStyle(
          fontSize: 10,
          color: _primary,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        report.title,
        style: pw.TextStyle(
          fontSize: 20,
          color: _ink,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
      pw.SizedBox(height: 6),
      if (report.category case final category?) field('Catégorie', category),
      field('Statut du dossier', report.statusLabel),
      if (report.deadline case final deadline?) field('Date limite', deadline),
      field('Généré le', report.generatedOn),
    ],
  );
}

pw.Widget _progress(PdfReport report) {
  final ratio = report.progressRatio;
  final filled = ratio == null ? 0 : (ratio * 1000).round();
  return pw.Container(
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(
      color: _tint,
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'Progression : ',
              style: pw.TextStyle(fontSize: 11, color: _ink),
            ),
            pw.Text(
              report.progressLabel,
              style: pw.TextStyle(
                fontSize: 14,
                color: _primary,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            if (report.progressDetail case final detail?) ...[
              pw.SizedBox(width: 8),
              pw.Text(detail, style: pw.TextStyle(fontSize: 10, color: _muted)),
            ],
          ],
        ),
        if (ratio != null) ...[
          pw.SizedBox(height: 8),
          pw.ClipRRect(
            horizontalRadius: 3,
            verticalRadius: 3,
            child: pw.Container(
              height: 6,
              color: PdfColors.white,
              child: pw.Row(
                children: [
                  if (filled > 0)
                    pw.Expanded(
                      flex: filled,
                      child: pw.Container(color: _primary),
                    ),
                  if (filled < 1000)
                    pw.Expanded(flex: 1000 - filled, child: pw.SizedBox()),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

pw.Widget _counts(PdfReport report) {
  return pw.Row(
    children: [
      for (var i = 0; i < report.counts.length; i++) ...[
        if (i > 0) pw.SizedBox(width: 6),
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _line),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              children: [
                pw.Text(
                  '${report.counts[i].value}',
                  style: pw.TextStyle(
                    fontSize: 14,
                    color: _ink,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  report.counts[i].label,
                  style: pw.TextStyle(fontSize: 9, color: _muted),
                  textAlign: pw.TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    ],
  );
}

pw.Widget _sectionTitle(String title) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 6),
  child: pw.Text(
    title,
    style: pw.TextStyle(
      fontSize: 13,
      color: _primary,
      fontWeight: pw.FontWeight.bold,
    ),
  ),
);

pw.Widget _emptyLine(String text) =>
    pw.Text(text, style: pw.TextStyle(fontSize: 10, color: _muted));

pw.Widget _itemsTable(List<PdfItemRow> items) {
  const cellPadding = pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5);
  final headerStyle = pw.TextStyle(
    fontSize: 9,
    color: PdfColors.white,
    fontWeight: pw.FontWeight.bold,
  );
  final cellStyle = pw.TextStyle(fontSize: 9, color: _ink);
  final mutedStyle = pw.TextStyle(fontSize: 9, color: _muted);

  pw.Widget headerCell(String text) => pw.Padding(
    padding: cellPadding,
    child: pw.Text(text, style: headerStyle),
  );
  pw.Widget cell(pw.Widget child) =>
      pw.Padding(padding: cellPadding, child: child);

  return pw.Table(
    columnWidths: const {
      0: pw.FixedColumnWidth(22),
      1: pw.FlexColumnWidth(2.4),
      2: pw.FixedColumnWidth(58),
      3: pw.FixedColumnWidth(36),
      4: pw.FixedColumnWidth(84),
      5: pw.FlexColumnWidth(2.2),
      6: pw.FlexColumnWidth(2.4),
    },
    border: pw.TableBorder(
      horizontalInside: pw.BorderSide(color: _line, width: 0.6),
      bottom: pw.BorderSide(color: _line, width: 0.6),
    ),
    children: [
      pw.TableRow(
        repeat: true,
        decoration: pw.BoxDecoration(color: _primary),
        children: [
          headerCell('N°'),
          headerCell('Pièce'),
          headerCell('Caractère'),
          headerCell('Qté'),
          headerCell('Statut'),
          headerCell('Documents associés'),
          headerCell('Instructions'),
        ],
      ),
      for (final item in items)
        pw.TableRow(
          verticalAlignment: pw.TableCellVerticalAlignment.top,
          children: [
            cell(pw.Text('${item.number}', style: mutedStyle)),
            cell(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    item.name,
                    style: cellStyle.copyWith(fontWeight: pw.FontWeight.bold),
                  ),
                  if (item.dueDate case final due?)
                    pw.Text('Échéance : $due', style: mutedStyle),
                ],
              ),
            ),
            cell(
              pw.Text(
                item.mandatory ? 'Obligatoire' : 'Facultative',
                style: item.mandatory ? cellStyle : mutedStyle,
              ),
            ),
            cell(pw.Text(item.quantity, style: cellStyle)),
            cell(_statusLabel(item.status)),
            cell(
              item.documents.isEmpty
                  ? pw.Text('—', style: mutedStyle)
                  : pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        for (final d in item.documents)
                          pw.Text(d, style: cellStyle),
                      ],
                    ),
            ),
            cell(pw.Text(item.instructions ?? '—', style: mutedStyle)),
          ],
        ),
    ],
  );
}

/// Statut : libellé textuel précédé d'un repère de couleur (la couleur n'est
/// jamais le seul moyen de distinguer les statuts).
pw.Widget _statusLabel(ItemStatus status) {
  final color = _statusColor(status);
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Container(
        width: 6,
        height: 6,
        decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle),
      ),
      pw.SizedBox(width: 4),
      pw.Flexible(
        child: pw.Text(
          status.label,
          style: pw.TextStyle(
            fontSize: 9,
            color: color,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
    ],
  );
}

pw.Widget _listEntry(PdfListEntry entry) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 5),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Container(
        width: 12,
        child: pw.Text('•', style: pw.TextStyle(fontSize: 10, color: _primary)),
      ),
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              entry.title,
              style: pw.TextStyle(fontSize: 10, color: _ink),
            ),
            for (final d in entry.details)
              pw.Text(d, style: pw.TextStyle(fontSize: 9, color: _muted)),
          ],
        ),
      ),
    ],
  ),
);

List<pw.Widget> _notes(PdfNotes notes) {
  pw.Widget paragraph(String label, String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 8),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 10,
            color: _ink,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(text, style: pw.TextStyle(fontSize: 10, color: _ink)),
      ],
    ),
  );

  pw.Widget subTitle(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 4, bottom: 4),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 10,
        color: _ink,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
  );

  return [
    pw.SizedBox(height: 18),
    ..._keepWithFirst(_sectionTitle('Notes'), [
      if (notes.isEmpty) _emptyLine('Aucune note.'),
      if (notes.description case final description?)
        paragraph('Description', description),
      if (notes.notes case final dossierNotes?)
        paragraph('Notes du dossier', dossierNotes),
      if (notes.itemNotes.isNotEmpty)
        ..._keepWithFirst(
          subTitle('Notes sur les pièces'),
          notes.itemNotes.map(_listEntry).toList(),
        ),
      if (notes.openTasks.isNotEmpty)
        ..._keepWithFirst(
          subTitle('Tâches restantes'),
          notes.openTasks.map(_listEntry).toList(),
        ),
    ]),
  ];
}

/// Regroupe un titre avec le premier élément qui le suit, pour qu'un titre ne
/// reste jamais seul en bas de page.
List<pw.Widget> _keepWithFirst(pw.Widget title, List<pw.Widget> body) {
  if (body.isEmpty) return [title];
  return [
    pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [title, body.first],
    ),
    ...body.skip(1),
  ];
}

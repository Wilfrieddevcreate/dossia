import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dossia/core/database/app_database.dart';
import 'package:dossia/core/models/document_category.dart';
import 'package:dossia/core/models/dossier_category.dart';
import 'package:dossia/core/models/stored_statuses.dart';
import 'package:dossia/core/pdf/dossier_pdf_service.dart';
import 'package:dossia/features/dossiers/domain/dossier_models.dart';
import 'package:dossia/features/requirements/domain/item_status.dart';
import 'package:dossia/features/requirements/domain/requirement_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

final _created = DateTime(2026, 1, 1);
final _generatedAt = DateTime(2026, 10, 29, 10, 30);
final _today = DateTime(2026, 10, 29);

DocumentTypeRow _type(String id, String name) => DocumentTypeRow(
  id: id,
  name: name,
  category: DocumentCategory.identity,
  expiryApplicable: false,
  isCustom: false,
  createdAt: _created,
);

PersonalDocumentRow _doc(
  String id,
  DocumentTypeRow type, {
  DateTime? expiryDate,
  DateTime? archivedAt,
  String? customName,
}) => PersonalDocumentRow(
  id: id,
  typeId: type.id,
  customName: customName,
  expiryDate: expiryDate,
  createdAt: _created,
  updatedAt: _created,
  archivedAt: archivedAt,
);

RequiredItemRow _item(
  String id,
  int position, {
  DocumentTypeRow? type,
  String? customName,
  bool mandatory = true,
  int quantity = 1,
  String? instructions,
  String? notes,
  ManualItemStatus status = ManualItemStatus.auto,
  DateTime? dueDate,
}) => RequiredItemRow(
  id: id,
  dossierId: 'dossier-1',
  typeId: type?.id,
  customName: customName,
  isMandatory: mandatory,
  quantity: quantity,
  instructions: instructions,
  status: status,
  notes: notes,
  position: position,
  dueDate: dueDate,
  createdAt: _created,
  updatedAt: _created,
);

LinkedDocument _link(
  RequiredItemRow item,
  PersonalDocumentRow doc,
  DocumentTypeRow type, {
  int quantity = 1,
}) => LinkedDocument(
  link: ItemDocumentLinkRow(
    id: 'link-${item.id}-${doc.id}',
    requiredItemId: item.id,
    personalDocumentId: doc.id,
    quantityAssigned: quantity,
    linkedAt: _created,
  ),
  doc: doc,
  docType: type,
);

DossierRow _dossier({
  String title = 'Visa études — France',
  String? description = 'Demande de visa long séjour',
  String? notes = 'Rendez-vous au consulat le 20 novembre',
}) => DossierRow(
  id: 'dossier-1',
  title: title,
  category: DossierCategory.travel,
  description: description,
  notes: notes,
  deadline: DateTime(2026, 12, 15),
  status: ManualDossierStatus.inProgress,
  createdAt: _created,
  updatedAt: _created,
);

/// Dossier couvrant tous les statuts : disponible, manquant, à vérifier
/// (quantité et condition), à renouveler, facultatif.
DossierOverview _fixture() {
  final passportType = _type('builtin.passport', 'Passeport');
  final birthType = _type('builtin.birth_certificate', 'Acte de naissance');
  final bankType = _type('builtin.bank_statement', 'Relevé bancaire');
  final idType = _type('builtin.id_card', "Carte d'identité");
  final photoType = _type('builtin.id_photo', "Photo d'identité");

  final passport = _doc(
    'doc-passport',
    passportType,
    expiryDate: DateTime(2031, 3, 1),
  );
  final bank = _doc('doc-bank', bankType, customName: 'Relevé Ecobank mars');
  final idCard = _doc('doc-id', idType, expiryDate: DateTime(2026, 1, 3));
  final photo = _doc('doc-photo', photoType);

  final passportItem = _item(
    'item-passport',
    0,
    type: passportType,
    instructions: 'Copie des pages 1 à 3',
  );
  final birthItem = _item(
    'item-birth',
    1,
    type: birthType,
    instructions: 'Copie certifiée conforme',
    notes: 'Demander à la mairie de Cotonou',
  );
  final bankItem = _item('item-bank', 2, type: bankType, quantity: 3);
  final idItem = _item('item-id', 3, type: idType);
  final letterItem = _item(
    'item-letter',
    4,
    customName: 'Lettre de recommandation',
    mandatory: false,
  );
  final photoItem = _item(
    'item-photo',
    5,
    type: photoType,
    mandatory: false,
    quantity: 2,
    status: ManualItemStatus.toVerify,
    dueDate: DateTime(2026, 11, 5),
  );

  return DossierOverview.build(
    dossier: _dossier(),
    requirements: [
      RequirementView(
        item: passportItem,
        type: passportType,
        links: [_link(passportItem, passport, passportType)],
      ),
      RequirementView(item: birthItem, type: birthType, links: const []),
      RequirementView(
        item: bankItem,
        type: bankType,
        links: [_link(bankItem, bank, bankType)],
      ),
      RequirementView(
        item: idItem,
        type: idType,
        links: [_link(idItem, idCard, idType)],
      ),
      RequirementView(item: letterItem, type: null, links: const []),
      RequirementView(
        item: photoItem,
        type: photoType,
        links: [_link(photoItem, photo, photoType, quantity: 2)],
      ),
    ],
    tasks: [
      TaskRow(
        id: 'task-open',
        dossierId: 'dossier-1',
        title: 'Prendre rendez-vous',
        dueDate: DateTime(2026, 11, 10),
        isCompleted: false,
        notes: 'Appeler le matin',
        createdAt: _created,
        updatedAt: _created,
      ),
      TaskRow(
        id: 'task-done',
        dossierId: 'dossier-1',
        title: 'Payer les frais de dossier',
        isCompleted: true,
        createdAt: _created,
        updatedAt: _created,
      ),
    ],
    today: _today,
  );
}

/// Tout le texte du rapport, pour vérifier ce qui figurera (ou non) dans le PDF.
String _allText(PdfReport r) => [
  r.title,
  r.category,
  r.generatedOn,
  r.deadline,
  r.statusLabel,
  r.progressLabel,
  r.progressDetail,
  for (final c in r.counts) '${c.label} ${c.value}',
  for (final i in r.items) ...[
    i.name,
    i.quantity,
    i.instructions,
    i.dueDate,
    ...i.documents,
  ],
  for (final s in r.sections) ...[
    s.title,
    for (final e in s.entries) ...[e.title, ...e.details],
  ],
  if (r.notes case final n?) ...[
    n.description,
    n.notes,
    for (final e in [...n.itemNotes, ...n.openTasks]) ...[
      e.title,
      ...e.details,
    ],
  ],
].whereType<String>().join('\n');

Future<ByteData> _loadFromDisk(String key) async =>
    ByteData.sublistView(await File(key).readAsBytes());

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  group('buildDossierReport', () {
    test("reprend l'en-tête, la progression et les compteurs", () {
      final report = buildDossierReport(
        _fixture(),
        options: const PdfExportOptions(),
        generatedAt: _generatedAt,
      );

      expect(report.title, 'Visa études — France');
      expect(report.category, 'Voyage et visa');
      expect(report.generatedOn, '29 octobre 2026 à 10:30');
      expect(report.deadline, '15 décembre 2026 (dans 47 jours)');
      expect(report.statusLabel, 'En préparation');
      // 4 pièces obligatoires, seul le passeport est disponible.
      expect(report.progressLabel, '25 %');
      expect(report.progressDetail, '1 sur 4 pièces obligatoires disponibles');
      expect(report.progressRatio, 0.25);
      expect(
        {for (final c in report.counts) c.label: c.value},
        {
          'Obligatoires': 4,
          'Disponibles': 1,
          'Manquantes': 1,
          'À vérifier': 1,
          'À renouveler': 1,
          'Facultatives': 2,
        },
      );
    });

    test('liste toutes les pièces dans l’ordre avec statut et quantités', () {
      final report = buildDossierReport(
        _fixture(),
        options: const PdfExportOptions(),
        generatedAt: _generatedAt,
      );

      expect(report.items.map((i) => i.number), [1, 2, 3, 4, 5, 6]);
      expect(report.items.map((i) => i.name), [
        'Passeport',
        'Acte de naissance',
        'Relevé bancaire',
        "Carte d'identité",
        'Lettre de recommandation',
        "Photo d'identité",
      ]);
      expect(report.items.map((i) => i.status), [
        ItemStatus.available,
        ItemStatus.missing,
        ItemStatus.toVerify,
        ItemStatus.toRenew,
        ItemStatus.optional,
        ItemStatus.toVerify,
      ]);
      expect(report.items.map((i) => i.mandatory), [
        true,
        true,
        true,
        true,
        false,
        false,
      ]);
      expect(report.items[2].quantity, '1 / 3');
      expect(report.items[2].documents, ['Relevé Ecobank mars']);
      expect(report.items[5].documents, ["Photo d'identité ×2"]);
      expect(report.items[0].instructions, 'Copie des pages 1 à 3');
      expect(report.items[5].dueDate, '5 nov. 2026');
    });

    test('détaille les pièces manquantes, à vérifier et à renouveler', () {
      final report = buildDossierReport(
        _fixture(),
        options: const PdfExportOptions(),
        generatedAt: _generatedAt,
      );
      final sections = {for (final s in report.sections) s.title: s.entries};

      expect(sections.keys, [
        'Pièces manquantes',
        'Pièces à vérifier',
        'Pièces à renouveler',
      ]);
      // Une pièce facultative manquante n'est pas listée comme manquante.
      expect(sections['Pièces manquantes']!.map((e) => e.title), [
        'Acte de naissance',
      ]);
      expect(sections['Pièces manquantes']!.single.details, [
        'Copie certifiée conforme',
      ]);
      final toVerify = sections['Pièces à vérifier']!;
      expect(toVerify.map((e) => e.title), [
        'Relevé bancaire',
        "Photo d'identité (facultative)",
      ]);
      expect(toVerify.first.details, ['Quantité incomplète : 1 sur 3']);
      expect(toVerify.last.details, ['Une condition reste à confirmer']);
      expect(sections['Pièces à renouveler']!.single.details, [
        "Carte d'identité : expiré le 3 janvier 2026",
      ]);
    });

    test("n'inclut aucune note par défaut", () {
      final report = buildDossierReport(
        _fixture(),
        options: const PdfExportOptions(),
        generatedAt: _generatedAt,
      );
      final text = _allText(report);

      expect(report.notes, isNull);
      expect(text, isNot(contains('Demande de visa long séjour')));
      expect(text, isNot(contains('Rendez-vous au consulat')));
      expect(text, isNot(contains('Demander à la mairie de Cotonou')));
      expect(text, isNot(contains('Prendre rendez-vous')));
      expect(text, isNot(contains('Appeler le matin')));
    });

    test('inclut notes et tâches ouvertes sur demande', () {
      final report = buildDossierReport(
        _fixture(),
        options: const PdfExportOptions(includeNotes: true),
        generatedAt: _generatedAt,
      );
      final notes = report.notes!;

      expect(notes.description, 'Demande de visa long séjour');
      expect(notes.notes, 'Rendez-vous au consulat le 20 novembre');
      expect(notes.itemNotes.single.title, 'Acte de naissance');
      expect(notes.itemNotes.single.details, [
        'Demander à la mairie de Cotonou',
      ]);
      // Les tâches terminées ne figurent pas dans le récapitulatif.
      expect(notes.openTasks.map((t) => t.title), ['Prendre rendez-vous']);
      expect(notes.openTasks.single.details, [
        'Échéance : 10 novembre 2026',
        'Appeler le matin',
      ]);
    });

    test('affiche « Aucune pièce obligatoire » plutôt que 100 %', () {
      final overview = DossierOverview.build(
        dossier: _dossier(description: null, notes: null),
        requirements: const [],
        tasks: const [],
        today: _today,
      );
      final report = buildDossierReport(
        overview,
        options: const PdfExportOptions(includeNotes: true),
        generatedAt: _generatedAt,
      );

      expect(report.progressLabel, 'Aucune pièce obligatoire');
      expect(report.progressDetail, isNull);
      expect(report.progressRatio, isNull);
      expect(report.items, isEmpty);
      expect(report.sections.map((s) => s.title), [
        'Pièces manquantes',
        'Pièces à vérifier',
      ]);
      expect(report.sections.every((s) => s.entries.isEmpty), isTrue);
      expect(report.notes!.isEmpty, isTrue);
    });
  });

  group('DossierPdfService', () {
    final service = DossierPdfService(loadAsset: _loadFromDisk);

    Future<void> expectValidPdf(Uint8List bytes) async {
      expect(bytes.length, greaterThan(10 * 1024));
      expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
      expect(latin1.decode(bytes.sublist(bytes.length - 8)), contains('%%EOF'));
    }

    test('génère un PDF avec et sans notes', () async {
      final withoutNotes = await service.buildSummary(
        _fixture(),
        generatedAt: _generatedAt,
      );
      final withNotes = await service.buildSummary(
        _fixture(),
        options: const PdfExportOptions(includeNotes: true),
        generatedAt: _generatedAt,
      );

      await expectValidPdf(withoutNotes);
      await expectValidPdf(withNotes);
      expect(withNotes, isNot(equals(withoutNotes)));
    });

    test('répartit un long dossier sur plusieurs pages', () async {
      final type = _type('builtin.transcript', 'Relevé de notes');
      final overview = DossierOverview.build(
        dossier: _dossier(),
        requirements: [
          for (var i = 0; i < 120; i++)
            RequirementView(
              item: _item(
                'item-$i',
                i,
                type: type,
                customName: 'Relevé de notes — semestre ${i + 1}',
                instructions:
                    'Copie certifiée conforme, signée et tamponnée par '
                    "l'établissement d'origine, datant de moins de trois mois.",
              ),
              type: type,
              links: const [],
            ),
        ],
        tasks: const [],
        today: _today,
      );

      final bytes = await service.buildSummary(
        overview,
        generatedAt: _generatedAt,
      );

      await expectValidPdf(bytes);
      final pageCount = RegExp(
        r'/Type\s*/Page\b',
      ).allMatches(latin1.decode(bytes)).length;
      expect(pageCount, greaterThan(1));
    });

    test('propose un nom de fichier ASCII daté', () {
      expect(
        service.suggestedFileName(_fixture(), generatedAt: _generatedAt),
        'dossia-visa-etudes-france-2026-10-29.pdf',
      );
      expect(
        slugify('Œuvre & Bourse : Côte d’Ivoire'),
        'oeuvre-bourse-cote-d-ivoire',
      );
      expect(slugify('!!!'), 'dossier');
      expect(slugify('a' * 80).length, 50);
    });
  });
}

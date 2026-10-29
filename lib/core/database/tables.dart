import 'package:drift/drift.dart';

import '../models/document_category.dart';
import '../models/dossier_category.dart';
import '../models/stored_statuses.dart';
import 'converters.dart';

// Les identifiants sont des UUID v4 stockés en texte. Les horodatages sont
// stockés en texte ISO-8601 (option `store_date_time_values_as_text` de
// build.yaml) et les dates calendaires au format AAAA-MM-JJ.

@DataClassName('DocumentTypeRow')
class DocumentTypes extends Table {
  @override
  String get tableName => 'document_types';

  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get category => textEnum<DocumentCategory>()();
  TextColumn get description => text().nullable()();
  BoolColumn get expiryApplicable =>
      boolean().withDefault(const Constant(false))();

  /// `true` pour les types créés par l'utilisateur, `false` pour le catalogue
  /// fourni avec l'application.
  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PersonalDocumentRow')
class PersonalDocuments extends Table {
  @override
  String get tableName => 'personal_documents';

  TextColumn get id => text()();
  TextColumn get typeId => text().references(
    DocumentTypes,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get customName => text().nullable()();
  TextColumn get issueDate =>
      text().map(const DateOnlyConverter()).nullable()();
  TextColumn get expiryDate =>
      text().map(const DateOnlyConverter()).nullable()();
  TextColumn get issuer => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get archivedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('DocumentFileRow')
class DocumentFiles extends Table {
  @override
  String get tableName => 'document_files';

  TextColumn get id => text()();
  TextColumn get documentId => text().references(
    PersonalDocuments,
    #id,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get fileName => text()();

  /// Chemin relatif au dossier privé de l'application (jamais un chemin
  /// absolu, pour que les sauvegardes restent portables).
  TextColumn get relativePath => text()();
  TextColumn get mimeType => text().nullable()();
  IntColumn get sizeBytes => integer()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('DossierRow')
class Dossiers extends Table {
  @override
  String get tableName => 'dossiers';

  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 160)();
  TextColumn get category => textEnum<DossierCategory>().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get deadline => text().map(const DateOnlyConverter()).nullable()();
  TextColumn get status => textEnum<ManualDossierStatus>().withDefault(
    Constant(ManualDossierStatus.inProgress.name),
  )();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get archivedAt => dateTime().nullable()();

  /// Dernière consultation, pour la section « Récemment consultés ».
  DateTimeColumn get lastOpenedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('RequiredItemRow')
class RequiredItems extends Table {
  @override
  String get tableName => 'required_items';

  TextColumn get id => text()();
  TextColumn get dossierId => text().references(
    Dossiers,
    #id,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get typeId => text().nullable().references(
    DocumentTypes,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get customName => text().nullable()();
  BoolColumn get isMandatory => boolean().withDefault(const Constant(true))();
  // Idiome drift pour une contrainte CHECK sur la colonne elle-même.
  IntColumn get quantity => integer()
      .withDefault(const Constant(1))
      // ignore: recursive_getters
      .check(quantity.isBiggerOrEqualValue(1))();
  TextColumn get instructions => text().nullable()();
  TextColumn get status => textEnum<ManualItemStatus>().withDefault(
    Constant(ManualItemStatus.auto.name),
  )();
  TextColumn get notes => text().nullable()();
  IntColumn get position => integer()();
  TextColumn get dueDate => text().map(const DateOnlyConverter()).nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    // Une pièce doit être identifiée par un type ou par un nom libre.
    'CHECK (type_id IS NOT NULL OR custom_name IS NOT NULL)',
  ];
}

@DataClassName('ItemDocumentLinkRow')
class ItemDocumentLinks extends Table {
  @override
  String get tableName => 'item_document_links';

  TextColumn get id => text()();
  TextColumn get requiredItemId => text().references(
    RequiredItems,
    #id,
    onDelete: KeyAction.cascade,
  )();

  /// RESTRICT : supprimer un document utilisé dans des dossiers doit passer
  /// par le dépôt, qui retire explicitement les associations après
  /// confirmation de l'utilisateur.
  TextColumn get personalDocumentId => text().references(
    PersonalDocuments,
    #id,
    onDelete: KeyAction.restrict,
  )();
  // Idiome drift pour une contrainte CHECK sur la colonne elle-même.
  IntColumn get quantityAssigned => integer()
      .withDefault(const Constant(1))
      // ignore: recursive_getters
      .check(quantityAssigned.isBiggerOrEqualValue(1))();
  DateTimeColumn get linkedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {requiredItemId, personalDocumentId},
  ];
}

@DataClassName('TaskRow')
class Tasks extends Table {
  @override
  String get tableName => 'tasks';

  TextColumn get id => text()();
  TextColumn get dossierId => text().references(
    Dossiers,
    #id,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get dueDate => text().map(const DateOnlyConverter()).nullable()();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SettingRow')
class Settings extends Table {
  @override
  String get tableName => 'settings';

  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

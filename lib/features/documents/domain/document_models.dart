import '../../../core/database/app_database.dart';
import '../../../core/models/document_category.dart';
import '../../../core/utils/dates.dart';

/// Délai en dessous duquel un document est signalé « expire bientôt ».
const expiringSoonDays = 30;

enum ExpiryState { none, valid, expiringSoon, expired }

ExpiryState expiryStateOf(DateTime? expiryDate, DateTime today) {
  if (expiryDate == null) return ExpiryState.none;
  final days = daysBetween(today, expiryDate);
  if (days < 0) return ExpiryState.expired;
  if (days <= expiringSoonDays) return ExpiryState.expiringSoon;
  return ExpiryState.valid;
}

String documentDisplayName(PersonalDocumentRow doc, DocumentTypeRow type) {
  final custom = doc.customName?.trim();
  return (custom == null || custom.isEmpty) ? type.name : custom;
}

/// Document personnel tel qu'affiché dans la bibliothèque.
class DocumentView {
  const DocumentView({
    required this.doc,
    required this.type,
    this.fileCount = 0,
    this.usageCount = 0,
  });

  final PersonalDocumentRow doc;
  final DocumentTypeRow type;
  final int fileCount;

  /// Nombre de pièces (tous dossiers confondus) auxquelles il est associé.
  final int usageCount;

  String get id => doc.id;
  String get displayName => documentDisplayName(doc, type);
  DocumentCategory get category => type.category;
  bool get isArchived => doc.archivedAt != null;

  ExpiryState expiryState(DateTime today) =>
      expiryStateOf(doc.expiryDate, today);

  /// Correspondance pour la recherche locale (nom, type, émetteur, notes).
  bool matches(String query) {
    final q = normalizeForSearch(query);
    if (q.isEmpty) return true;
    return [displayName, type.name, doc.issuer, doc.notes]
        .whereType<String>()
        .any((value) => normalizeForSearch(value).contains(q));
  }
}

/// Pièce d'un dossier à laquelle un document est associé.
class DocumentUsage {
  const DocumentUsage({
    required this.linkId,
    required this.dossierId,
    required this.dossierTitle,
    required this.dossierArchived,
    required this.itemId,
    required this.itemName,
  });

  final String linkId;
  final String dossierId;
  final String dossierTitle;
  final bool dossierArchived;
  final String itemId;
  final String itemName;
}

class DocumentDetail {
  const DocumentDetail({
    required this.view,
    required this.files,
    required this.usages,
  });

  final DocumentView view;
  final List<DocumentFileRow> files;
  final List<DocumentUsage> usages;
}

/// Minuscules sans accents, pour une recherche tolérante.
String normalizeForSearch(String value) {
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyyoa';
  final lower = value.toLowerCase().trim();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    final index = from.indexOf(char);
    buffer.write(index >= 0 ? to[index] : char);
  }
  return buffer.toString();
}

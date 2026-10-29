import '../models/document_category.dart';

/// Type de document du catalogue fourni avec l'application.
///
/// Les identifiants sont stables (`builtin.*`) afin que les sauvegardes et les
/// migrations référencent toujours le même type.
class BuiltinDocumentType {
  const BuiltinDocumentType(
    this.id,
    this.name,
    this.category, {
    this.expiryApplicable = false,
    this.description,
  });

  final String id;
  final String name;
  final DocumentCategory category;
  final bool expiryApplicable;
  final String? description;
}

const builtinDocumentTypes = <BuiltinDocumentType>[
  // Identité
  BuiltinDocumentType(
    'builtin.id_card',
    "Carte d'identité",
    DocumentCategory.identity,
    expiryApplicable: true,
  ),
  BuiltinDocumentType(
    'builtin.passport',
    'Passeport',
    DocumentCategory.identity,
    expiryApplicable: true,
  ),
  BuiltinDocumentType(
    'builtin.birth_certificate',
    'Acte de naissance',
    DocumentCategory.identity,
  ),
  BuiltinDocumentType(
    'builtin.nationality_certificate',
    'Certificat de nationalité',
    DocumentCategory.identity,
  ),
  BuiltinDocumentType(
    'builtin.id_photo',
    "Photo d'identité",
    DocumentCategory.identity,
  ),
  BuiltinDocumentType(
    'builtin.criminal_record',
    'Extrait de casier judiciaire',
    DocumentCategory.identity,
    expiryApplicable: true,
  ),
  BuiltinDocumentType(
    'builtin.driving_licence',
    'Permis de conduire',
    DocumentCategory.identity,
    expiryApplicable: true,
  ),
  // Éducation
  BuiltinDocumentType(
    'builtin.baccalaureate',
    'Diplôme du baccalauréat',
    DocumentCategory.education,
  ),
  BuiltinDocumentType(
    'builtin.university_degree',
    'Diplôme universitaire',
    DocumentCategory.education,
  ),
  BuiltinDocumentType(
    'builtin.transcript',
    'Relevé de notes',
    DocumentCategory.education,
  ),
  BuiltinDocumentType(
    'builtin.pass_certificate',
    'Attestation de réussite',
    DocumentCategory.education,
  ),
  BuiltinDocumentType(
    'builtin.enrolment_certificate',
    'Certificat de scolarité',
    DocumentCategory.education,
  ),
  BuiltinDocumentType(
    'builtin.recommendation_letter',
    'Lettre de recommandation',
    DocumentCategory.education,
  ),
  // Professionnel
  BuiltinDocumentType('builtin.cv', 'CV', DocumentCategory.professional),
  BuiltinDocumentType(
    'builtin.cover_letter',
    'Lettre de motivation',
    DocumentCategory.professional,
  ),
  BuiltinDocumentType(
    'builtin.work_certificate',
    'Attestation de travail',
    DocumentCategory.professional,
  ),
  BuiltinDocumentType(
    'builtin.training_certificate',
    'Certificat de formation',
    DocumentCategory.professional,
  ),
  BuiltinDocumentType(
    'builtin.employment_contract',
    'Contrat de travail',
    DocumentCategory.professional,
  ),
  BuiltinDocumentType(
    'builtin.payslip',
    'Bulletin de salaire',
    DocumentCategory.professional,
  ),
  // Finances
  BuiltinDocumentType(
    'builtin.bank_statement',
    'Relevé bancaire',
    DocumentCategory.finance,
  ),
  BuiltinDocumentType(
    'builtin.proof_of_income',
    'Justificatif de revenus',
    DocumentCategory.finance,
  ),
  BuiltinDocumentType(
    'builtin.financial_guarantee',
    'Attestation de prise en charge',
    DocumentCategory.finance,
  ),
  BuiltinDocumentType(
    'builtin.tax_notice',
    "Avis d'imposition",
    DocumentCategory.finance,
  ),
  // Domicile
  BuiltinDocumentType(
    'builtin.proof_of_address',
    'Justificatif de domicile',
    DocumentCategory.housing,
  ),
  BuiltinDocumentType(
    'builtin.accommodation_certificate',
    "Attestation d'hébergement",
    DocumentCategory.housing,
  ),
  BuiltinDocumentType(
    'builtin.residence_certificate',
    'Certificat de résidence',
    DocumentCategory.housing,
  ),
  // Autres
  BuiltinDocumentType(
    'builtin.vaccination_record',
    'Carnet de vaccination',
    DocumentCategory.other,
  ),
  BuiltinDocumentType(
    'builtin.travel_insurance',
    'Assurance voyage',
    DocumentCategory.other,
    expiryApplicable: true,
  ),
  BuiltinDocumentType(
    'builtin.travel_booking',
    'Réservation de voyage',
    DocumentCategory.other,
  ),
];

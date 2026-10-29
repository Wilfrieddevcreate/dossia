/// Erreur dont le message peut être montré tel quel à l'utilisateur.
///
/// Les erreurs techniques (SQLite, système de fichiers…) ne l'implémentent
/// pas : l'interface affiche alors un message générique, sans détails
/// internes ni contenu de document.
abstract interface class UserFacingError implements Exception {
  String get message;
}

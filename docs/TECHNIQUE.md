# Dossia — documentation technique (V1.0)

## 1. Architecture

Application Flutter monoplateforme (Android), sans serveur. Le code est
organisé par fonctionnalité, chacune séparée en trois couches :

| Couche | Rôle | Exemples |
| --- | --- | --- |
| `domain/` | Règles métier pures (sans Flutter ni base) | `item_status.dart`, `dossier_progress.dart`, `deadline_models.dart`, `reminder_planner.dart` |
| `data/` | Dépôts (accès drift) et providers Riverpod | `documents_repository.dart`, `requirements_repository.dart` |
| `presentation/` | Écrans et widgets | `dossier_detail_screen.dart` |

Services transverses dans `lib/core/` : base de données, fichiers privés,
génération PDF, sauvegarde, notifications, widgets communs.

**Flux de données.** Les dépôts exposent des flux (`Stream`) recalculés à
chaque modification des tables concernées (`watchComputed` dans
`core/database/database_provider.dart`). Les providers Riverpod combinent ces
flux et évaluent les pièces à la date du jour (`todayProvider`, rafraîchi au
retour de l'application au premier plan). Toute modification (ajout,
association, archivage, changement de date) met donc à jour l'interface,
la progression et les échéances sans action manuelle.

**Navigation.** GoRouter, `StatefulShellRoute` à quatre onglets (Accueil,
Dossiers, Documents, Réglages). Les écrans de détail et les formulaires
s'ouvrent au-dessus de la barre de navigation. Chemins dans
`lib/app/router.dart` (`Routes`).

## 2. Dépendances

Versions figées par `pubspec.lock`.

| Paquet | Version | Usage |
| --- | --- | --- |
| drift / drift_flutter / sqlite3 | 2.35.3 / 0.3.1 / 3.5.2 | Base SQLite, requêtes typées, migrations ; SQLite embarqué dans l'APK |
| flutter_riverpod | 3.4.3 | Gestion d'état |
| go_router | 18.1.1 | Navigation |
| file_picker | 13.3.0 | Choix de fichiers, « Enregistrer sous » |
| path_provider / path | 2.1.6 / 1.9.1 | Répertoires privés |
| pdf | 3.13.1 | Récapitulatif PDF |
| share_plus | 13.3.1 | Partage Android |
| open_filex | 5.0.0 | Ouverture des PDF joints dans une autre application |
| flutter_local_notifications / timezone / flutter_timezone | 22.3.3 / 0.11.2 / 5.1.1 | Rappels locaux programmés |
| archive / crypto | 4.5.2 / 3.0.8 | Sauvegarde .zip, empreintes SHA-256 |
| intl / flutter_localizations | 0.20.2 | Dates et interface en français |
| uuid | 4.6.0 | Identifiants |
| drift_dev / build_runner (dev) | 2.35.2 / 2.15.1 | Génération de code drift |

Police **Noto Sans** (licence SIL OFL 1.1, `assets/fonts/OFL.txt`) embarquée
pour le PDF : génération hors ligne avec accents et typographie française.

## 3. Modèle de données

Schéma v1, instantané : `drift_schemas/dossia/drift_schema_v1.json`.
Définition : `lib/core/database/tables.dart`. Clés étrangères activées
(`PRAGMA foreign_keys = ON`), identifiants UUID v4 en texte, horodatages en
ISO-8601, dates calendaires en `AAAA-MM-JJ` (pas de décalage de fuseau).

| Table | Champs | Notes |
| --- | --- | --- |
| `document_types` | id, name, category, description, expiry_applicable, **is_custom**, created_at | 29 types fournis (`builtin.*`, identifiants stables), plus les types créés par l'utilisateur |
| `personal_documents` | id, type_id → document_types (RESTRICT), custom_name, issue_date, expiry_date, issuer, notes, created_at, updated_at, archived_at | |
| `document_files` | id, document_id → personal_documents (CASCADE), file_name, relative_path, mime_type, size_bytes, created_at | Chemin **relatif** à l'espace privé |
| `dossiers` | id, title, category, description, **notes**, deadline, status, created_at, updated_at, archived_at, **last_opened_at** | `status` : `inProgress` ou `completed` |
| `required_items` | id, dossier_id → dossiers (CASCADE), type_id → document_types (RESTRICT), custom_name, is_mandatory, quantity (≥ 1), instructions, status, notes, position, **due_date**, created_at, updated_at | CHECK : type_id ou custom_name renseigné. `status` : `auto` ou `toVerify` |
| `item_document_links` | id, required_item_id → required_items (CASCADE), personal_document_id → personal_documents (RESTRICT), quantity_assigned (≥ 1), linked_at | Unicité (pièce, document) |
| `tasks` | id, dossier_id → dossiers (CASCADE), title, due_date, is_completed, notes, created_at, updated_at | |
| `settings` | key, value | Préférences |

En **gras** : champs ajoutés au modèle indicatif du cahier des charges, pour
couvrir des besoins qu'il décrit ailleurs (types personnalisés, notes du
dossier § 3.2, « récemment consultés » § 4.1, échéance d'une pièce § 3.3).

La suppression d'un document lié à des pièces est refusée par la base
(RESTRICT) : elle passe obligatoirement par le dépôt, qui retire les
associations après confirmation de l'utilisateur. Aucune perte silencieuse.

## 4. Règles métier

### Statut d'une pièce (`features/requirements/domain/item_status.dart`)

Calculé, jamais saisi directement, dans cet ordre :

1. Aucun document associé → **Manquant** (obligatoire) ou **Facultatif**.
2. Un document associé a une date d'expiration **antérieure** à aujourd'hui
   → **À renouveler** (un document reste valide le jour de son expiration).
3. Sinon **À vérifier** si au moins une condition reste à confirmer :
   - quantité associée inférieure à la quantité attendue ;
   - document associé archivé ;
   - condition signalée par l'utilisateur (« copie certifiée »…, colonne
     `required_items.status = toVerify`) ;
   - document qui expire avant la date limite du dossier.
4. Sinon **Disponible**.

L'association d'un document est toujours un geste de l'utilisateur : Dossia
*propose* les documents du même type, il n'associe jamais automatiquement.
Aucune date d'expiration n'est supposée.

### Progression (`features/dossiers/domain/dossier_progress.dart`)

`pièces obligatoires disponibles / pièces obligatoires × 100`, arrondi à
l'entier inférieur (100 % uniquement si tout est disponible). Les pièces
facultatives sont ignorées. Sans pièce obligatoire : « Aucune pièce
obligatoire ». À vérifier et À renouveler ne comptent pas comme disponibles.

### Statut d'un dossier

Archivé (si `archived_at`) > Terminé (confirmation explicite de
l'utilisateur, avec rappel qu'il ne vaut pas acceptation) > Prêt à vérifier
(toutes les pièces obligatoires disponibles) > En préparation.

### Échéances et rappels

Sources : date limite des dossiers actifs, date d'expiration des documents
non archivés, tâches ouvertes, pièces non disponibles ayant une échéance
(`deadline_models.dart`). Rappels : un rappel *N* jours avant (3 jours par
défaut pour les échéances, 30 jours pour les expirations, réglables) et un
le jour même, à 9 h, 60 au maximum. Ils sont reprogrammés automatiquement à
chaque modification. Mode `inexactAllowWhileIdle` : aucune permission
d'alarme exacte, Android peut décaler légèrement l'heure. Contenu masqué sur
l'écran de verrouillage. Désactivés par défaut.

## 5. Fichiers joints

- Copiés dans `getApplicationSupportDirectory()/attachments/<id document>/`,
  sous un nom généré. Jamais dans un répertoire public.
- Formats : PDF, JPG, PNG, WEBP, HEIC/HEIF ; 25 Mo maximum par fichier.
- Les chemins sont vérifiés (aucune sortie du répertoire privé possible).
- Un fichier absent est signalé (« Fichier introuvable ») sans plantage.
- Les images s'affichent dans l'application ; les PDF s'ouvrent dans une
  application externe via le FileProvider d'`open_filex`.

## 6. Récapitulatif PDF

`lib/core/pdf/dossier_pdf_service.dart`. Construction en deux temps : un
modèle de données pur (`buildDossierReport`, testé), puis le rendu dans un
isolate séparé pour ne pas bloquer l'interface. Contenu : en-tête, statut,
progression, compteurs, tableau des pièces (statut en texte, jamais par la
seule couleur), pièces manquantes / à vérifier / à renouveler, notes
facultatives, pied de page avec pagination et avertissement de non-
certification. Les scans ne sont jamais inclus.

## 7. Sauvegarde et restauration

`lib/core/backup/backup_service.dart` ; format documenté en tête du fichier.

- Archive `.zip` : `manifest.json` (format `dossia-backup`, version de format
  1, version de schéma, version de l'application, date, compteurs, empreintes
  SHA-256), `data.json` (toutes les tables), `files/…` (fichiers joints, en
  option).
- Restauration : vérification complète **avant** toute modification (format,
  versions, empreintes, références entre tables, chemins), puis remplacement
  des données dans **une seule transaction** ; les fichiers joints ne sont
  remplacés qu'après validation de la transaction. En cas d'échec, les données
  locales restent intactes.
- Une sauvegarde créée par une version plus récente du schéma est refusée.
- Les archives temporaires et exports précédents sont effacés du cache.

## 8. Sécurité et confidentialité

- Aucune permission Internet ni stockage dans le manifeste fusionné : seules
  `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, `VIBRATE` (ajoutée par le
  module de notifications) et une permission interne AndroidX.
- Les permissions d'accès aux médias déclarées par `open_filex` sont retirées
  (`tools:node="remove"`) : le sélecteur système ne les requiert pas.
- Sauvegarde automatique Android désactivée (`allowBackup="false"`,
  `data_extraction_rules.xml`) : rien n'est copié vers le cloud.
- Aucun service d'analyse, de publicité ni de suivi.
- Aucun contenu de document n'est écrit dans les journaux ; les messages
  d'erreur affichés sont génériques pour les erreurs techniques
  (`UserFacingError` pour les messages destinés à l'utilisateur).
- **Pas de chiffrement applicatif** : la base, les fichiers joints et les
  sauvegardes ne sont pas chiffrés par Dossia. Ils reposent sur l'isolation
  des applications et le chiffrement du téléphone. Les sauvegardes .zip sont
  lisibles par quiconque y accède ; l'interface le dit explicitement.

## 9. Migrations

- `AppDatabase.schemaVersion = 1`, instantané dans `drift_schemas/`.
- `test/drift/dossia/migration_test.dart` vérifie que le schéma créé
  correspond à l'instantané et qu'une base existante est relue sans perte.
- Pour une évolution du schéma :
  1. modifier `tables.dart`, incrémenter `schemaVersion` ;
  2. écrire l'étape dans `onUpgrade` (sans suppression de données) ;
  3. `dart run drift_dev make-migrations` (nouvel instantané et helpers de
     test) ;
  4. ajouter les tests `migrateAndValidate` et de conservation des données ;
  5. adapter la sauvegarde si le format des tables change (le champ
     `schemaVersion` du manifeste permet de convertir les anciennes
     sauvegardes).

## 10. Compatibilité

- `minSdk = 24` (Android 7.0) : minimum compatible avec l'ensemble des
  dépendances retenues ; `targetSdk` et `compileSdk` suivent Flutter 3.44.
- Testé automatiquement sur deux gabarits (320×640 avec texte agrandi ×1,3,
  412×915). **À valider sur un téléphone Android réel** (voir la recette).
- Desugaring de la bibliothèque Java activé (requis par les notifications).

## 11. Publication

- L'APK de test est signé avec la clé de debug. Pour Google Play : créer une
  clé (`keytool -genkey -v -keystore dossia.jks -keyalg RSA -keysize 2048
  -validity 10000 -alias dossia`), la déclarer dans
  `android/key.properties` (non versionné) et dans `signingConfigs` de
  `android/app/build.gradle.kts`, puis `flutter build appbundle`.
- Identifiant d'application : `net.alopro.dossia`.
- Éléments à préparer : politique de confidentialité (le texte de l'écran
  « Confidentialité et stockage » sert de base), captures d'écran,
  formulaire « Sécurité des données » (aucune donnée collectée ni partagée).

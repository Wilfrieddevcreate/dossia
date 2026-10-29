# Dossia

Application Android de gestion documentaire et de préparation de dossiers.
Dossia permet d'enregistrer les documents que l'on possède, de créer des
dossiers (visa, inscription, candidature…), de lister les pièces demandées et
de voir immédiatement ce qui manque.

- **Hors ligne** : aucune connexion, aucun compte, aucun serveur. L'APK ne
  déclare même pas la permission Internet.
- **Local** : base SQLite et fichiers joints dans l'espace privé de
  l'application.
- **Version** : 1.0.0 (cahier des charges Dossia V1.0).

## Fonctionnalités

- Onboarding facultatif avec inventaire des documents possédés.
- Bibliothèque de documents : ajout sans fichier, PDF/image facultatif,
  dates de délivrance et d'expiration, recherche, filtres, archivage.
- Dossiers personnalisés : pièces obligatoires ou facultatives, quantités,
  instructions, échéances, tâches, notes.
- Association d'un même document à plusieurs pièces et dossiers, avec
  suggestion des documents correspondants.
- Statuts calculés (Manquant, Disponible, À vérifier, À renouveler,
  Facultatif) et progression sur les seules pièces obligatoires.
- Tableau de bord, liste des échéances (à venir / dépassées), rappels
  locaux configurables.
- Récapitulatif PDF d'un dossier, généré hors ligne, à partager ou
  enregistrer.
- Sauvegarde manuelle (.zip versionné, vérifié par SHA-256) et restauration
  contrôlée.

## Installer l'APK de test

L'APK se trouve dans `build/app/outputs/flutter-apk/` après compilation :

| Fichier | Pour qui |
| --- | --- |
| `app-arm64-v8a-release.apk` | La plupart des téléphones récents (recommandé) |
| `app-armeabi-v7a-release.apk` | Anciens téléphones 32 bits |
| `app-release.apk` | Universel (tous les téléphones, plus volumineux) |

Copiez le fichier sur le téléphone, ouvrez-le et autorisez l'installation
depuis cette source lorsque Android le demande. Android 7.0 ou plus récent est
requis.

## Développement

Prérequis : Flutter 3.44 (Dart 3.12), Android SDK, JDK 17.

```bash
flutter pub get
dart run build_runner build      # code généré par drift (app_database.g.dart)
flutter analyze
flutter test                     # tests unitaires, d'intégration et d'interface
flutter build apk --release --split-per-abi   # APK par architecture
flutter build apk --release                   # APK universel
```

Les versions exactes des dépendances sont figées par `pubspec.lock`, versionné
avec le code.

## Organisation du code

```text
lib/
  app/            application, routeur (GoRouter), thème Material 3
  core/           base de données (drift), fichiers, PDF, sauvegarde,
                  notifications, widgets partagés, utilitaires
  features/       une fonctionnalité par dossier (data / domain / presentation)
    onboarding/ dashboard/ documents/ dossiers/ requirements/ deadlines/ settings/
test/             domain/ data/ core/ widget/ drift/
drift_schemas/    instantanés versionnés du schéma de la base
docs/             documentation technique, guide d'utilisation, recette
```

## Documentation

- [Documentation technique](docs/TECHNIQUE.md) : architecture, schéma de
  données, règles métier, sauvegarde, sécurité, migrations, publication.
- [Guide d'utilisation](docs/GUIDE_UTILISATEUR.md), dont la procédure de
  sauvegarde et de restauration.
- [Recette](docs/RECETTE.md) : les 24 scénarios du cahier des charges, leur
  couverture automatique, les vérifications à faire sur téléphone et les
  limites connues.

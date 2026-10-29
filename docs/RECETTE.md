# Dossia V1.0 — recette

## 1. Tests automatisés

`flutter test` : **87 tests, tous réussis** (état au 29/10/2026).

| Dossier | Tests | Contenu |
| --- | --- | --- |
| `test/domain/` | 29 | Statuts des pièces, progression, statut du dossier, planification des rappels |
| `test/data/` | 19 | Dépôts sur base SQLite réelle (en mémoire et sur fichier) : associations multiples, suppressions, contraintes, persistance, recherche, échéances |
| `test/core/` | 27 | Sauvegarde/restauration (18) et récapitulatif PDF (9) |
| `test/widget/` | 10 | Parcours principaux, et ouverture des 18 écrans avec des données longues, sur deux gabarits : 320×640 avec texte ×1,3, et 412×915 (tout débordement fait échouer le test) |
| `test/drift/` | 2 | Schéma conforme à l'instantané v1, relecture d'une base existante |

## 2. Scénarios du cahier des charges (§ 10)

Légende : **Auto** = couvert par un test automatisé ; **Tél.** = à
confirmer sur un téléphone Android réel (interactions système : sélecteur de
fichiers, partage, notifications).

| # | Scénario | Couverture | Où |
| --- | --- | --- | --- |
| 1 | Commencer sans compte | Auto | widget « premier lancement » |
| 2 | Ignorer l'inventaire initial | Auto | widget « premier lancement » |
| 3 | Document sans fichier numérique | Auto | data « sans fichier numérique » ; widget « inventaire » |
| 4 | Importer un PDF ou une image | Auto + Tél. | data : copie privée, refus d'un format non pris en charge. Sélecteur Android : Tél. |
| 5 | Dossier sans date limite | Auto | data, widget « créer un dossier » |
| 6 | Pièces obligatoires et facultatives | Auto | data « pièces obligatoires, facultatives… » |
| 7 | Pièce obligatoire sans document → Manquant | Auto | domain, widget |
| 8 | Pièce associée → Disponible ou À vérifier | Auto | domain (toutes les règles), data |
| 9 | Progression recalculée après chaque modification | Auto | data « émise à nouveau », widget « associé » |
| 10 | Pièce facultative manquante sans effet sur la progression | Auto | domain, widget (100 % avec une facultative manquante) |
| 11 | Même document dans plusieurs dossiers | Auto | data « plusieurs dossiers » |
| 12 | Retirer une association ne touche pas les autres dossiers | Auto | data « plusieurs dossiers » |
| 13 | Persistance après fermeture et réouverture | Auto + Tél. | data « persistent après fermeture » (fichier SQLite) |
| 14 | Affichage des échéances | Auto + Tél. | data « échéances » (tri, à venir / dépassées) |
| 15 | Rappels selon permissions et paramètres | Auto + Tél. | domain « planification » ; réception réelle : Tél. |
| 16 | Contenu du PDF | Auto | core « PDF » (modèle du rapport, rendu multipage) |
| 17 | Partager ou enregistrer le PDF | Tél. | feuille de partage et « Enregistrer sous » Android |
| 18 | Restaurer une sauvegarde | Auto + Tél. | core « aller-retour », « second appareil » ; choix du fichier : Tél. |
| 19 | Sauvegarde incorrecte détectée | Auto | core : fichier modifié, mauvais format, version plus récente, références cassées, chemins dangereux |
| 20 | Confirmation des suppressions définitives | Tél. | dialogues sur document, dossier, pièce, fichier, tâche, toutes les données |
| 21 | Recherches et filtres | Auto + Tél. | data « recherche » (accents, casse) ; filtres à l'écran : Tél. |
| 22 | Fonctionnement hors ligne | Auto | l'APK ne déclare pas la permission Internet (manifeste fusionné vérifié) |
| 23 | Cohérence après migration | Auto (v1) | drift « schéma v1 », « relecture » ; aucune migration n'existe encore |
| 24 | Fichier inaccessible signalé sans plantage | Auto + Tél. | data : fichier supprimé → `resolve` nul ; affichage « Fichier introuvable » : Tél. |

## 3. Vérifications à faire sur téléphone

1. Installer l'APK, ouvrir Dossia **en mode avion** : tout doit fonctionner.
2. Inventaire : cocher 3 documents, ajouter un document personnalisé.
3. Joindre un PDF et une photo à un document ; les ouvrir.
4. Créer un dossier avec 3 pièces (dont une facultative), associer les
   documents proposés, vérifier progression et statuts.
5. Mettre une date d'expiration passée sur un document associé →
   « À renouveler ».
6. Activer les rappels (accepter l'autorisation), créer une échéance dans
   2 jours avec un délai de 1 jour : un rappel doit arriver le lendemain vers
   9 h. Redémarrer le téléphone entre-temps pour vérifier la reprogrammation.
7. Exporter le PDF : le partager, puis l'enregistrer ; l'ouvrir.
8. Créer une sauvegarde avec fichiers ; supprimer toutes les données ;
   restaurer : tout doit revenir, fichiers compris.
9. Restaurer un fichier qui n'est pas une sauvegarde Dossia → message
   d'erreur, données intactes.
10. Fermer l'application (la retirer des applications récentes), la rouvrir :
    les données sont là.
11. Activer une grande taille de police dans Android et vérifier la
    lisibilité des écrans principaux.

## 4. Fonctionnalités livrées

Toutes les fonctionnalités du § 2.1 du cahier des charges : onboarding et
inventaire facultatifs, bibliothèque (ajout, modification, recherche,
filtres, archivage, suppression, fichiers joints, utilisation dans les
dossiers), dossiers (création, modification, archivage, réactivation,
suppression, recherche, tri, tâches, notes), pièces (types existants ou
nouveaux, nom libre, obligatoire/facultative, quantité, instructions, note,
échéance, réorganisation, associations multiples), statuts et progression,
tableau de bord, échéances, rappels locaux, export PDF, sauvegarde et
restauration, écran de confidentialité, suppression de toutes les données.

## 5. Limites connues

- **Pas encore testé sur un téléphone réel** : les vérifications du § 3
  restent à faire.
- **Aucun chiffrement applicatif** de la base, des fichiers ou des
  sauvegardes (protection par l'isolation Android et le chiffrement du
  téléphone). Les sauvegardes .zip sont lisibles par qui y accède.
- **Signature de debug** : l'APK de test n'est pas publiable tel quel sur
  Google Play (voir `TECHNIQUE.md` § 11).
- **Rappels** : heure approximative (mode inexact) ; certains fabricants
  (économiseurs de batterie agressifs) peuvent les retarder ou les bloquer.
- **Fuseau horaire** : les horodatages d'une sauvegarde (création,
  modification) sont restaurés en heure locale ; restaurés dans un autre
  fuseau, ils sont décalés de la différence. Les dates (expiration,
  échéances) ne sont pas affectées.
- **« Enregistrer sur l'appareil »** charge la sauvegarde entière en mémoire
  (contrainte du sélecteur Android) ; pour une très grosse sauvegarde,
  préférer « Envoyer vers une autre application ».
- **Images HEIC** : l'aperçu intégré peut ne pas fonctionner sur certains
  appareils ; le bouton « Ouvrir avec une autre application » reste
  disponible.
- Catégories de dossier issues d'une liste fixe (avec « Autre »).
- Interface en français uniquement ; thème sombre fourni mais palette validée
  principalement en thème clair.
- Les tests d'interface utilisent la police de test de Flutter (glyphes
  carrés, plus larges que Roboto) : ils sont plus sévères que la réalité sur
  les débordements, mais ne remplacent pas un essai sur téléphone.

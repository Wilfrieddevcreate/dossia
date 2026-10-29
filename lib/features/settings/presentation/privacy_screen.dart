import 'package:flutter/material.dart';

/// Explication du stockage local et de la confidentialité (§ 8).
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const _sections = [
    (
      Icons.phone_android,
      'Stockage sur ce téléphone uniquement',
      'Dossia fonctionne sans compte et sans serveur. Vos documents, dossiers '
          'et notes sont enregistrés dans une base de données locale, dans '
          "l'espace privé de l'application, inaccessible aux autres "
          'applications. Aucune donnée n’est envoyée sur Internet.',
    ),
    (
      Icons.attach_file,
      'Fichiers joints facultatifs',
      'Vous pouvez enregistrer un document sans fichier. Si vous joignez un '
          'PDF ou une image, Dossia en fait une copie dans son espace privé ; '
          "l'original reste à son emplacement. Les fichiers ne sont jamais "
          'placés dans un dossier public.',
    ),
    (
      Icons.lock_outline,
      'Chiffrement',
      'Dossia ne chiffre pas lui-même ses données. Elles sont protégées par '
          "l'isolation des applications Android et par le chiffrement de "
          'votre téléphone lorsqu’il est verrouillé. Protégez votre appareil '
          'par un code ou une empreinte.',
    ),
    (
      Icons.backup_outlined,
      'Sauvegardes',
      'La sauvegarde automatique Android est désactivée pour Dossia : vos '
          'données ne sont pas copiées vers un service en ligne. Seules les '
          'sauvegardes manuelles que vous créez existent. Ce sont des fichiers '
          '.zip non chiffrés : conservez-les en lieu sûr.',
    ),
    (
      Icons.warning_amber_rounded,
      'Désinstallation et perte du téléphone',
      'Désinstaller Dossia ou effacer ses données supprime définitivement '
          'tout son contenu. En cas de perte, de vol ou de panne du téléphone, '
          'seule une sauvegarde récente conservée ailleurs permet de '
          'récupérer vos informations.',
    ),
    (
      Icons.notifications_outlined,
      'Rappels',
      'Les rappels sont des notifications locales programmées sur le '
          "téléphone. Leur contenu est masqué sur l'écran de verrouillage.",
    ),
    (
      Icons.analytics_outlined,
      'Aucune mesure d’audience',
      'Dossia n’intègre aucun outil de statistiques, de publicité ou de '
          'suivi.',
    ),
    (
      Icons.verified_outlined,
      'Ce que Dossia ne garantit pas',
      'Dossia enregistre vos déclarations. Il ne vérifie ni l’authenticité '
          'ni la validité de vos documents, et un dossier « Terminé » ne '
          'signifie pas qu’il sera accepté par une administration.',
    ),
    (
      Icons.delete_outline,
      'Supprimer vos données',
      'Vous pouvez supprimer un document, un dossier ou l’ensemble des '
          'données à tout moment depuis les réglages.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Confidentialité et stockage')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _sections.length,
        separatorBuilder: (_, _) => const SizedBox(height: 20),
        itemBuilder: (context, i) {
          final (icon, title, body) = _sections[i];
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Icon(icon, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(title, style: theme.textTheme.titleSmall),
                    ),
                    const SizedBox(height: 4),
                    Text(body, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

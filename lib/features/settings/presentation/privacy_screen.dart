import 'package:flutter/material.dart';

import '../../../core/widgets/common.dart';

/// Explication du stockage local et de la confidentialité (§ 8).
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const _storage = [
    (
      Icons.phone_android_rounded,
      'Tout reste sur ce téléphone',
      'Pas de compte, pas de serveur, pas de connexion Internet. Vos '
          'documents, dossiers et notes sont enregistrés dans l’espace privé '
          'de Dossia, inaccessible aux autres applications.',
    ),
    (
      Icons.attach_file_rounded,
      'Fichiers joints facultatifs',
      'Un document peut être enregistré sans fichier. Si vous joignez un PDF '
          'ou une photo, Dossia en garde une copie privée ; l’original ne '
          'bouge pas. Rien n’est placé dans un dossier public.',
    ),
    (
      Icons.lock_outline_rounded,
      'Chiffrement',
      'Dossia ne chiffre pas lui-même ses données : elles sont protégées par '
          'l’isolation des applications Android et le chiffrement du '
          'téléphone verrouillé. Protégez-le par un code ou une empreinte.',
    ),
    (
      Icons.notifications_none_rounded,
      'Rappels',
      'Notifications programmées sur le téléphone uniquement. Leur contenu '
          'est masqué sur l’écran de verrouillage.',
    ),
  ];

  static const _backups = [
    (
      Icons.cloud_off_outlined,
      'Pas de copie automatique',
      'La sauvegarde automatique d’Android est désactivée pour Dossia : rien '
          'n’est copié vers un service en ligne. Seules les sauvegardes que '
          'vous créez existent ; ce sont des fichiers .zip non chiffrés.',
    ),
    (
      Icons.warning_amber_rounded,
      'Désinstallation et perte',
      'Désinstaller Dossia ou effacer ses données supprime tout son contenu. '
          'Après une perte, un vol ou une panne, seule une sauvegarde gardée '
          'ailleurs permet de récupérer vos informations.',
    ),
  ];

  static const _commitments = [
    (
      Icons.visibility_off_outlined,
      'Aucun suivi',
      'Ni statistiques, ni publicité, ni outil de mesure d’audience.',
    ),
    (
      Icons.verified_outlined,
      'Ce que Dossia ne garantit pas',
      'Dossia enregistre vos déclarations. Il ne vérifie ni l’authenticité '
          'ni la validité de vos documents, et un dossier « Terminé » n’est '
          'pas une garantie d’acceptation par une administration.',
    ),
    (
      Icons.delete_outline_rounded,
      'Vos données, votre choix',
      'Supprimez un document, un dossier ou tout le contenu de Dossia à tout '
          'moment depuis les réglages.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DetailScaffold(
      title: 'Confidentialité',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Confidentialité et stockage',
                    style: theme.textTheme.headlineMedium,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Où sont vos données, et ce que Dossia en fait.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        for (final (title, items) in [
          ('Stockage', _storage),
          ('Sauvegardes', _backups),
          ('Engagements', _commitments),
        ]) ...[
          SliverToBoxAdapter(child: SectionTitle(title)),
          SliverBox(
            child: ListGroup(
              children: [
                for (final (icon, heading, body) in items)
                  _Item(icon: icon, title: heading, body: body),
              ],
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconTile(icon),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

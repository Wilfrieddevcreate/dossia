import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';

/// Premier écran : présentation de l'application (§ 3.1).
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.folder_copy_outlined,
                      color: scheme.onPrimary,
                      size: 34,
                      semanticLabel: 'Logo Dossia',
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('Dossia', style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 12),
                  Text(
                    'Préparez vos dossiers sans oublier une seule pièce.',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Organisez les documents que vous possédez et visualisez '
                    "ce qu'il vous reste à réunir.",
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  const _Point(
                    icon: Icons.inventory_2_outlined,
                    text: 'Quels documents est-ce que je possède déjà ?',
                  ),
                  const _Point(
                    icon: Icons.checklist,
                    text: 'Quelles pièces dois-je réunir pour mon dossier ?',
                  ),
                  const _Point(
                    icon: Icons.pending_actions_outlined,
                    text: 'Quelles pièces me manquent encore ?',
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Aucun compte requis. Vos informations restent sur ce '
                    'téléphone et fonctionnent sans connexion Internet.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () =>
                          context.push('${Routes.inventory}?onboarding=1'),
                      child: const Text('Commencer'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Icon(icon, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );
  }
}

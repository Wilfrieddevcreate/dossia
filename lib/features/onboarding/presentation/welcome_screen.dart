import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/models/document_category.dart';
import '../../../core/widgets/common.dart';

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
          builder: (context, constraints) {
            // L'illustration occupe la hauteur laissée libre par le texte.
            final art = (constraints.maxHeight - 400).clamp(200.0, 440.0);
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                  // Logo en haut, illustration au centre, texte et bouton en bas.
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(
                              Icons.folder_copy_outlined,
                              size: 17,
                              color: scheme.onPrimary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Dossia',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(
                        height: art,
                        child: const ExcludeSemantics(child: _Illustration()),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(
                              'Vos papiers,\nenfin en ordre.',
                              style: theme.textTheme.displaySmall,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Notez les documents que vous avez, préparez vos '
                            'dossiers et voyez d’un coup d’œil ce qu’il manque.',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          SizedBox(
                            height: constraints.maxHeight > 700 ? 40 : 28,
                          ),
                          FilledButton(
                            onPressed: () => context.push(
                              '${Routes.inventory}?onboarding=1',
                            ),
                            child: const Text('Commencer'),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.lock_outline_rounded,
                                size: 15,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  textAlign: TextAlign.center,
                                  'Sans compte · Fonctionne hors ligne',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Pile de documents posée sur une forme douce, avec une coche.
class _Illustration extends StatelessWidget {
  const _Illustration();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = StatusColors.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final s = math.min(c.maxWidth, c.maxHeight);
        final card = Size(s * 0.66, s * 0.32);
        Widget doc(
          Offset offset,
          double angle,
          DocumentCategory category,
          List<double> lines,
        ) {
          return Transform.translate(
            offset: offset * s,
            child: Transform.rotate(
              angle: angle,
              child: _DocCard(size: card, category: category, lines: lines),
            ),
          );
        }

        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Container(
              width: s * 0.84,
              height: s * 0.84,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(s * 0.3),
              ),
            ),
            doc(
              const Offset(-0.08, -0.27),
              -0.07,
              DocumentCategory.education,
              const [0.7, 0.45],
            ),
            doc(const Offset(0.08, 0), 0.05, DocumentCategory.housing, const [
              0.55,
              0.8,
            ]),
            doc(
              const Offset(-0.02, 0.27),
              -0.02,
              DocumentCategory.identity,
              const [0.75, 0.5],
            ),
            Transform.translate(
              offset: Offset(s * 0.29, s * 0.12),
              child: Container(
                width: s * 0.16,
                height: s * 0.16,
                decoration: BoxDecoration(
                  color: status.successIcon,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppPalette.of(context).card,
                    width: s * 0.014,
                  ),
                ),
                child: Icon(
                  Icons.check_rounded,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF0E1311)
                      : Colors.white,
                  size: s * 0.095,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DocCard extends StatelessWidget {
  const _DocCard({
    required this.size,
    required this.category,
    required this.lines,
  });

  final Size size;
  final DocumentCategory category;

  /// Largeurs relatives des lignes de texte simulées.
  final List<double> lines;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final pad = size.height * 0.16;
    return Container(
      width: size.width,
      height: size.height,
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(size.height * 0.2),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          CategoryAvatar(category, size: size.height * 0.42),
          SizedBox(width: pad * 0.8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < lines.length; i++) ...[
                  if (i > 0) SizedBox(height: size.height * 0.09),
                  FractionallySizedBox(
                    widthFactor: lines[i],
                    child: Container(
                      height: size.height * (i == 0 ? 0.1 : 0.08),
                      decoration: BoxDecoration(
                        color: i == 0 ? palette.hairlineStrong : palette.muted,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

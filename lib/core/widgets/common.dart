import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../models/document_category.dart';
import '../models/dossier_category.dart';
import '../utils/errors.dart';
import 'progress_ring.dart';
import 'surfaces.dart';

export 'progress_ring.dart';
export 'surfaces.dart';

/// État vide : une phrase, une explication courte et une action utile.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  icon,
                  size: 34,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}

/// Affiche une valeur asynchrone avec ses états de chargement et d'erreur.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.builder});

  final AsyncValue<T> value;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      data: builder,
      loading: () => const Center(
        child: SizedBox.square(
          dimension: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
      error: (error, _) => ErrorState(error: error),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.cloud_off_rounded,
      title: 'Impossible de charger vos données',
      message:
          "Fermez puis rouvrez l'application. Si le problème persiste, "
          'restaurez une sauvegarde.',
    );
  }
}

/// Titre de section (alias historique de [SectionTitle]).
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing, this.padding});

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => SectionTitle(
    title,
    action: trailing,
    padding: padding ?? const EdgeInsets.fromLTRB(20, 28, 12, 10),
  );
}

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                    minimumSize: const Size(64, 44),
                  )
                : FilledButton.styleFrom(minimumSize: const Size(64, 44)),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// Message bref en bas de l'écran. [onUndo] ajoute un bouton « Annuler ».
void showMessage(
  BuildContext context,
  String message, {
  bool error = false,
  VoidCallback? onUndo,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final scheme = Theme.of(context).colorScheme;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (error) ...[
              Icon(
                Icons.error_outline_rounded,
                color: scheme.onInverseSurface,
                size: 20,
              ),
              const SizedBox(width: 10),
            ],
            Expanded(child: Text(message)),
          ],
        ),
        duration: Duration(seconds: error || onUndo != null ? 5 : 3),
        action: onUndo == null
            ? null
            : SnackBarAction(label: 'Annuler', onPressed: onUndo),
      ),
    );
}

/// Exécute une action d'écriture et affiche un message clair en cas d'échec,
/// sans perdre la saisie de l'utilisateur.
Future<bool> runGuarded(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
  VoidCallback? onUndo,
  String failure = "L'opération n'a pas pu être enregistrée. Réessayez.",
}) async {
  try {
    await action();
    if (success != null && context.mounted) {
      showMessage(context, success, onUndo: onUndo);
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      showMessage(
        context,
        e is UserFacingError ? e.message : failure,
        error: true,
      );
    }
    return false;
  }
}

IconData documentCategoryIcon(DocumentCategory category) => switch (category) {
  DocumentCategory.identity => Icons.badge_outlined,
  DocumentCategory.education => Icons.school_outlined,
  DocumentCategory.professional => Icons.work_outline_rounded,
  DocumentCategory.finance => Icons.account_balance_wallet_outlined,
  DocumentCategory.housing => Icons.home_outlined,
  DocumentCategory.other => Icons.description_outlined,
};

IconData dossierCategoryIcon(DossierCategory? category) => switch (category) {
  DossierCategory.travel => Icons.flight_takeoff_rounded,
  DossierCategory.studies => Icons.school_outlined,
  DossierCategory.scholarship => Icons.workspace_premium_outlined,
  DossierCategory.employment => Icons.work_outline_rounded,
  DossierCategory.administrative => Icons.account_balance_outlined,
  DossierCategory.finance => Icons.payments_outlined,
  DossierCategory.housing => Icons.home_outlined,
  DossierCategory.personal => Icons.person_outline_rounded,
  DossierCategory.other || null => Icons.folder_outlined,
};

/// Icône de catégorie sur un carré arrondi teinté.
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar(this.category, {super.key, this.size = 42});

  final DocumentCategory category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = AppPalette.of(context).categoryTints[category]!;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(size * 0.32),
        ),
        child: Icon(documentCategoryIcon(category), color: fg, size: size * 0.5),
      ),
    );
  }
}

/// Icône simple sur un carré arrondi neutre (réglages, actions).
class IconTile extends StatelessWidget {
  const IconTile(
    this.icon, {
    super.key,
    this.size = 40,
    this.background,
    this.foreground,
  });

  final IconData icon;
  final double size;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background ?? AppPalette.of(context).muted,
          borderRadius: BorderRadius.circular(size * 0.32),
        ),
        child: Icon(
          icon,
          size: size * 0.52,
          color: foreground ?? theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// Barre de progression avec son libellé, pour les listes.
class ProgressLine extends StatelessWidget {
  const ProgressLine({super.key, required this.ratio, required this.label});

  /// `null` lorsque le dossier n'a aucune pièce obligatoire.
  final double? ratio;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: 'Progression : $label',
      excludeSemantics: true,
      child: Row(
        children: [
          Expanded(child: ProgressBar(ratio: ratio, height: 6)),
          const SizedBox(width: 12),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: ratio == null
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// Note discrète (explication, avertissement) sur fond teinté.
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.title,
    this.background,
    this.foreground,
    this.action,
  });

  final String message;
  final String? title;
  final IconData icon;
  final Color? background;
  final Color? foreground;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = foreground ?? theme.colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: background ?? AppPalette.of(context).muted,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: ExcludeSemantics(child: Icon(icon, color: fg, size: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: theme.textTheme.titleSmall?.copyWith(color: fg),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: fg,
                    fontSize: 14,
                  ),
                ),
                if (action != null) ...[const SizedBox(height: 6), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

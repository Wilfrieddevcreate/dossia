import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/document_category.dart';
import '../models/dossier_category.dart';
import '../utils/errors.dart';

/// État vide : une explication et une action utile (§ 5.3).
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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(icon, size: 48, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium,
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
            if (action != null) ...[const SizedBox(height: 20), action!],
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
      loading: () => const Center(child: CircularProgressIndicator()),
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
      icon: Icons.error_outline,
      title: 'Une erreur est survenue',
      message:
          "Les données n'ont pas pu être chargées. Fermez puis rouvrez "
          "l'application. Si le problème persiste, restaurez une sauvegarde.",
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing, this.padding});

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(16, 24, 8, 8),
      // Le bouton d'action passe à la ligne s'il ne tient pas à côté du titre
      // (petit écran ou grande taille de texte).
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.titleMedium),
          ),
          ?trailing,
        ],
      ),
    );
  }
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
                  )
                : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

void showMessage(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final scheme = Theme.of(context).colorScheme;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? scheme.error : null,
        showCloseIcon: true,
      ),
    );
}

/// Exécute une action d'écriture et affiche un message clair en cas d'échec,
/// sans perdre la saisie de l'utilisateur.
Future<bool> runGuarded(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
  String failure = "L'opération n'a pas pu être enregistrée. Réessayez.",
}) async {
  try {
    await action();
    if (success != null && context.mounted) showMessage(context, success);
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
  DocumentCategory.professional => Icons.work_outline,
  DocumentCategory.finance => Icons.account_balance_outlined,
  DocumentCategory.housing => Icons.home_outlined,
  DocumentCategory.other => Icons.description_outlined,
};

IconData dossierCategoryIcon(DossierCategory? category) => switch (category) {
  DossierCategory.travel => Icons.flight_takeoff,
  DossierCategory.studies => Icons.school_outlined,
  DossierCategory.scholarship => Icons.emoji_events_outlined,
  DossierCategory.employment => Icons.work_outline,
  DossierCategory.administrative => Icons.account_balance_outlined,
  DossierCategory.finance => Icons.payments_outlined,
  DossierCategory.housing => Icons.home_outlined,
  DossierCategory.personal => Icons.person_outline,
  DossierCategory.other || null => Icons.folder_outlined,
};

/// Barre de progression d'un dossier, avec texte accessible.
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
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio ?? 0,
                minHeight: 8,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                color: theme.colorScheme.secondary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
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

/// Bloc d'information sobre (explication, avertissement).
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.message,
    this.icon = Icons.info_outline,
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background ?? theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Icon(icon, color: fg, size: 22)),
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
                  const SizedBox(height: 4),
                ],
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                ),
                if (action != null) ...[const SizedBox(height: 8), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

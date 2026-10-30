import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_theme.dart';

/// Bloc blanc arrondi, à peine ombré, posé sur le fond légèrement teinté.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.color,
    this.radius = 20,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final shape = BorderRadius.circular(radius);
    Widget content = Padding(padding: padding ?? EdgeInsets.zero, child: child);
    if (onTap != null) {
      content = InkWell(onTap: onTap, borderRadius: shape, child: content);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: color ?? palette.card,
        borderRadius: shape,
        clipBehavior: Clip.antiAlias,
        child: content,
      ),
    );
  }
}

/// Liste groupée dans un [Panel], séparée par de fins traits en retrait.
class ListGroup extends StatelessWidget {
  const ListGroup({super.key, required this.children, this.dividerIndent = 70});

  final List<Widget> children;

  /// Retrait du séparateur, pour l'aligner sur le texte des lignes.
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(indent: dividerIndent, endIndent: 16),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Ligne de liste standard : visuel, titre, sous-titre, élément de droite.
class AppRow extends StatelessWidget {
  const AppRow({
    super.key,
    required this.title,
    this.leading,
    this.subtitle,
    this.subtitleWidget,
    this.trailing,
    this.onTap,
    this.chevron,
    this.titleStyle,
    this.dense = false,
  });

  final String title;
  final Widget? leading;
  final String? subtitle;
  final Widget? subtitleWidget;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Affiche un chevron à droite ; par défaut lorsque la ligne est cliquable
  /// et sans autre élément à droite.
  final bool? chevron;
  final TextStyle? titleStyle;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showChevron = chevron ?? (onTap != null && trailing == null);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: dense ? 52 : 64),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: dense ? 10 : 14,
          ),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 14)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style:
                          titleStyle ??
                          theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: theme.textTheme.bodySmall),
                    ],
                    if (subtitleWidget != null) ...[
                      const SizedBox(height: 4),
                      subtitleWidget!,
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 10),
                // L'élément de droite ne doit jamais écraser le titre.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.4,
                  ),
                  child: trailing!,
                ),
              ],
              if (showChevron) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Titre de section au-dessus d'un groupe, avec une action facultative.
class SectionTitle extends StatelessWidget {
  const SectionTitle(
    this.title, {
    super.key,
    this.action,
    this.padding = const EdgeInsets.fromLTRB(20, 28, 12, 10),
  });

  final String title;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      // L'action passe à la ligne si elle ne tient pas à côté du titre.
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Semantics(
              header: true,
              child: Text(title, style: theme.textTheme.titleMedium),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// Petit bouton d'action de section (« Tout voir », « Ajouter »).
class SectionAction extends StatelessWidget {
  const SectionAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 10),
    );
    return icon == null
        ? TextButton(onPressed: onPressed, style: style, child: Text(label))
        : TextButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: 20),
            label: Text(label),
          );
  }
}

/// Puces de filtre défilant horizontalement ; la puce choisie est foncée.
class PillTabs<T> extends StatelessWidget {
  const PillTabs({
    super.key,
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final List<T> options;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(labelOf(option)),
                selected: option == selected,
                labelStyle: theme.textTheme.labelMedium?.copyWith(
                  fontSize: 13.5,
                  color: option == selected
                      ? theme.colorScheme.surface
                      : theme.colorScheme.onSurface,
                ),
                onSelected: (_) {
                  HapticFeedback.selectionClick();
                  onSelected(option);
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Champ de recherche en forme de pilule.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search_rounded),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(999)),
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(999)),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(999)),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 1.4,
          ),
        ),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Effacer la recherche',
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
      ),
    );
  }
}

/// Grand titre des écrans principaux, qui glisse dans la barre au défilement.
class LargeTitleAppBar extends StatelessWidget {
  const LargeTitleAppBar({super.key, required this.title, this.actions});

  final String title;
  final List<Widget>? actions;

  static const _toolbar = 60.0;
  static const _extra = 58.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    return SliverAppBar(
      pinned: true,
      toolbarHeight: _toolbar,
      expandedHeight: _toolbar + _extra,
      actions: [...?actions, const SizedBox(width: 8)],
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final top = MediaQuery.paddingOf(context).top;
          final t =
              ((constraints.maxHeight - top - _toolbar) / _extra).clamp(
                0.0,
                1.0,
              );
          double lerp(double a, double b) => a + (b - a) * t;
          return DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: palette.hairline.withValues(alpha: 1 - t),
                ),
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: lerp(canPop ? 60 : 20, 20),
                  right: 112 * (1 - t) + 20 * t,
                  bottom: lerp(17, 10),
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontSize: lerp(19, 30),
                        letterSpacing: lerp(-0.2, -0.6),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Écran de détail : grand en-tête dans le contenu, titre qui apparaît en
/// fondu dans la barre une fois l'en-tête dépassé.
class DetailScaffold extends StatefulWidget {
  const DetailScaffold({
    super.key,
    required this.title,
    required this.slivers,
    this.actions,
    this.floatingActionButton,
    this.bottomBar,
  });

  final String title;
  final List<Widget> slivers;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget? bottomBar;

  @override
  State<DetailScaffold> createState() => _DetailScaffoldState();
}

class _DetailScaffoldState extends State<DetailScaffold> {
  final _controller = ScrollController();
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final scrolled = _controller.hasClients && _controller.offset > 56;
      if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      floatingActionButton: widget.floatingActionButton,
      bottomNavigationBar: widget.bottomBar,
      body: CustomScrollView(
        controller: _controller,
        slivers: [
          SliverAppBar(
            pinned: true,
            toolbarHeight: 60,
            title: AnimatedOpacity(
              opacity: _scrolled ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: Text(widget.title, overflow: TextOverflow.ellipsis),
            ),
            actions: [...?widget.actions, const SizedBox(width: 4)],
            shape: Border(
              bottom: BorderSide(
                color: _scrolled ? palette.hairline : Colors.transparent,
              ),
            ),
          ),
          ...widget.slivers,
          // Laisse la dernière ligne au-dessus de la barre de navigation.
          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.paddingOf(context).bottom),
          ),
        ],
      ),
    );
  }
}

/// Raccourci : un widget dans le flux d'un [CustomScrollView], avec marges.
class SliverBox extends StatelessWidget {
  const SliverBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: padding,
    sliver: SliverToBoxAdapter(child: child),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_theme.dart';
import '../utils/dates.dart';

/// Champ de date facultatif : ouvre le calendrier, peut être effacé.
class DateField extends FormField<DateTime> {
  DateField({
    super.key,
    required String label,
    super.initialValue,
    String? helperText,
    required ValueChanged<DateTime?> onChanged,
    super.validator,
    DateTime? firstDate,
    DateTime? lastDate,
  }) : super(
         builder: (state) {
           final context = state.context;
           final value = state.value;
           Future<void> pick() async {
             final now = DateTime.now();
             final picked = await showDatePicker(
               context: context,
               initialDate: value ?? now,
               firstDate: firstDate ?? DateTime(1950),
               lastDate: lastDate ?? DateTime(now.year + 30),
               helpText: label,
               cancelText: 'Annuler',
               confirmText: 'Valider',
             );
             if (picked != null) {
               state.didChange(dateOnly(picked));
               onChanged(dateOnly(picked));
             }
           }

           return Semantics(
             button: true,
             label: label,
             value: value == null ? 'Non renseignée' : formatLongDate(value),
             child: InkWell(
               onTap: pick,
               borderRadius: BorderRadius.circular(14),
               child: InputDecorator(
                 decoration: InputDecoration(
                   labelText: label,
                   helperText: helperText,
                   errorText: state.errorText,
                   prefixIcon: const Icon(Icons.event_outlined),
                   suffixIcon: value == null
                       ? null
                       : IconButton(
                           tooltip: 'Effacer la date',
                           icon: const Icon(Icons.close_rounded),
                           onPressed: () {
                             state.didChange(null);
                             onChanged(null);
                           },
                         ),
                 ),
                 isEmpty: value == null,
                 child: Text(value == null ? '' : formatLongDate(value)),
               ),
             ),
           );
         },
       );
}

/// Sélecteur de quantité (1 à 99) en forme de pilule.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 99,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;

  void _set(int v) {
    HapticFeedback.selectionClick();
    onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: palette.muted,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Diminuer',
                onPressed: value > min ? () => _set(value - 1) : null,
                icon: const Icon(Icons.remove_rounded),
              ),
              SizedBox(
                width: 32,
                child: Semantics(
                  label: '$label : $value',
                  liveRegion: true,
                  excludeSemantics: true,
                  child: Text(
                    '$value',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Augmenter',
                onPressed: value < max ? () => _set(value + 1) : null,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Espacement vertical standard entre les champs d'un formulaire.
const formGap = SizedBox(height: 14);

/// Bouton d'enregistrement fixé en bas des formulaires.
class FormSaveBar extends StatelessWidget {
  const FormSaveBar({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: AppPalette.of(context).hairline)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: FilledButton(
          onPressed: busy ? null : onPressed,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: busy
                ? const SizedBox.square(
                    key: ValueKey('busy'),
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Text(label, key: const ValueKey('label')),
          ),
        ),
      ),
    );
  }
}

/// Bloc de champs regroupés sous un petit titre, dans un formulaire.
class FormSection extends StatelessWidget {
  const FormSection({super.key, this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 10),
              child: Semantics(
                header: true,
                child: Text(
                  title!,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) formGap,
            children[i],
          ],
        ],
      ),
    );
  }
}

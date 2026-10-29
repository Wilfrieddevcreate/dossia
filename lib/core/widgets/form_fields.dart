import 'package:flutter/material.dart';

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
               borderRadius: BorderRadius.circular(12),
               child: InputDecorator(
                 decoration: InputDecoration(
                   labelText: label,
                   helperText: helperText,
                   errorText: state.errorText,
                   suffixIcon: value == null
                       ? const Icon(Icons.calendar_today_outlined)
                       : IconButton(
                           tooltip: 'Effacer la date',
                           icon: const Icon(Icons.clear),
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

/// Sélecteur de quantité (1 à 99).
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
        IconButton.outlined(
          tooltip: 'Diminuer',
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 48,
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
        IconButton.outlined(
          tooltip: 'Augmenter',
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

/// Espacement vertical standard entre les champs d'un formulaire.
const formGap = SizedBox(height: 16);

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
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(label),
      ),
    );
  }
}

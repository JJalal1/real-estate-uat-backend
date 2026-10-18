import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A form value with an accessible, scrollable selection sheet.
class AppSelectField<T> extends StatelessWidget {
  const AppSelectField({required this.items, required this.onChanged, this.value,
    this.decoration = const InputDecoration(), this.hint, this.isExpanded = true,
    this.validator, this.onSaved, super.key});
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final InputDecoration decoration;
  final Widget? hint;
  final bool isExpanded;
  final FormFieldValidator<T>? validator;
  final FormFieldSetter<T>? onSaved;

  @override
  Widget build(BuildContext context) => FormField<T>(
    key: ValueKey(value), initialValue: value, enabled: onChanged != null, validator: validator, onSaved: onSaved,
    builder: (field) {
      final selected = items.where((item) => item.value == field.value).firstOrNull;
      Future<void> choose() async {
        final choice = await showModalBottomSheet<_Selection<T>>(context: context, isScrollControlled: true,
          useSafeArea: true, showDragHandle: true, builder: (sheet) => Directionality(textDirection: Directionality.of(context),
            child: ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * .72),
              child: Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(decoration.labelText ?? 'اختر من القائمة', style: Theme.of(sheet).textTheme.titleLarge),
                  const SizedBox(height: 6), Text('اختر الخيار المناسب', style: Theme.of(sheet).textTheme.bodySmall),
                  const SizedBox(height: 16),
                  Flexible(child: ListView.separated(shrinkWrap: true, itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (_, index) {
                      final item = items[index], active = item.value == field.value;
                      final scheme = Theme.of(sheet).colorScheme;
                      return Material(color: active ? scheme.primaryContainer : scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16), child: InkWell(
                          key: ValueKey('select-option-${item.value}'), borderRadius: BorderRadius.circular(16),
                          onTap: !item.enabled ? null : () => Navigator.of(sheet).pop(_Selection(item.value)),
                          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            child: Row(children: [Expanded(child: DefaultTextStyle.merge(style: TextStyle(
                              color: item.enabled ? scheme.onSurface : scheme.onSurfaceVariant, fontWeight: active ? FontWeight.w600 : FontWeight.w400),
                              child: item.child)), const SizedBox(width: 12), Icon(active ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                              size: 22, color: active ? scheme.primary : scheme.outline)]))));
                    })),
                ])))));
        if (choice == null || !context.mounted) return;
        field.didChange(choice.value); onChanged?.call(choice.value);
      }
      return Semantics(button: true, enabled: onChanged != null,
        child: Material(color: Colors.transparent, child: InkWell(onTap: onChanged == null ? null : choose,
          borderRadius: BorderRadius.circular(16), child: InputDecorator(
            decoration: decoration.copyWith(enabled: onChanged != null, errorText: decoration.errorText ?? field.errorText,
              floatingLabelBehavior: FloatingLabelBehavior.always),
            isEmpty: false, child: ConstrainedBox(constraints: BoxConstraints(minHeight: math.max(20, MediaQuery.textScalerOf(context).scale(16))),
              child: Row(children: [Expanded(child: selected?.child ?? hint ?? const Text('اختر…')),
                const SizedBox(width: 8), Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: Theme.of(context).colorScheme.onSurfaceVariant)])))));
    });
}

class _Selection<T> {
  const _Selection(this.value);
  final T? value;
}

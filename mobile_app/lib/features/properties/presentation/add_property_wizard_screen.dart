import 'package:flutter/material.dart';
import '../domain/property_details.dart';
import 'listing_draft_entry_screen.dart';

/// One entry for all existing Add Property actions. A previously chosen method
/// enters recovery directly; generic actions choose their method first.
class AddPropertyWizardScreen extends StatefulWidget {
  const AddPropertyWizardScreen({super.key, this.existingProperty, this.startWithAssistant, this.showSavedDrafts = false});
  final PropertyDetails? existingProperty;
  final bool? startWithAssistant;
  final bool showSavedDrafts;
  @override
  State<AddPropertyWizardScreen> createState() => _AddPropertyWizardState();
}
class _AddPropertyWizardState extends State<AddPropertyWizardScreen> {
  late bool? _assistant = widget.existingProperty != null || widget.showSavedDrafts ? false : widget.startWithAssistant;
  @override
  Widget build(BuildContext context) {
    if (_assistant != null) {
      return ListingDraftEntryScreen(existingProperty: widget.existingProperty,
        startWithAssistant: _assistant!, showSavedDrafts: widget.showSavedDrafts);
    }
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(backgroundColor: Colors.transparent,
      body: Center(child: Dialog(key: const ValueKey('listing-method-choice'), child: Padding(padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('إضافة عقار', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 12),
          FilledButton.icon(key: const ValueKey('listing-method-ai'), onPressed: () => setState(() => _assistant = true),
            icon: const Icon(Icons.auto_awesome_outlined), label: const Text('ذكاء اصطناعي')),
          OutlinedButton.icon(key: const ValueKey('listing-method-manual'), onPressed: () => setState(() => _assistant = false),
            icon: const Icon(Icons.edit_note_outlined), label: const Text('تعبئة يدوية')),
          TextButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('رجوع')),
        ]))))));
  }
}

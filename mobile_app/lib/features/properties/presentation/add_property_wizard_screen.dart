import 'package:flutter/material.dart';

import '../domain/property_details.dart';
import 'listing_editor_screen.dart';

/// Compatibility entry point retained for existing routes and deep links.
///
/// The active advertiser journey is implemented by [ListingEditorScreen].
class AddPropertyWizardScreen extends StatelessWidget {
  const AddPropertyWizardScreen({
    super.key,
    this.existingProperty,
  });

  final PropertyDetails? existingProperty;

  @override
  Widget build(BuildContext context) {
    return ListingEditorScreen(existingProperty: existingProperty);
  }
}

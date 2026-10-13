import 'package:flutter/material.dart';

import '../domain/property_details.dart';
import 'listing_editor_screen.dart';
import 'personal_listing_creation_gate.dart';

/// Compatibility entry point retained for existing routes and deep links.
///
/// Phase 2 moved the active implementation to [ListingEditorScreen], where
/// Save Draft, Preview, and Submit for Review are explicit separate actions.
class AddPropertyWizardScreen extends StatelessWidget {
  const AddPropertyWizardScreen({
    super.key,
    this.existingProperty,
  });

  final PropertyDetails? existingProperty;

  @override
  Widget build(BuildContext context) {
    final editor = ListingEditorScreen(existingProperty: existingProperty);
    return existingProperty == null ? PersonalListingCreationGate(child: editor) : editor;
  }
}

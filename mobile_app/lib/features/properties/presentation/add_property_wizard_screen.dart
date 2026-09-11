import 'package:flutter/material.dart';

import '../domain/property_details.dart';
import 'advertiser_listing_journey_screen.dart';

/// Compatibility entry point retained for existing routes and deep links.
class AddPropertyWizardScreen extends StatelessWidget {
  const AddPropertyWizardScreen({
    super.key,
    this.existingProperty,
  });

  final PropertyDetails? existingProperty;

  @override
  Widget build(BuildContext context) {
    return AdvertiserListingJourneyScreen(existingProperty: existingProperty);
  }
}

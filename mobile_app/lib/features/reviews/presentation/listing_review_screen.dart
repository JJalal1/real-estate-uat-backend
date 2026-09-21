import 'package:flutter/material.dart';

import 'listing_review_workspace_screen.dart';

/// Compatibility entry point retained for the existing admin route.
/// The active Phase 2 review experience is evidence-first and requires support
/// claim ownership before sensitive review decisions.
class ListingReviewScreen extends StatelessWidget {
  const ListingReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ListingReviewWorkspaceScreen();
  }
}

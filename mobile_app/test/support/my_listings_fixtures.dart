import 'package:real_estate_mobile/features/properties/data/my_listings_pages.dart';
import 'package:real_estate_mobile/features/properties/domain/my_listings_page.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';

/// Fixed, complete workspace data for existing card/layout regression tests.
MyListingsPagesController fixedMyListings(List<PropertyDetails> items) =>
  MyListingsPagesController(
    load: (page) async => MyListingsPage(items: items, currentPage: page,
      lastPage: 1, total: items.length),
    signedIn: true, isCurrent: () => true, onSessionChange: () {},
  );

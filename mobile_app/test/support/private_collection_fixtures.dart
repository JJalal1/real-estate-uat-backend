import 'package:real_estate_mobile/features/account/data/private_collection.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';

PrivateCollectionController<PropertySummary> fixedFavoritePages(List<PropertySummary> items) =>
  PrivateCollectionController(load: (_) async => PrivateCollectionPage(
    items: items, currentPage: 1, lastPage: 1, total: items.length),
    idOf: (PropertySummary item) => item.id);

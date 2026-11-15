import 'property_details.dart';

class MyListingsPage {
  const MyListingsPage({required this.items, required this.currentPage,
    required this.lastPage, required this.total});

  final List<PropertyDetails> items;
  final int currentPage;
  final int lastPage;
  final int total;
  bool get hasMore => currentPage < lastPage;
}

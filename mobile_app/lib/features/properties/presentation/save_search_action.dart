import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../account/data/auth_controller.dart';
import '../../account/data/auth_return_intent.dart';
import 'saved_search_builder_screen.dart';

Future<void> saveSearchFilters(BuildContext context, WidgetRef ref, Map<String, dynamic> filters, {String returnLocation = '/smart-search'}) async {
  if (filters.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حدد شروط بحثك أولًا.')));
    return;
  }
  if (ref.read(authControllerProvider).asData?.value == null) {
    setAuthReturnLocation(ref, returnLocation);
    await context.push('/auth');
    if (!context.mounted || ref.read(authControllerProvider).asData?.value == null) return;
  }
  if (ref.read(authControllerProvider).asData?.value?.isActive != true) {
    setAuthReturnLocation(ref, returnLocation);
    await context.push('/verify-phone');
    if (!context.mounted || ref.read(authControllerProvider).asData?.value?.isActive != true) return;
  }
  if (!context.mounted) return;
  final saved = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
    builder: (_) => SavedSearchBuilderScreen(initialFilters: filters, fixedFilters: true)));
  if (context.mounted && saved == true) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ البحث بشروطه وتنبيهاته.')));
}

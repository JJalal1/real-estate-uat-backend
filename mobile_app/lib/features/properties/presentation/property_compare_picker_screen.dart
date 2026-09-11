import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../data/favorites_repository.dart';
import '../domain/property_marker.dart';
import 'property_compare_screen.dart';

class PropertyComparePickerScreen extends ConsumerStatefulWidget {
  const PropertyComparePickerScreen({super.key});

  @override
  ConsumerState<PropertyComparePickerScreen> createState() =>
      _PropertyComparePickerScreenState();
}

class _PropertyComparePickerScreenState
    extends ConsumerState<PropertyComparePickerScreen> {
  final Set<int> _selected = <int>{};

  @override
  Widget build(BuildContext context) {
    final favorites = ref.watch(favoritePropertiesProvider);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppAppBar(title: 'مقارنة العقارات (${_selected.length}/4)'),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            elevation: AppElevation.floating,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.s12),
              child: AppButton(
                label: _selected.length < 2
                    ? 'اختر عقارين على الأقل'
                    : 'مقارنة ${_selected.length} عقارات',
                icon: Icons.compare_arrows_rounded,
                onPressed: _selected.length < 2 ? null : _openComparison,
                expand: true,
              ),
            ),
          ),
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(favoritePropertiesProvider);
            await ref.read(favoritePropertiesProvider.future);
          },
          child: favorites.when(
            loading: () => ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppLayout.compactPageGutter),
              itemCount: 3,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.s12),
              itemBuilder: (_, __) => const AppSkeleton(height: 280),
            ),
            error: (error, _) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * .7,
                  child: AppErrorState(
                    message: friendlyApiError(error),
                    onRetry: () => ref.invalidate(favoritePropertiesProvider),
                  ),
                ),
              ],
            ),
            data: (items) {
              if (items.isEmpty) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: AppSpacing.s40),
                    AppEmptyState(
                      title: 'لا توجد عقارات في المفضلة',
                      message:
                          'احفظ عقارين أو أكثر في المفضلة أولاً، ثم ارجع للمقارنة.',
                      icon: Icons.compare_arrows_rounded,
                    ),
                  ],
                );
              }
              return ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppLayout.compactPageGutter,
                  AppSpacing.s12,
                  AppLayout.compactPageGutter,
                  112,
                ),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.s12),
                itemBuilder: (context, index) {
                  final property = items[index];
                  final selected = _selected.contains(property.id);
                  return AppPropertyCard(
                    title: property.title,
                    price: _formatPrice(property.price),
                    currency: property.currency,
                    imageUrl: property.mainImage,
                    location: property.address,
                    purposeLabel:
                        property.purpose == 'rent' ? 'للإيجار' : 'للبيع',
                    facts: _facts(property),
                    trailing: Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    onTap: () => _toggle(property.id),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _toggle(int propertyId) {
    setState(() {
      if (_selected.remove(propertyId)) return;
      if (_selected.length >= 4) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يمكن مقارنة أربعة عقارات كحد أقصى.')),
        );
        return;
      }
      _selected.add(propertyId);
    });
  }

  Future<void> _openComparison() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PropertyCompareScreen(
          propertyIds: _selected.toList(growable: false),
        ),
      ),
    );
  }

  List<AppPropertyFact> _facts(PropertyMarker property) => [
        if (property.areaM2 != null)
          AppPropertyFact(
            icon: Icons.square_foot,
            label: '${property.areaM2} م²',
          ),
        if (property.bedrooms != null)
          AppPropertyFact(
            icon: Icons.bed_outlined,
            label: '${property.bedrooms} غرف',
          ),
        if (property.bathrooms != null)
          AppPropertyFact(
            icon: Icons.bathtub_outlined,
            label: '${property.bathrooms} حمام',
          ),
      ];

  String _formatPrice(double value) {
    final rounded = value.round().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < rounded.length; i++) {
      if (i > 0 && (rounded.length - i) % 3 == 0) buffer.write(',');
      buffer.write(rounded[i]);
    }
    return buffer.toString();
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../data/favorites_repository.dart';
import '../domain/property_marker.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritePropertiesProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: const AppAppBar(title: 'المفضلة'),
        body: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(favoritePropertiesProvider);
            await ref.read(favoritePropertiesProvider.future);
          },
          child: favorites.when(
            loading: () => ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppLayout.compactPageGutter,
                AppSpacing.s12,
                AppLayout.compactPageGutter,
                AppSpacing.s32,
              ),
              itemCount: 4,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.s12),
              itemBuilder: (_, __) => const AppSkeleton(height: 300),
            ),
            error: (error, _) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.7,
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
                      title: 'لا توجد عقارات محفوظة',
                      message: 'اضغط على رمز القلب في أي عقار ليظهر هنا ويظل محفوظاً في حسابك.',
                      icon: Icons.favorite_border_rounded,
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
                  AppSpacing.s32,
                ),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.s12),
                itemBuilder: (context, index) {
                  final property = items[index];
                  return AppPropertyCard(
                    title: property.title,
                    price: _formatPrice(property.price),
                    currency: property.currency,
                    imageUrl: property.mainImage,
                    location: property.address,
                    purposeLabel: _purposeLabel(property.purpose),
                    facts: _facts(property),
                    trailing: IconButton.filledTonal(
                      tooltip: 'إزالة من المفضلة',
                      onPressed: () => _remove(context, ref, property.id),
                      icon: Icon(
                        Icons.favorite_rounded,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    onTap: () => context.push('/properties/${property.id}'),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, int propertyId) async {
    try {
      await ref.read(favoritesRepositoryProvider).remove(propertyId);
      ref.read(favoriteDataRevisionProvider.notifier).state++;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت إزالة العقار من المفضلة.')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyApiError(error))),
      );
    }
  }

  List<AppPropertyFact> _facts(PropertyMarker property) {
    return [
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
  }

  String _purposeLabel(String? purpose) => purpose == 'rent' ? 'للإيجار' : 'للبيع';

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

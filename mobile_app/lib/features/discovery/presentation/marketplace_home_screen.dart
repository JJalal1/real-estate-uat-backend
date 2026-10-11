import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/marketplace_layout.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/marketplace_components.dart';
import '../../map/presentation/map_screen.dart';
import '../../properties/domain/property_marker.dart';

// The original map's initial area, shown explicitly rather than claiming that
// these results are the device's current location or a new nationwide feed.
const homeDiscoveryQuery = NearbyQuery(center: LatLng(15.3694, 44.1910));

class MarketplaceHomeScreen extends ConsumerWidget {
  const MarketplaceHomeScreen({this.showAdvertiserActions = false, super.key});

  final bool showAdvertiserActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final properties = ref.watch(nearbyPropertiesProvider(homeDiscoveryQuery));
    void openMap() => context.push('/property-market');

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            try {
              final refreshed = ref.refresh(
                nearbyPropertiesProvider(homeDiscoveryQuery).future,
              );
              await refreshed;
            } catch (_) {
              // The provider exposes the error and its retry action below.
            }
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: MarketplaceLayout.contentMaxWidth,
                ),
                child: Padding(
                  padding: const EdgeInsetsDirectional.all(
                    MarketplaceLayout.pageGutter,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.s12),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(
                                AppRadii.control,
                              ),
                            ),
                            child: Icon(
                              Icons.home_work_outlined,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s12),
                          Expanded(
                            child: Text(
                              'العقارات',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          AppIconButton(
                            icon: Icons.notifications_none_outlined,
                            tooltip: 'الإشعارات',
                            onPressed: () => context.push('/notifications'),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s24),
                      Container(
                        padding: const EdgeInsetsDirectional.all(AppSpacing.s24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: AlignmentDirectional.topStart,
                            end: AlignmentDirectional.bottomEnd,
                            colors: [scheme.primary, AppTheme.brandStrong],
                          ),
                          borderRadius: BorderRadius.circular(
                            MarketplaceLayout.heroRadius,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.other_houses_outlined,
                              size: 36,
                              color: scheme.onPrimary,
                            ),
                            const SizedBox(height: AppSpacing.s12),
                            Text(
                              'عقارك القادم يبدأ هنا',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(color: scheme.onPrimary),
                            ),
                            const SizedBox(height: AppSpacing.s8),
                            Text(
                              'استكشف العقارات على الخريطة، واحتفظ بما يناسبك.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: scheme.onPrimary),
                            ),
                            const SizedBox(height: AppSpacing.s20),
                            MarketplaceSearchEntry(
                              key: const ValueKey('home-search'),
                              onPressed: openMap,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: MarketplaceLayout.sectionGap),
                      Text(
                        'استكشف بطريقتك',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.s12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final largeText =
                              MediaQuery.textScalerOf(context).scale(14) > 22;
                          final columns = largeText ? 2 : 3;
                          final width = (constraints.maxWidth -
                                  MarketplaceLayout.itemGap * (columns - 1)) /
                              columns;
                          return Wrap(
                            spacing: MarketplaceLayout.itemGap,
                            runSpacing: MarketplaceLayout.itemGap,
                            children: [
                              SizedBox(
                                width: width,
                                child: MarketplaceActionTile(
                                  key: const ValueKey('home-map'),
                                  label: 'الخريطة',
                                  icon: Icons.map_outlined,
                                  onPressed: openMap,
                                ),
                              ),
                              SizedBox(
                                width: width,
                                child: MarketplaceActionTile(
                                  key: const ValueKey('home-favorites'),
                                  label: 'المفضلة',
                                  icon: Icons.favorite_border,
                                  onPressed: () => context.push('/favorites'),
                                ),
                              ),
                              SizedBox(
                                width: width,
                                child: MarketplaceActionTile(
                                  key: const ValueKey('home-compare'),
                                  label: 'المقارنة',
                                  icon: Icons.compare_arrows,
                                  onPressed: () =>
                                      context.push('/favorites?compare=1'),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: MarketplaceLayout.sectionGap),
                      MarketplaceSectionHeader(
                        title: 'عقارات في صنعاء',
                        actionLabel: 'فتح الخريطة',
                        onPressed: openMap,
                      ),
                      Text(
                        'افتح الخريطة للاستكشاف حسب موقعك.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.s16),
                      properties.when(
                        loading: () => const _HomeLoading(),
                        error: (error, _) => AppErrorState(
                          message: friendlyApiError(error),
                          onRetry: () => ref.invalidate(
                            nearbyPropertiesProvider(homeDiscoveryQuery),
                          ),
                        ),
                        data: (items) => items.isEmpty
                            ? AppEmptyState(
                                title: 'لا توجد عقارات في هذا النطاق',
                                message: 'يمكنك استكشاف مناطق أخرى على الخريطة.',
                                icon: Icons.home_work_outlined,
                                actionLabel: 'استكشاف الخريطة',
                                onAction: openMap,
                              )
                            : Column(
                                children: [
                                  for (final property in items.take(4))
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: AppSpacing.s16,
                                      ),
                                      child: _HomeProperty(property: property),
                                    ),
                                ],
                              ),
                      ),
                      if (showAdvertiserActions) ...[
                        const SizedBox(height: AppSpacing.s20),
                        AppSurface(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'أضف عقارك إلى السوق',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: AppSpacing.s8),
                              const Text(
                                'تابع إعلانك من المسودة حتى المراجعة والنشر.',
                              ),
                              const SizedBox(height: AppSpacing.s16),
                              AppButton(
                                label: 'إضافة عقار',
                                icon: Icons.add_home_outlined,
                                expand: true,
                                onPressed: () => context.push('/add-property'),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.s12),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeProperty extends StatelessWidget {
  const _HomeProperty({required this.property});

  final PropertyMarker property;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppPropertyCard(
            key: ValueKey('home-property-${property.id}'),
            title: property.title,
            price: property.price.toStringAsFixed(0),
            currency: property.currency,
            imageUrl: property.mainImage,
            location: property.address,
            purposeLabel: switch (property.purpose) {
              'sale' => 'للبيع',
              'rent' => 'للإيجار',
              _ => null,
            },
            onTap: () => context.push('/properties/${property.id}'),
          ),
          if (property.priceDisplayNote?.trim().isNotEmpty == true)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: AppSpacing.s12,
                end: AppSpacing.s12,
                top: AppSpacing.s8,
              ),
              child: Text(
                property.priceDisplayNote!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      );
}

class _HomeLoading extends StatelessWidget {
  const _HomeLoading();

  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSkeleton(height: 160),
          SizedBox(height: AppSpacing.s12),
          AppSkeleton(height: 20, width: 200),
          SizedBox(height: AppSpacing.s8),
          AppSkeleton(height: 16, width: 140),
          SizedBox(height: AppSpacing.s24),
        ],
      );
}

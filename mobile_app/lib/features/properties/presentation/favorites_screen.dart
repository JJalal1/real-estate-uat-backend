import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../data/favorites_repository.dart';
import '../domain/property_marker.dart';
import 'property_compare_screen.dart';
import 'property_compare_actions.dart';

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key, this.startInCompareMode = false});

  final bool startInCompareMode;

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  Set<int> get _selected => ref.read(propertyCompareSelectionProvider);
  late bool _compareMode;

  @override
  void initState() {
    super.initState();
    _compareMode = widget.startInCompareMode;
  }

  @override
  Widget build(BuildContext context) {
    final favorites = ref.watch(favoritePropertiesProvider);
    ref.watch(propertyCompareSelectionProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppAppBar(
          title: _compareMode ? 'اختر للمقارنة (${_selected.length}/2)' : 'المفضلة',
          actions: [
            if (_compareMode)
              AppIconButton(
                icon: Icons.close_rounded,
                tooltip: 'إلغاء المقارنة',
                onPressed: _exitCompareMode,
              )
            else
              AppIconButton(
                icon: Icons.compare_arrows_rounded,
                tooltip: 'مقارنة العقارات',
                onPressed: () => setState(() => _compareMode = true),
              ),
          ],
        ),
        bottomNavigationBar: _compareMode
            ? SafeArea(
                top: false,
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.all(AppSpacing.s12),
                    child: AppButton(
                      label: _selected.length < 2
                          ? 'اختر العقار الثاني'
                          : 'قارن العقارين',
                      icon: Icons.compare_arrows_rounded,
                      onPressed: _selected.length < 2 ? null : _openComparison,
                      expand: true,
                    ),
                  ),
                ),
              )
            : const SafeArea(top: false, child: Padding(padding: EdgeInsets.all(16), child: PropertyCompareTray())),
        body: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(favoritePropertiesProvider);
            try { await ref.read(favoritePropertiesProvider.future); } catch (_) { /* The state renders failure and retry. */ }
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
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.s12),
                itemBuilder: (context, index) {
                  final property = items[index];
                  final selected = _selected.contains(property.id);
                  return Stack(
                    children: [
                      AppPropertyCard(horizontal: true,
                        categoryLabel: ebrokerPropertyTypeLabel(property.type),
                  title: property.title,
                        price: _formatPrice(property.purpose == 'rent' ? property.monthlyRent ?? property.price : property.price),
                        priceSuffix: property.purpose == 'rent' && property.monthlyRent != null ? 'شهريًا' : null,
                        currency: property.currency,
                        imageUrl: property.mainImage, imageUrls: property.imageUrls, isSpotlight: property.isSpotlight,
                        location: property.address,
                        purposeLabel: _purposeLabel(property.purpose),
                        facts: _facts(property),
                        action: PropertyCompareAction(propertyId: property.id),
                        trailing: IconButton(
                                tooltip: 'إزالة من المفضلة',
                                onPressed: () => _remove(context, property.id),
                                style: IconButton.styleFrom(minimumSize: const Size(48, 48), shape: const CircleBorder()),
                                icon: EbrokerIcon(
                                  Icons.favorite_rounded,
                                  size: 19,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                        onTap: _compareMode
                            ? () => _toggleSelection(property.id)
                            : () => context.push('/properties/${property.id}'),
                      ),
                      if (_compareMode && selected)
                        PositionedDirectional(
                          top: AppSpacing.s8,
                          start: AppSpacing.s8,
                          child: AppStatusBadge(
                            label: '${_selectionPosition(property.id)}',
                            tone: AppStatusTone.success,
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _toggleSelection(int propertyId) {
    if (!ref.read(propertyCompareSelectionProvider.notifier).toggle(propertyId)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('المقارنة بين عقارين فقط. أزل أحدهما لإضافة آخر.')));
    }
  }

  int _selectionPosition(int propertyId) => _selected.toList().indexOf(propertyId) + 1;

  void _exitCompareMode() {
    setState(() {
      _compareMode = false;
      ref.read(propertyCompareSelectionProvider.notifier).clear();
    });
  }

  Future<void> _openComparison() async {
    final ids = _selected.toList(growable: false);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PropertyCompareScreen(propertyIds: ids),
      ),
    );
  }

  Future<void> _remove(BuildContext context, int propertyId) async {
    try {
      await ref.read(favoritesRepositoryProvider).remove(propertyId);
      if (!mounted) return;
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
      if (property.areaM2 != null && property.areaM2! > 0)
        AppPropertyFact(
          icon: Icons.square_foot,
          label: '${arabicDigits('${property.areaM2}')} م²',
        ),
      if (property.bedrooms != null && property.bedrooms! > 0)
        AppPropertyFact(
          icon: Icons.bed_outlined,
          label: '${arabicDigits('${property.bedrooms}')} غرف',
        ),
      if (property.bathrooms != null && property.bathrooms! > 0)
        AppPropertyFact(
          icon: Icons.bathtub_outlined,
          label: '${arabicDigits('${property.bathrooms}')} حمام',
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

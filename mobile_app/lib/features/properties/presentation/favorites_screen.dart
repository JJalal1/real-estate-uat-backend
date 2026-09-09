import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../data/favorites_repository.dart';
import '../domain/property_marker.dart';
import 'property_compare_screen.dart';

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  final Set<int> _selected = <int>{};
  bool _compareMode = false;

  @override
  Widget build(BuildContext context) {
    final favorites = ref.watch(favoritePropertiesProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppAppBar(
          title: _compareMode ? 'اختر للمقارنة (${_selected.length}/4)' : 'المفضلة',
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
                  elevation: AppElevation.floating,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.all(AppSpacing.s12),
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
              )
            : null,
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
                  final selected = _selected.contains(property.id);
                  return Stack(
                    children: [
                      AppPropertyCard(
                        title: property.title,
                        price: _formatPrice(property.price),
                        currency: property.currency,
                        imageUrl: property.mainImage,
                        location: property.address,
                        purposeLabel: _purposeLabel(property.purpose),
                        facts: _facts(property),
                        trailing: _compareMode
                            ? Icon(
                                selected
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                color: selected
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.onSurfaceVariant,
                              )
                            : IconButton.filledTonal(
                                tooltip: 'إزالة من المفضلة',
                                onPressed: () => _remove(context, property.id),
                                icon: Icon(
                                  Icons.favorite_rounded,
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
    setState(() {
      if (_selected.contains(propertyId)) {
        _selected.remove(propertyId);
        return;
      }
      if (_selected.length >= 4) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يمكن مقارنة أربعة عقارات كحد أقصى.')),
        );
        return;
      }
      _selected.add(propertyId);
    });
  }

  int _selectionPosition(int propertyId) => _selected.toList().indexOf(propertyId) + 1;

  void _exitCompareMode() {
    setState(() {
      _compareMode = false;
      _selected.clear();
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

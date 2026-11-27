import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../account/data/private_collection.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../data/favorites_repository.dart';
import '../domain/property_details.dart';
import 'property_summary_card.dart';
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
    final favorites = ref.watch(favoritePagesProvider);
    final controller = ref.read(favoritePagesProvider.notifier);
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
          onRefresh: controller.refresh,
          child: _content(favorites, controller),
        ),
      ),
    );
  }

  Widget _content(PrivateCollectionState<PropertySummary> state,
      PrivateCollectionController<PropertySummary> controller) {
    if (state.items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (state.loading) ...[
            for (var i = 0; i < 4; i++) const Padding(
              padding: EdgeInsets.all(12), child: AppSkeleton(height: 300)),
          ] else if (state.error != null) AppErrorState(
            message: friendlyApiError(state.error!), onRetry: controller.refresh,
          ) else const Padding(padding: EdgeInsets.only(top: AppSpacing.s40),
            child: AppEmptyState(
              title: 'لا توجد عقارات محفوظة',
              message: 'اضغط على رمز القلب في أي عقار ليظهر هنا ويظل محفوظاً في حسابك.',
              icon: Icons.favorite_border_rounded,
            )),
        ],
      );
    }
    final hasHeader = state.loading || state.error != null;
    final hasFooter = state.page!.hasMore;
    return ListView.separated(
      key: ObjectKey(controller),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: AppLayout.compactPageGutter, vertical: 16),
      itemCount: state.items.length + (hasHeader ? 1 : 0) + (hasFooter ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.s12),
      itemBuilder: (context, index) {
        if (hasHeader && index == 0) {
          return AppRefreshStatus(loading: state.loading,
            error: state.error == null ? null : friendlyApiError(state.error!),
            onRetry: controller.refresh);
        }
        final itemIndex = index - (hasHeader ? 1 : 0);
        if (itemIndex == state.items.length) {
          if (state.loadingMore || state.pageError != null) {
            return AppRefreshStatus(key: const ValueKey('favorites-page-status'),
              loading: state.loadingMore,
              error: state.pageError == null ? null : friendlyApiError(state.pageError!),
              onRetry: controller.loadMore);
          }
          return TextButton.icon(key: const ValueKey('favorites-more'),
            onPressed: state.loading || state.error != null ? null : controller.loadMore,
            icon: const Icon(Icons.expand_more), label: const Text('المزيد من المفضلة'));
        }
        final property = state.items[itemIndex];
        final selected = _selected.contains(property.id);
        return Stack(
          children: [
            PropertySummaryCard(
              key: ValueKey('favorite-listing-${property.id}'),
              property: property,
              compact: true,
              knownFavorite: true,
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
}

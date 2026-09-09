import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../data/saved_search_repository.dart';
import '../domain/property_marker.dart';
import '../domain/saved_property_search.dart';

class SavedSearchesScreen extends ConsumerWidget {
  const SavedSearchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searches = ref.watch(savedSearchesProvider);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: const AppAppBar(title: 'البحوث المحفوظة'),
        body: searches.when(
          loading: () => const _SavedSearchSkeleton(),
          error: (error, _) => AppErrorState(
            message: friendlyApiError(error),
            onRetry: () => ref.invalidate(savedSearchesProvider),
          ),
          data: (items) {
            if (items.isEmpty) {
              return const AppEmptyState(
                title: 'ما حفظت أي بحث حتى الآن',
                message: 'اضبط الفلاتر التي تناسبك من شاشة العقارات ثم اختر «حفظ البحث».',
                icon: Icons.manage_search_outlined,
              );
            }
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(savedSearchesProvider);
                await ref.read(savedSearchesProvider.future);
              },
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppLayout.compactPageGutter,
                  AppSpacing.s16,
                  AppLayout.compactPageGutter,
                  AppSpacing.s40,
                ),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.s12),
                itemBuilder: (context, index) => _SavedSearchCard(search: items[index]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SavedSearchCard extends ConsumerStatefulWidget {
  const _SavedSearchCard({required this.search});
  final SavedPropertySearch search;

  @override
  ConsumerState<_SavedSearchCard> createState() => _SavedSearchCardState();
}

class _SavedSearchCardState extends ConsumerState<_SavedSearchCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final search = widget.search;
    final scheme = Theme.of(context).colorScheme;
    return AppSurface(
      padding: const EdgeInsetsDirectional.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadii.control),
                ),
                child: Icon(Icons.saved_search_rounded, color: scheme.primary),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(search.name, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      '${search.matchingCount} عقار مطابق الآن',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                enabled: !_busy,
                tooltip: 'إعدادات البحث',
                onSelected: _handleMenu,
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'instant', child: Text('تنبيه فوري')),
                  const PopupMenuItem(value: 'daily', child: Text('ملخص يومي')),
                  const PopupMenuItem(value: 'off', child: Text('إيقاف التنبيهات')),
                  const PopupMenuDivider(),
                  const PopupMenuItem(value: 'delete', child: Text('حذف البحث')),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              AppStatusBadge(
                label: savedSearchAlertLabel(search.alertFrequency),
                tone: search.alertFrequency == 'off'
                    ? AppStatusTone.neutral
                    : AppStatusTone.success,
                icon: search.alertFrequency == 'off'
                    ? Icons.notifications_off_outlined
                    : Icons.notifications_active_outlined,
              ),
              ..._filterBadges(search.filters),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          AppButton(
            label: 'عرض النتائج',
            icon: Icons.travel_explore_outlined,
            style: AppButtonStyle.tonal,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SavedSearchResultsScreen(search: search),
              ),
            ),
            expand: true,
          ),
        ],
      ),
    );
  }

  List<Widget> _filterBadges(Map<String, dynamic> filters) {
    final badges = <Widget>[];
    final purpose = filters['purpose']?.toString();
    if (purpose != null) {
      badges.add(AppStatusBadge(label: purpose == 'rent' ? 'إيجار' : 'بيع'));
    }
    final type = filters['type']?.toString();
    if (type != null) badges.add(AppStatusBadge(label: _typeLabel(type)));
    if (filters['max_price'] != null) {
      badges.add(AppStatusBadge(label: 'حتى ${_compact(filters['max_price'])}'));
    }
    if (filters['min_bedrooms'] != null) {
      badges.add(AppStatusBadge(label: '${filters['min_bedrooms']}+ غرف'));
    }
    if (filters['search']?.toString().trim().isNotEmpty == true) {
      badges.add(AppStatusBadge(label: '«${filters['search']}»'));
    }
    return badges.take(5).toList(growable: false);
  }

  Future<void> _handleMenu(String value) async {
    if (_busy) return;
    if (value == 'delete') {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('حذف البحث المحفوظ؟'),
          content: const Text('سيتم إيقاف تنبيهاته وحذفه من حسابك.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
          ],
        ),
      );
      if (approved != true) return;
    }

    setState(() => _busy = true);
    try {
      final repo = ref.read(savedSearchRepositoryProvider);
      if (value == 'delete') {
        await repo.delete(widget.search.id);
      } else {
        await repo.updateAlert(widget.search.id, alertFrequency: value);
      }
      ref.read(savedSearchRevisionProvider.notifier).state++;
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyApiError(error))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class SavedSearchResultsScreen extends ConsumerWidget {
  const SavedSearchResultsScreen({required this.search, super.key});
  final SavedPropertySearch search;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppAppBar(title: search.name),
        body: FutureBuilder<List<PropertyMarker>>(
          future: ref.read(savedSearchRepositoryProvider).results(search),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _SavedSearchSkeleton();
            }
            if (snapshot.hasError) {
              return AppErrorState(message: friendlyApiError(snapshot.error!));
            }
            final items = snapshot.data ?? const <PropertyMarker>[];
            if (items.isEmpty) {
              return const AppEmptyState(
                title: 'لا توجد نتائج مطابقة الآن',
                message: 'سيبقى البحث محفوظًا ويمكن للتنبيهات إخبارك عند ظهور عقار جديد مطابق.',
                icon: Icons.notifications_active_outlined,
              );
            }
            return ListView.separated(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppLayout.compactPageGutter,
                AppSpacing.s16,
                AppLayout.compactPageGutter,
                AppSpacing.s40,
              ),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.s12),
              itemBuilder: (context, index) {
                final item = items[index];
                return AppPropertyCard(
                  title: item.title,
                  price: _formatPrice(item.price),
                  currency: item.currency,
                  imageUrl: item.mainImage,
                  location: item.address,
                  purposeLabel: item.purpose == 'rent' ? 'للإيجار' : 'للبيع',
                  facts: [
                    if (item.areaM2 != null)
                      AppPropertyFact(icon: Icons.square_foot, label: '${item.areaM2} م²'),
                    if (item.bedrooms != null)
                      AppPropertyFact(icon: Icons.bed_outlined, label: '${item.bedrooms} غرف'),
                    if (item.bathrooms != null)
                      AppPropertyFact(icon: Icons.bathtub_outlined, label: '${item.bathrooms} حمام'),
                  ],
                  onTap: () => context.push('/properties/${item.id}'),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _SavedSearchSkeleton extends StatelessWidget {
  const _SavedSearchSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsetsDirectional.all(AppLayout.compactPageGutter),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.s12),
      itemBuilder: (_, __) => const AppSkeleton(height: 144),
    );
  }
}

String _typeLabel(String type) => switch (type) {
      'apartment' => 'شقة',
      'house' => 'منزل',
      'villa' => 'فيلا',
      'land' => 'أرض',
      'shop' => 'محل',
      'office' => 'مكتب',
      'farm' => 'مزرعة',
      _ => type,
    };

String _compact(dynamic value) {
  final number = value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  if (number >= 1000000000) return '${(number / 1000000000).toStringAsFixed(number % 1000000000 == 0 ? 0 : 1)} مليار';
  if (number >= 1000000) return '${(number / 1000000).toStringAsFixed(number % 1000000 == 0 ? 0 : 1)} مليون';
  if (number >= 1000) return '${(number / 1000).toStringAsFixed(number % 1000 == 0 ? 0 : 1)} ألف';
  return number.toStringAsFixed(0);
}

String _formatPrice(double value) => value.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../data/property_repository.dart';
import '../domain/property_details.dart';
import '../domain/property_field_options.dart';
import '../domain/property_sai.dart';

class PropertyCompareScreen extends ConsumerWidget {
  const PropertyCompareScreen({required this.propertyIds, super.key});

  final List<int> propertyIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = propertyIds.where((id) => id > 0).toSet().take(4).toList(growable: false);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: const AppAppBar(title: 'مقارنة العقارات'),
        body: FutureBuilder<List<_CompareItem>>(
          future: _load(ref, ids),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _CompareSkeleton();
            }
            if (snapshot.hasError) {
              return AppErrorState(message: friendlyApiError(snapshot.error!));
            }
            final items = snapshot.data ?? const <_CompareItem>[];
            if (items.length < 2) {
              return const AppEmptyState(
                title: 'اختر عقارين على الأقل',
                message: 'المقارنة تكون أوضح عند اختيار عقارين إلى أربعة من المفضلة.',
                icon: Icons.compare_arrows_rounded,
              );
            }
            return _ComparisonTable(items: items);
          },
        ),
      ),
    );
  }

  Future<List<_CompareItem>> _load(WidgetRef ref, List<int> ids) async {
    final repository = ref.read(propertyRepositoryProvider);
    final items = <_CompareItem>[];
    for (final id in ids) {
      final values = await Future.wait<dynamic>([
        repository.details(id),
        repository.sai(id),
      ]);
      items.add(_CompareItem(
        property: values[0] as PropertyDetails,
        sai: values[1] as PropertySaiEnvelope,
      ));
    }
    return items;
  }
}

class _ComparisonTable extends StatelessWidget {
  const _ComparisonTable({required this.items});

  final List<_CompareItem> items;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columnWidth = width < 420 ? 210.0 : 240.0;
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.s40),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppLayout.compactPageGutter,
          AppSpacing.s16,
          AppLayout.compactPageGutter,
          AppSpacing.s16,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: items
              .map((item) => Padding(
                    padding: const EdgeInsetsDirectional.only(end: AppSpacing.s12),
                    child: SizedBox(width: columnWidth, child: _PropertyCompareColumn(item: item)),
                  ))
              .toList(growable: false),
        ),
      ),
    );
  }
}

class _PropertyCompareColumn extends StatelessWidget {
  const _PropertyCompareColumn({required this.item});

  final _CompareItem item;

  @override
  Widget build(BuildContext context) {
    final property = item.property;
    final image = property.images.isEmpty ? null : property.images.first.url;
    return AppSurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.card)),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: image == null
                  ? Container(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      child: const Icon(Icons.home_work_outlined, size: 44),
                    )
                  : Image.network(
                      image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        child: const Icon(Icons.broken_image_outlined, size: 40),
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.all(AppSpacing.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  property.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.s8),
                AppPropertyPrice(
                  price: _formatPrice(property.price),
                  currency: property.currency,
                  suffix: property.purpose == 'rent' ? 'للإيجار' : 'للبيع',
                ),
                const SizedBox(height: AppSpacing.s8),
                _valueRow(context, 'السعي', item.sai.sai?.displayText ?? 'غير متاح'),
                _valueRow(context, 'المساحة', _area(property)),
                _valueRow(context, 'الغرف', property.bedrooms?.toString() ?? '—'),
                _valueRow(context, 'الحمامات', property.bathrooms?.toString() ?? '—'),
                _valueRow(context, 'الموقع', property.address ?? 'غير محدد'),
                _valueRow(
                  context,
                  'المعلن',
                  property.advertiser?.verificationLabel ?? 'معلن',
                ),
                if (property.advertiser != null)
                  _valueRow(
                    context,
                    'التقييم',
                    property.advertiser!.ratingCount > 0
                        ? '${property.advertiser!.ratingAverage.toStringAsFixed(1)} (${property.advertiser!.ratingCount})'
                        : 'لا توجد تقييمات بعد',
                  ),
                const SizedBox(height: AppSpacing.s12),
                AppButton(
                  label: 'فتح العقار',
                  icon: Icons.open_in_new_rounded,
                  style: AppButtonStyle.tonal,
                  onPressed: () => context.push('/properties/${property.id}'),
                  expand: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _valueRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: AppSpacing.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.s8),
          const Divider(height: 1),
        ],
      ),
    );
  }

  String _area(PropertyDetails property) {
    if (property.areaValue != null && property.areaUnit != null) {
      return '${property.areaValue!.toStringAsFixed(property.areaValue! % 1 == 0 ? 0 : 1)} ${propertyAreaUnitLabel(property.areaUnit)}';
    }
    return property.areaM2 == null ? '—' : '${property.areaM2} م²';
  }
}

class _CompareItem {
  const _CompareItem({required this.property, required this.sai});
  final PropertyDetails property;
  final PropertySaiEnvelope sai;
}

class _CompareSkeleton extends StatelessWidget {
  const _CompareSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsetsDirectional.all(AppLayout.compactPageGutter),
      child: const Row(
        children: [
          SizedBox(width: 220, child: AppSkeleton(height: 560)),
          SizedBox(width: AppSpacing.s12),
          SizedBox(width: 220, child: AppSkeleton(height: 560)),
        ],
      ),
    );
  }
}

String _formatPrice(double value) {
  final rounded = value.round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < rounded.length; i++) {
    if (i > 0 && (rounded.length - i) % 3 == 0) buffer.write(',');
    buffer.write(rounded[i]);
  }
  return buffer.toString();
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/design/app_design.dart';
import '../data/property_market_repository.dart';
import '../data/property_repository.dart';
import '../domain/property_details.dart';
import '../domain/property_field_options.dart';
import '../domain/property_sai.dart';

class PropertyCompareScreen extends ConsumerWidget {
  const PropertyCompareScreen({required this.propertyIds, super.key});

  final List<int> propertyIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(propertyDataRevisionProvider);
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
              return AppErrorState(
                message: friendlyApiError(snapshot.error!),
                onRetry: () =>
                    ref.read(propertyDataRevisionProvider.notifier).state++,
              );
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
    final marketRepository = ref.read(propertyMarketRepositoryProvider);
    final items = <_CompareItem>[];
    for (final id in ids) {
      final values = await Future.wait<dynamic>([
        repository.details(id),
        repository.sai(id),
        _loadMarket(marketRepository, id),
      ]);
      items.add(_CompareItem(
        property: values[0] as PropertyDetails,
        sai: values[1] as PropertySaiEnvelope,
        market: values[2] as PropertyMarketContext?,
      ));
    }
    return items;
  }

  Future<PropertyMarketContext?> _loadMarket(
    PropertyMarketRepository repository,
    int propertyId,
  ) async {
    try {
      return await repository.context(propertyId);
    } catch (_) {
      return null;
    }
  }
}

class _ComparisonTable extends StatelessWidget {
  const _ComparisonTable({required this.items});
  final List<_CompareItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    TableRow values(String label, String Function(_CompareItem) value) => TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: Text(label, style: theme.textTheme.labelLarge),
        ),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.s16),
            child: Text(value(item), style: theme.textTheme.bodyMedium),
          ),
      ],
    );
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.s32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppContentFrame(child: AppPageHeading(
            title: '${items.length} عقارات للمقارنة',
            subtitle: 'اسحب الجدول جانبياً لعرض العقارات، ومرّر لأسفل لمراجعة المواصفات.',
          )),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
            child: AppSurface(
              padding: EdgeInsets.zero,
              child: Table(
                textDirection: TextDirection.rtl,
                defaultColumnWidth: const FixedColumnWidth(AppLayout.comparisonColumnWidth),
                columnWidths: const {0: FixedColumnWidth(AppLayout.comparisonLabelWidth)},
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                border: TableBorder(
                  horizontalInside: BorderSide(color: scheme.outlineVariant),
                  verticalInside: BorderSide(color: scheme.outlineVariant),
                ),
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: scheme.surfaceContainerLow),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.s16),
                        child: Text('العقار', style: theme.textTheme.titleMedium),
                      ),
                      for (final item in items) _ComparisonHeading(property: item.property),
                    ],
                  ),
                  values('السعي', (item) => item.sai.sai?.displayText ?? 'غير متاح'),
                  values('مؤشر السوق', (item) => _marketValue(item.market, item.property.currency)),
                  values('المساحة', (item) => _area(item.property)),
                  values('الغرف', (item) => item.property.bedrooms?.toString() ?? '—'),
                  values('الحمامات', (item) => item.property.bathrooms?.toString() ?? '—'),
                  values('الموقع', (item) => item.property.address ?? 'غير محدد'),
                  values('المعلن', (item) => item.property.advertiser?.verificationLabel ?? 'معلن'),
                  if (items.any((item) => item.property.advertiser != null))
                    values('التقييم', (item) {
                      final advertiser = item.property.advertiser;
                      if (advertiser == null) return '—';
                      return advertiser.ratingCount > 0
                          ? '${advertiser.ratingAverage.toStringAsFixed(1)} (${advertiser.ratingCount})'
                          : 'لا توجد تقييمات بعد';
                    }),
                  TableRow(children: [
                    const SizedBox.shrink(),
                    for (final item in items)
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.s16),
                        child: AppButton(
                          label: 'فتح العقار', icon: Icons.open_in_new_rounded,
                          style: AppButtonStyle.tonal, expand: true,
                          onPressed: () => context.push('/properties/${item.property.id}'),
                        ),
                      ),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _marketValue(
    PropertyMarketContext? market,
    String currency,
  ) {
    if (market == null) {
      return 'تعذر تحميل المؤشر الآن';
    }
    if (!market.sufficientData) {
      return 'البيانات غير كافية (${market.sampleCount}/${market.minimumSampleSize ?? 5})';
    }
    final median = market.medianPrice;
    final medianText = median == null
        ? market.positionLabel
        : '${market.positionLabel}\nوسيط المقارنات: ${_formatPrice(median)} $currency';
    return '$medianText\n${market.sampleCount} عقار مقارنة';
  }

  String _area(PropertyDetails property) {
    if (property.areaValue != null && property.areaUnit != null) {
      return '${property.areaValue!.toStringAsFixed(property.areaValue! % 1 == 0 ? 0 : 1)} ${propertyAreaUnitLabel(property.areaUnit)}';
    }
    return property.areaM2 == null ? '—' : '${property.areaM2} م²';
  }
}

class _ComparisonHeading extends StatelessWidget {
  const _ComparisonHeading({required this.property});
  final PropertyDetails property;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.control),
              child: AppPropertyMedia(imageUrl: property.images.isEmpty ? null : property.images.first.url),
            ),
            const SizedBox(height: AppSpacing.s16),
            AppPropertyPrice(
              price: _formatPrice(property.price), currency: property.currency,
              suffix: property.purpose == 'rent' ? 'للإيجار' : 'للبيع',
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(property.title, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      );
}

class _CompareItem {
  const _CompareItem({
    required this.property,
    required this.sai,
    required this.market,
  });
  final PropertyDetails property;
  final PropertySaiEnvelope sai;
  final PropertyMarketContext? market;
}

class _CompareSkeleton extends StatelessWidget {
  const _CompareSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: AppLayout.comparisonColumnWidth, child: AppPropertyCardSkeleton()),
            SizedBox(width: AppSpacing.s12),
            SizedBox(width: AppLayout.comparisonColumnWidth, child: AppPropertyCardSkeleton()),
          ],
        ),
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

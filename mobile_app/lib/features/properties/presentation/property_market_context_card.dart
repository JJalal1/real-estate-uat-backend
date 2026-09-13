import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../data/property_market_repository.dart';
import '../data/property_repository.dart';

final propertyMarketContextProvider = FutureProvider.autoDispose
    .family<PropertyMarketContext, int>((ref, propertyId) {
  ref.watch(propertyDataRevisionProvider);
  return ref.watch(propertyMarketRepositoryProvider).context(propertyId);
});

class PropertyMarketContextCard extends ConsumerWidget {
  const PropertyMarketContextCard({
    required this.propertyId,
    required this.currency,
    super.key,
  });

  final int propertyId;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(propertyMarketContextProvider(propertyId));
    return state.when(
      loading: () => const AppSkeleton(height: 156, radius: AppRadii.card),
      error: (_, __) => AppSurface(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.query_stats_outlined,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('مؤشر السوق', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    'تعذر تحميل مؤشر السوق الآن. باقي تفاصيل العقار متاحة بشكل طبيعي.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  TextButton.icon(
                    onPressed: () => ref.invalidate(
                      propertyMarketContextProvider(propertyId),
                    ),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      data: (market) => _MarketDataCard(market: market, currency: currency),
    );
  }
}

class _MarketDataCard extends StatelessWidget {
  const _MarketDataCard({required this.market, required this.currency});

  final PropertyMarketContext market;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!market.sufficientData) {
      final required = market.minimumSampleSize ?? 5;
      return AppSurface(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadii.control),
              ),
              child: Icon(Icons.insights_outlined, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('مؤشر السوق', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    market.message ??
                        'البيانات الحالية غير كافية لتقديم مؤشر سعري موثوق لهذا العقار.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  AppStatusBadge(
                    label: '${market.sampleCount} من $required عقارات مقارنة',
                    tone: AppStatusTone.neutral,
                    icon: Icons.dataset_outlined,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final delta = market.deltaFromMedianPercent;
    final deltaText = delta == null
        ? null
        : '${delta.abs().toStringAsFixed(1)}% ${delta < 0 ? 'أقل' : delta > 0 ? 'أعلى' : 'مطابق'} من الوسيط';
    final median = market.medianPrice;
    final perM2 = market.medianPricePerM2;

    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadii.control),
                ),
                child: Icon(Icons.insights_rounded, color: scheme.primary),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('مؤشر السوق', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      market.positionLabel,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
              AppStatusBadge(
                label: '${market.sampleCount} مقارنة',
                tone: AppStatusTone.info,
                icon: Icons.dataset_outlined,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              if (median != null)
                _Metric(
                  label: 'وسيط السعر',
                  value: '${_formatPrice(median)} $currency',
                ),
              if (perM2 != null)
                _Metric(
                  label: 'وسيط المتر',
                  value: '${_formatPrice(perM2)} $currency/م²',
                ),
              if (deltaText != null)
                _Metric(label: 'موقع السعر', value: deltaText),
            ],
          ),
          if (market.disclaimer != null) ...[
            const SizedBox(height: AppSpacing.s12),
            Text(
              market.disclaimer!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 124),
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s8,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

String _formatPrice(double value) {
  final digits = value.round().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    final remaining = digits.length - index;
    buffer.write(digits[index]);
    if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
  }
  return buffer.toString();
}

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../domain/property_marker.dart';

final _priceIndicatorPropertiesProvider =
    FutureProvider.autoDispose<List<PropertyMarker>>((ref) async {
  final dio = ref.watch(dioProvider);
  final response = await dio.get<Map<String, dynamic>>(
    '/properties',
    queryParameters: const {'page': 1, 'per_page': 50},
  );
  final rows = response.data?['data'] as List<dynamic>? ?? const <dynamic>[];
  return rows
      .whereType<Map<String, dynamic>>()
      .map(PropertyMarker.fromJson)
      .toList(growable: false);
});

class PriceIndicatorsScreen extends ConsumerWidget {
  const PriceIndicatorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final properties = ref.watch(_priceIndicatorPropertiesProvider);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: const AppAppBar(title: 'مؤشرات الأسعار'),
        body: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(_priceIndicatorPropertiesProvider);
            await ref.read(_priceIndicatorPropertiesProvider.future);
          },
          child: properties.when(
            loading: () => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppLayout.compactPageGutter),
              children: const [
                AppSkeleton(height: 110),
                SizedBox(height: AppSpacing.s12),
                AppSkeleton(height: 260),
              ],
            ),
            error: (error, _) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * .7,
                  child: AppErrorState(
                    message: friendlyApiError(error),
                    onRetry: () =>
                        ref.invalidate(_priceIndicatorPropertiesProvider),
                  ),
                ),
              ],
            ),
            data: (items) => ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppLayout.compactPageGutter,
                AppSpacing.s12,
                AppLayout.compactPageGutter,
                AppSpacing.s32,
              ),
              itemCount: items.length + 1,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.s12),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return const AppInlineMessage(
                    title: 'اختر عقاراً لعرض المؤشر',
                    message:
                        'المؤشر يظهر داخل صفحة العقار ويعتمد فقط على عقارات منشورة ومعتمدة مشابهة داخل المنصة. إذا كانت العينة غير كافية سيظهر ذلك بوضوح.',
                    tone: AppStatusTone.info,
                  );
                }
                final property = items[index - 1];
                return AppPropertyCard(
                  title: property.title,
                  price: _formatPrice(property.price),
                  currency: property.currency,
                  imageUrl: property.mainImage,
                  location: property.address,
                  purposeLabel:
                      property.purpose == 'rent' ? 'للإيجار' : 'للبيع',
                  facts: [
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
                  ],
                  trailing: const Icon(Icons.insights_outlined),
                  onTap: () => context.push('/properties/${property.id}'),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  static String _formatPrice(double value) {
    final rounded = value.round().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < rounded.length; i++) {
      if (i > 0 && (rounded.length - i) % 3 == 0) buffer.write(',');
      buffer.write(rounded[i]);
    }
    return buffer.toString();
  }
}

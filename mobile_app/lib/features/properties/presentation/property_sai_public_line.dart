import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../data/property_repository.dart';
import '../domain/property_sai.dart';

final propertySaiPublicProvider =
    FutureProvider.autoDispose.family<PropertySaiEnvelope, int>((ref, propertyId) {
  return ref.watch(propertyRepositoryProvider).sai(propertyId);
});

class PropertySaiPublicLine extends ConsumerWidget {
  const PropertySaiPublicLine({required this.propertyId, super.key});

  final int propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(propertySaiPublicProvider(propertyId));

    return state.when(
      loading: () => const Padding(
        padding: EdgeInsetsDirectional.only(top: AppSpacing.s8),
        child: AppSkeleton(height: 20, width: 220),
      ),
      error: (_, __) => Padding(
        padding: const EdgeInsetsDirectional.only(top: AppSpacing.s8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'تعذر تحميل السعي لهذا الإعلان.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            TextButton(
              onPressed: () => ref.invalidate(propertySaiPublicProvider(propertyId)),
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
      data: (envelope) {
        final sai = envelope.sai;
        if (sai == null || sai.displayText.trim().isEmpty) {
          return Padding(
            padding: const EdgeInsetsDirectional.only(top: AppSpacing.s8),
            child: Text(
              'بيانات السعي غير متاحة لهذا الإعلان.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          );
        }

        return PropertySaiDisplayLine(text: sai.displayText);
      },
    );
  }
}

class PropertySaiDisplayLine extends StatelessWidget {
  const PropertySaiDisplayLine({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: text,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(top: AppSpacing.s8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.handshake_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

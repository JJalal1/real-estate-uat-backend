import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/local/stage6_secure_session_store.dart';
import '../../account/data/auth_controller.dart';
import '../../account/presentation/actor_scoped_page.dart';
import '../data/property_repository.dart';
import '../domain/property_details.dart';

Future<PropertyDetails?> publishListing(
  BuildContext context,
  WidgetRef ref,
  int propertyId,
) async {
  final repository = ref.read(propertyRepositoryProvider);
  final userId = ref.read(authControllerProvider).asData?.value?.id;
  final session = Stage6SecureSessionStore.instance;
  final epoch = session.sessionEpoch;
  bool sameActor() =>
      context.mounted &&
      session.sessionEpoch == epoch &&
      ref.read(authControllerProvider).asData?.value?.id == userId;

  try {
    final listing = await repository.submitListing(propertyId);
    if (!sameActor()) throw StateError('ACCOUNT_CHANGED');
    return listing;
  } on DioException catch (error) {
    final data = error.response?.data;
    if (error.response?.statusCode != 409 ||
        data is! Map ||
        data['code'] != 'broker_upgrade_required') {
      rethrow;
    }
  }
  if (!context.mounted || !sameActor()) throw StateError('ACCOUNT_CHANGED');
  final consent = await showActorDialog<bool>(
    context: context,
    ref: ref,
    builder: (dialogContext) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        scrollable: true,
        title: const Text('ترقية حسابك إلى دلال؟'),
        content: const Text(
            'انشر إعلانك الثاني بحساب دلال، وأدِر عقاراتك وإعلاناتك وتابع عملاءك من مكان واحد.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('ليس الآن'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('ترقية ونشر الإعلان'),
          ),
        ],
      ),
    ),
  );
  if (!sameActor()) throw StateError('ACCOUNT_CHANGED');
  if (consent != true) return null;
  final result = await repository.submitWithBrokerUpgrade(propertyId);
  if (!sameActor()) throw StateError('ACCOUNT_CHANGED');
  try {
    await ref.read(authControllerProvider.notifier).refresh();
  } on DioException {
    // Publication is already complete. The next session refresh loads the enrollment.
  }
  if (!sameActor()) throw StateError('ACCOUNT_CHANGED');
  return result;
}

String publicationMessage(PropertyDetails listing) =>
    listing.status == 'published'
        ? 'تم نشر إعلانك.'
        : 'أُرسل إعلانك للمراجعة. يمكنك متابعة حالته من إعلاناتي.';

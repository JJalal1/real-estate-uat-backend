import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/local/listing_recovery_store.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/offline/offline_connection.dart';
import '../../account/data/auth_controller.dart';
import 'my_listings_screen.dart';

final personalRecoveredListingIdProvider = FutureProvider.autoDispose.family<int?, int>((ref, userId) async {
  final snapshot = await ref.watch(listingRecoveryStoreProvider).read(userId, null);
  final id = snapshot?['server_property_id'];
  return id is int && id > 0 ? id : null;
});

class PersonalListingCreationGate extends ConsumerWidget {
  const PersonalListingCreationGate({
    required this.child,
    this.allowDraftContinuation = false,
    super.key,
  });
  final Widget child;
  final bool allowDraftContinuation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).asData?.value;
    if (user == null || !user.isOwner || !user.hasVerifiedPublishingProfile) {
      return child;
    }
    // Local preparation grants no server publishing permission. The normal
    // authoritative personal-property limit is checked again on upload.
    if (const [OfflineConnection.offline, OfflineConnection.unavailable]
        .contains(ref.watch(offlineConnectionProvider))) {
      return child;
    }
    final listings = ref.watch(myListingsProvider);
    return listings.when(
      loading: () => _loading(context),
      error: (error, _) => _dialog(
        context,
        content: Text(friendlyApiError(error)),
        action: FilledButton(
          onPressed: () => ref.invalidate(myListingsProvider),
          child: const Text('إعادة المحاولة'),
        ),
      ),
      data: (rows) {
        final current = rows.where((row) => row.status != 'archived').toList();
        if (current.isEmpty) return child;
        final recoverable = current.where((row) =>
            row.status == 'draft' || row.reviewStatus == 'returned_for_correction');
        if (allowDraftContinuation && recoverable.any((row) => row.canEdit)) {
          return child;
        }
        if (recoverable.isNotEmpty) {
          final recovered = ref.watch(personalRecoveredListingIdProvider(user.id));
          if (recovered.isLoading) return _loading(context);
          if (recoverable.any((row) => row.id == recovered.asData?.value)) {
            return child;
          }
        }
        return _dialog(
          context,
          content: const Text('مسموح لك بنشر عقار واحد. هل تريد ترقية حسابك إلى دلال؟'),
          action: FilledButton(
            onPressed: () => context.push('/account-verification?upgrade=broker'),
            child: const Text('ترقية الحساب'),
          ),
        );
      },
    );
  }

  Widget _loading(BuildContext context) => _dialog(
    context,
    content: const Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('جارٍ التحقق من أهلية النشر…'),
        SizedBox(height: 12),
        LinearProgressIndicator(),
      ],
    ),
  );

  Widget _dialog(BuildContext context, {required Widget content, Widget? action}) =>
    Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        scrollable: true,
        content: content,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('رجوع'),
          ),
          if (action != null) action,
        ],
      ),
    );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/local/listing_recovery_store.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/auth_controller.dart';
import 'my_listings_screen.dart';

final personalRecoveredListingIdProvider = FutureProvider.autoDispose.family<int?, int>((ref, userId) async {
  final snapshot = await ref.watch(listingRecoveryStoreProvider).read(userId, null);
  final id = snapshot?['server_property_id'];
  return id is int && id > 0 ? id : null;
});

class PersonalListingCreationGate extends ConsumerWidget {
  const PersonalListingCreationGate({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).asData?.value;
    if (user == null || !user.isOwner || !user.hasVerifiedPublishingProfile) return child;
    final listings = ref.watch(myListingsProvider);
    final recovered = ref.watch(personalRecoveredListingIdProvider(user.id));
    return listings.when(
      loading: () => _loading(),
      error: (error, _) => Scaffold(appBar: const AppAppBar(title: 'إضافة عقار'),
        body: AppErrorState(message: friendlyApiError(error), onRetry: () => ref.invalidate(myListingsProvider))),
      data: (rows) {
        final current = rows.where((row) => row.status != 'archived').toList();
        if (current.isEmpty) return child;
        if (recovered.isLoading) return _loading();
        final recoveryId = recovered.asData?.value;
        if (current.any((row) => row.id == recoveryId && (row.status == 'draft' || row.reviewStatus == 'returned_for_correction'))) return child;
        return Directionality(textDirection: TextDirection.rtl, child: Scaffold(
          appBar: const AppAppBar(title: 'عرض أكثر من عقار'),
          body: ListView(padding: const EdgeInsets.all(24), children: [
            Text('هل لديك أكثر من عقار لعرضه؟', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 14),
            const Text('حساب المالك العادي يتيح عقارًا شخصيًا واحدًا. فعّل حساب دلال لإدارة عدة عقارات والعملاء والإحصائيات وأدوات العمل بعد اعتماد التوثيق.'),
            const SizedBox(height: 24),
            AppButton(label: 'فعّل حساب دلال', expand: true,
              onPressed: () => context.push('/account-verification?upgrade=broker')),
            const SizedBox(height: 10),
            TextButton(onPressed: () => context.go('/my-listings'), child: const Text('متابعة عقاري الحالي')),
          ]),
        ));
      },
    );
  }

  Widget _loading() => const Scaffold(appBar: AppAppBar(title: 'إضافة عقار'),
    body: Padding(padding: EdgeInsets.all(24), child: Column(children: [
      AppSkeleton(height: 28), SizedBox(height: 16), AppSkeleton(height: 72),
    ])));
}

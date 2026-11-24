import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/local/listing_recovery_store.dart';
import '../../../core/local/stage6_secure_session_store.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/offline/offline_connection.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../account/data/account_request_scope.dart';
import '../../account/data/auth_controller.dart';
import '../../properties/data/listing_account_draft_repository.dart';
import '../../properties/data/my_listings_pages.dart';
import '../../properties/data/property_repository.dart';
import '../../properties/domain/property_details.dart';
import '../../properties/presentation/property_share.dart';
import '../data/broker_repository.dart';

final _resumableDraftProvider = FutureProvider.autoDispose<bool>((ref) async {
  final actor = ref.watch(authControllerProvider).asData?.value?.id;
  if (actor == null) return false;
  ref.watch(propertyDataRevisionProvider);
  ref.watch(brokerWorkspaceProvider);
  final connection = ref.watch(offlineConnectionProvider);
  final scope = ref.watch(accountRequestScopeProvider);
  final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
  var alive = true;
  ref.onDispose(() => alive = false);
  bool current() => alive && scope.isCurrent && Stage6SecureSessionStore.instance.sessionEpoch == epoch;

  final store = ref.watch(listingRecoveryStoreProvider);
  try {
    final device = await store.read(actor, null).timeout(const Duration(seconds: 8));
    if (!current()) return false;
    if (device != null && device['draft_kind'] != 'retired') return true;
    final saved = await store.saved(actor).timeout(const Duration(seconds: 8));
    if (!current()) return false;
    if (saved.any((item) => item['draft_kind'] != 'retired')) return true;
  } catch (_) {
    // An unavailable device cache does not rule out a saved account draft.
  }
  if (!current() || connection == OfflineConnection.offline ||
      connection == OfflineConnection.unavailable) return false;
  final drafts = await ref.read(listingAccountDraftRepositoryProvider)
      .list().timeout(const Duration(seconds: 15));
  return current() && drafts.any((draft) => !draft.isRetired);
});

class BrokerDashboardShortcuts extends ConsumerWidget {
  const BrokerDashboardShortcuts({this.legacyDraftCount = 0, super.key});

  final int legacyDraftCount;

  Future<void> _share(BuildContext context, WidgetRef ref) async {
    final scope = ref.read(accountRequestScopeProvider);
    final actor = ref.read(authControllerProvider).asData?.value?.id;
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    if (actor == null || !scope.isCurrent) return;
    final property = await AppBottomSheet.show<PropertyDetails>(
      context,
      builder: (_) => _PublishedListingsSheet(scope: scope, actor: actor, epoch: epoch),
    );
    if (property == null || !context.mounted || !scope.isCurrent ||
        Stage6SecureSessionStore.instance.sessionEpoch != epoch ||
        ref.read(authControllerProvider).asData?.value?.id != actor) return;
    await sharePublicProperty(context, property);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final canResume = legacyDraftCount > 0 || ref.watch(_resumableDraftProvider).asData?.value == true;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: AppSurface(
        padding: EdgeInsets.zero,
        child: Material(
          color: Colors.transparent,
          child: Column(
            children: [
              if (canResume) ...[
                ListTile(
                  key: const ValueKey('broker-shortcut-resume-draft'),
                  leading: EbrokerIcon(Icons.drafts_outlined, color: scheme.primary, size: 20),
                  title: const Text('أكمل مسودة'),
                  trailing: const EbrokerIcon(Icons.chevron_left, size: 18),
                  onTap: () async {
                    await context.push('/add-property?resume=1');
                    if (!context.mounted) return;
                    ref.invalidate(_resumableDraftProvider);
                    ref.invalidate(brokerWorkspaceProvider);
                  },
                ),
                const Divider(height: 1, indent: 12, endIndent: 12),
              ],
              ListTile(
                key: const ValueKey('broker-shortcut-share-listing'),
                leading: EbrokerIcon(Icons.ios_share_outlined, color: scheme.primary, size: 20),
                title: const Text('مشاركة إعلان منشور'),
                trailing: const EbrokerIcon(Icons.chevron_left, size: 18),
                onTap: () => _share(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PublishedListingsSheet extends ConsumerWidget {
  const _PublishedListingsSheet({required this.scope, required this.actor, required this.epoch});

  final AccountRequestScope scope;
  final int actor;
  final int epoch;

  bool _isCurrent(int? currentActor) =>
      currentActor == actor && scope.isCurrent &&
      Stage6SecureSessionStore.instance.sessionEpoch == epoch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = _isCurrent(ref.watch(authControllerProvider).asData?.value?.id);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        top: false,
        child: FractionallySizedBox(
          heightFactor: .66,
          child: Column(
            children: [
              ListTile(
                title: Text('مشاركة إعلان منشور', style: Theme.of(context).textTheme.titleLarge),
                trailing: IconButton(
                  tooltip: 'إغلاق',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ),
              Expanded(
                child: current
                    ? _listings(context, ref)
                    : const Center(child: Text('تغيّر الحساب. أعد فتح المشاركة من حسابك الحالي.')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _listings(BuildContext context, WidgetRef ref) {
    final state = ref.watch(myListingsPagesProvider);
    final controller = ref.read(myListingsPagesProvider.notifier);
    if (state.page == null && state.loading) return const AppLoadingState();
    if (state.page == null && state.error != null) {
      return AppErrorState(message: friendlyApiError(state.error!), onRetry: controller.refresh);
    }
    final listings = state.items.where((property) =>
        property.isOwner && property.id > 0 && property.status == 'published' &&
        property.reviewStatus == 'approved' && property.availabilityStatus == 'available');
    final hasMore = state.page?.hasMore ?? false;
    return ListView(
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        if (state.page != null && (state.loading || state.error != null))
          AppRefreshStatus(
            loading: state.loading,
            error: state.error == null ? null : friendlyApiError(state.error!),
            onRetry: controller.refresh,
          ),
        for (final property in listings)
          ListTile(
            key: ValueKey('broker-share-listing-${property.id}'),
            title: Text(property.title),
            trailing: const Icon(Icons.ios_share_outlined),
            onTap: () {
              if (_isCurrent(ref.read(authControllerProvider).asData?.value?.id)) {
                Navigator.of(context).pop(property);
              }
            },
          ),
        if (listings.isEmpty && !hasMore)
          const ListTile(title: Text('لا توجد إعلانات منشورة ومتاحة للمشاركة.')),
        if (state.pageError != null)
          AppRefreshStatus(error: friendlyApiError(state.pageError!), onRetry: controller.loadMore)
        else if (state.loadingMore)
          const AppRefreshStatus(loading: true)
        else if (hasMore)
          Center(child: TextButton(
            onPressed: state.loading ? null : controller.loadMore,
            child: const Text('تحميل المزيد'),
          )),
      ],
    );
  }
}

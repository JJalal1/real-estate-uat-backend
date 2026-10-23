import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../../agreements/data/agreement_repository.dart';
import '../../agreements/domain/agreement_models.dart';
import '../../messages/data/message_repository.dart';
import '../../messages/domain/message_models.dart';
import '../../properties/data/favorites_repository.dart';
import '../../properties/domain/property_marker.dart';

final propertyJourneyProvider = FutureProvider.autoDispose<_JourneyData>((ref) async {
  final values = await Future.wait<dynamic>([
    ref.read(favoritesRepositoryProvider).favorites(),
    ref.read(messageRepositoryProvider).threads(),
    ref.read(agreementRepositoryProvider).mine(),
  ]);
  return _JourneyData(
    favorites: values[0] as List<PropertyMarker>,
    threads: values[1] as List<MessageThreadSummary>,
    agreements: values[2] as List<PropertyAgreement>,
  );
});

class PropertyJourneyScreen extends ConsumerWidget {
  const PropertyJourneyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(propertyJourneyProvider);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: const AppAppBar(title: 'رحلتي العقارية'),
        body: state.when(
          loading: () => const _JourneySkeleton(),
          error: (error, _) => AppErrorState(
            message: friendlyApiError(error),
            onRetry: () => ref.invalidate(propertyJourneyProvider),
          ),
          data: (data) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(propertyJourneyProvider);
              await ref.read(propertyJourneyProvider.future);
            },
            child: _JourneyContent(data: data),
          ),
        ),
      ),
    );
  }
}

class _JourneyContent extends StatelessWidget {
  const _JourneyContent({required this.data});
  final _JourneyData data;

  @override
  Widget build(BuildContext context) {
    final next = _nextAction();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppLayout.compactPageGutter,
        AppSpacing.s16,
        AppLayout.compactPageGutter,
        AppSpacing.s40,
      ),
      children: [
        AppSurface(
          selected: next.tone == AppStatusTone.warning,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EbrokerIcon(next.icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('الخطوة التالية', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: AppSpacing.s4),
                    Text(next.title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      next.subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    if (next.route != null) ...[
                      const SizedBox(height: AppSpacing.s12),
                      AppButton(
                        label: next.actionLabel ?? 'فتح',
                        icon: Icons.arrow_back_rounded,
                        style: AppButtonStyle.tonal,
                        onPressed: () => context.push(next.route!),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s24),
        const AppSectionHeader(
          title: 'نظرة سريعة',
          subtitle: 'كل ما يخص رحلة البحث والتواصل والاتفاق في مكان واحد.',
        ),
        const SizedBox(height: AppSpacing.s12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.s12,
          crossAxisSpacing: AppSpacing.s12,
          childAspectRatio: 1.55,
          children: [
            _MetricCard(
              icon: Icons.favorite_outline_rounded,
              label: 'المحفوظة',
              value: data.favorites.length,
              onTap: () => context.push('/services'),
            ),
            _MetricCard(
              icon: Icons.forum_outlined,
              label: 'المحادثات',
              value: data.threads.length,
              badge: data.unreadMessages == 0 ? null : '${data.unreadMessages} غير مقروء',
              onTap: () => context.push('/messages'),
            ),
            _MetricCard(
              icon: Icons.handshake_outlined,
              label: 'الاتفاقات',
              value: data.agreements.length,
              badge: data.acceptableAgreements == 0 ? null : '${data.acceptableAgreements} بانتظارك',
              onTap: () => context.push('/agreements'),
            ),
          ],
        ),
        if (data.agreements.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s24),
          const AppSectionHeader(title: 'آخر الاتفاقات'),
          const SizedBox(height: AppSpacing.s8),
          ...data.agreements.take(3).map((agreement) => Padding(
                padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.s8),
                child: AppListRow(
                  title: '${agreement.transactionLabel} • ${_formatPrice(agreement.currentRevision.agreedAmount)} ${agreement.currentRevision.currency}',
                  subtitle: agreement.statusLabel,
                  leading: const EbrokerIcon(Icons.handshake_outlined),
                  trailing: agreement.canAccept
                      ? const AppStatusBadge(label: 'بانتظار موافقتك', tone: AppStatusTone.warning)
                      : const EbrokerIcon(Icons.chevron_left_rounded),
                  onTap: () => context.push('/agreements/${agreement.id}'),
                ),
              )),
        ],
      ],
    );
  }

  _NextAction _nextAction() {
    final agreement = data.agreements.where((item) => item.canAccept).firstOrNull;
    if (agreement != null) {
      return _NextAction(
        title: 'راجع الاتفاق وقرر',
        subtitle: 'هناك اتفاق بانتظار موافقتك قبل الانتقال للخطوة التالية.',
        icon: Icons.handshake_outlined,
        route: '/agreements/${agreement.id}',
        actionLabel: 'مراجعة الاتفاق',
        tone: AppStatusTone.warning,
      );
    }
    final unread = data.threads.where((item) => item.unreadCount > 0).firstOrNull;
    if (unread != null) {
      return _NextAction(
        title: 'عندك رسالة جديدة',
        subtitle: unread.propertyTitle ?? unread.otherUserName,
        icon: Icons.mark_chat_unread_outlined,
        route: '/messages/${unread.id}',
        actionLabel: 'فتح المحادثة',
      );
    }
    if (data.favorites.isNotEmpty) {
      return const _NextAction(
        title: 'قارن خياراتك قبل التواصل',
        subtitle: 'عندك عقارات محفوظة. قارن بينها أو افتح الأنسب وابدأ محادثة مرتبطة بالعقار.',
        icon: Icons.compare_arrows_rounded,
        route: '/services',
        actionLabel: 'فتح الأدوات',
      );
    }
    return const _NextAction(
      title: 'ابدأ بحفظ العقارات المناسبة',
      subtitle: 'احفظ ما يعجبك أثناء البحث، وبعدها تابع المحادثات والاتفاق من هنا.',
      icon: Icons.travel_explore_outlined,
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final int value;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          EbrokerIcon(icon, color: Theme.of(context).colorScheme.primary),
          const Spacer(),
          Text('$value', style: Theme.of(context).textTheme.headlineSmall),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (badge != null)
            Text(
              badge!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
        ],
      ),
    );
  }
}

class _JourneyData {
  const _JourneyData({
    required this.favorites,
    required this.threads,
    required this.agreements,
  });

  final List<PropertyMarker> favorites;
  final List<MessageThreadSummary> threads;
  final List<PropertyAgreement> agreements;

  int get unreadMessages => threads.fold(0, (sum, item) => sum + item.unreadCount);
  int get acceptableAgreements => agreements.where((item) => item.canAccept).length;
}

class _NextAction {
  const _NextAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.route,
    this.actionLabel,
    this.tone = AppStatusTone.info,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final String? route;
  final String? actionLabel;
  final AppStatusTone tone;
}

class _JourneySkeleton extends StatelessWidget {
  const _JourneySkeleton();
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsetsDirectional.all(AppLayout.compactPageGutter),
      children: const [
        AppSkeleton(height: 150),
        SizedBox(height: AppSpacing.s20),
        AppSkeleton(height: 240),
        SizedBox(height: AppSpacing.s20),
        AppSkeleton(height: 180),
      ],
    );
  }
}


String _formatPrice(double value) => value.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );

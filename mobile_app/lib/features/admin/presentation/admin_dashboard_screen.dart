import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../account/data/auth_controller.dart';
import '../data/admin_workspace_repository.dart';
import '../domain/admin_workspace_models.dart';

final _adminDashboardProvider =
    FutureProvider.autoDispose<AdminDashboardSummary>((ref) {
  return ref.watch(adminWorkspaceRepositoryProvider).dashboard();
});

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).asData?.value;
    final state = ref.watch(_adminDashboardProvider);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(user?.isPlatformOwner == true
              ? 'لوحة المدير العام / صاحب النظام'
              : 'لوحة إدارة النظام'),
          actions: [
            IconButton(
                onPressed: () => ref.invalidate(_adminDashboardProvider),
                icon: const Icon(Icons.refresh))
          ],
        ),
        body: state.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(friendlyApiError(error),
                      textAlign: TextAlign.center))),
          data: (summary) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(_adminDashboardProvider);
              await ref.read(_adminDashboardProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
              children: [
                _SummaryGrid(summary: summary, user: user),
                if (summary.alerts.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _Title('تنبيهات ومهام تحتاج تدخل'),
                  const SizedBox(height: 8),
                  ...summary.alerts.map((item) => Card(
                        child: ListTile(
                          leading:
                              const Icon(Icons.notification_important_outlined),
                          title: Text(item.label,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          trailing: Badge(
                              label: Text('${item.count}'),
                              child: const Icon(Icons.chevron_left)),
                          onTap: item.route.isEmpty
                              ? null
                              : () => context.push(item.route),
                        ),
                      )),
                ],
                const SizedBox(height: 18),
                _Title('إدارة النظام'),
                const SizedBox(height: 8),
                _AdminMenu(user: user),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary, required this.user});
  final AdminDashboardSummary summary;
  final dynamic user;

  bool _can(String key) =>
      user?.isPlatformOwner == true || user?.hasPermission(key) == true;

  @override
  Widget build(BuildContext context) {
    final rows = <({String label, int value, IconData icon, bool visible})>[
      (
        label: 'المستخدمون',
        value: summary.usersTotal,
        icon: Icons.people_alt_outlined,
        visible: _can('users.view')
      ),
      (
        label: 'إعلانات للمراجعة',
        value: summary.pendingListings,
        icon: Icons.fact_check_outlined,
        visible: _can('listings.moderate')
      ),
      (
        label: 'طلبات دعم مفتوحة',
        value: summary.supportTicketsOpen,
        icon: Icons.support_agent_outlined,
        visible: _can('support.handle_reports')
      ),
      (
        label: 'بلاغات مفتوحة',
        value: summary.reportsOpen,
        icon: Icons.report_outlined,
        visible: _can('support.handle_reports')
      ),
      (
        label: 'طلبات معاينة تنتظر الإجراء',
        value: summary.bookingsRequested,
        icon: Icons.event_available_outlined,
        visible: _can('bookings.manage')
      ),
      (
        label: 'توثيق دلالين',
        value: summary.brokerKycPending,
        icon: Icons.badge_outlined,
        visible: _can('brokers.verify_accounts')
      ),
      (
        label: 'مدفوعات معلقة',
        value: summary.paymentsPending,
        icon: Icons.payments_outlined,
        visible: _can('payments.manage')
      ),
    ].where((row) => row.visible).toList(growable: false);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 1.9,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8),
      itemCount: rows.length,
      itemBuilder: (_, i) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Icon(rows[i].icon),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('${rows[i].value}',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w900)),
                  Text(rows[i].label,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
          ]),
        ),
      ),
    );
  }
}

class _AdminMenu extends StatelessWidget {
  const _AdminMenu({required this.user});
  final dynamic user;
  bool _can(String key) =>
      user?.isPlatformOwner == true || user?.hasPermission(key) == true;

  @override
  Widget build(BuildContext context) {
    final items = <({
      String title,
      String subtitle,
      IconData icon,
      String route,
      bool visible
    })>[
      (
        title: 'المستخدمون والأدوار والصلاحيات',
        subtitle: 'بحث، حالة الحساب، الأدوار والصلاحيات المباشرة.',
        icon: Icons.admin_panel_settings_outlined,
        route: '/admin/access',
        visible: _can('users.view')
      ),
      (
        title: 'الإعلانات والمراجعة',
        subtitle: 'مراجعة الإعلان والصور والمستندات وسجل القرار.',
        icon: Icons.fact_check_outlined,
        route: '/admin/listing-review',
        visible: _can('listings.moderate')
      ),
      (
        title: 'الخريطة والمناطق',
        subtitle:
            'المحافظات والمناطق والعقارات داخل كل منطقة دون أي دلال حصري.',
        icon: Icons.map_outlined,
        route: '/admin/regions',
        visible: _can('regions.manage')
      ),
      (
        title: 'الدعم والبلاغات',
        subtitle: 'لوحة الدعم والتذاكر والبلاغات وفريق الدعم.',
        icon: Icons.support_agent_outlined,
        route: '/support/workspace',
        visible: _can('support.handle_reports')
      ),
      (
        title: 'الحجوزات والمعاينات',
        subtitle: 'متابعة طلبات المعاينة والتأكيد والرفض وإعادة الجدولة.',
        icon: Icons.event_available_outlined,
        route: '/bookings',
        visible: _can('bookings.manage')
      ),
      (
        title: 'الخدمات والمدفوعات',
        subtitle: 'الخدمات والطلبات والتسويات والاسترجاعات حسب الصلاحية.',
        icon: Icons.payments_outlined,
        route: '/services',
        visible: _can('services.manage') || _can('payments.manage')
      ),
      (
        title: 'سجل العمليات',
        subtitle: 'من قام بأي إجراء ومتى وعلى ماذا.',
        icon: Icons.history_outlined,
        route: '/admin/audit-log',
        visible: _can('audit.view')
      ),
      (
        title: 'الإعدادات',
        subtitle:
            'إعدادات المنصة العامة والإعلانات والدعم والإشعارات بدون أسرار.',
        icon: Icons.settings_outlined,
        route: '/admin/settings',
        visible: _can('settings.view')
      ),
    ];
    final visible = items.where((item) => item.visible).toList(growable: false);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var i = 0; i < visible.length; i++) ...[
          ListTile(
            leading: Icon(visible[i].icon),
            title: Text(visible[i].title,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(visible[i].subtitle),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => context.push(visible[i].route),
          ),
          if (i != visible.length - 1) const Divider(height: 1),
        ],
      ]),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: Theme.of(context)
          .textTheme
          .titleLarge
          ?.copyWith(fontWeight: FontWeight.w900));
}

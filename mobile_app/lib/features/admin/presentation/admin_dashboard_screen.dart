import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/auth_controller.dart';
import '../data/admin_workspace_repository.dart';
import '../domain/admin_workspace_models.dart';

final _adminDashboardProvider =
    FutureProvider.autoDispose.family<AdminDashboardSummary, int>((ref, actor) {
  return ref.watch(adminWorkspaceRepositoryProvider).dashboard();
});

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).asData?.value;
    if (user == null) return const Scaffold(body: Center(child: Text('سجّل الدخول للمتابعة.')));
    final provider = _adminDashboardProvider(user.id);
    final state = ref.watch(provider);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(user.isPlatformOwner == true
              ? 'لوحة المدير العام / صاحب النظام'
              : 'لوحة إدارة النظام'),
          actions: [
            IconButton(
                tooltip: 'تحديث لوحة الإدارة',
                onPressed: state.isLoading ? null : () => ref.invalidate(provider),
                icon: const EbrokerIcon(Icons.refresh))
          ],
        ),
        body: state.when(
          loading: () => const AppLoadingState(label: 'جارٍ تحميل لوحة الإدارة…'),
          error: (error, _) => AppErrorState(message: friendlyApiError(error), onRetry: () => ref.invalidate(provider)),
          data: (summary) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(provider);
              try { await ref.read(provider.future); } catch (_) { /* The page renders failure and retry. */ }
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
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
                              const EbrokerIcon(Icons.notification_important_outlined),
                          title: Text(item.label,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          trailing: Badge(
                              label: Text('${item.count}'),
                              child: const EbrokerIcon(Icons.chevron_left)),
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
        label: 'طلبات توثيق الحسابات',
        value: summary.accountVerificationsPending,
        icon: Icons.verified_user_outlined,
        visible: _can('accounts.verify_profiles')
      ),
      (
        label: 'مدفوعات معلقة',
        value: summary.paymentsPending,
        icon: Icons.payments_outlined,
        visible: _can('payments.manage')
      ),
    ].where((row) => row.visible).toList(growable: false);
    return LayoutBuilder(builder: (context, constraints) {
      final columns = MediaQuery.textScalerOf(context).scale(14) > 20 ? 1 : 2;
      final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < rows.length; i++) SizedBox(width: width, child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            EbrokerIcon(rows[i].icon),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('${rows[i].value}',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w600)),
                  Text(rows[i].label),
                ])),
          ]),
        ),
      )),
      ]);
    });
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
        title: 'توثيق أنواع الحسابات',
        subtitle: 'مراجعة طلبات المالك والدلال ومكتب العقارات ومستنداتهم.',
        icon: Icons.verified_user_outlined,
        route: '/admin/account-verifications',
        visible: _can('accounts.verify_profiles')
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
            leading: EbrokerIcon(visible[i].icon),
            title: Text(visible[i].title,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(visible[i].subtitle),
            trailing: const EbrokerIcon(Icons.chevron_left),
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
          ?.copyWith(fontWeight: FontWeight.w600));
}

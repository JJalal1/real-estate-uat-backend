import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../account/data/auth_controller.dart';
import '../data/support_repository.dart';
import '../domain/support_models.dart';

final _supportSummaryProvider = FutureProvider.autoDispose<SupportAdminSummary>(
  (ref) => ref.watch(supportRepositoryProvider).adminSummary(),
);

class SupportWorkspaceScreen extends ConsumerWidget {
  const SupportWorkspaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).asData?.value;
    final state = ref.watch(_supportSummaryProvider);
    final isManager = user?.isPlatformOwner == true ||
        user?.hasPermission('support.view_team_metrics') == true;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(isManager ? 'لوحة مدير الدعم' : 'لوحة موظف الدعم'),
          actions: [
            IconButton(
                onPressed: () => ref.invalidate(_supportSummaryProvider),
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
              ref.invalidate(_supportSummaryProvider);
              await ref.read(_supportSummaryProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
              children: [
                _SupportMetrics(summary: summary),
                if (summary.slaWarning > 0 ||
                    summary.overdueUnescalated > 0) ...[
                  const SizedBox(height: 10),
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: ListTile(
                      leading: const Icon(Icons.timer_outlined),
                      title: const Text('تنبيه مدة الاستجابة',
                          style: TextStyle(fontWeight: FontWeight.w900)),
                      subtitle: Text(
                          'اقتربت ${summary.slaWarning} حالة من تجاوز SLA، ومتأخرة ${summary.overdueUnescalated} حالة.'),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text('العمل',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(children: [
                    _row(
                        context,
                        Icons.support_agent_outlined,
                        'طلبات الدعم والتذاكر',
                        'الرد، الحالة، الملاحظات الداخلية والإسناد حسب الصلاحية.',
                        '/admin/support'),
                    _row(
                        context,
                        Icons.report_outlined,
                        'البلاغات',
                        'بلاغات الإعلانات والتعليقات والتقييمات والتحويل لمسؤول أعلى.',
                        '/admin/support?kind=report'),
                    if (user?.hasPermission('users.view') == true ||
                        user?.isPlatformOwner == true)
                      _row(
                          context,
                          Icons.person_search_outlined,
                          'المستخدمون',
                          'البحث بالاسم أو الهاتف أو البريد ومشاهدة سياق الدعم.',
                          '/support/users'),
                    _row(
                        context,
                        Icons.privacy_tip_outlined,
                        'المحادثات المبلغ عنها',
                        'لا تظهر المحادثات الخاصة إلا عند وجود بلاغ، وفتح المحتوى يحتاج صلاحية مستقلة.',
                        '/admin/message-reports'),
                    if (user?.hasPermission('support.view_worklog') == true ||
                        user?.isPlatformOwner == true)
                      _row(
                          context,
                          Icons.history_outlined,
                          'سجل العمل والمتابعة',
                          'الإجراءات والتذاكر المحولة والمغلقة ووقت كل إجراء.',
                          '/support/worklog'),
                    if (user?.hasPermission('accounts.verify_profiles') == true ||
                        user?.isPlatformOwner == true)
                      _row(
                          context,
                          Icons.verified_user_outlined,
                          'توثيق أنواع الحسابات',
                          'مراجعة المالك والدلال ومكتب العقارات ومستندات كل نوع.',
                          '/admin/account-verifications',
                          last: true),
                  ]),
                ),
                if (isManager && summary.team.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('متابعة فريق الدعم',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  ...summary.team.map((member) => Card(
                          child: ListTile(
                        leading: const CircleAvatar(
                            child: Icon(Icons.support_agent)),
                        title: Text(member.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(
                            'حالات نشطة مسندة: ${member.assignedActive} • إجراءات آخر 7 أيام: ${member.actions7d}'),
                      ))),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String title,
      String subtitle, String route,
      {bool last = false}) {
    return Column(children: [
      ListTile(
          leading: Icon(icon),
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_left),
          onTap: () => context.push(route)),
      if (!last) const Divider(height: 1),
    ]);
  }
}

class _SupportMetrics extends StatelessWidget {
  const _SupportMetrics({required this.summary});
  final SupportAdminSummary summary;
  @override
  Widget build(BuildContext context) {
    final rows = [
      ('تذاكر جديدة', summary.newTickets, Icons.mark_email_unread_outlined),
      ('مسندة لي', summary.assignedToMe, Icons.assignment_ind_outlined),
      ('مفتوحة', summary.open, Icons.inbox_outlined),
      ('متأخرة', summary.overdueUnescalated, Icons.schedule_outlined),
      ('بلاغات جديدة', summary.newReports, Icons.report_problem_outlined),
      ('قيد المعالجة', summary.inProgress, Icons.autorenew),
    ];
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
                Icon(rows[i].$3),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('${rows[i].$2}',
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w900)),
                      Text(rows[i].$1)
                    ])),
              ]))),
    );
  }
}

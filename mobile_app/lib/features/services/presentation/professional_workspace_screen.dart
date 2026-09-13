import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../data/professional_workspace_repository.dart';

class ProfessionalWorkspaceScreen extends ConsumerWidget {
  const ProfessionalWorkspaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(professionalWorkspaceProvider);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: const AppAppBar(title: 'لوحة عملي'),
        body: state.when(
          loading: () => const _WorkspaceSkeleton(),
          error: (error, _) => AppErrorState(
            message: friendlyApiError(error),
            onRetry: () => ref.invalidate(professionalWorkspaceProvider),
          ),
          data: (data) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(professionalWorkspaceProvider);
              await ref.read(professionalWorkspaceProvider.future);
            },
            child: _WorkspaceContent(data: data),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceContent extends StatelessWidget {
  const _WorkspaceContent({required this.data});
  final ProfessionalWorkspace data;

  @override
  Widget build(BuildContext context) {
    final priorities = <_WorkspacePriority>[
      if (data.unreadConversations > 0)
        _WorkspacePriority(
          icon: Icons.mark_chat_unread_outlined,
          title: 'رد على ${data.unreadConversations} محادثات غير مقروءة',
          subtitle: 'العميل ينتظر ردك؛ افتح صندوق الرسائل وابدأ بالأحدث.',
          route: '/messages',
          tone: AppStatusTone.warning,
        ),
      if (data.corrections.isNotEmpty)
        _WorkspacePriority(
          icon: Icons.edit_note_outlined,
          title: 'صحح ${data.corrections.length} إعلانات معادة للتعديل',
          subtitle: 'راجع سبب الإعادة وعدّل نفس الإعلان قبل إعادة الإرسال.',
          route: '/my-listings',
          tone: AppStatusTone.warning,
        ),
      if (data.activeViewings > 0)
        _WorkspacePriority(
          icon: Icons.event_available_outlined,
          title: 'تابع ${data.activeViewings} معاينات نشطة',
          subtitle: 'راجع الموعد والحالة والطرف الآخر قبل الانتقال للخطوة التالية.',
          route: '/bookings',
          tone: AppStatusTone.info,
        ),
      if (data.activeAgreements > 0)
        _WorkspacePriority(
          icon: Icons.handshake_outlined,
          title: 'راجع ${data.activeAgreements} اتفاقات نشطة',
          subtitle: 'تأكد من آخر revision وحالة القبول قبل أي متابعة.',
          route: '/agreements',
          tone: AppStatusTone.info,
        ),
      if (data.staleListings.isNotEmpty)
        _WorkspacePriority(
          icon: Icons.update_rounded,
          title: 'راجع ${data.staleListings.length} إعلانات قديمة',
          subtitle: 'أكد التوفر وحدّث المعلومات حتى تبقى الإعلانات دقيقة.',
          route: '/my-listings',
          tone: AppStatusTone.info,
        ),
    ];

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
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadii.control),
                ),
                child: Icon(Icons.business_center_outlined, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data.publisherLabel, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      'ركز على العملاء والإعلانات التي تحتاج منك إجراء الآن.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s24),
        AppSectionHeader(
          title: 'يحتاج إجراء الآن',
          subtitle: priorities.isEmpty
              ? 'لا توجد عناصر عاجلة حالياً. استمر في متابعة نشاط العملاء.'
              : 'مرتبة من بياناتك الفعلية؛ ابدأ بالأعلى ثم انتقل لما بعده.',
        ),
        const SizedBox(height: AppSpacing.s8),
        if (priorities.isEmpty)
          const AppSurface(
            child: AppListRow(
              title: 'أنت متابع كل شيء',
              subtitle: 'لا توجد محادثات غير مقروءة أو إعلانات تحتاج تصحيحاً الآن.',
              leading: Icon(Icons.task_alt_rounded),
            ),
          )
        else
          AppSurface(
            padding: EdgeInsets.zero,
            child: Column(
              children: priorities
                  .map(
                    (item) => AppListRow(
                      title: item.title,
                      subtitle: item.subtitle,
                      leading: Icon(item.icon),
                      trailing: AppStatusBadge(label: 'إجراء', tone: item.tone),
                      onTap: () => context.push(item.route),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        const SizedBox(height: AppSpacing.s24),
        const AppSectionHeader(title: 'ملخص نشاط العملاء'),
        const SizedBox(height: AppSpacing.s12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: AppSpacing.s12,
          mainAxisSpacing: AppSpacing.s12,
          childAspectRatio: 1.45,
          children: [
            _Metric(icon: Icons.favorite_rounded, value: data.favorites, label: 'عمليات حفظ الإعلانات'),
            _Metric(
              icon: Icons.forum_outlined,
              value: data.conversations,
              label: 'محادثات العملاء',
              badge: data.unreadConversations > 0 ? '${data.unreadConversations} غير مقروء' : null,
              onTap: () => context.push('/messages'),
            ),
            _Metric(
              icon: Icons.calendar_month_outlined,
              value: data.activeViewings,
              label: 'معاينات نشطة',
              onTap: () => context.push('/bookings'),
            ),
            _Metric(
              icon: Icons.handshake_outlined,
              value: data.activeAgreements,
              label: 'اتفاقات نشطة',
              onTap: () => context.push('/agreements'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s24),
        AppSectionHeader(
          title: 'إعلاناتي',
          actionLabel: 'فتح الكل',
          onAction: () => context.push('/my-listings'),
        ),
        const SizedBox(height: AppSpacing.s12),
        AppSurface(
          child: Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              AppStatusBadge(label: '${data.publishedListings} منشور', tone: AppStatusTone.success),
              AppStatusBadge(label: '${data.pendingListings} قيد المراجعة', tone: AppStatusTone.info),
              AppStatusBadge(label: '${data.draftListings} مسودة'),
              if (data.returnedListings > 0)
                AppStatusBadge(label: '${data.returnedListings} يحتاج تصحيح', tone: AppStatusTone.warning),
            ],
          ),
        ),
        if (data.corrections.isNotEmpty || data.staleListings.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s24),
          const AppSectionHeader(
            title: 'تحتاج انتباهك',
            subtitle: 'هذه ليست أرقام تجميلية؛ كل عنصر هنا له إجراء واضح.',
          ),
          const SizedBox(height: AppSpacing.s8),
          AppSurface(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ...data.corrections.map((item) => AppListRow(
                      title: item.title,
                      subtitle: item.reason ?? 'أعد تصحيح الإعلان وأرسله للمراجعة.',
                      leading: const Icon(Icons.edit_note_outlined),
                      trailing: const AppStatusBadge(label: 'تصحيح', tone: AppStatusTone.warning),
                      onTap: () => context.push('/properties/${item.id}'),
                    )),
                ...data.staleListings.map((item) => AppListRow(
                      title: item.title,
                      subtitle: 'الإعلان منشور منذ فترة بدون تحديث. راجع المعلومات والتوفر.',
                      leading: const Icon(Icons.update_rounded),
                      trailing: const Icon(Icons.chevron_left_rounded),
                      onTap: () => context.push('/properties/${item.id}'),
                    )),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.s24),
        AppButton(
          label: 'إضافة عقار جديد',
          icon: Icons.add_home_work_outlined,
          onPressed: () => context.push('/add-property'),
          expand: true,
        ),
      ],
    );
  }
}

class _WorkspacePriority {
  const _WorkspacePriority({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
  final AppStatusTone tone;
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.value, required this.label, this.badge, this.onTap});
  final IconData icon;
  final int value;
  final String label;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const Spacer(),
          Text('$value', style: Theme.of(context).textTheme.headlineSmall),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (badge != null)
            Text(
              badge!,
              maxLines: 1,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
        ],
      ),
    );
  }
}

class _WorkspaceSkeleton extends StatelessWidget {
  const _WorkspaceSkeleton();
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsetsDirectional.all(AppLayout.compactPageGutter),
      children: const [
        AppSkeleton(height: 110),
        SizedBox(height: AppSpacing.s20),
        AppSkeleton(height: 250),
        SizedBox(height: AppSpacing.s20),
        AppSkeleton(height: 140),
      ],
    );
  }
}

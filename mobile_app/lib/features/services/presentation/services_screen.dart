import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/auth_controller.dart';
import '../../properties/presentation/saved_searches_screen.dart';
import '../data/service_repository.dart';
import '../domain/service_models.dart';
import 'professional_workspace_screen.dart';
import 'property_journey_screen.dart';

class ServicesScreen extends ConsumerWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.page,
        appBar: const AppAppBar(title: 'الخدمات والأدوات'),
        body: auth.when(
          loading: () => const AppLoadingState(),
          error: (_, __) => AppErrorState(
            message: 'تعذر تحميل بيانات الحساب.',
            onRetry: () => ref.read(authControllerProvider.notifier).refresh(),
          ),
          data: (user) {
            if (user == null) {
              return AppEmptyState(
                title: 'سجّل الدخول أولاً',
                message: 'الخدمات المرتبطة بالحساب تظهر بعد تسجيل الدخول.',
                icon: Icons.apps_outlined,
                actionLabel: 'تسجيل الدخول',
                onAction: () => context.push('/auth'),
              );
            }

            final hub = ref.watch(freeServicesHubProvider);
            return hub.when(
              loading: () => const AppLoadingState(label: 'جارٍ تحميل الخدمات...'),
              error: (error, _) => AppErrorState(
                message: friendlyApiError(error),
                onRetry: () => ref.invalidate(freeServicesHubProvider),
              ),
              data: (model) => RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(freeServicesHubProvider);
                  await ref.read(freeServicesHubProvider.future);
                },
                child: _ServicesHub(model: model),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ServicesHub extends StatelessWidget {
  const _ServicesHub({required this.model});

  final FreeServicesHubModel model;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final professionalMessage = model.verifiedProfessional
        ? 'حسابك موثق للنشر وإدارة العقارات.'
        : model.accountType == 'basic'
            ? 'تصفح العقارات والأدوات، وفعّل صفتك المهنية عندما تحتاج إلى النشر.'
            : 'أكمل التحقق من صفتك المهنية لتفعيل نشر العقارات.';

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppLayout.compactPageGutter,
        AppSpacing.s12,
        AppLayout.compactPageGutter,
        AppSpacing.s32,
      ),
      children: [
        AppSurface(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadii.control),
                ),
                child: Icon(Icons.home_work_outlined, color: scheme.primary),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'أدوات عقارية تساعدك تكمل الرحلة',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      'الخدمات الحالية مجانية • ${model.accountTypeLabel} • $professionalMessage',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s24),
        const AppSectionHeader(
          title: 'أدوات الباحث',
          subtitle: 'من البحث إلى المعاينة والاتفاق، بدون ما تضيع الخطوة التالية.',
        ),
        const SizedBox(height: AppSpacing.s8),
        AppSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              AppListRow(
                title: 'رحلتي العقارية',
                subtitle: 'المحفوظات والرسائل والمعاينات والاتفاقات مع الخطوة التالية.',
                leading: const Icon(Icons.route_outlined),
                trailing: const AppStatusBadge(label: 'جديد', tone: AppStatusTone.success),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const PropertyJourneyScreen()),
                ),
              ),
              const Divider(height: 1),
              AppListRow(
                title: 'البحوث المحفوظة والتنبيهات',
                subtitle: 'تابع نتائج بحثك واحصل على تنبيه عند ظهور عقار مطابق.',
                leading: const Icon(Icons.saved_search_rounded),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SavedSearchesScreen()),
                ),
              ),
              const Divider(height: 1),
              AppListRow(
                title: 'اتفاقاتي وعقودي',
                subtitle: 'تابع الاتفاقات المقبولة وعقود الإيجار المرتبطة بعقاراتك.',
                leading: const Icon(Icons.handshake_outlined),
                trailing: const AppStatusBadge(label: 'متاح', tone: AppStatusTone.success),
                onTap: () => context.push('/agreements'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s24),
        const AppSectionHeader(
          title: 'أدوات المعلن',
          subtitle: 'النشر والإدارة والمتابعة حسب صلاحية حسابك وحالة التحقق.',
        ),
        const SizedBox(height: AppSpacing.s8),
        AppSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              if (model.verifiedProfessional) ...[
                AppListRow(
                  title: 'لوحة عملي',
                  subtitle: 'نشاط العملاء، المعاينات، الاتفاقات والإعلانات التي تحتاج إجراء.',
                  leading: const Icon(Icons.space_dashboard_outlined),
                  trailing: const AppStatusBadge(label: 'جديد', tone: AppStatusTone.success),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const ProfessionalWorkspaceScreen()),
                  ),
                ),
                const Divider(height: 1),
              ],
              AppListRow(
                title: 'إضافة عقار',
                subtitle: model.can('create_listing')
                    ? 'أنشئ إعلاناً جديداً وأرسله للمراجعة.'
                    : 'يتطلب حساب مالك أو دلال أو مكتب عقاري موثق.',
                leading: const Icon(Icons.add_home_work_outlined),
                trailing: AppStatusBadge(
                  label: model.requiresVerification('create_listing') ? 'يتطلب التحقق' : 'متاح',
                  tone: model.requiresVerification('create_listing')
                      ? AppStatusTone.warning
                      : AppStatusTone.success,
                ),
                onTap: () {
                  if (model.can('create_listing') && model.isAvailable('create_listing')) {
                    context.push('/add-property');
                  } else {
                    context.push('/account-verification');
                  }
                },
              ),
              const Divider(height: 1),
              AppListRow(
                title: 'إعلاناتي',
                subtitle: 'تابع إعلاناتك وحالات المراجعة والنشر.',
                leading: const Icon(Icons.inventory_2_outlined),
                trailing: const AppStatusBadge(label: 'متاح', tone: AppStatusTone.success),
                onTap: () => context.push('/my-listings'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s24),
        const AppSectionHeader(
          title: 'قادم لاحقاً',
          subtitle: 'لن نظهر أي أداة كأنها تعمل قبل أن تكون مبنية على بيانات حقيقية ومختبرة.',
        ),
        const SizedBox(height: AppSpacing.s8),
        AppSurface(
          padding: EdgeInsets.zero,
          child: const Column(
            children: [
              _PlannedServiceRow(
                title: 'مؤشرات الأسعار',
                subtitle: 'مؤشرات من الإعلانات المنشورة والمعتمدة فقط.',
                icon: Icons.bar_chart_rounded,
              ),
              Divider(height: 1),
              _PlannedServiceRow(
                title: 'تقييم العقار',
                subtitle: 'تقدير استرشادي من عقارات مقارنة مؤهلة.',
                icon: Icons.analytics_outlined,
              ),
              Divider(height: 1),
              _PlannedServiceRow(
                title: 'الدليل العقاري',
                subtitle: 'محتوى عملي للشراء والبيع والإيجار بأمان.',
                icon: Icons.menu_book_outlined,
              ),
              Divider(height: 1),
              _PlannedServiceRow(
                title: 'المستندات القانونية',
                subtitle: 'نماذج وإرشادات معلوماتية دون ادعاء اعتماد حكومي.',
                icon: Icons.article_outlined,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlannedServiceRow extends StatelessWidget {
  const _PlannedServiceRow({required this.title, required this.subtitle, required this.icon});
  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AppListRow(
      title: title,
      subtitle: subtitle,
      leading: Icon(icon),
      trailing: const AppStatusBadge(label: 'قريباً', tone: AppStatusTone.neutral),
    );
  }
}

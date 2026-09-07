import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/auth_controller.dart';
import '../data/service_repository.dart';
import '../domain/service_models.dart';

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
            ? 'تصفح العقارات والخدمات المتاحة، وفعّل صفتك المهنية عندما تحتاج إلى النشر.'
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
                      'الخدمات الحالية مجانية',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      '${model.accountTypeLabel} • $professionalMessage',
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
          title: 'متاح الآن',
          subtitle: 'هذه المسارات تعمل فعلياً في النسخة الحالية.',
        ),
        const SizedBox(height: AppSpacing.s8),
        AppSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              AppListRow(
                title: 'إضافة عقار',
                subtitle: model.can('create_listing')
                    ? 'أنشئ إعلاناً جديداً وأرسله للمراجعة.'
                    : 'يتطلب حساب مالك أو دلال أو مكتب عقاري موثق.',
                leading: const Icon(Icons.add_home_work_outlined),
                trailing: AppStatusBadge(
                  label: model.requiresVerification('create_listing')
                      ? 'يتطلب التحقق'
                      : 'متاح',
                  tone: model.requiresVerification('create_listing')
                      ? AppStatusTone.warning
                      : AppStatusTone.success,
                ),
                onTap: () {
                  if (model.can('create_listing') &&
                      model.isAvailable('create_listing')) {
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
                trailing: const AppStatusBadge(
                  label: 'متاح',
                  tone: AppStatusTone.success,
                ),
                onTap: () => context.push('/my-listings'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s24),
        const AppSectionHeader(
          title: 'قادم لاحقاً',
          subtitle:
              'تظهر هنا الاتجاهات المعتمدة فقط، ولا تفتح مسارات وهمية قبل اكتمال الـBackend والاختبارات.',
        ),
        const SizedBox(height: AppSpacing.s8),
        AppSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              if (model.can('rental_contracts')) ...[
                const _PlannedServiceRow(
                  title: 'عقود الإيجار',
                  subtitle: 'اتفاقات داخل التطبيق مرتبطة بعقار وأطراف حقيقيين.',
                  icon: Icons.description_outlined,
                ),
                const Divider(height: 1),
              ],
              const _PlannedServiceRow(
                title: 'مؤشرات الأسعار',
                subtitle: 'مؤشرات من الإعلانات المنشورة والمعتمدة فقط.',
                icon: Icons.bar_chart_rounded,
              ),
              const Divider(height: 1),
              const _PlannedServiceRow(
                title: 'تقييم العقار',
                subtitle: 'تقدير استرشادي من عقارات مقارنة مؤهلة.',
                icon: Icons.analytics_outlined,
              ),
              const Divider(height: 1),
              const _PlannedServiceRow(
                title: 'الدليل العقاري',
                subtitle: 'محتوى عملي للشراء والبيع والإيجار بأمان.',
                icon: Icons.menu_book_outlined,
              ),
              const Divider(height: 1),
              const _PlannedServiceRow(
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
  const _PlannedServiceRow({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AppListRow(
      title: title,
      subtitle: subtitle,
      leading: Icon(icon),
      trailing: const AppStatusBadge(
        label: 'قريباً',
        tone: AppStatusTone.neutral,
      ),
    );
  }
}

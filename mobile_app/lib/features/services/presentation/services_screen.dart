import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/auth_controller.dart';
import '../data/service_repository.dart';
import '../domain/service_models.dart';
import 'professional_workspace_screen.dart';

class ServicesScreen extends ConsumerWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
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
              loading: () =>
                  const AppLoadingState(label: 'جارٍ تحميل الخدمات...'),
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
                child: EbrokerIcon(Icons.home_work_outlined, color: scheme.primary),
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
                      'الخدمات الحالية مجانية.',
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
        const AppSectionHeader(title: 'أدوات الباحث'),
        const SizedBox(height: AppSpacing.s8),
        AppSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              AppListRow(
                title: 'مقارنة العقارات',
                subtitle:
                    'قارن السعر والمساحة وخصائص العقارات في المفضلة.',
                leading: const EbrokerIcon(Icons.compare_arrows_rounded),
                trailing: const AppStatusBadge(
                  label: 'متاح الآن',
                  tone: AppStatusTone.success,
                ),
                onTap: () => context.push('/favorites?compare=1'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s24),
        const AppSectionHeader(
          title: 'أدوات المعلن',
          subtitle:
              'أنشئ إعلاناتك وتابع حالتها.',
        ),
        const SizedBox(height: AppSpacing.s8),
        AppSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              if (model.verifiedProfessional && const ['broker', 'office'].contains(model.accountType)) ...[
                AppListRow(
                  title: 'لوحة عملي',
                  subtitle:
                      'نشاط العملاء، الرسائل، الاتفاقات والإعلانات التي تحتاج إجراء.',
                  leading: const EbrokerIcon(Icons.space_dashboard_outlined),
                  trailing: const AppStatusBadge(
                    label: 'متاح الآن',
                    tone: AppStatusTone.success,
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ProfessionalWorkspaceScreen(),
                    ),
                  ),
                ),
                const Divider(height: 1),
              ],
              AppListRow(
                title: 'إضافة عقار',
                subtitle: 'أضف تفاصيل العقار وصوره ثم انشر إعلانك.',
                leading: const EbrokerIcon(Icons.add_home_work_outlined),
                onTap: () => context.push('/add-property'),
              ),
              const Divider(height: 1),
              AppListRow(
                title: 'إعلاناتي',
                subtitle:
                    'تابع دورة الإعلان، وما يحتاج إجراء، والمراجعة والنشر.',
                leading: const EbrokerIcon(Icons.inventory_2_outlined),
                trailing: const AppStatusBadge(
                  label: 'متاح الآن',
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
              'لن نظهر أي أداة كأنها تعمل قبل أن تكون مبنية ومختبرة فعليًا.',
        ),
        const SizedBox(height: AppSpacing.s8),
        const AppSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _PlannedServiceRow(
                title: 'الدليل العقاري',
                subtitle: 'محتوى عملي للشراء والبيع والإيجار بأمان.',
                icon: Icons.menu_book_outlined,
              ),
              Divider(height: 1),
              _PlannedServiceRow(
                title: 'نماذج وإرشادات المستندات',
                subtitle:
                    'محتوى معلوماتي يساعد المستخدم دون ادعاء اعتماد حكومي أو قانوني.',
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
      leading: EbrokerIcon(icon),
      trailing: const AppStatusBadge(
        label: 'قريباً',
        tone: AppStatusTone.neutral,
      ),
    );
  }
}

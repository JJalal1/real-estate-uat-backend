import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/v2_package.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/auth_controller.dart';

class P02HomeScreen extends ConsumerWidget {
  const P02HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).asData?.value;
    final scheme = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('عقارات حولك'),
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpacing.s16),
              child: Center(
                child: Container(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: AppSpacing.s10,
                    vertical: AppSpacing.s4,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    V2Package.code,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppLayout.compactPageGutter,
            AppSpacing.s20,
            AppLayout.compactPageGutter,
            AppSpacing.s40,
          ),
          children: [
            Text(
              user == null ? 'وين تريد العقار؟' : 'وين تريد العقار يا ${_firstName(user.name)}؟',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              'ابدأ بالمكان، ثم اختر بيع أو إيجار ونوع العقار والفلاتر التي تحتاجها فقط.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: AppSpacing.s20),
            AppSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadii.control),
                    onTap: () => context.push('/property-market'),
                    child: Container(
                      padding: const EdgeInsetsDirectional.all(AppSpacing.s16),
                      decoration: BoxDecoration(
                        border: Border.all(color: scheme.outlineVariant),
                        borderRadius: BorderRadius.circular(AppRadii.control),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search_rounded, color: scheme.primary),
                          const SizedBox(width: AppSpacing.s12),
                          Expanded(
                            child: Text(
                              'ابحث بالمنطقة أو حرّك الخريطة',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s12),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: 'للبيع',
                          icon: Icons.sell_outlined,
                          expand: true,
                          onPressed: () => context.push('/property-market'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s8),
                      Expanded(
                        child: AppButton(
                          label: 'للإيجار',
                          icon: Icons.key_outlined,
                          style: AppButtonStyle.outlined,
                          expand: true,
                          onPressed: () => context.push('/property-market'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s24),
            const AppSectionHeader(
              title: 'اختصارات مفيدة',
              subtitle: 'أشياء تحتاجها بعد البحث، بدون ازدحام في الصفحة الرئيسية.',
            ),
            const SizedBox(height: AppSpacing.s10),
            AppSurface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  AppListRow(
                    title: 'المفضلة',
                    subtitle: 'العقارات التي حفظتها للرجوع لها',
                    leading: const Icon(Icons.favorite_border_rounded),
                    onTap: () => context.push('/favorites'),
                  ),
                  const Divider(height: 1),
                  AppListRow(
                    title: 'طلباتي العقارية الخاصة',
                    subtitle: 'إذا ما لقيت المناسب، خلّ النظام يتابع لك',
                    leading: const Icon(Icons.manage_search_outlined),
                    onTap: () => context.push('/property-requests'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s24),
            AppInlineMessage(
              title: 'طلباتك خاصة',
              message:
                  'طلب العقار لا يظهر للدلالين أو المكاتب. يستخدمه النظام لمطابقة العقارات الجديدة وإشعارك.',
              tone: AppStatusTone.info,
            ),
          ],
        ),
      ),
    );
  }

  static String _firstName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty ? name : parts.first;
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/v2_package.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/auth_controller.dart';

class P01HomeScreen extends ConsumerWidget {
  const P01HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).asData?.value;
    final scheme = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('عقارات حولك'),
          actions: const [
            Padding(
              padding: EdgeInsetsDirectional.only(end: AppSpacing.s16),
              child: Center(child: _PackageBadge()),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppLayout.compactPageGutter,
            AppSpacing.s16,
            AppLayout.compactPageGutter,
            AppSpacing.s32,
          ),
          children: [
            AppSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(AppRadii.control),
                    ),
                    child: Icon(
                      Icons.location_city_outlined,
                      color: scheme.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  Text(
                    user == null ? 'أهلاً بك' : 'مرحباً ' + _firstName(user.name),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.s6),
                  Text(
                    'هذه الحزمة تثبّت تجربة الحساب والهوية قبل إضافة السوق والعقارات في الحزمة التالية.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.s20),
                  if (user == null)
                    AppButton(
                      label: 'تسجيل الدخول أو إنشاء حساب',
                      icon: Icons.login,
                      expand: true,
                      onPressed: () => context.push('/auth'),
                    )
                  else if (user.needsProfileCompletion)
                    AppButton(
                      label: 'إكمال بيانات الحساب',
                      icon: Icons.edit_outlined,
                      expand: true,
                      onPressed: () => context.push('/complete-profile'),
                    )
                  else
                    AppButton(
                      label: user.hasVerifiedPublishingProfile
                          ? 'عرض حالة التوثيق'
                          : 'التوثيق كمالك أو دلال أو مكتب',
                      icon: user.hasVerifiedPublishingProfile
                          ? Icons.verified_outlined
                          : Icons.badge_outlined,
                      expand: true,
                      onPressed: () => context.push('/account-verification'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppLayout.groupGap),
            const AppSectionHeader(
              title: 'ما نختبره الآن',
              subtitle: 'ركزوا على الوضوح والبساطة وسهولة الحركة، وليس عدد الميزات.',
            ),
            const SizedBox(height: AppSpacing.s12),
            const _FocusItem(
              icon: Icons.phone_android_outlined,
              title: 'الدخول والحساب',
              subtitle: 'رقم واتساب، رمز التحقق، الاسم والملف الشخصي.',
            ),
            const SizedBox(height: AppSpacing.s10),
            const _FocusItem(
              icon: Icons.verified_user_outlined,
              title: 'الهوية والتوثيق',
              subtitle: 'مالك، دلال، أو مكتب بخطوات واضحة ومعلومات تظهر عند الحاجة فقط.',
            ),
            const SizedBox(height: AppSpacing.s10),
            const _FocusItem(
              icon: Icons.touch_app_outlined,
              title: 'سهولة الاستخدام',
              subtitle: 'خط عربي واضح، مسافات مريحة، وحركة بسيطة بدون حشو.',
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

class _FocusItem extends StatelessWidget {
  const _FocusItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PackageBadge extends StatelessWidget {
  const _PackageBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
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
    );
  }
}

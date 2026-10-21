import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/auth_controller.dart';
import '../../../core/branding/aqer_brand.dart';

class Stage6AuthGate extends ConsumerWidget {
  const Stage6AuthGate({
    super.key,
    required this.child,
    this.requireActive = true,
    this.requireListingEligible = false,
    this.requireProfessional = false,
  });

  final Widget child;
  final bool requireActive;
  final bool requireListingEligible;
  final bool requireProfessional;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(authControllerProvider).when(
          loading: () =>
              const Scaffold(body: AqerAccountLoading()),
          error: (_, __) => Scaffold(
            appBar: AppBar(),
            body: Center(
              child: EbrokerFilledButton.icon(
                onPressed: () =>
                    ref.read(authControllerProvider.notifier).refresh(),
                icon: const EbrokerIcon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ),
          ),
          data: (user) {
            if (user == null) {
              return _GateMessage(
                icon: Icons.lock_outline,
                title: 'سجّل الدخول أولاً',
                message: 'هذه العملية مرتبطة بحسابك الحقيقي.',
                button: 'تسجيل الدخول',
                onPressed: () => context.push('/auth'),
              );
            }
            if (requireActive && !user.isActive) {
              return _GateMessage(
                icon: Icons.verified_user_outlined,
                title: 'تحقق من رقم واتساب',
                message: 'أكمل التحقق لتتمكن من إدارة حسابك.',
                button: 'التحقق الآن',
                onPressed: () => context.push('/verify-phone'),
              );
            }
            if (requireListingEligible && user.needsProfileCompletion) {
              return _GateMessage(
                icon: Icons.edit_outlined,
                title: 'أكمل الاسم الرباعي أولاً',
                message:
                    'أكمل بيانات الحساب الأساسية قبل اختيار نوع الحساب وبدء إجراءات النشر.',
                button: 'إكمال البيانات',
                onPressed: () => context.push('/complete-profile'),
              );
            }
            if (requireListingEligible && !user.hasVerifiedPublishingProfile) {
              return _GateMessage(
                icon: Icons.badge_outlined,
                title: 'توثيق نوع الحساب مطلوب',
                message:
                    'للنشر اختر من حسابي نوع الحساب: مالك أو دلال أو مكتب عقارات، ثم أرسل مستندات التحقق وانتظر اعتماد فريق التحقق.',
                button: 'اختيار نوع الحساب والتحقق',
                onPressed: () => context.push('/account-verification'),
              );
            }
            if (requireProfessional && !user.hasVerifiedProfessionalProfile) {
              return _GateMessage(icon: Icons.work_outline, title: 'أدوات الدلال بعد اعتماد التوثيق',
                message: 'فعّل حساب دلال أو مكتب عقارات ليظهر لك العمل والعملاء والإحصائيات.',
                button: 'فعّل حساب دلال', onPressed: () => context.push('/account-verification?upgrade=broker'));
            }
            return KeyedSubtree(key: ValueKey('account:${user.id}'), child: child);
          },
        );
  }
}

class _GateMessage extends StatelessWidget {
  const _GateMessage(
      {required this.icon,
      required this.title,
      required this.message,
      required this.button,
      required this.onPressed});
  final IconData icon;
  final String title;
  final String message;
  final String button;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                EbrokerIcon(icon, size: 68),
                const SizedBox(height: 16),
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                EbrokerFilledButton(onPressed: onPressed, child: Text(button)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

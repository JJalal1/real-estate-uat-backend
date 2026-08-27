import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/auth_controller.dart';

class Stage6AuthGate extends ConsumerWidget {
  const Stage6AuthGate({
    super.key,
    required this.child,
    this.requireActive = true,
    this.requireListingEligible = false,
  });

  final Widget child;
  final bool requireActive;
  final bool requireListingEligible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(authControllerProvider).when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (_, __) => Scaffold(
            appBar: AppBar(),
            body: Center(
              child: FilledButton.icon(
                onPressed: () =>
                    ref.read(authControllerProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh),
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
            if (requireListingEligible &&
                user.isBroker &&
                !user.isBrokerVerified) {
              return _GateMessage(
                icon: Icons.badge_outlined,
                title: 'توثيق حساب الدلال مطلوب',
                message:
                    'يمكنك تصفح الإعلانات الآن، لكن رفع إعلان يتطلب موافقة فريق الدعم على صورة البطاقة الأمامية والخلفية وصورة السلفي.',
                button: 'إرسال بيانات التوثيق',
                onPressed: () => context.push('/broker/account-verification'),
              );
            }
            return child;
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
                Icon(icon, size: 68),
                const SizedBox(height: 16),
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton(onPressed: onPressed, child: Text(button)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

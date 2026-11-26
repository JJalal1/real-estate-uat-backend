import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/auth_controller.dart';
import '../../../core/branding/aqer_brand.dart';

class Stage6AuthGate extends ConsumerStatefulWidget {
  const Stage6AuthGate({
    super.key,
    required this.child,
    this.requireActive = true,
    this.requireListingEligible = false,
    this.requireProfessional = false,
    this.guestIcon = Icons.lock_outline,
  });

  final Widget child;
  final IconData guestIcon;
  final bool requireActive;
  final bool requireListingEligible;
  final bool requireProfessional;

  @override
  ConsumerState<Stage6AuthGate> createState() => _Stage6AuthGateState();
}

class _Stage6AuthGateState extends ConsumerState<Stage6AuthGate> {
  int? _boundActor;
  bool _changed = false;
  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (_, next) {
      if (_boundActor != null && next.asData != null && next.asData?.value?.id != _boundActor) {
        setState(() => _changed = true);
      }
    });
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
                icon: widget.guestIcon,
                title: 'سجّل الدخول أولاً',
                message: 'هذه العملية مرتبطة بحسابك الحقيقي.',
                button: 'تسجيل الدخول',
                onPressed: () => context.push('/auth'),
              );
            }
            _boundActor ??= user.id;
            if (_changed) {
              return _GateMessage(icon: Icons.account_circle_outlined, title: 'تغيّر الحساب',
                message: 'أعد فتح الصفحة من حسابك الحالي لحماية بيانات الحساب السابق.',
                button: 'العودة للرئيسية', onPressed: () => context.go('/'));
            }
            if (widget.requireActive && !user.isActive) {
              return _GateMessage(
                icon: Icons.verified_user_outlined,
                title: 'تحقق من رقم واتساب',
                message: 'أكمل التحقق لتتمكن من إدارة حسابك.',
                button: 'التحقق الآن',
                onPressed: () => context.push('/verify-phone'),
              );
            }
            if (widget.requireListingEligible && user.needsProfileCompletion) {
              return _GateMessage(
                icon: Icons.edit_outlined,
                title: 'أكمل الاسم الرباعي أولاً',
                message:
                    'أكمل بيانات حسابك الأساسية لنشر إعلانك.',
                button: 'إكمال البيانات',
                onPressed: () => context.push('/complete-profile'),
              );
            }
            if (widget.requireProfessional && !user.hasMarketplaceProfessionalProfile) {
              return _GateMessage(
                icon: Icons.work_outline,
                title: 'أدوات الدلال',
                message: 'يمكنك ترقية حسابك عند نشر إعلانك الثاني لإدارة عقاراتك وعملائك.',
                button: 'إعلاناتي',
                onPressed: () => context.push('/my-listings'),
              );
            }
            return KeyedSubtree(key: ValueKey((user.id,user.isActive,user.roles.toString(),user.permissions.toString())), child: widget.child);
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
          child: SingleChildScrollView(child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _GateIllustration(icon: icon),
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
          )),
        ),
      ),
    );
  }
}

class _GateIllustration extends StatelessWidget {
  const _GateIllustration({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.primaryContainer, borderRadius: BorderRadius.circular(22),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Icon(icon, size: 44, color: colors.onPrimaryContainer),
          ),
        ),
        if (icon == Icons.chat_bubble_outline || icon == Icons.inventory_2_outlined)
          PositionedDirectional(
            end: -3, top: -3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
                border: Border.all(width: 2, color: Theme.of(context).scaffoldBackgroundColor),
              ),
              child: const SizedBox.square(dimension: 16),
            ),
          ),
      ],
    );
  }
}

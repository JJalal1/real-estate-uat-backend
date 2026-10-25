import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/widgets/app_components.dart';
import '../data/auth_controller.dart';

/// Private page state belongs to one resolved account and permission scope.
/// Replacing the subtree also rejects late receipts through its mounted guards.
class ActorScopedPage extends ConsumerWidget {
  const ActorScopedPage({required this.title, required this.builder, super.key});
  final String title;
  final WidgetBuilder builder;
  Widget _state(Widget child) => Scaffold(appBar: AppBar(title: Text(title)), body: child);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    if (auth.isLoading) return _state(const AppLoadingState(label: 'جارٍ تحميل الحساب…'));
    if (auth.hasError) {
      return _state(AppErrorState(message: friendlyApiError(auth.error!),
        onRetry: () => ref.invalidate(authControllerProvider)));
    }
    final actor = auth.asData?.value;
    if (actor == null) return _state(const Center(child: Text('سجّل الدخول للمتابعة.')));
    return KeyedSubtree(key: ValueKey((actor.id, actor.isActive, actor.roles.toString(), actor.permissions.toString())),
      child: Builder(builder: builder));
  }
}

/// Forms initialized from private data cannot be transferred to another actor.
/// Keep the binding even if logout and login happen before the next frame.
class ActorBoundPage extends ConsumerStatefulWidget {
  const ActorBoundPage({required this.title, required this.builder, super.key});
  final String title;
  final WidgetBuilder builder;
  @override
  ConsumerState<ActorBoundPage> createState() => _ActorBoundPageState();
}

class _ActorBoundPageState extends ConsumerState<ActorBoundPage> {
  int? _actor;
  bool _changed = false;

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (_, next) {
      if (_actor != null && next.asData != null && next.asData?.value?.id != _actor) {
        setState(() => _changed = true);
      }
    });
    final actor = ref.watch(authControllerProvider).asData?.value;
    if (!_changed && _actor == null && actor != null) _actor = actor.id;
    // Keep the normal guest entry state after logout. A later login still
    // cannot reuse this page's old private form, even with the same user ID.
    if (_changed && actor != null) {
      return Scaffold(appBar: AppBar(title: Text(widget.title)),
        body: AppEmptyState(title: 'تغيّر الحساب',
          message: 'أعد فتح هذه الصفحة من حسابك الحالي لحماية بيانات الحساب السابق.',
          icon: Icons.account_circle_outlined, actionLabel: 'العودة',
          onAction: () => Navigator.of(context).maybePop()));
    }
    return ActorScopedPage(title: widget.title, builder: widget.builder);
  }
}

Widget _accountOverlay({required int actor, required WidgetBuilder builder,
  required WidgetBuilder changed}) => _ActorBoundOverlay(actor: actor, builder: builder, changed: changed);

class _ActorBoundOverlay extends ConsumerStatefulWidget {
  const _ActorBoundOverlay({required this.actor, required this.builder, required this.changed});
  final int actor;
  final WidgetBuilder builder;
  final WidgetBuilder changed;
  @override
  ConsumerState<_ActorBoundOverlay> createState() => _ActorBoundOverlayState();
}

class _ActorBoundOverlayState extends ConsumerState<_ActorBoundOverlay> {
  bool _expired = false;
  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (_, next) {
      if (next.asData != null && next.asData?.value?.id != widget.actor) _expired = true;
    });
    final current = ref.watch(authControllerProvider).asData?.value?.id;
    if (current != widget.actor) _expired = true;
    return _expired ? widget.changed(context) : widget.builder(context);
  }
}

Future<T?> showActorDialog<T>({required BuildContext context, required WidgetRef ref,
  required WidgetBuilder builder, bool barrierDismissible = true}) {
  final actor = ref.read(authControllerProvider).asData?.value?.id;
  if (actor == null) return Future<T?>.value();
  return showDialog<T>(context: context, barrierDismissible: barrierDismissible, builder: (_) => _accountOverlay(actor: actor,
    builder: builder, changed: (dialog) => AlertDialog(title: const Text('تغيّر الحساب'),
      content: const Text('أغلق النافذة وأعد فتح العملية من حسابك الحالي.'),
      actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('إغلاق'))])));
}

Future<T?> showActorModalBottomSheet<T>({required BuildContext context, required WidgetRef ref,
  required WidgetBuilder builder, bool isScrollControlled = false, bool useSafeArea = false}) {
  final actor = ref.read(authControllerProvider).asData?.value?.id;
  if (actor == null) return Future<T?>.value();
  return showModalBottomSheet<T>(context: context, isScrollControlled: isScrollControlled, useSafeArea: useSafeArea,
    builder: (_) => _accountOverlay(actor: actor, builder: builder,
      changed: (sheet) => SafeArea(child: Padding(padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('تغيّر الحساب'), const SizedBox(height: 12),
          TextButton(onPressed: () => Navigator.pop(sheet), child: const Text('إغلاق')),
        ])))));
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/widgets/app_components.dart';
import '../data/auth_controller.dart';

/// Private page state belongs to one resolved account and permission scope.
/// Replacing the subtree also rejects late receipts through its mounted guards.
class ActorScopedPage extends ConsumerWidget {
  const ActorScopedPage({required this.builder, super.key});
  final WidgetBuilder builder;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    if (auth.isLoading) return const Scaffold(body: AppLoadingState(label: 'جارٍ تحميل الحساب…'));
    if (auth.hasError) {
      return Scaffold(body: AppErrorState(message: friendlyApiError(auth.error!),
        onRetry: () => ref.invalidate(authControllerProvider)));
    }
    final actor = auth.asData?.value;
    if (actor == null) return const Scaffold(body: Center(child: Text('سجّل الدخول للمتابعة.')));
    return KeyedSubtree(key: ValueKey((actor.id, actor.isActive, actor.roles.toString(), actor.permissions.toString())),
      child: Builder(builder: builder));
  }
}

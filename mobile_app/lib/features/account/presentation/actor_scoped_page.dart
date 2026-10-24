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

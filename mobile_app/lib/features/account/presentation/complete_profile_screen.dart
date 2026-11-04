import 'package:flutter/material.dart';
import 'actor_scoped_page.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../data/auth_controller.dart';
import '../data/auth_return_intent.dart';

class CompleteProfileScreen extends ConsumerWidget {
  const CompleteProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ActorBoundPage(
    title: 'إكمال الحساب', builder: (_) => const _CompleteProfileScreenBody());
}

class _CompleteProfileScreenBody extends ConsumerStatefulWidget {
  const _CompleteProfileScreenBody();
  @override
  ConsumerState<_CompleteProfileScreenBody> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends ConsumerState<_CompleteProfileScreenBody> {
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('إكمال الحساب')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'أدخل اسمك الرباعي',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'اكتب الاسم الرباعي كما هو في وثيقة الهوية. بعد ذلك يصبح حسابك حسابًا أساسيًا للتصفح والبحث والشراء، ويمكنك لاحقًا اختيار نوع حساب موثق من صفحة «حسابي».',
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              textInputAction: TextInputAction.done,
              onSubmitted: _busy ? null : (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'الاسم الرباعي',
                hintText: 'الاسم الأول الثاني الثالث الرابع',

              ),
            ),
            const SizedBox(height: 16),
            EbrokerFilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const EbrokerIcon(Icons.check_circle_outline),
              label: const Text('حفظ ومتابعة'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final parts = _name.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل الاسم الرباعي كاملًا.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).completeProfile(_name.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إكمال الحساب بنجاح.')),
      );
      context.go(takeAuthReturnLocation(ref));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../data/auth_controller.dart';

class CompleteProfileScreen extends ConsumerStatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  ConsumerState<CompleteProfileScreen> createState() =>
      _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends ConsumerState<CompleteProfileScreen> {
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
                  ?.copyWith(fontWeight: FontWeight.w900),
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
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline),
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
      context.go('/');
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

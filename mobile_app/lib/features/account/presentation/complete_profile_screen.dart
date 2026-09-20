import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/design/app_design.dart';
import '../data/auth_controller.dart';
import '../data/auth_return_intent.dart';

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
        appBar: const AppAppBar(title: 'إكمال الحساب'),
        body: AppContentFrame(child: ListView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s24),
          children: [
            const AppIdentityMark(icon: Icons.person_outline),
            const AppPageHeading(
              title: 'أدخل اسمك الرباعي',
              subtitle: 'اكتب الاسم الرباعي كما هو في وثيقة الهوية. بعد ذلك يصبح حسابك حسابًا أساسيًا للتصفح والبحث والشراء، ويمكنك لاحقًا اختيار نوع حساب موثق من صفحة «حسابي».',
            ),
            AppSectionCard(
              title: 'الاسم في وثيقة الهوية',
              child: TextField(
                controller: _name,
                textInputAction: TextInputAction.done,
                onSubmitted: _busy ? null : (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'الاسم الرباعي',
                  hintText: 'الاسم الأول الثاني الثالث الرابع',
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s24),
            AppButton(
              label: 'حفظ ومتابعة',
              icon: Icons.check_circle_outline,
              loading: _busy,
              onPressed: _busy ? null : _submit,
              expand: true,
            ),
          ],
        )),
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

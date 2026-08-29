import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../data/auth_controller.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, this.startWithRegister = false});

  // Retained for route compatibility with older deep links. The unified flow
  // no longer exposes separate login/register modes.
  final bool startWithRegister;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _phone = TextEditingController(text: '+967');
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('تسجيل الدخول أو إنشاء حساب')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Icon(Icons.home_work_outlined, size: 72),
            const SizedBox(height: 18),
            Text(
              'حساب واحد للجميع',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'أدخل رقم واتساب. إذا كان لديك حساب سنسجل دخولك، وإذا كان الرقم جديدًا سننشئ حسابًا أساسيًا كباحث أو متصفح أو مشتري.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              onSubmitted: _busy ? null : (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'رقم واتساب',
                hintText: '+9677xxxxxxxx',
                prefixIcon: Icon(Icons.chat_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'سيتم إرسال رمز تحقق مكوّن من 6 أرقام عبر واتساب. الحساب الجديد سيُطلب منه إدخال الاسم الرباعي بعد التحقق.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.mark_chat_read_outlined),
              label: const Text('إرسال رمز واتساب'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .startWhatsApp(phone: _phone.text);
      if (!mounted) return;
      context.push('/verify-phone');
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

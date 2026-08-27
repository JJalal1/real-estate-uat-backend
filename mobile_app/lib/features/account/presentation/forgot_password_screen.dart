import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../data/auth_controller.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _login = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _requested = false;
  bool _busy = false;
  String? _debugCode;

  @override
  void dispose() {
    _login.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('استعادة الحساب')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _login,
              enabled: !_requested,
              decoration: const InputDecoration(
                labelText: 'البريد الإلكتروني أو الهاتف',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            if (!_requested)
              FilledButton(
                onPressed: _busy ? null : _request,
                child: const Text('إرسال رمز الاستعادة'),
              )
            else ...[
              if (_debugCode != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'رمز بيئة التطوير المحلية: $_debugCode',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'رمز الاستعادة',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور الجديدة',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _busy ? null : _reset,
                child: const Text('تغيير كلمة المرور'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _request() async {
    setState(() => _busy = true);
    try {
      final code = await ref
          .read(authControllerProvider.notifier)
          .requestPasswordReset(_login.text);
      if (!mounted) return;
      setState(() {
        _requested = true;
        _debugCode = code;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).resetPassword(
            login: _login.text,
            code: _code.text,
            password: _password.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تغيير كلمة المرور. سجّل الدخول من جديد.'),
        ),
      );
      context.go('/auth');
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

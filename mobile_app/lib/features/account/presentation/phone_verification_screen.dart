import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../data/auth_controller.dart';

class PhoneVerificationScreen extends ConsumerStatefulWidget {
  const PhoneVerificationScreen({super.key});

  @override
  ConsumerState<PhoneVerificationScreen> createState() =>
      _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState
    extends ConsumerState<PhoneVerificationScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _legacyDebugCode;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(whatsAppAuthPendingProvider);
    final user = ref.watch(authControllerProvider).asData?.value;
    final debugCode = pending?.debugCode ?? _legacyDebugCode;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('رمز التحقق عبر واتساب')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              pending != null
                  ? 'أدخل الرمز الذي أُرسل إلى واتساب: ${pending.phone}'
                  : user?.phone == null
                      ? 'اطلب رمز التحقق.'
                      : 'سيتم التحقق من الرقم: ${user!.phone}',
            ),
            const SizedBox(height: 16),
            if (pending == null)
              OutlinedButton.icon(
                onPressed: _busy ? null : _requestLegacyCode,
                icon: const Icon(Icons.chat_outlined),
                label: const Text('إرسال رمز واتساب'),
              )
            else
              OutlinedButton.icon(
                onPressed: _busy ? null : _resendPending,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة إرسال الرمز'),
              ),
            if (debugCode != null) ...[
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'رمز بيئة الاختبار المحلية: $debugCode',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              maxLength: 6,
              onSubmitted: _busy ? null : (_) => _verify(),
              decoration: const InputDecoration(
                  labelText: 'رمز التحقق', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _verify,
              icon: const Icon(Icons.verified_outlined),
              label: const Text('تأكيد والدخول'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resendPending() async {
    final pending = ref.read(whatsAppAuthPendingProvider);
    if (pending == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .startWhatsApp(phone: pending.phone);
      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _requestLegacyCode() async {
    setState(() => _busy = true);
    try {
      final code = await ref
          .read(authControllerProvider.notifier)
          .requestPhoneVerification();
      if (mounted) {
        setState(() => _legacyDebugCode = code);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _verify() async {
    setState(() => _busy = true);
    try {
      final pending = ref.read(whatsAppAuthPendingProvider);
      if (pending != null) {
        final result = await ref
            .read(authControllerProvider.notifier)
            .verifyWhatsApp(_code.text);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم التحقق من رقم واتساب بنجاح.')),
        );
        context.go(result.user.needsProfileCompletion ? '/complete-profile' : '/');
        return;
      }

      await ref.read(authControllerProvider.notifier).verifyPhone(_code.text);
      if (!mounted) return;
      final user = ref.read(authControllerProvider).asData?.value;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم التحقق من رقم واتساب بنجاح.')),
      );
      context.go(user?.needsProfileCompletion == true ? '/complete-profile' : '/');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}

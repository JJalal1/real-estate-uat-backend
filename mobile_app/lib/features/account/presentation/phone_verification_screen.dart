import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../../core/widgets/ebroker_otp_field.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../data/auth_controller.dart';
import '../data/auth_return_intent.dart';

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
        appBar: AppBar(title: Text(pending?.isEmail == true ? 'رمز التحقق عبر البريد' : 'رمز التحقق عبر واتساب')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              pending != null
                  ? 'أدخل رمز التحقق المرسل إلى ${pending.isEmail ? 'البريد' : 'واتساب'}: ${pending.destination}'
                  : user?.phone == null
                      ? 'أضف رقم واتساب إلى ملفك الشخصي ثم أكّد الرقم.'
                      : 'سيتم التحقق من الرقم: ${user!.phone}',
            ),
            const SizedBox(height: 16),
            if (pending == null)
              EbrokerOutlinedButton.icon(
                onPressed: _busy ? null : user?.phone == null ? () => context.push('/profile') : _requestLegacyCode,
                icon: const EbrokerIcon(Icons.chat_outlined),
                label: Text(user?.phone == null ? 'إضافة رقم واتساب' : 'إرسال رمز واتساب'),
              )
            else
              EbrokerOutlinedButton.icon(
                onPressed: _busy ? null : _resendPending,
                icon: const EbrokerIcon(Icons.refresh),
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
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            EbrokerOtpField(controller: _code,
              onSubmitted: _busy ? null : (_) => _verify()),
            const SizedBox(height: 12),
            EbrokerFilledButton.icon(
              onPressed: _busy ? null : _verify,
              icon: const EbrokerIcon(Icons.verified_outlined),
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
      final auth = ref.read(authControllerProvider.notifier);
      if (pending.isEmail) { await auth.startEmail(email: pending.email!, name: pending.name); }
      else { await auth.startWhatsApp(phone: pending.phone, name: pending.name); }
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
          SnackBar(content: Text(pending.isEmail ? 'تم التحقق من البريد بنجاح.' : 'تم التحقق من رقم واتساب بنجاح.')),
        );
        if (result.user.needsProfileCompletion) {
          context.go('/complete-profile');
        } else {
          context.go(takeAuthReturnLocation(ref));
        }
        return;
      }

      await ref.read(authControllerProvider.notifier).verifyPhone(_code.text);
      if (!mounted) return;
      final user = ref.read(authControllerProvider).asData?.value;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم التحقق من رقم واتساب بنجاح.')),
      );
      if (user?.needsProfileCompletion == true) {
        context.go('/complete-profile');
      } else {
        context.go(takeAuthReturnLocation(ref));
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
}


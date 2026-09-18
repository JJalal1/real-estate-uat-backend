import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_error_message.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_components.dart';
import '../../data/auth_controller.dart';
import '../../data/auth_return_intent.dart';

class P01PhoneVerificationScreen extends ConsumerStatefulWidget {
  const P01PhoneVerificationScreen({super.key});

  @override
  ConsumerState<P01PhoneVerificationScreen> createState() =>
      _P01PhoneVerificationScreenState();
}

class _P01PhoneVerificationScreenState
    extends ConsumerState<P01PhoneVerificationScreen> {
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
    final phone = pending?.phone ?? user?.phone;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('تأكيد رقم واتساب')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.all(
              AppLayout.compactPageGutter,
            ),
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: AppLayout.contentMaxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'أدخل رمز التحقق',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.s6),
                  Text(
                    phone == null
                        ? 'أدخل الرمز المرسل عبر واتساب.'
                        : 'أرسلنا رمزًا من 6 أرقام إلى ' + phone,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                  ),
                  if (debugCode != null) ...[
                    const SizedBox(height: AppSpacing.s16),
                    AppInlineMessage(
                      title: 'رمز بيئة الاختبار',
                      message: debugCode,
                      tone: AppStatusTone.info,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.s20),
                  TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                    decoration: const InputDecoration(
                      labelText: 'رمز التحقق',
                      counterText: '',
                    ),
                    onSubmitted: _busy ? null : (_) => _verify(),
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  AppButton(
                    label: 'تأكيد',
                    icon: Icons.verified_outlined,
                    expand: true,
                    loading: _busy,
                    onPressed: _busy ? null : _verify,
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  AppButton(
                    label: 'إعادة إرسال الرمز',
                    style: AppButtonStyle.text,
                    expand: true,
                    onPressed: _busy
                        ? null
                        : pending == null
                            ? _requestLegacyCode
                            : _resendPending,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _resendPending() async {
    final pending = ref.read(whatsAppAuthPendingProvider);
    if (pending == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .startWhatsApp(phone: pending.phone);
      _message('تم إرسال رمز جديد.');
    } catch (error) {
      _message(friendlyApiError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestLegacyCode() async {
    setState(() => _busy = true);
    try {
      final code = await ref
          .read(authControllerProvider.notifier)
          .requestPhoneVerification();
      if (mounted) setState(() => _legacyDebugCode = code);
    } catch (error) {
      _message(friendlyApiError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length != 6 || int.tryParse(code) == null) {
      _message('أدخل رمز التحقق المكوّن من 6 أرقام.');
      return;
    }

    setState(() => _busy = true);
    try {
      final pending = ref.read(whatsAppAuthPendingProvider);
      if (pending != null) {
        final result = await ref
            .read(authControllerProvider.notifier)
            .verifyWhatsApp(code);
        if (!mounted) return;
        if (result.user.needsProfileCompletion) {
          context.go('/complete-profile');
        } else {
          context.go(takeAuthReturnLocation(ref));
        }
        return;
      }

      await ref.read(authControllerProvider.notifier).verifyPhone(code);
      if (!mounted) return;
      final user = ref.read(authControllerProvider).asData?.value;
      if (user?.needsProfileCompletion == true) {
        context.go('/complete-profile');
      } else {
        context.go(takeAuthReturnLocation(ref));
      }
    } catch (error) {
      _message(friendlyApiError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

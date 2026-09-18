import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_error_message.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_components.dart';
import '../../data/auth_controller.dart';

class P02LoginScreen extends ConsumerStatefulWidget {
  const P02LoginScreen({super.key});

  @override
  ConsumerState<P02LoginScreen> createState() => _P02LoginScreenState();
}

class _P02LoginScreenState extends ConsumerState<P02LoginScreen> {
  final _phone = TextEditingController(text: '+967');
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          actions: [
            TextButton.icon(
              onPressed: () => context.push('/support-info'),
              icon: const Icon(Icons.headset_mic_outlined, size: 19),
              label: const Text('الدعم'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AuthMark(
                      icon: Icons.key_rounded,
                      background: scheme.secondaryContainer,
                      foreground: scheme.secondary,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'مرحباً بعودتك',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'سجّل الدخول برقمك المسجل. سنرسل لك رمز تحقق سريع عبر واتساب.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 28),
                    AppTextField(
                      controller: _phone,
                      label: 'رقم الهاتف',
                      hint: '+967 7xx xxx xxx',
                      prefixIcon: Icons.phone_iphone_rounded,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      onSubmitted: _busy ? null : (_) => _submit(),
                    ),
                    const SizedBox(height: 16),
                    AppButton(
                      label: 'إرسال رمز الدخول',
                      icon: Icons.arrow_back_rounded,
                      expand: true,
                      loading: _busy,
                      onPressed: _busy ? null : _submit,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'ما عندك حساب؟',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        TextButton(
                          onPressed: _busy ? null : () => context.go('/register'),
                          child: const Text('إنشاء حساب'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _TrustLine(
                      icon: Icons.lock_outline_rounded,
                      text: 'رقم واحد = حساب واحد. لن ننشئ حساباً جديداً عند تسجيل الدخول.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final phone = _normalizePhoneInput(_phone.text);
    if (!_looksLikePhone(phone)) {
      _message('أدخل رقم هاتف صحيحاً مع مفتاح الدولة.');
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).startWhatsApp(
            phone: phone,
            intent: 'login',
          );
      if (!mounted) return;
      context.push('/verify-phone');
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
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
  }
}

class _AuthMark extends StatelessWidget {
  const _AuthMark({
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(icon, color: foreground, size: 30),
      ),
    );
  }
}

class _TrustLine extends StatelessWidget {
  const _TrustLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsetsDirectional.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

String _normalizePhoneInput(String value) {
  var text = value.trim();
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  const latin = '0123456789';
  for (var i = 0; i < arabic.length; i++) {
    text = text.replaceAll(arabic[i], latin[i]);
  }
  text = text.replaceAll(RegExp(r'[\s\-().]'), '');
  if (text.startsWith('00')) text = '+${text.substring(2)}';
  return text;
}

bool _looksLikePhone(String value) =>
    RegExp(r'^\+?[0-9]{7,20}$').hasMatch(value);

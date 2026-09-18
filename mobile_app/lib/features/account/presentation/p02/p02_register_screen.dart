import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_error_message.dart';
import '../../../../core/widgets/app_components.dart';
import '../../data/auth_controller.dart';

class P02RegisterScreen extends ConsumerStatefulWidget {
  const P02RegisterScreen({super.key});

  @override
  ConsumerState<P02RegisterScreen> createState() => _P02RegisterScreenState();
}

class _P02RegisterScreenState extends ConsumerState<P02RegisterScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController(text: '+967');
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
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
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Container(
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                          color: scheme.tertiaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          Icons.person_add_alt_1_rounded,
                          color: scheme.onTertiaryContainer,
                          size: 30,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'أنشئ حسابك',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'خطوتان فقط: بياناتك الأساسية ثم رمز التحقق.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 28),
                    AppTextField(
                      controller: _name,
                      label: 'الاسم الكامل',
                      hint: 'مثال: أحمد محمد علي',
                      prefixIcon: Icons.person_outline_rounded,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 14),
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
                      label: 'إنشاء الحساب',
                      icon: Icons.arrow_back_rounded,
                      expand: true,
                      loading: _busy,
                      onPressed: _busy ? null : _submit,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'لن نطلب منك اختيار مشتري أو مستأجر. صفة مالك أو دلال أو مكتب تُفعّل لاحقاً فقط عند حاجتك للنشر.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'عندك حساب؟',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        TextButton(
                          onPressed: _busy ? null : () => context.go('/login'),
                          child: const Text('تسجيل الدخول'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsetsDirectional.all(14),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.verified_user_outlined,
                            size: 20,
                            color: scheme.secondary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'إذا كان الرقم مسجلاً مسبقاً فلن يُنشأ حساب آخر، وسيطلب منك استخدام تسجيل الدخول.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ],
                      ),
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
    final name = _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final parts = name.split(' ').where((part) => part.isNotEmpty).toList();
    if (parts.length != 3) {
      _message('أدخل الاسم الثلاثي الكامل.');
      return;
    }

    final phone = _normalizePhoneInput(_phone.text);
    if (!_looksLikePhone(phone)) {
      _message('أدخل رقم هاتف صحيحاً مع مفتاح الدولة.');
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).startWhatsApp(
            phone: phone,
            intent: 'register',
            name: name,
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

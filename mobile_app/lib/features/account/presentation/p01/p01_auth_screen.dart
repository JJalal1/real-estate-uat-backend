import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_error_message.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_components.dart';
import '../../data/auth_controller.dart';

class P01AuthScreen extends ConsumerStatefulWidget {
  const P01AuthScreen({super.key, this.startWithRegister = false});

  final bool startWithRegister;

  @override
  ConsumerState<P01AuthScreen> createState() => _P01AuthScreenState();
}

class _P01AuthScreenState extends ConsumerState<P01AuthScreen> {
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
        appBar: AppBar(),
        body: SafeArea(
          child: Center(
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
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(AppRadii.card),
                        ),
                        child: Icon(
                          Icons.home_work_outlined,
                          color: scheme.primary,
                          size: 30,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s20),
                    Text(
                      'دخول بسيط بحساب واحد',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    Text(
                      'أدخل رقم واتساب وسنرسل لك رمز التحقق. إذا كان الرقم جديدًا يُنشأ الحساب تلقائيًا.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.s24),
                    AppTextField(
                      controller: _phone,
                      label: 'رقم واتساب',
                      hint: '+9677xxxxxxxx',
                      prefixIcon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      onSubmitted: _busy ? null : (_) => _submit(),
                    ),
                    const SizedBox(height: AppSpacing.s16),
                    AppButton(
                      label: 'متابعة',
                      icon: Icons.arrow_back,
                      expand: true,
                      loading: _busy,
                      onPressed: _busy ? null : _submit,
                    ),
                    const SizedBox(height: AppSpacing.s16),
                    Text(
                      'لن نطلب منك اختيار مشتري أو مستأجر عند التسجيل. إذا أردت النشر يمكنك توثيق صفتك لاحقًا.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
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
    final phone = _phone.text.trim();
    if (phone.length < 8) {
      _message('أدخل رقم واتساب صحيحًا.');
      return;
    }

    setState(() => _busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .startWhatsApp(phone: phone, intent: 'login');
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
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

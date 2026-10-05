import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_error_message.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_components.dart';
import '../../data/auth_controller.dart';
import '../../data/auth_return_intent.dart';

class P01CompleteProfileScreen extends ConsumerStatefulWidget {
  const P01CompleteProfileScreen({super.key});

  @override
  ConsumerState<P01CompleteProfileScreen> createState() =>
      _P01CompleteProfileScreenState();
}

class _P01CompleteProfileScreenState
    extends ConsumerState<P01CompleteProfileScreen> {
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
                  Text('اسمك كما في الهوية',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: AppSpacing.s6),
                  Text(
                    'أدخل الاسم الرباعي مرة واحدة. سنستخدمه لاحقًا عند طلب التوثيق.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.s20),
                  AppTextField(
                    controller: _name,
                    label: 'الاسم الرباعي',
                    hint: 'الاسم الأول الثاني الثالث الرابع',
                    prefixIcon: Icons.person_outline,
                    textInputAction: TextInputAction.done,
                    onSubmitted: _busy ? null : (_) => _submit(),
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  AppButton(
                    label: 'حفظ ومتابعة',
                    icon: Icons.check,
                    expand: true,
                    loading: _busy,
                    onPressed: _busy ? null : _submit,
                  ),
                ],
              ),
            ),
          ),
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
      _message('أدخل الاسم الرباعي كاملًا.');
      return;
    }

    setState(() => _busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .completeProfile(_name.text);
      if (!mounted) return;
      context.go(takeAuthReturnLocation(ref));
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

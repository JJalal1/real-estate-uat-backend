import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_error_message.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_components.dart';
import '../../data/auth_controller.dart';
import '../../domain/auth_user.dart';

class P01ProfileScreen extends ConsumerStatefulWidget {
  const P01ProfileScreen({super.key});

  @override
  ConsumerState<P01ProfileScreen> createState() => _P01ProfileScreenState();
}

class _P01ProfileScreenState extends ConsumerState<P01ProfileScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _initialized = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).asData?.value;
    if (!_initialized && user != null) {
      _initialized = true;
      _name.text = user.name;
      _phone.text = user.phone ?? '';
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الملف الشخصي')),
        body: user == null
            ? const Center(child: Text('سجّل الدخول أولاً.'))
            : ListView(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppLayout.compactPageGutter,
                  AppSpacing.s20,
                  AppLayout.compactPageGutter,
                  AppSpacing.s32,
                ),
                children: [
                  AppTextField(
                    controller: _name,
                    label: 'الاسم الرباعي',
                    prefixIcon: Icons.person_outline,
                    enabled: !_nameLocked(user),
                  ),
                  if (_nameLocked(user)) ...[
                    const SizedBox(height: AppSpacing.s8),
                    AppInlineMessage(
                      title: 'الاسم مرتبط بالتوثيق',
                      message:
                          'لتصحيح الاسم بعد بدء مراجعة الهوية تواصل مع الدعم.',
                      tone: AppStatusTone.info,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.s16),
                  AppTextField(
                    controller: _phone,
                    label: 'رقم الهاتف',
                    prefixIcon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Text(
                    'تغيير رقم الهاتف يتطلب التحقق من الرقم الجديد.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.s20),
                  AppButton(
                    label: 'حفظ',
                    icon: Icons.save_outlined,
                    expand: true,
                    loading: _busy,
                    onPressed: _busy ? null : _save,
                  ),
                ],
              ),
      ),
    );
  }

  bool _nameLocked(AuthUser user) =>
      user.verificationProfile.status == 'pending' ||
      user.verificationProfile.status == 'approved';

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).updateProfile(
            name: _name.text,
            phone: _phone.text,
          );
      _message('تم حفظ بيانات الحساب.');
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

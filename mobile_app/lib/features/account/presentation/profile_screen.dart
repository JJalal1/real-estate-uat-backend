import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/widgets/ebroker_otp_field.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../broker/data/broker_repository.dart';
import '../../broker/presentation/broker_public_profile.dart';
import '../data/auth_controller.dart';
import '../domain/auth_user.dart';
import 'actor_scoped_page.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ActorBoundPage(
    title: 'الملف الشخصي',
    builder: (_) => const _ProfileScreenBody(),
  );
}

class _ProfileScreenBody extends ConsumerStatefulWidget {
  const _ProfileScreenBody();

  @override
  ConsumerState<_ProfileScreenBody> createState() => _ProfileScreenState();
}

enum _ProfileField {
  fullName('الاسم الرباعي', TextInputType.name),
  phone('رقم الهاتف', TextInputType.phone),
  email('البريد الإلكتروني', TextInputType.emailAddress);

  const _ProfileField(this.label, this.keyboardType);

  final String label;
  final TextInputType keyboardType;

  String savedValue(AuthUser user) => switch (this) {
    fullName => user.name.trim() == 'مستخدم جديد' ? '' : user.name.trim(),
    phone => user.phone?.trim() ?? '',
    email => user.email.toLowerCase().endsWith('@phone.local.invalid')
        ? ''
        : user.email.trim(),
  };

  String normalize(String value) =>
      this == email ? value.trim().toLowerCase() : value.trim();
}

class _ProfileScreenState extends ConsumerState<_ProfileScreenBody> {
  final _form = GlobalKey<FormState>();
  final _controllers = {
    for (final field in _ProfileField.values) field: TextEditingController(),
  };
  final _focus = {
    for (final field in _ProfileField.values) field: FocusNode(),
  };
  final _editing = <_ProfileField>{};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authControllerProvider).asData?.value;
    if (user != null) _resetFields(user);
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _resetFields(AuthUser user) {
    _editing.clear();
    for (final field in _ProfileField.values) {
      final value = field.savedValue(user);
      _controllers[field]!.text = value;
      if (value.isEmpty) _editing.add(field);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).asData?.value;
    final publicProfile = user?.isActive == true
        ? ref.watch(brokerProfileProvider(user!.id)).valueOrNull
        : null;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الملف الشخصي')),
        body: user == null
            ? const Center(child: Text('يجب تسجيل الدخول.'))
            : Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (publicProfile != null && publicProfile.id == user.id) ...[
                      BrokerPublicProfileSummary(profile: publicProfile),
                      BrokerPublicProfileActions(
                        profile: publicProfile,
                        enabled: !_busy,
                      ),
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 12),
                    ],
                    _field(_ProfileField.fullName, user),
                    const SizedBox(height: 16),
                    _field(_ProfileField.phone, user),
                    const SizedBox(height: 8),
                    const Text(
                      'تغيير رقم الهاتف يعيد الحساب إلى حالة انتظار التحقق.',
                    ),
                    if (!user.isActive && _ProfileField.phone.savedValue(user).isNotEmpty)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy ? null : () => context.push('/verify-phone'),
                          icon: const Icon(Icons.phone_outlined),
                          label: const Text('تأكيد رقم الهاتف'),
                        ),
                      ),
                    const SizedBox(height: 16),
                    _field(_ProfileField.email, user),
                    TextButton.icon(
                      key: const ValueKey('profile-verify-email'),
                      onPressed: _busy ||
                              user.isEmailVerified ||
                              _ProfileField.email.savedValue(user).isEmpty
                          ? null
                          : _confirmEmail,
                      icon: Icon(user.isEmailVerified
                          ? Icons.verified_outlined
                          : Icons.mark_email_read_outlined),
                      label: Text(user.isEmailVerified
                          ? 'البريد مؤكد'
                          : 'تأكيد البريد لاستخدامه في الدخول'),
                    ),
                    const SizedBox(height: 18),
                    EbrokerFilledButton.icon(
                      onPressed: _busy || !_hasChanges(user)
                          ? null
                          : () => _save(user),
                      icon: const EbrokerIcon(Icons.save_outlined),
                      label: const Text('حفظ'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _field(_ProfileField field, AuthUser user) {
    final editable = _editing.contains(field);
    return TextFormField(
      key: ValueKey('profile-field-${field.name}'),
      controller: _controllers[field],
      focusNode: _focus[field],
      readOnly: _busy || !editable,
      keyboardType: field.keyboardType,
      textDirection: field == _ProfileField.fullName ? null : TextDirection.ltr,
      textAlign: TextAlign.right,
      decoration: InputDecoration(
        labelText: field.label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        suffixIcon: editable
            ? null
            : IconButton(
                key: ValueKey('profile-edit-${field.name}'),
                tooltip: 'تعديل ${field.label}',
                icon: const Icon(Icons.edit_outlined),
                onPressed: _busy
                    ? null
                    : () {
                        setState(() => _editing.add(field));
                        _focus[field]!.requestFocus();
                      },
              ),
      ),
      onChanged: (_) => setState(() {}),
      validator: (value) => editable &&
              field.savedValue(user).isNotEmpty &&
              (value?.trim().isEmpty ?? true)
          ? 'أدخل ${field.label}'
          : null,
    );
  }

  bool _hasChanges(AuthUser user) =>
      _ProfileField.values.any((field) => _changedValue(field, user) != null);

  String? _changedValue(_ProfileField field, AuthUser user) {
    final value = field.normalize(_controllers[field]!.text);
    final current = field.normalize(field.savedValue(user));
    return _editing.contains(field) && value != current ? value : null;
  }

  Future<void> _confirmEmail() async {
    final user = ref.read(authControllerProvider).asData?.value;
    if (user == null || _busy) return;
    if (_changedValue(_ProfileField.email, user) != null) {
      _showMessage('احفظ البريد الجديد أولًا ثم أكّده.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).requestEmailVerification();
      if (!mounted) return;
      final value = await showActorDialog<String>(
        context: context,
        ref: ref,
        builder: (_) => _EmailCodeDialog(email: user.email),
      );
      if (value == null || !mounted) return;
      await ref.read(authControllerProvider.notifier).verifyEmail(value);
      if (mounted) {
        _showMessage('تم تأكيد البريد. يمكنك الدخول به إلى الحساب نفسه.');
      }
    } catch (error) {
      if (mounted) _showMessage(friendlyApiError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(AuthUser user) async {
    if (_busy || !_form.currentState!.validate()) return;
    final name = _changedValue(_ProfileField.fullName, user);
    final phone = _changedValue(_ProfileField.phone, user);
    final email = _changedValue(_ProfileField.email, user);
    if (name == null && phone == null && email == null) return;

    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).updateProfile(
        name: name,
        phone: phone,
        email: email,
      );
      if (!mounted) return;
      final saved = ref.read(authControllerProvider).asData?.value;
      if (saved?.id != user.id) return;
      _resetFields(saved!);
      if (name != null) invalidateBrokerProfile(ref, user.id);
      _showMessage('تم حفظ الملف الشخصي.');
    } catch (error) {
      if (mounted) _showMessage(friendlyApiError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _EmailCodeDialog extends StatefulWidget {
  const _EmailCodeDialog({required this.email});
  final String email;
  @override
  State<_EmailCodeDialog> createState() => _EmailCodeDialogState();
}
class _EmailCodeDialogState extends State<_EmailCodeDialog> {
  final _code = TextEditingController();
  @override
  void dispose() { _code.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl,
    child: AlertDialog(title: const Text('تأكيد البريد الإلكتروني'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('أدخل الرمز المرسل إلى ${widget.email}'), const SizedBox(height: 16), EbrokerOtpField(controller: _code),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        TextButton(onPressed: () => Navigator.pop(context, _code.text), child: const Text('تأكيد'))]));
}


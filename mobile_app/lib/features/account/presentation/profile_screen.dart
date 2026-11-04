import 'package:flutter/material.dart';
import 'actor_scoped_page.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../../core/widgets/ebroker_otp_field.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../data/auth_controller.dart';
import '../domain/auth_user.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ActorBoundPage(
    title: 'الملف الشخصي', builder: (_) => const _ProfileScreenBody());
}

class _ProfileScreenBody extends ConsumerStatefulWidget {
  const _ProfileScreenBody();
  @override
  ConsumerState<_ProfileScreenBody> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<_ProfileScreenBody> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  bool _initialized = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).asData?.value;
    if (!_initialized && user != null) {
      _initialized = true;
      _name.text = user.name;
      _phone.text = user.phone ?? '';
      _email.text = user.email;
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الملف الشخصي')),
        body: user == null
            ? const Center(child: Text('يجب تسجيل الدخول.'))
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (user.hasVerifiedPublishingProfile) TextButton.icon(onPressed: () => context.push('/advertisers/${user.id}'), icon: const EbrokerIcon(Icons.add_a_photo_outlined, size: 20), label: const Text('تعديل الصورة والنبذة العامة')),
                  TextField(
                    controller: _name,
                    enabled: !_nameLocked(user),
                    decoration: const InputDecoration(
                      labelText: 'الاسم الرباعي',

                    ),
                  ),
                  if (_nameLocked(user)) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'الاسم مرتبط بمراجعة الهوية ولا يمكن تغييره أثناء قيد المراجعة أو بعد الاعتماد. عند الحاجة إلى تصحيح الاسم تواصل مع الدعم لإعادة فتح التحقق.',
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'رقم الهاتف',

                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'تغيير رقم الهاتف يعيد الحساب إلى حالة انتظار التحقق.',
                  ),
                  const SizedBox(height: 18),
                  TextField(controller: _email, keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'البريد الإلكتروني')),
                  TextButton.icon(key: const ValueKey('profile-verify-email'),
                    onPressed: _busy || user.isEmailVerified ? null : _confirmEmail,
                    icon: Icon(user.isEmailVerified ? Icons.verified_outlined : Icons.mark_email_read_outlined),
                    label: Text(user.isEmailVerified ? 'البريد مؤكد' : 'تأكيد البريد لاستخدامه في الدخول')),
                  const SizedBox(height: 18),
                  EbrokerFilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: const EbrokerIcon(Icons.save_outlined),
                    label: const Text('حفظ'),
                  ),
                ],
              ),
      ),
    );
  }

  bool _nameLocked(AuthUser user) =>
      user.verificationProfile.status == 'pending' ||
      user.verificationProfile.status == 'approved';

  Future<void> _confirmEmail() async {
    final user = ref.read(authControllerProvider).asData?.value;
    if (user == null) return;
    if (_email.text.trim().toLowerCase() != user.email) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('احفظ البريد الجديد أولًا ثم أكّده.'))); return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).requestEmailVerification();
      if (!mounted) return;
      final value = await showActorDialog<String>(context: context, ref: ref, builder: (_) => _EmailCodeDialog(email: user.email));
      if (value == null || !mounted) return;
      await ref.read(authControllerProvider.notifier).verifyEmail(value);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تأكيد البريد. يمكنك الدخول به إلى الحساب نفسه.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).updateProfile(
            name: _name.text,
            phone: _phone.text,
            email: _email.text,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ الملف الشخصي.')),
        );
      }
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


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../data/auth_controller.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, this.startWithRegister = false});
  final bool startWithRegister;
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _phone = TextEditingController(text: '+967');
  final _name = TextEditingController();
  final _email = TextEditingController();
  late bool _register;
  bool _useEmail = false;
  bool _busy = false;
  String? _error;
  @override
  void initState() { super.initState(); _register = widget.startWithRegister; }
  @override
  void dispose() { _phone.dispose(); _name.dispose(); _email.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(
      backgroundColor: const Color(0xFF101F30),
      body: DecoratedBox(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topRight,
        end: Alignment.bottomLeft, colors: [Color(0xFF132D40), Color(0xFF101F30), Color(0xFF0B1725)])),
        child: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(24, 12, 24, 28), children: [
          Row(children: [Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(14)), child: const EbrokerImage('home_active', size: 24, color: Color(0xFF9CE6D8))),
            const SizedBox(width: 10), Expanded(child: Text('عقارات حولك', style: theme.textTheme.titleSmall?.copyWith(color: Colors.white))),
            IconButton(tooltip: 'رجوع', onPressed: () {
              if (context.canPop()) { context.pop(); } else { context.go('/'); }
            }, icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white70))]),
          const SizedBox(height: 44),
          Align(alignment: AlignmentDirectional.centerStart, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(color: const Color(0xFF9CE6D8).withValues(alpha: .1), borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFF9CE6D8).withValues(alpha: .22))),
            child: const Text('خطوة أقرب إلى مكانك', style: TextStyle(color: Color(0xFFAFEBDD), fontSize: 12)))),
          const SizedBox(height: 18), Text('مكانك القادم\nيبدأ من هنا.', style: theme.textTheme.headlineLarge?.copyWith(
            fontSize: 34, height: 1.5, color: Colors.white, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10), Text('احفظ ما يعجبك، تواصل مع المعلنين،\nوتابع فرصك في مكان واحد.',
            style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFFB7C9D7), height: 1.7)),
          const SizedBox(height: 32),
          Container(key: const ValueKey('auth-form-card'), padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(color: const Color(0xFF192F43), borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: .08))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('مرحبًا بك', style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: [
                ChoiceChip(key: const ValueKey('auth-mode-login'), label: const Text('تسجيل الدخول'), selected: !_register,
                  onSelected: _busy ? null : (_) => setState(() { _register = false; _error = null; })),
                ChoiceChip(key: const ValueKey('auth-mode-register'), label: const Text('إنشاء حساب جديد'), selected: _register,
                  onSelected: _busy ? null : (_) => setState(() { _register = true; _error = null; })),
              ]),
              const SizedBox(height: 12),
              Text(_register ? 'أدخل اسمك واختر طريقة التحقق.' : 'اختر البريد أو واتساب للدخول برمز تحقق فقط.',
                style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFFB7C9D7))),
              const SizedBox(height: 16),
              if (_register) ...[
                TextField(key: const ValueKey('auth-name'), controller: _name, enabled: !_busy,
                autofillHints: const [AutofillHints.name], textInputAction: TextInputAction.next,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'الاسم الرباعي',
                  labelStyle: TextStyle(color: Color(0xFFB7C9D7)), fillColor: Color(0xFF102336))),
                const SizedBox(height: 12),
              ],
              Wrap(spacing: 8, runSpacing: 8, children: [
                ChoiceChip(key: const ValueKey('auth-channel-whatsapp'), label: const Text('واتساب'), selected: !_useEmail,
                  onSelected: _busy ? null : (_) => setState(() { _useEmail = false; _error = null; })),
                ChoiceChip(key: const ValueKey('auth-channel-email'), label: const Text('البريد الإلكتروني'), selected: _useEmail,
                  onSelected: _busy ? null : (_) => setState(() { _useEmail = true; _error = null; })),
              ]),
              const SizedBox(height: 12),
              if (_useEmail) TextField(key: const ValueKey('auth-email'), controller: _email,
                keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email],
                enabled: !_busy, textDirection: TextDirection.ltr, textInputAction: TextInputAction.done,
                onSubmitted: _busy ? null : (_) => _submit(), style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'البريد الإلكتروني', hintText: 'name@example.com',
                  floatingLabelBehavior: FloatingLabelBehavior.always, labelStyle: TextStyle(color: Color(0xFFB7C9D7)),
                  hintStyle: TextStyle(color: Color(0xFF9AABB9)), fillColor: Color(0xFF102336)))
              else TextField(key: const ValueKey('auth-phone'), controller: _phone, keyboardType: TextInputType.phone,
                enabled: !_busy, autofillHints: const [AutofillHints.telephoneNumber],
                textInputAction: TextInputAction.done, onSubmitted: _busy ? null : (_) => _submit(), textDirection: TextDirection.ltr,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: InputDecoration(labelText: 'رقم واتساب', hintText: '+9677xxxxxxxx',
                  floatingLabelBehavior: FloatingLabelBehavior.always, labelStyle: const TextStyle(color: Color(0xFFB7C9D7)),
                  hintStyle: const TextStyle(color: Color(0xFF9AABB9)), fillColor: const Color(0xFF102336),
                  prefixIcon: const Icon(Icons.phone_outlined, color: Color(0xFF9CE6D8)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF355066))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF9CE6D8))),
                )),
              const SizedBox(height: 12), Text(_useEmail ? 'نرسل لك رمز تحقق من 6 أرقام إلى بريدك. للبريد المرتبط بحساب واتساب، أكّد البريد من الملف الشخصي أولًا.' : 'نرسل لك رمز تحقق من 6 أرقام عبر واتساب.',
                style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFFB7C9D7), height: 1.6)),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Semantics(liveRegion: true,
                child: Text(_error!, style: const TextStyle(color: Color(0xFFFFC7BC), height: 1.6)))),
              const SizedBox(height: 22),
              FilledButton(key: const ValueKey('auth-submit'), onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF9CE6D8), foregroundColor: const Color(0xFF103A39),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16)),
                child: _busy ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: [Flexible(child: Text(_useEmail ? 'إرسال رمز البريد' : 'إرسال رمز واتساب')),
                    const SizedBox(width: 10), const Icon(Icons.arrow_back_rounded, size: 19)])),
              const SizedBox(height: 16), Text(_register
                ? 'نحفظ اسم الحساب الجديد بعد نجاح التحقق.\nتوثيق الجوال مطلوب للنشر والتواصل.'
                : 'تدخل إلى حسابك الحالي بعد تأكيد الرمز.',
                textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFFB7C9D7), height: 1.6)),
            ])),
          const SizedBox(height: 18), TextButton(onPressed: () {
            if (context.canPop()) { context.pop(); } else { context.go('/'); }
          }, child: const Text('متابعة التصفح', style: TextStyle(color: Color(0xFF9CE6D8)))),
        ]))),
    ));
  }

  Future<void> _submit() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    if (_register && _name.text.trim().split(RegExp(r'\s+')).length != 4) {
      setState(() => _error = 'أدخل الاسم الرباعي كما هو في وثيقة الهوية.'); return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final auth = ref.read(authControllerProvider.notifier);
      final name = _register ? _name.text.trim() : null;
      if (_useEmail) { await auth.startEmail(email: _email.text, name: name); }
      else { await auth.startWhatsApp(phone: _phone.text, name: name); }
      if (mounted) context.push('/verify-phone');
    } catch (error) {
      if (mounted) setState(() => _error = friendlyApiError(error));
    } finally { if (mounted) setState(() => _busy = false); }
  }
}


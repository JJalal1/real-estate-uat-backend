import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../data/auth_controller.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, this.startWithRegister = false});
  final bool startWithRegister;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController(text: '+967');
  final _legacyLogin = TextEditingController();
  final _legacyPassword = TextEditingController();
  late bool _register;
  String _accountType = 'regular';
  bool _busy = false;
  bool _legacyMode = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _register = widget.startWithRegister;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _legacyLogin.dispose();
    _legacyPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(_register ? 'إنشاء حساب' : 'تسجيل الدخول')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('نوع الحساب',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'regular',
                    icon: Icon(Icons.person_outline),
                    label: Text('مستخدم عادي')),
                ButtonSegment(
                    value: 'broker',
                    icon: Icon(Icons.real_estate_agent_outlined),
                    label: Text('دلال')),
              ],
              selected: {_accountType},
              onSelectionChanged: _busy || _legacyMode
                  ? null
                  : (value) => setState(() => _accountType = value.first),
            ),
            const SizedBox(height: 18),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('دخول')),
                ButtonSegment(value: true, label: Text('حساب جديد')),
              ],
              selected: {_register},
              onSelectionChanged: _busy || _legacyMode
                  ? null
                  : (value) => setState(() => _register = value.first),
            ),
            const SizedBox(height: 22),
            if (!_legacyMode) ...[
              if (_register) ...[
                TextField(
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: _accountType == 'broker'
                        ? 'الاسم الثلاثي أو الرباعي'
                        : 'الاسم الثلاثي',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                onSubmitted: _busy ? null : (_) => _submitWhatsApp(),
                decoration: const InputDecoration(
                  labelText: 'رقم واتساب',
                  hintText: '+9677xxxxxxxx',
                  prefixIcon: Icon(Icons.chat_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              const Text('سيصلك رمز تحقق مكوّن من 6 أرقام عبر واتساب.',
                  style: TextStyle(color: Colors.black54)),
              if (_register && _accountType == 'broker') ...[
                const SizedBox(height: 12),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                        'بعد الدخول يمكنك تصفح الإعلانات مباشرة. ولرفع إعلان يجب توثيق حساب الدلال من الإعدادات بإرسال صورة البطاقة الأمامية والخلفية وصورة سلفي إلى فريق الدعم.'),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _busy ? null : _submitWhatsApp,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.mark_chat_read_outlined),
                label: Text(_register
                    ? 'إرسال رمز واتساب وإنشاء الحساب'
                    : 'إرسال رمز واتساب'),
              ),
            ] else ...[
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                      'دخول إداري/قديم فقط للحسابات التي ما زالت تستخدم البريد أو كلمة المرور.'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _legacyLogin,
                decoration: const InputDecoration(
                    labelText: 'البريد أو الهاتف',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _legacyPassword,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'كلمة المرور',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(_obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                  onPressed: _busy ? null : _submitLegacy,
                  child: const Text('دخول قديم')),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() => _legacyMode = !_legacyMode),
              child: Text(
                  _legacyMode ? 'العودة للدخول عبر واتساب' : 'دخول إداري/قديم'),
            ),
            if (!_register && _legacyMode)
              TextButton(
                onPressed:
                    _busy ? null : () => context.push('/forgot-password'),
                child: const Text('نسيت كلمة المرور؟'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitWhatsApp() async {
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).startWhatsApp(
            intent: _register ? 'register' : 'login',
            accountType: _accountType,
            name: _register ? _name.text : null,
            phone: _phone.text,
          );
      if (!mounted) {
        return;
      }
      context.push('/verify-phone');
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

  Future<void> _submitLegacy() async {
    setState(() => _busy = true);
    try {
      final result = await ref.read(authControllerProvider.notifier).login(
            login: _legacyLogin.text,
            password: _legacyPassword.text,
          );
      if (!mounted) {
        return;
      }
      context.go(result.user.needsPhoneVerification ? '/verify-phone' : '/');
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

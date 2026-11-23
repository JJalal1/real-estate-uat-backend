import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/branding/aqer_brand.dart';
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

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  InputDecoration _decoration(String label, IconData icon, {String? hint}) {
    final scheme = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      prefixIcon: Icon(icon, color: scheme.primary),
      filled: true,
      fillColor: scheme.primaryContainer,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      border: border,
      enabledBorder: border,
      disabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final submitColor = theme.brightness == Brightness.dark ? scheme.primary : AppTheme.brandMint;
    final onSubmit = theme.brightness == Brightness.dark ? scheme.onPrimary : AppTheme.brandStrong;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: scheme.surface,
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color.lerp(scheme.primaryContainer, scheme.surface, .45)!, scheme.surface],
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          IconButton(
                            tooltip: 'رجوع',
                            onPressed: _leave,
                            icon: const Icon(Icons.arrow_back_rounded),
                            color: scheme.onSurface,
                          ),
                          const Spacer(),
                          const AqerBrandWordmark(width: 124),
                        ]),
                        const SizedBox(height: 28),
                        Semantics(
                          header: true,
                          child: Text(
                            _register ? 'أنشئ حسابك' : 'مرحبًا بعودتك',
                            key: const ValueKey('auth-heading'),
                            style: theme.textTheme.headlineLarge?.copyWith(
                              color: scheme.onSurface,
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              height: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _register
                            ? 'احفظ عقاراتك المفضلة وتواصل مع المعلنين.'
                            : 'سجّل دخولك لحفظ العقارات والتواصل مع المعلنين.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant, height: 1.7,
                          ),
                        ),
                        const SizedBox(height: 28),
                        AutofillGroup(
                          child: Column(
                            key: const ValueKey('auth-form-card'),
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                ChoiceChip(
                                  key: const ValueKey('auth-channel-whatsapp'),
                                  label: const Text('واتساب'),
                                  selected: !_useEmail,
                                  onSelected: _busy ? null : (_) => setState(() {
                                    _useEmail = false; _error = null;
                                  }),
                                ),
                                ChoiceChip(
                                  key: const ValueKey('auth-channel-email'),
                                  label: const Text('البريد الإلكتروني'),
                                  selected: _useEmail,
                                  onSelected: _busy ? null : (_) => setState(() {
                                    _useEmail = true; _error = null;
                                  }),
                                ),
                              ]),
                              const SizedBox(height: 20),
                              if (_register) ...[
                                TextField(
                                  key: const ValueKey('auth-name'),
                                  controller: _name,
                                  enabled: !_busy,
                                  autofillHints: const [AutofillHints.name],
                                  textInputAction: TextInputAction.next,
                                  style: TextStyle(color: scheme.onSurface),
                                  decoration: _decoration('الاسم الرباعي', Icons.person_outline_rounded),
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (_useEmail)
                                TextField(
                                  key: const ValueKey('auth-email'),
                                  controller: _email,
                                  keyboardType: TextInputType.emailAddress,
                                  autofillHints: const [AutofillHints.email],
                                  enabled: !_busy,
                                  textDirection: TextDirection.ltr,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: _busy ? null : (_) => _submit(),
                                  style: TextStyle(color: scheme.onSurface),
                                  decoration: _decoration('البريد الإلكتروني', Icons.mail_outline_rounded,
                                    hint: 'name@example.com'),
                                )
                              else
                                TextField(
                                  key: const ValueKey('auth-phone'),
                                  controller: _phone,
                                  keyboardType: TextInputType.phone,
                                  enabled: !_busy,
                                  autofillHints: const [AutofillHints.telephoneNumber],
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: _busy ? null : (_) => _submit(),
                                  textDirection: TextDirection.ltr,
                                  style: TextStyle(color: scheme.onSurface, fontSize: 18),
                                  decoration: _decoration('رقم واتساب', Icons.phone_outlined,
                                    hint: '+9677xxxxxxxx'),
                                ),
                              const SizedBox(height: 12),
                              Text(
                                _useEmail
                                  ? 'نرسل لك رمز تحقق من 6 أرقام إلى بريدك.'
                                  : 'نرسل لك رمز تحقق من 6 أرقام عبر واتساب.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant, height: 1.7,
                                ),
                              ),
                              if (_error != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Semantics(liveRegion: true,
                                    child: Text(_error!, style: TextStyle(
                                      color: theme.colorScheme.error, height: 1.7,
                                    )),
                                  ),
                                ),
                              const SizedBox(height: 24),
                              FilledButton(
                                key: const ValueKey('auth-submit'),
                                onPressed: _busy ? null : _submit,
                                style: FilledButton.styleFrom(
                                  backgroundColor: submitColor,
                                  foregroundColor: onSubmit,
                                  disabledBackgroundColor: submitColor,
                                  disabledForegroundColor: onSubmit,
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                                  textStyle: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                                child: _busy
                                  ? Semantics(
                                      liveRegion: true,
                                      label: 'جارٍ إرسال رمز التحقق',
                                      child: SizedBox.square(dimension: 24,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: onSubmit)),
                                    )
                                  : Text(_useEmail ? 'إرسال رمز البريد' : 'إرسال رمز واتساب', textAlign: TextAlign.center),
                              ),
                              const SizedBox(height: 16),
                              TextButton(
                                key: ValueKey(_register ? 'auth-mode-login' : 'auth-mode-register'),
                                onPressed: _busy ? null : () => setState(() {
                                  _register = !_register; _error = null;
                                }),
                                style: TextButton.styleFrom(
                                  foregroundColor: scheme.primary,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                ),
                                child: Text(_register ? 'لديك حساب؟ تسجيل الدخول' : 'إنشاء حساب جديد',
                                  textAlign: TextAlign.center),
                              ),
                              if (_register) ...[
                                const SizedBox(height: 8),
                                Text('نحفظ اسمك بعد التحقق. توثيق الجوال مطلوب للنشر والتواصل.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.7)),
                              ],
                              if (_useEmail && !_register) ...[
                                const SizedBox(height: 8),
                                Text('لحساب واتساب، استخدم البريد الذي أكّدته من ملفك الشخصي.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.7)),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(children: [
                          const Expanded(child: Divider()),
                          Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text('أو', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant))),
                          const Expanded(child: Divider()),
                        ]),
                        const SizedBox(height: 20),
                        OutlinedButton(
                          key: const ValueKey('auth-browse'),
                          onPressed: _leave,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: scheme.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Text('متابعة التصفح', textAlign: TextAlign.center),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
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


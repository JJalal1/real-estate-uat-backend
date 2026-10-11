import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../../core/widgets/ebroker_screen_sections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/ebroker_design.dart';
import '../data/auth_controller.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, this.startWithRegister = false});

  // Retained for route compatibility with older deep links. The unified flow
  // no longer exposes separate login/register modes.
  final bool startWithRegister;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _phone = TextEditingController(text: '+967');
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('تسجيل الدخول أو إنشاء حساب')),
        backgroundColor: EbrokerDesign.page,
        body: LayoutBuilder(builder: (context, constraints) => SingleChildScrollView(
          child: Column(children: [
            SizedBox(height: (constraints.maxHeight - 400.rh(context)).clamp(140.0, 485.0),
              width: double.infinity,
              child: Image.asset(ebrokerBannerAsset, fit: BoxFit.cover,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: .3), colorBlendMode: BlendMode.srcATop)),
            Container(width: double.infinity, constraints: BoxConstraints(minHeight: 400.rh(context)),
              padding: EdgeInsets.symmetric(horizontal: 18.rw(context)),
              decoration: const BoxDecoration(color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
              child: Column(children: [
                const SizedBox(height: 32),
                const EbrokerText('تسجيل الدخول أو إنشاء حساب', size: 24, weight: FontWeight.w700, align: TextAlign.center),
                const SizedBox(height: 20), const Divider(height: 1), const SizedBox(height: 20),
                const EbrokerText('حساب واحد للجميع', size: 16, weight: FontWeight.w500, align: TextAlign.center),
                const SizedBox(height: 4),
                const EbrokerText('أدخل رقم واتساب للمتابعة بحسابك أو إنشاء حساب أساسي جديد.',
                  size: 14, color: EbrokerDesign.textLight, align: TextAlign.center),
                const SizedBox(height: 20),
                TextField(controller: _phone, keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done, onSubmitted: _busy ? null : (_) => _submit(),
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(hintText: '+9677xxxxxxxx',
                    prefixIcon: Padding(padding: EdgeInsets.all(12), child: EbrokerImage('call', size: 24)))),
                const SizedBox(height: 10),
                const EbrokerText('سيتم إرسال رمز تحقق مكوّن من 6 أرقام عبر واتساب. الحساب الجديد سيُطلب منه إدخال الاسم الرباعي بعد التحقق.',
                  size: 12, color: EbrokerDesign.textLight),
                const SizedBox(height: 20),
                EbrokerButton(onPressed: _submit, loading: _busy, expand: true,
                  child: const Text('إرسال رمز واتساب')),
                const SizedBox(height: 32),
              ])),
          ])),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .startWhatsApp(phone: _phone.text);
      if (!mounted) return;
      context.push('/verify-phone');
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

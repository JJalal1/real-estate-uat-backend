import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_components.dart';
import '../../account/data/auth_controller.dart';

class P02SupportInfoScreen extends ConsumerWidget {
  const P02SupportInfoScreen({super.key});

  static const supportPhone =
      String.fromEnvironment('SUPPORT_PHONE', defaultValue: '');
  static const supportWhatsApp =
      String.fromEnvironment('SUPPORT_WHATSAPP', defaultValue: '');
  static const supportEmail =
      String.fromEnvironment('SUPPORT_EMAIL', defaultValue: '');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).asData?.value;
    final scheme = Theme.of(context).colorScheme;
    final hasDirectContact = supportPhone.isNotEmpty ||
        supportWhatsApp.isNotEmpty ||
        supportEmail.isNotEmpty;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الدعم الفني')),
        body: ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 32),
          children: [
            Container(
              padding: const EdgeInsetsDirectional.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scheme.primary,
                    scheme.secondary,
                  ],
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.headset_mic_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'نحن هنا للمساعدة',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'إذا واجهتك مشكلة في الدخول أو الحساب أو استخدام التطبيق، استخدم قناة الدعم المناسبة.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.88),
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (hasDirectContact)
              AppSurface(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    if (supportPhone.isNotEmpty)
                      AppListRow(
                        title: 'هاتف الدعم',
                        subtitle: supportPhone,
                        leading: const Icon(Icons.phone_outlined),
                      ),
                    if (supportWhatsApp.isNotEmpty) ...[
                      if (supportPhone.isNotEmpty) const Divider(height: 1),
                      AppListRow(
                        title: 'واتساب الدعم',
                        subtitle: supportWhatsApp,
                        leading: const Icon(Icons.chat_bubble_outline_rounded),
                      ),
                    ],
                    if (supportEmail.isNotEmpty) ...[
                      if (supportPhone.isNotEmpty || supportWhatsApp.isNotEmpty)
                        const Divider(height: 1),
                      AppListRow(
                        title: 'البريد الإلكتروني',
                        subtitle: supportEmail,
                        leading: const Icon(Icons.email_outlined),
                      ),
                    ],
                  ],
                ),
              ),
            if (hasDirectContact) const SizedBox(height: 16),
            AppSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.support_agent_rounded, color: scheme.secondary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'مركز الدعم داخل التطبيق',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    user == null
                        ? 'سجّل الدخول ثم افتح تذكرة، وستبقى المحادثة محفوظة في حسابك.'
                        : 'افتح تذكرة دعم وتابع الردود من نفس المكان.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 16),
                  AppButton(
                    label: user == null ? 'تسجيل الدخول' : 'فتح مركز الدعم',
                    icon: user == null
                        ? Icons.login_rounded
                        : Icons.headset_mic_outlined,
                    expand: true,
                    onPressed: () =>
                        context.push(user == null ? '/login' : '/support'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

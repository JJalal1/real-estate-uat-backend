import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/v2_package.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_components.dart';
import '../../data/auth_controller.dart';
import '../../domain/auth_user.dart';

class P01AccountScreen extends ConsumerWidget {
  const P01AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('حسابي')),
        body: auth.when(
          loading: () => const AppLoadingState(),
          error: (_, __) => AppErrorState(
            message: 'تعذر تحميل بيانات الحساب.',
            onRetry: () => ref.read(authControllerProvider.notifier).refresh(),
          ),
          data: (user) => user == null
              ? const _GuestAccount()
              : _SignedInAccount(user: user),
        ),
      ),
    );
  }
}

class _GuestAccount extends StatelessWidget {
  const _GuestAccount();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppLayout.compactPageGutter,
        AppSpacing.s20,
        AppLayout.compactPageGutter,
        AppSpacing.s32,
      ),
      children: [
        AppSurface(
          child: Column(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  Icons.person_outline,
                  size: 34,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.s12),
              Text('حساب واحد وبسيط',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.s6),
              Text(
                'سجّل برقم واتساب. لا تحتاج لاختيار مشتري أو مستأجر عند إنشاء الحساب.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: AppSpacing.s20),
              AppButton(
                label: 'تسجيل الدخول أو إنشاء حساب',
                icon: Icons.login,
                expand: true,
                onPressed: () => context.push('/auth'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SignedInAccount extends ConsumerWidget {
  const _SignedInAccount({required this.user});

  final AuthUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppLayout.compactPageGutter,
        AppSpacing.s16,
        AppLayout.compactPageGutter,
        AppSpacing.s32,
      ),
      children: [
        _ProfileHeader(user: user),
        if (user.needsProfileCompletion) ...[
          const SizedBox(height: AppSpacing.s12),
          AppInlineMessage(
            title: 'أكمل بيانات الحساب',
            message: 'أدخل الاسم الرباعي قبل طلب التوثيق.',
            tone: AppStatusTone.warning,
          ),
          const SizedBox(height: AppSpacing.s8),
          AppButton(
            label: 'إكمال الآن',
            icon: Icons.edit_outlined,
            style: AppButtonStyle.outlined,
            expand: true,
            onPressed: () => context.push('/complete-profile'),
          ),
        ],
        const SizedBox(height: AppSpacing.s24),
        const AppSectionHeader(title: 'الحساب'),
        const SizedBox(height: AppSpacing.s8),
        _AccountGroup(
          rows: [
            _AccountRow(
              title: 'الملف الشخصي',
              subtitle: 'الاسم ورقم الهاتف',
              icon: Icons.manage_accounts_outlined,
              onTap: () => context.push('/profile'),
            ),
            _AccountRow(
              title: 'التوثيق والنشر',
              subtitle: _verificationSubtitle(user),
              icon: user.hasVerifiedPublishingProfile
                  ? Icons.verified_outlined
                  : Icons.badge_outlined,
              onTap: user.needsProfileCompletion
                  ? () => context.push('/complete-profile')
                  : () => context.push('/account-verification'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s24),
        const AppSectionHeader(title: 'المساعدة'),
        const SizedBox(height: AppSpacing.s8),
        _AccountGroup(
          rows: [
            _AccountRow(
              title: 'المساعدة والدعم',
              subtitle: 'إذا واجهتك مشكلة في الحساب أو التوثيق',
              icon: Icons.help_outline,
              onTap: () => context.push('/support'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s24),
        AppButton(
          label: 'تسجيل الخروج',
          icon: Icons.logout,
          style: AppButtonStyle.outlined,
          expand: true,
          onPressed: () async {
            await ref.read(authControllerProvider.notifier).logout();
          },
        ),
        const SizedBox(height: AppSpacing.s24),
        Text(
          V2Package.displayLabel,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  static String _verificationSubtitle(AuthUser user) {
    if (user.verificationProfile.status == 'approved') {
      return 'موثق كـ ${user.accountTypeLabel}';
    }
    if (user.verificationProfile.status == 'pending') {
      return 'طلب التوثيق قيد المراجعة';
    }
    if (user.verificationProfile.status == 'needs_more_info') {
      return 'التوثيق يحتاج مستندًا أو توضيحًا';
    }
    if (user.verificationProfile.status == 'rejected') {
      return 'راجع ملاحظة فريق الدعم وأعد الإرسال';
    }
    return 'فعّل صفة مالك أو دلال أو مكتب عند حاجتك للنشر';
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});

  final AuthUser user;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppSurface(
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: scheme.primaryContainer,
            child: Icon(Icons.person_outline, size: 32, color: scheme.primary),
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  user.phone ?? user.email,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountGroup extends StatelessWidget {
  const _AccountGroup({required this.rows});

  final List<_AccountRow> rows;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      padding: EdgeInsets.zero,
      child: Column(
        children: List.generate(rows.length, (index) {
          final row = rows[index];
          return Column(
            children: [
              AppListRow(
                title: row.title,
                subtitle: row.subtitle,
                leading: Icon(row.icon),
                onTap: row.onTap,
              ),
              if (index != rows.length - 1) const Divider(height: 1),
            ],
          );
        }),
      ),
    );
  }
}

class _AccountRow {
  const _AccountRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
}

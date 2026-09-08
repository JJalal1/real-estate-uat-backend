import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../../properties/presentation/favorites_screen.dart';
import '../data/auth_controller.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: const AppAppBar(title: 'حسابي'),
        body: auth.when(
          loading: () => const AppLoadingState(),
          error: (_, __) => AppErrorState(
            message: 'تعذر تحميل بيانات الحساب.',
            onRetry: () => ref.read(authControllerProvider.notifier).refresh(),
          ),
          data: (user) {
            final administrativeRole = user != null &&
                (user.isPlatformOwner ||
                    user.roles.contains('super_admin') ||
                    user.roles.contains('support_manager') ||
                    user.roles.contains('support_agent'));
            return ListView(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppLayout.compactPageGutter,
                AppSpacing.s12,
                AppLayout.compactPageGutter,
                AppSpacing.s32,
              ),
              children: [
                _ProfileHeader(user: user),
                const SizedBox(height: AppSpacing.s16),
                if (user == null)
                  AppButton(
                    label: 'تسجيل الدخول أو إنشاء حساب',
                    icon: Icons.login,
                    onPressed: () => context.push('/auth'),
                    expand: true,
                  )
                else ...[
                  if (!user.isActive) ...[
                    AppInlineMessage(
                      title: 'الحساب يحتاج تحقق الهاتف',
                      message: user.phone ?? 'أكمل تحقق الهاتف للمتابعة.',
                      tone: AppStatusTone.warning,
                    ),
                    const SizedBox(height: AppSpacing.s12),
                  ],
                  if (user.needsProfileCompletion) ...[
                    AppSurface(
                      onTap: () => context.push('/complete-profile'),
                      child: const AppListRow(
                        title: 'أكمل الاسم الرباعي',
                        subtitle: 'أكمل بيانات الحساب الأساسية.',
                        leading: Icon(Icons.edit_outlined),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s12),
                  ],
                  _AccountGroup(
                    rows: [
                      _AccountRow(
                        'الملف الشخصي',
                        Icons.manage_accounts_outlined,
                        () => context.push('/profile'),
                      ),
                      _AccountRow(
                        'الإشعارات',
                        Icons.notifications_outlined,
                        () => context.push('/notifications'),
                      ),
                      if (!administrativeRole)
                        _AccountRow(
                          'الخدمات والأدوات',
                          Icons.apps_outlined,
                          () => context.push('/services'),
                        ),
                      if (!administrativeRole)
                        _AccountRow(
                          'المساعدة والدعم',
                          Icons.help_outline,
                          () => context.push('/support'),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s20),
                  if (administrativeRole)
                    AppInlineMessage(
                      title: 'مساحة العمل منفصلة عن الحساب',
                      message: user.isPlatformOwner || user.roles.contains('super_admin')
                          ? 'وظائف الإدارة موجودة في «لوحة الإدارة».'
                          : user.roles.contains('support_manager')
                              ? 'وظائف الإشراف موجودة في «لوحة الدعم» و«الأعمال» و«الفريق».'
                              : 'وظائف الدعم موجودة في «لوحة الدعم» و«الوارد» و«مهامي».',
                      tone: AppStatusTone.info,
                    )
                  else ...[
                    AppSurface(
                      onTap: () => context.push('/account-verification'),
                      child: AppListRow(
                        title: 'نوع الحساب: ${user.accountTypeLabel}',
                        subtitle: user.verificationProfile.status == 'approved'
                            ? 'تم التحقق من صفتك المهنية.'
                            : user.verificationProfile.status == 'pending'
                                ? 'طلب التحقق قيد المراجعة من فريق الدعم.'
                                : 'تحقق كمالك أو دلال أو مكتب عقارات عندما تحتاج إلى النشر.',
                        leading: Icon(
                          user.isOwner
                              ? Icons.home_work_outlined
                              : user.isBroker
                                  ? Icons.real_estate_agent_outlined
                                  : user.isOffice
                                      ? Icons.apartment_outlined
                                      : Icons.verified_user_outlined,
                        ),
                      ),
                    ),
                    if (user.hasVerifiedPublishingProfile) ...[
                      const SizedBox(height: AppSpacing.s24),
                      const AppSectionHeader(title: 'إدارة عقاراتي'),
                      const SizedBox(height: AppSpacing.s8),
                      _AccountGroup(
                        rows: [
                          _AccountRow(
                            'إعلاناتي',
                            Icons.inventory_2_outlined,
                            () => context.push('/my-listings'),
                          ),
                          _AccountRow(
                            'إضافة عقار',
                            Icons.add_home_work_outlined,
                            () => context.push('/add-property'),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: AppSpacing.s24),
                    const AppSectionHeader(title: 'نشاطي'),
                    const SizedBox(height: AppSpacing.s8),
                    _AccountGroup(
                      rows: [
                        _AccountRow(
                          'المعاينات',
                          Icons.event_available_outlined,
                          () => context.push('/bookings'),
                        ),
                        _AccountRow(
                          'اتفاقاتي وعقودي',
                          Icons.handshake_outlined,
                          () => context.push('/agreements'),
                        ),
                        _AccountRow(
                          'المفضلة',
                          Icons.favorite_border,
                          () => Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => const FavoritesScreen(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.s20),
                  AppButton(
                    label: 'تسجيل الخروج',
                    icon: Icons.logout,
                    style: AppButtonStyle.text,
                    onPressed: () async {
                      await ref.read(authControllerProvider.notifier).logout();
                    },
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});

  final dynamic user;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsetsDirectional.all(AppSpacing.s20),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: scheme.surface,
            child: Icon(Icons.person_outline, size: 32, color: scheme.primary),
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user == null ? 'مرحباً بك' : user.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  user == null
                      ? 'تصفح العقارات بحرية وسجّل الدخول عند الحاجة.'
                      : (user.phone ?? user.email),
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
  const _AccountRow(this.title, this.icon, this.onTap);

  final String title;
  final IconData icon;
  final VoidCallback onTap;
}

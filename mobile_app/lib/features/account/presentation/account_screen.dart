import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../../core/theme/ebroker_design.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../../financial/presentation/financial_account_screen.dart';
import '../../properties/presentation/favorites_screen.dart';
import '../data/auth_controller.dart';
import '../../broker/data/broker_repository.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
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
            return SafeArea(bottom: false, child: CustomScrollView(slivers: [
              SliverPersistentHeader(pinned: true, delegate: _AccountHeaderDelegate(user: user, scale: MediaQuery.textScalerOf(context).scale(14) / 14)),
              SliverPadding(padding: const EdgeInsetsDirectional.fromSTEB(AppLayout.compactPageGutter, 12, AppLayout.compactPageGutter, AppSpacing.s32),
                sliver: SliverList.list(children: [
                if (user == null) ...[
                  AppListRow(title: 'المفضلة', leading: const EbrokerImage('heart'),
                    onTap: () => context.push('/favorites')),
                  const SizedBox(height: 12),
                  AppButton(
                    label: 'تسجيل الدخول أو إنشاء حساب',
                    icon: Icons.login,
                    onPressed: () => context.push('/auth'),
                    expand: true,
                  ),
                ] else ...[
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
                        leading: EbrokerIcon(Icons.edit_outlined),
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
                      _AccountRow(
                        'مدفوعاتي',
                        Icons.payments_outlined,
                        () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => const FinancialAccountScreen(
                              showAccountSummary: false,
                            ),
                          ),
                        ),
                      ),
                      if (!administrativeRole && !user.hasVerifiedPublishingProfile)
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
                        leading: EbrokerIcon(
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
                          _AccountRow('ملفي العام', Icons.person_outline, () => context.push('/advertisers/${user.id}')),
                          _AccountRow(
                            'عقاراتي',
                            Icons.inventory_2_outlined,
                            () => context.push('/my-listings'),
                          ),
                          _AccountRow(
                            'إضافة عقار',
                            Icons.add_home_work_outlined,
                            () => context.push('/add-property'),
                          ),
                          _AccountRow(
                            'مستحقات المنصة',
                            Icons.account_balance_wallet_outlined,
                            () => context.push('/broker/finance'),
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
                          'نتائج الصفقات',
                          Icons.check_circle_outline,
                          () => context.push('/broker/activity'),
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
                ])),
            ]));
          },
        ),
      ),
    );
  }
}

class _ProfileHeader extends ConsumerWidget {
  const _ProfileHeader({required this.user});

  final dynamic user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final photo = user?.hasVerifiedPublishingProfile == true ? ref.watch(brokerProfileProvider(user.id as int)).asData?.value?.photoUrl : null;
    return Container(
      padding: const EdgeInsetsDirectional.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: EbrokerDesign.border, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(width: 56, height: 56, alignment: Alignment.center,
            decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(8)),
            child: photo == null ? EbrokerImage('defaultProfileIcon', size: 40, color: scheme.primary) : ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(photo, width: 56, height: 56, fit: BoxFit.cover, errorBuilder: (_, __, ___) => EbrokerImage('defaultProfileIcon', size: 40, color: scheme.primary)))),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user == null ? 'مرحباً بك' : user.name,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  user == null
                      ? 'تصفح العقارات بحرية وسجّل الدخول عند الحاجة.'
                      : (user.phone ?? user.email),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 12, color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          if (user != null) IconButton(tooltip: 'تعديل الملف الشخصي', onPressed: () => context.push('/profile'), icon: const EbrokerIcon(Icons.edit_outlined, size: 20)),
        ],
      ),
    );
  }
}

class _AccountHeaderDelegate extends SliverPersistentHeaderDelegate {
  _AccountHeaderDelegate({required this.user, required this.scale});
  final dynamic user;
  final double scale;
  double get cardHeight => 140 + (scale - 1).clamp(0, 2).toDouble() * 72;
  @override
  double get minExtent => cardHeight;
  @override
  double get maxExtent => 176 + cardHeight - 64;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final top = (176 - 64 - shrinkOffset).clamp(0.0, 176.0).toDouble();
    final banner = (176 - shrinkOffset).clamp(0.0, 176.0).toDouble();
    return ColoredBox(color: Theme.of(context).scaffoldBackgroundColor, child: Stack(children: [
      if (banner > 0) Positioned(top: 0, left: 0, right: 0, height: banner, child: ColoredBox(color: Theme.of(context).colorScheme.primary,
        child: const Padding(padding: EdgeInsets.all(20), child: Align(alignment: Alignment.topRight, child: Text('حسابي', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)))))),
      Positioned(top: top, left: 16, right: 16, height: cardHeight - 16, child: _ProfileHeader(user: user)),
    ]));
  }
  @override
  bool shouldRebuild(covariant _AccountHeaderDelegate old) => old.user != user || old.scale != scale;
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
                leading: EbrokerIcon(row.icon),
                onTap: row.onTap,
              ),
              if (index != rows.length - 1) const SizedBox(height: 4),
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

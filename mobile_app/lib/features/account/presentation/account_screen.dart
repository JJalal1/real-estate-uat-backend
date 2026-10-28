import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../../core/theme/ebroker_design.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/app_components.dart';
import '../../financial/presentation/financial_account_screen.dart';
import '../../properties/presentation/favorites_screen.dart';
import '../data/auth_controller.dart';
import '../../../core/branding/aqer_brand.dart';
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
          loading: () => const AqerAccountLoading(),
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
                _AccountGroup(key: const ValueKey('account-preferences-group'), rows: [
                  _AccountRow('البحث الذكي', Icons.auto_awesome_outlined,
                    () => context.push('/smart-search'),
                    key: const ValueKey('account-smart-search'),
                    subtitle: 'ابحث بالنص أو الصوت وعدّل شروطك بسهولة'),
                  _AccountRow('شوهد مؤخرًا', Icons.history_outlined,
                    () => context.push('/recent'), subtitle: 'سجل محلي على هذا الجهاز فقط'),
                  _AccountRow('المظهر', Icons.contrast_outlined, () => showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => const _ThemeModeSheet(),
                  ), subtitle: _themeModeLabel(ref.watch(appThemeModeProvider))),
                ]),
                const SizedBox(height: AppSpacing.s12),
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
                        'الأمان والخصوصية',
                        Icons.security_outlined,
                        () => context.push('/account-safety'),
                      ),
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
                            ? user.isOwner ? 'هوية المالك معتمدة لعرض عقار شخصي.' : 'تم التحقق من صفتك المهنية.'
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
                    if (user.isOwner && user.hasVerifiedPublishingProfile) ...[
                      const SizedBox(height: AppSpacing.s20),
                      const AppSectionHeader(title: 'عقاري الشخصي'),
                      const SizedBox(height: AppSpacing.s8),
                      _AccountGroup(rows: [
                        _AccountRow('عقاري', Icons.home_outlined, () => context.push('/my-listings')),
                        _AccountRow('إضافة عقار شخصي', Icons.add_home_outlined, () => context.push('/add-property')),
                        _AccountRow('مستحقات المنصة', Icons.account_balance_wallet_outlined, () => context.push('/broker/finance')),
                        _AccountRow('فعّل حساب دلال', Icons.work_outline, () => context.push('/account-verification?upgrade=broker')),
                      ]),
                    ],
                    if (user.hasVerifiedProfessionalProfile) ...[
                      const SizedBox(height: AppSpacing.s24),
                      const AppSectionHeader(title: 'إدارة عقاراتي'),
                      const SizedBox(height: AppSpacing.s8),
                      _AccountGroup(
                        rows: [
                          _AccountRow('لوحة العمل', Icons.work_outline, () => context.push('/broker/workspace')),
                          _AccountRow('إدارة العملاء', Icons.people_outline, () => context.push('/broker/customers')),
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
                        if (user.hasVerifiedProfessionalProfile) _AccountRow(
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
    final photo = user?.hasVerifiedPublishingProfile == true ? ref.watch(brokerProfileProvider(user.id as int)).asData?.value.photoUrl : null;
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
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  user == null
                      ? 'تصفح العقارات بحرية وسجّل الدخول عند الحاجة.'
                      : (user.email is String && (user.email as String).trim().isNotEmpty ? user.email : (user.phone ?? '')),
                  maxLines: 2, overflow: TextOverflow.ellipsis,
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
  const _AccountGroup({required this.rows, super.key});

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
                key: row.key,
                title: row.title,
                subtitle: row.subtitle,
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

String _themeModeLabel(ThemeMode mode) => switch (mode) {
      ThemeMode.light => 'فاتح',
      ThemeMode.dark => 'داكن',
      _ => 'حسب إعداد الجهاز',
    };

class _ThemeModeSheet extends ConsumerWidget {
  const _ThemeModeSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(appThemeModeProvider);
    return SafeArea(
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('مظهر التطبيق', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final entry in const [
                (ThemeMode.system, 'حسب إعداد الجهاز', Icons.brightness_auto_outlined),
                (ThemeMode.light, 'فاتح', Icons.light_mode_outlined),
                (ThemeMode.dark, 'داكن', Icons.dark_mode_outlined),
              ])
                RadioListTile<ThemeMode>(
                  value: entry.$1,
                  groupValue: selected,
                  title: Text(entry.$2),
                  secondary: Icon(entry.$3),
                  onChanged: (value) async {
                    if (value == null) return;
                    await ref.read(appThemeModeProvider.notifier).setMode(value);
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}


class _AccountRow {
  const _AccountRow(this.title, this.icon, this.onTap, {this.subtitle, this.key});

  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final String? subtitle;
  final Key? key;
}


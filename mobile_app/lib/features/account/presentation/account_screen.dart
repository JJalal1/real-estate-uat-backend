import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../data/auth_controller.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('حسابي')),
        body: auth.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
            child: FilledButton.icon(
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ),
          data: (user) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: AlignmentDirectional.topStart,
                    end: AlignmentDirectional.bottomEnd,
                    colors: [AppTheme.brand, AppTheme.brandStrong],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 32,
                      backgroundColor: Colors.white,
                      child: Icon(
                        Icons.person_outline,
                        size: 34,
                        color: AppTheme.brandStrong,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user == null ? 'مرحباً بك' : user.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user == null
                                ? 'سجّل الدخول لإدارة عقاراتك بحساب حقيقي.'
                                : (user.phone ?? user.email),
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (user == null) ...[
                FilledButton.icon(
                  onPressed: () => context.push('/auth'),
                  icon: const Icon(Icons.login),
                  label: const Text('تسجيل الدخول أو إنشاء حساب'),
                ),
              ] else ...[
                if (!user.isActive)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.warning_amber_rounded),
                      title: const Text('الحساب يحتاج تحقق الهاتف'),
                      subtitle: Text(user.phone ?? ''),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => context.push('/verify-phone'),
                    ),
                  ),
                if (user.needsProfileCompletion) ...[
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.person_edit_outlined),
                      title: const Text('أكمل الاسم الرباعي'),
                      subtitle: const Text(
                        'أكمل بيانات الحساب الأساسية قبل إرسال طلب تحقق نوع الحساب.',
                      ),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => context.push('/complete-profile'),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => context.push('/profile'),
                  icon: const Icon(Icons.manage_accounts_outlined),
                  label: const Text('الملف الشخصي'),
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: Icon(
                      user.isOwner
                          ? Icons.home_work_outlined
                          : user.isBroker
                              ? Icons.real_estate_agent_outlined
                              : user.isOffice
                                  ? Icons.apartment_outlined
                                  : Icons.manage_accounts_outlined,
                    ),
                    title: Text(
                      'نوع الحساب: ${user.accountTypeLabel}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      user.verificationProfile.status == 'approved'
                          ? 'الحساب موثق. ${user.verificationProfile.statusLabel}'
                          : user.verificationProfile.status == 'pending'
                              ? 'طلب التحقق قيد المراجعة من فريق التحقق.'
                              : 'اختر مالك أو دلال أو مكتب عقارات وارفع مستندات التحقق المطلوبة.',
                    ),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => context.push('/account-verification'),
                  ),
                ),
                if (user.roles.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: user.roles
                        .map((role) => Chip(label: Text(role)))
                        .toList(),
                  ),
                ],
                if (user.canAccessSystemWorkspace) ...[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => context.push('/admin/dashboard'),
                    icon: const Icon(Icons.dashboard_customize_outlined),
                    label: Text(user.isPlatformOwner
                        ? 'لوحة المدير العام / صاحب النظام'
                        : 'لوحة إدارة النظام'),
                  ),
                ],
                if (user.canAccessSupportWorkspace) ...[
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: () => context.push('/support/workspace'),
                    icon: const Icon(Icons.support_agent_outlined),
                    label: Text(user.hasPermission('support.view_team_metrics')
                        ? 'لوحة مدير الدعم'
                        : 'لوحة موظف الدعم'),
                  ),
                ],
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: () => context.push('/messages'),
                  icon: const Icon(Icons.forum_outlined),
                  label: const Text('الرسائل'),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: () => context.push('/notifications'),
                  icon: const Icon(Icons.notifications_outlined),
                  label: const Text('الإشعارات'),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: () => context.push('/support'),
                  icon: const Icon(Icons.support_agent_outlined),
                  label: const Text('الدعم وبلاغاتي'),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () async {
                    await ref.read(authControllerProvider.notifier).logout();
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('تسجيل الخروج'),
                ),
              ],
              const SizedBox(height: 22),
              Text(
                'إدارة العقارات',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 10),
              _AccountMenu(
                rows: [
                  _AccountRow(
                    'إضافة إعلان جديد',
                    Icons.add_home_work_outlined,
                    () => context.push('/add-property'),
                  ),
                  _AccountRow(
                    'إعلاناتي',
                    Icons.inventory_2_outlined,
                    () => context.push('/my-listings'),
                  ),
                  _AccountRow(
                    'المشاريع والتطويرات العقارية',
                    Icons.apartment_outlined,
                    () => context.push('/developments'),
                  ),
                  _AccountRow(
                    'المفضلة',
                    Icons.favorite_border,
                    () =>
                        _message(context, 'ستتم إضافة المفضلة في مرحلة لاحقة.'),
                  ),
                  _AccountRow(
                    'الحجوزات',
                    Icons.event_available_outlined,
                    () => context.push('/bookings'),
                  ),
                  _AccountRow(
                    'الخدمات والترقيات والمدفوعات',
                    Icons.workspace_premium_outlined,
                    () => context.push('/services'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void _message(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _AccountMenu extends StatelessWidget {
  const _AccountMenu({required this.rows});
  final List<_AccountRow> rows;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: List.generate(rows.length, (index) {
          final row = rows[index];
          return Column(
            children: [
              ListTile(
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppTheme.brandSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(row.icon, color: AppTheme.brandStrong),
                ),
                title: Text(
                  row.title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                trailing: const Icon(Icons.chevron_left),
                onTap: row.onTap,
              ),
              if (index != rows.length - 1) const Divider(),
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

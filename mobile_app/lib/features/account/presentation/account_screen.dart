import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../services/data/service_repository.dart';
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
              onPressed: () => ref.read(authControllerProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ),
          data: (user) {
            final administrativeRole = user != null &&
                (user.isPlatformOwner ||
                    user.roles.contains('super_admin') ||
                    user.roles.contains('support_manager') ||
                    user.roles.contains('support_agent'));
            final servicesHub = user != null && !administrativeRole
                ? ref.watch(freeServicesHubProvider).asData?.value
                : null;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              children: [
                _profileHeader(user),
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
                        leading: const Icon(Icons.edit_outlined),
                        title: const Text('أكمل الاسم الرباعي'),
                        subtitle: const Text('أكمل بيانات الحساب الأساسية.'),
                        trailing: const Icon(Icons.chevron_left),
                        onTap: () => context.push('/complete-profile'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _AccountMenu(
                    rows: [
                      _AccountRow(
                        'الملف الشخصي',
                        Icons.manage_accounts_outlined,
                        () => context.push('/profile'),
                      ),
                      _AccountRow(
                        'الرسائل',
                        Icons.forum_outlined,
                        () => context.push('/messages'),
                      ),
                      _AccountRow(
                        'الإشعارات',
                        Icons.notifications_outlined,
                        () => context.push('/notifications'),
                      ),
                    ],
                  ),
                  if (administrativeRole) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: AppTheme.brandSoft,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            const Icon(Icons.space_dashboard_outlined, color: AppTheme.brandStrong),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                user.isPlatformOwner || user.roles.contains('super_admin')
                                    ? 'وظائف الإدارة موجودة الآن في «لوحة الإدارة» وليست داخل حسابي.'
                                    : user.roles.contains('support_manager')
                                        ? 'وظائف الإشراف موجودة الآن في «لوحة الدعم» و«الأعمال» و«الفريق».'
                                        : 'وظائف العمل موجودة الآن في «الرئيسية» و«مهامي» و«مركز الدعم».',
                                style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
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
                              ? 'تم التحقق ويمكنك النشر بهذه الصفة.'
                              : user.verificationProfile.status == 'pending'
                                  ? 'طلب التحقق قيد المراجعة من فريق الدعم.'
                                  : 'اختر مالك أو دلال أو مكتب عقارات وارفع مستندات التحقق المطلوبة.',
                        ),
                        trailing: const Icon(Icons.chevron_left),
                        onTap: () => context.push('/account-verification'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: () async {
                      await ref.read(authControllerProvider.notifier).logout();
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('تسجيل الخروج'),
                  ),
                ],
                if (!administrativeRole && user != null) ...[
                  const SizedBox(height: 22),
                  _sectionHeading(context, 'إدارة عقاراتي'),
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
                        'طلبات المعاينة على عقاراتي',
                        Icons.event_note_outlined,
                        () => context.push('/bookings'),
                      ),
                      _AccountRow(
                        'عقود الإيجار',
                        Icons.description_outlined,
                        () => _message(
                          context,
                          'عقود الإيجار ضمن التطوير الحالي وستُفعّل بعد اكتمال منطق العقود في الـBackend.',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _sectionHeading(context, 'نشاطي'),
                  const SizedBox(height: 10),
                  _AccountMenu(
                    rows: [
                      _AccountRow(
                        'المفضلة',
                        Icons.favorite_border,
                        () => _message(
                          context,
                          'المفضلة ستُربط بالحساب على الخادم ضمن مرحلة المفضلة الحالية.',
                        ),
                      ),
                      _AccountRow(
                        'طلبات العقار',
                        Icons.manage_search_outlined,
                        () => context.push('/property-requests'),
                      ),
                      _AccountRow(
                        'حجوزاتي',
                        Icons.event_available_outlined,
                        () => context.push('/bookings'),
                      ),
                      if (servicesHub?.can('view_researcher_requests') == true)
                        _AccountRow(
                          'طلبات الباحثين',
                          Icons.person_search_outlined,
                          () => context.push('/researcher-requests'),
                        ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _sectionHeading(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context)
          .textTheme
          .titleLarge
          ?.copyWith(fontWeight: FontWeight.w900),
    );
  }

  Widget _profileHeader(dynamic user) {
    return Container(
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
            child: Icon(Icons.person_outline, size: 34, color: AppTheme.brandStrong),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user == null ? 'مرحباً بك' : user.name,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  user == null
                      ? 'سجّل الدخول لإدارة حسابك.'
                      : (user.phone ?? user.email),
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static void _message(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
                  decoration: BoxDecoration(color: AppTheme.brandSoft, borderRadius: BorderRadius.circular(12)),
                  child: Icon(row.icon, color: AppTheme.brandStrong),
                ),
                title: Text(row.title, style: const TextStyle(fontWeight: FontWeight.w800)),
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

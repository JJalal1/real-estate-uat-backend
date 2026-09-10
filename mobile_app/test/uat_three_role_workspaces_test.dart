import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String relative) => File(relative).readAsStringSync();

  test('support agent and support manager navigation remain unchanged', () {
    final shell = read('lib/features/app_shell/presentation/app_shell_screen.dart');

    expect(shell, contains("label: 'لوحة الدعم'"));
    expect(shell, contains("label: 'الوارد'"));
    expect(shell, contains("label: 'مهامي'"));
    expect(shell, contains("label: 'الأعمال'"));
    expect(shell, contains("label: 'الفريق'"));
    expect(shell, contains("roles.contains('support_agent')"));
    expect(shell, contains("roles.contains('support_manager')"));
  });

  test('general manager has executive-only primary navigation', () {
    final shell = read('lib/features/app_shell/presentation/app_shell_screen.dart');

    expect(shell, contains('GeneralManagerHomeScreen()'));
    expect(shell, contains('GeneralManagerMarketScreen()'));
    expect(shell, contains('GeneralManagerAdministrationScreen()'));
    expect(shell, contains('GeneralManagerReportsScreen()'));
    expect(shell, contains("label: 'الرئيسية'"));
    expect(shell, contains("label: 'السوق'"));
    expect(shell, contains("label: 'الإدارة'"));
    expect(shell, contains("label: 'التقارير'"));
    expect(shell, contains("roles.contains('super_admin')"));
    expect(shell, isNot(contains('PlatformReviewsScreen()')));
    expect(shell, isNot(contains('PlatformOperationsScreen()')));
    expect(shell, isNot(contains("label: 'المراجعات'")));
    expect(shell, isNot(contains("label: 'المستخدمون'")));
    expect(shell, isNot(contains("label: 'المنصة'")));
  });

  test('general manager pages are executive not support task queues', () {
    final pages = read('lib/features/admin/presentation/general_manager_pages.dart');
    final repo = read('lib/features/admin/data/general_manager_repository.dart');

    expect(repo, contains('/admin/workspace/general-manager/insights'));
    expect(pages, contains('يحتاج انتباهك الآن'));
    expect(pages, contains('صورة السوق داخل المنصة'));
    expect(pages, contains('إدارة المنظمة لا إدارة الطلبات'));
    expect(pages, contains('الموظفون والفرق'));
    expect(pages, contains('الحسابات والأدوار والصلاحيات'));
    expect(pages, contains('المحافظات والمديريات'));
    expect(pages, contains('رحلة العقار داخل المنصة'));
    expect(pages, contains('المالية والتقارير'));
    expect(pages, isNot(contains("SupportTasksScreen(")));
    expect(pages, isNot(contains('مسند لي')));
    expect(pages, isNot(contains('غير مسند لي')));
  });

  test('consumer navigation follows accepted marketplace IA', () {
    final shell = read('lib/features/app_shell/presentation/app_shell_screen.dart');

    expect(shell, contains("label: 'العقارات'"));
    expect(shell, contains("label: 'الرسائل'"));
    expect(shell, contains("label: 'المعاينات'"));
    expect(shell, contains("label: 'إعلاناتي'"));
    expect(shell, contains("label: 'حسابي'"));
    expect(shell, isNot(contains("label: 'الخدمات'")));
    expect(shell, isNot(contains("label: 'المشاريع'")));
    expect(shell, isNot(contains('projects/presentation/projects_screen.dart')));
  });

  test('account stays personal for all administrative roles', () {
    final account = read('lib/features/account/presentation/account_screen.dart');

    expect(account, contains('administrativeRole'));
    expect(account, contains("user.roles.contains('support_agent')"));
    expect(account, contains("user.roles.contains('support_manager')"));
    expect(account, contains('مساحة العمل منفصلة عن الحساب'));
    expect(account, contains('أدوات المدير العام موزعة بين'));
    expect(account, contains("'الملف الشخصي'"));
    expect(account, contains("'الإشعارات'"));
  });

  test('shared support queue contract is unchanged in this manager-only phase', () {
    final repo = read('lib/features/support/data/support_workspace_repository.dart');
    final screen = read('lib/features/support/presentation/support_tasks_screen.dart');
    final pages = read('lib/features/support/presentation/support_workspace_pages.dart');

    expect(repo, contains('/admin/workspace/tasks/\$taskId/claim'));
    expect(repo, contains('/admin/workspace/dashboard'));
    expect(repo, contains('/admin/workspace/team'));
    expect(repo, contains('/admin/workspace/tasks/\$taskId/operational-status'));
    expect(repo, contains('/admin/workspace/tasks/\$taskId/events'));
    expect(screen, contains('استلام'));
    expect(screen, contains('غير مسند'));
    expect(screen, contains('انتظار المستخدم'));
    expect(screen, contains('انتظار داخلي'));
    expect(screen, contains('يحتاج متابعة'));
    expect(screen, contains('متأخر فقط'));
    expect(screen, contains('الأولوية والخطورة'));
    expect(screen, contains('سجل المهمة'));
    expect(screen, contains('فلترة حسب الموظف'));
    expect(pages, contains('يحتاج انتباهك'));
    expect(pages, contains('بلاغات حرجة'));
    expect(pages, contains('متوسط الاستلام'));
    expect(pages, contains('متوسط الرد'));
    expect(pages, contains('ملخص اليوم'));
  });

  test('platform regions workspace remains geographic without broker hierarchy', () {
    final regions = read('lib/features/regions/presentation/platform_regions_screen.dart');

    expect(regions, contains('المناطق والخريطة'));
    expect(regions, contains('إدارة جغرافية محايدة'));
    expect(regions, isNot(contains('assignBroker')));
    expect(regions, isNot(contains('activeBroker')));
  });
}

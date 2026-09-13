import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String relative) => File(relative).readAsStringSync();

  test('support workspaces keep their dedicated navigation', () {
    final shell = read('lib/features/app_shell/presentation/app_shell_screen.dart');
    expect(shell, contains("label: 'لوحة الدعم'"));
    expect(shell, contains("label: 'لوحة الفريق'"));
    expect(shell, contains("label: 'الوارد'"));
    expect(shell, contains("label: 'مهامي'"));
    expect(shell, contains("label: 'الأعمال'"));
    expect(shell, contains("label: 'الفريق'"));
    expect(shell, contains("roles.contains('support_agent')"));
    expect(shell, contains("roles.contains('support_manager')"));
  });

  test('general manager has executive-only primary navigation', () {
    final shell = read('lib/features/app_shell/presentation/app_shell_screen.dart');
    expect(shell, contains('GeneralManagerHomeFinancialOverlay()'));
    expect(shell, contains('GeneralManagerMarketScreen()'));
    expect(shell, contains('GeneralManagerAdministrationFinancialHubScreen()'));
    expect(shell, contains('GeneralManagerReportsFinancialHubScreen()'));
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

  test('general manager command center is interactive and not a support queue', () {
    final pages = read('lib/features/admin/presentation/general_manager_pages.dart');
    final repo = read('lib/features/admin/data/general_manager_repository.dart');
    expect(repo, contains('/admin/workspace/general-manager/insights'));
    expect(repo, contains('/admin/workspace/general-manager/team'));
    expect(repo, contains('/admin/workspace/general-manager/place-search'));
    expect(pages, contains('يحتاج تدخلك الآن'));
    expect(pages, contains('حالة التشغيل'));
    expect(pages, contains('الخريطة الإدارية'));
    expect(pages, contains('ابحث عن محافظة أو مديرية أو منطقة'));
    expect(pages, contains('عرض اليمن بالكامل'));
    expect(pages, contains('GeneralManagerTeamScreen'));
    expect(pages, contains('إدارة المنظمة لا إدارة الطلبات'));
    expect(pages, contains('الموظفون والفرق'));
    expect(pages, contains('الحسابات والأدوار والصلاحيات'));
    expect(pages, contains('GeneralManagerAccountsScreen'));
    expect(pages, contains('رحلة العقار داخل المنصة'));
    expect(pages, contains("const _SectionTitle('المالية')"));
    expect(pages, contains("ButtonSegment(value: '7d'"));
    expect(pages, contains("ButtonSegment(value: '30d'"));
    expect(pages, isNot(contains('SupportTasksScreen(')));
    expect(pages, isNot(contains('SupportTeamScreen(')));
  });

  test('consumer navigation remains unchanged', () {
    final shell = read('lib/features/app_shell/presentation/app_shell_screen.dart');
    expect(shell, contains("label: 'العقارات'"));
    expect(shell, contains("label: 'الرسائل'"));
    expect(shell, contains("label: 'المعاينات'"));
    expect(shell, contains("label: 'إعلاناتي'"));
    expect(shell, contains("label: 'حسابي'"));
    expect(shell, isNot(contains("label: 'الخدمات'")));
    expect(shell, isNot(contains("label: 'المشاريع'")));
  });

  test('shared support queue contract remains available', () {
    final repo = read('lib/features/support/data/support_workspace_repository.dart');
    final screen = read('lib/features/support/presentation/support_tasks_screen.dart');
    expect(repo, contains('/admin/workspace/tasks/\$taskId/claim'));
    expect(repo, contains('/admin/workspace/dashboard'));
    expect(repo, contains('/admin/workspace/team'));
    expect(screen, contains('استلام'));
    expect(screen, contains('غير مسند'));
    expect(screen, contains('انتظار المستخدم'));
    expect(screen, contains('يحتاج متابعة'));
  });
}

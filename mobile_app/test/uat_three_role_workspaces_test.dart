import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String relative) => File(relative).readAsStringSync();

  test('support workspaces keep their dedicated navigation', () {
    final shell = read('lib/features/app_shell/presentation/app_shell_screen.dart');
    expect(shell, contains("label: 'لوحة الدعم'"));
    expect(shell, contains("label: 'لوحة الفريق'"));
    expect(shell, contains("label: 'الوارد'"));
    expect(shell, contains('SupportMapScreen('));
    expect(shell, contains('SupportMessagesScreen('));
    expect(shell, contains('الدخول كمستخدم'));
    expect(shell, isNot(contains("label: 'مهامي'")));
    expect(shell, contains("label: 'الأعمال'"));
    expect(shell, contains("label: 'الفريق'"));
    expect(shell, contains("roles.contains('support_agent')"));
    expect(shell, contains("roles.contains('support_manager')"));
  });

  test('general manager has executive-only primary navigation', () {
    final shell = read('lib/features/app_shell/presentation/app_shell_screen.dart');
    expect(shell, contains('GeneralManagerOperationsScreen(GeneralManagerSection.home)'));
    expect(shell, contains('GeneralManagerMarketScreen()'));
    expect(shell, contains('GeneralManagerAdministrationFinancialHubScreen()'));
    expect(shell, contains('GeneralManagerOperationsScreen(GeneralManagerSection.reports)'));
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
    final operations = read('lib/features/admin/presentation/general_manager_operations_screen.dart');
    final administration = read('lib/features/admin/presentation/general_manager_finance_hubs.dart');
    final repo = read('lib/features/admin/data/general_manager_repository.dart');
    expect(repo, contains('/admin/workspace/general-manager'));
    expect(repo, contains('/operations'));
    expect(repo, contains('/decisions'));
    expect(repo, contains('/place-search'));
    expect(operations, contains('يحتاج قرارك'));
    expect(operations, contains('إرسال القرار لمدير الفريق'));
    expect(operations, contains('/support/internal'));
    expect(pages, contains('الخريطة الإدارية'));
    expect(pages, contains('ابحث عن محافظة أو مديرية أو منطقة'));
    expect(pages, contains('عرض اليمن بالكامل'));
    expect(administration, contains('فرق المحافظات'));
    expect(administration, contains('GeneralManagerAccountsScreen'));
    expect(operations, contains('رحلة العقار'));
    expect(operations, contains('GeneralManagerFinanceWorkspaceScreen'));
    expect(operations, contains("'7d': '٧ أيام'"));
    expect(operations, contains("'30d': '٣٠ يومًا'"));
    expect(operations, isNot(contains('SupportTasksScreen(')));
    expect(operations, isNot(contains('SupportTeamScreen(')));
  });

  test('regional team tab shows members and scopes activity to that person', () {
    final workspace = read('lib/features/support/presentation/support_workspace_pages.dart');
    final team = workspace.split('class _SupportTeamScreenState').last
        .split('class PlatformReviewsScreen').first;
    expect(team, contains('أعضاء فريقي'));
    expect(team, contains('المهام المنجزة في الفترة'));
    expect(team, contains('openStaffThread(memberId: member.id, teamId: member.teamId)'));
    expect(team, isNot(contains('.teams()')));
    expect(team, isNot(contains('SupportTeamAdministrationScreen')));
  });

  test('template consumer navigation preserves gated listings and messaging access', () {
    final shell = read('lib/features/app_shell/presentation/app_shell_screen.dart');
    expect(shell, contains("label: 'الرئيسية'"));
    expect(shell, contains("label: 'الرسائل'"));
    expect(shell, contains("label: 'إعلاناتي'"));
    final router = read('lib/router/app_router.dart');
    final addProperty = router.split("path: '/add-property'")[1].split("path: '/my-listings'")[0];
    expect(addProperty, contains('Stage6AuthGate('));
    expect(addProperty, contains('requireListingEligible: true'));
    expect(shell, contains('Stage6AuthGate(guestIcon: Icons.chat_bubble_outline, child: MessagesScreen())'));
    expect(File('lib/features/account/presentation/account_screen.dart').readAsStringSync(), isNot(contains("context.push('/bookings')")));
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
    expect(screen, contains('استلم'));
    expect(screen, isNot(contains('متابعة التواصل')));
    expect(screen, contains('انتظار المستخدم'));
    expect(screen, contains('يحتاج متابعة'));
  });
}

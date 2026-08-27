import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('admin workspace exposes only the requested core sections', () async {
    final source = await File(
      'lib/features/admin/presentation/admin_dashboard_screen.dart',
    ).readAsString();

    for (final label in const [
      'المستخدمون والأدوار والصلاحيات',
      'الإعلانات والمراجعة',
      'الخريطة والمناطق',
      'الدعم والبلاغات',
      'الحجوزات والمعاينات',
      'الخدمات والمدفوعات',
      'سجل العمليات',
      'الإعدادات',
    ]) {
      expect(source.contains(label), isTrue, reason: 'missing: $label');
    }
  });

  test('support workspace exposes staff and manager workflows', () async {
    final workspace = await File(
      'lib/features/support/presentation/support_workspace_screen.dart',
    ).readAsString();
    final cases = await File(
      'lib/features/support/presentation/support_admin_screen.dart',
    ).readAsString();
    final privateReports = await File(
      'lib/features/messages/presentation/conversation_reports_screen.dart',
    ).readAsString();
    final supportUsers = await File(
      'lib/features/support/presentation/support_users_screen.dart',
    ).readAsString();

    for (final label in const [
      'طلبات الدعم والتذاكر',
      'البلاغات',
      'المستخدمون',
      'المحادثات المبلغ عنها',
      'سجل العمل والمتابعة',
    ]) {
      expect(workspace.contains(label), isTrue, reason: 'missing: $label');
    }

    for (final action in const [
      'تصعيد',
      'إسناد',
      'إعادة فتح',
      'بدء المعالجة',
      'رد',
      'ملاحظة داخلية',
      'تغيير الحالة',
    ]) {
      expect(cases.contains(action), isTrue, reason: 'missing: $action');
    }

    expect(privateReports.contains('conversations.review_private'), isTrue);
    expect(privateReports.contains('فتح وتسجيل الوصول'), isTrue);
    expect(supportUsers.contains('/admin/support?case='), isTrue);
    expect(
      supportUsers.contains('فتح إجراءات الدعم المسموحة لك'),
      isTrue,
    );
  });

  test('active region and review UI do not restore exclusive broker regions',
      () async {
    final regions = await File(
      'lib/features/regions/presentation/regions_management_screen.dart',
    ).readAsString();
    final review = await File(
      'lib/features/reviews/presentation/listing_review_screen.dart',
    ).readAsString();

    expect(regions.contains('لا يتم تعيين دلال لمنطقة أو مربع'), isTrue);
    expect(review.contains('الدلال الرئيسي'), isFalse);
    expect(review.contains('دلال حصري'), isFalse);
  });
}

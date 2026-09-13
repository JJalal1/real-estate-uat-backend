import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('support workspace exposes listing investigation queue', () async {
    final shell = await File(
      'lib/features/app_shell/presentation/app_shell_screen.dart',
    ).readAsString();
    final tasks = await File(
      'lib/features/support/presentation/support_tasks_screen.dart',
    ).readAsString();

    expect(shell, contains("roles.contains('support_agent')"));
    expect(shell, contains("label: 'لوحة الدعم'"));
    expect(shell, contains("label: 'الوارد'"));
    expect(tasks, contains("_setType('listing_review')"));
    expect(tasks, contains("context.push('/admin/listing-review')"));
    expect(tasks, contains('تحقيق إعلانات'));
  });

  test('Phase 2 listing review requires claim and exposes duplicate evidence',
      () async {
    final entry = await File(
      'lib/features/reviews/presentation/listing_review_screen.dart',
    ).readAsString();
    final screen = await File(
      'lib/features/reviews/presentation/listing_review_workspace_screen.dart',
    ).readAsString();

    expect(entry, contains('ListingReviewWorkspaceScreen'));
    expect(screen, contains('استلام الطلب'));
    expect(screen, contains('تم الاستلام - قيد التحقيق'));
    expect(screen, contains('اشتباه تكرار'));
    expect(screen, contains('ربط الإعلان بهوية هذا العقار'));
    expect(screen, contains('سبب اعتبار الإعلان غير مكرر'));
    expect(screen, contains('ref.invalidate(reviewQueueProvider);'));
  });
}

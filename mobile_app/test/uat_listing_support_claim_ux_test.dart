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

    expect(shell.contains("roles.contains('support_agent')"), isTrue);
    expect(shell.contains("label: 'مركز الدعم'"), isTrue);
    expect(tasks.contains("_setType('listing_review')"), isTrue);
    expect(tasks.contains("context.push('/admin/listing-review')"), isTrue);
    expect(tasks.contains('تحقيق إعلانات'), isTrue);
  });

  test('listing review screen uses support claim wording', () async {
    final screen = await File(
      'lib/features/reviews/presentation/listing_review_screen.dart',
    ).readAsString();
    expect(screen.contains('استلام الطلب'), isTrue);
    expect(screen.contains('تم الاستلام - قيد التحقيق'), isTrue);
    expect(screen.contains('ref.invalidate(reviewQueueProvider);'), isTrue);
  });
}

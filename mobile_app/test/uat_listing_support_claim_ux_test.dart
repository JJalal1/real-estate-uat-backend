import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('support account exposes listing investigation queue', () async {
    final account = await File(
      'lib/features/account/presentation/account_screen.dart',
    ).readAsString();
    expect(account.contains("hasPermission('listings.moderate')"), isTrue);
    expect(account.contains("context.push('/admin/listing-review')"), isTrue);
    expect(account.contains('طلبات تحقيق الإعلانات'), isTrue);
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

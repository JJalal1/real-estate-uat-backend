import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('listing editor keeps rental settlement inputs in the listing journey', () {
    final source = File(
      'lib/features/properties/presentation/listing_editor_screen.dart',
    ).readAsStringSync();

    expect(source, contains('final _monthlyRent = TextEditingController()'));
    expect(source, contains('final _rentalTermMonths = TextEditingController()'));
    expect(source, contains('final _advanceMonths = TextEditingController()'));
    expect(source, contains('الإيجار الشهري بالريال اليمني *'));
    expect(source, contains('مدة التأجير يجب أن تكون من شهر إلى 24 شهراً.'));
    expect(source, contains('عدد أشهر المقدم'));
    expect(source, contains("String _priceDisplayMode = 'excludes_sai'"));
  });

  test('published listing Sai attestation keeps the locked oath and explicit action', () {
    final source = File(
      'lib/features/properties/presentation/my_listings_screen.dart',
    ).readAsStringSync();

    expect(
      source,
      contains(
        'أقسم بالله أنني إذا تمت الصفقة عن طريق المنصة فسأقوم بسداد مستحقات المنصة من السعي حسب الشروط التي وافقت عليها عند نشر الإعلان.',
      ),
    );
    expect(source, contains('إقرار السعي للإعلان المنشور'));
    expect(source, contains('أقسم بذلك'));
    expect(source, contains('financialRepositoryProvider).attestSai(item.id)'));
  });

  test('Financial V1 repository uses the authoritative API routes', () {
    final source = File(
      'lib/features/financial/data/financial_repository.dart',
    ).readAsStringSync();

    expect(source, contains('/properties/\$propertyId/financial-config'));
    expect(source, contains('/finance/sai-attestations/pending'));
    expect(source, contains('/finance/payments/\$paymentId/proof'));
    expect(source, contains('/admin/finance/payments/\$paymentId'));
    expect(source, contains('/admin/finance/payments/\$paymentId/review'));
    expect(source, contains('/admin/finance/summary'));
  });

  test('support task resolution handles payment proof inside the claimed task', () {
    final source = File(
      'lib/features/support/presentation/support_tasks_screen.dart',
    ).readAsStringSync();

    expect(source, contains("case 'payment_review':"));
    expect(source, contains('_paymentReviewDialog(task)'));
    expect(source, contains('التحقق من إثبات الدفع'));
    expect(source, contains('طلب تصحيح'));
    expect(source, contains('رفض'));
    expect(source, contains('تأكيد الدفع'));
    expect(source, contains('actingAsAgent: widget.actingAsAgent'));
  });

  test('general manager reports include the executive finance summary', () {
    final source = File(
      'lib/features/admin/presentation/general_manager_pages.dart',
    ).readAsStringSync();

    expect(source, contains("const _SectionTitle('المالية')"));
    expect(source, contains('financialRepositoryProvider).adminSummary()'));
    expect(source, contains('جاري تحميل الملخص المالي'));
    expect(source, contains('تعذر تحميل الملخص المالي'));
  });
}

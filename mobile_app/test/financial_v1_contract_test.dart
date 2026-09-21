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

  test('Financial V1 repository uses authoritative user and GM API routes', () {
    final source = File(
      'lib/features/financial/data/financial_repository.dart',
    ).readAsStringSync();

    expect(source, contains('/properties/\$propertyId/financial-config'));
    expect(source, contains('/finance/sai-attestations/pending'));
    expect(source, contains('/finance/payments/\$paymentId/proof'));
    expect(source, contains('/finance/receivables/\$receivableId/payments'));
    expect(source, contains('/admin/finance/payments/\$paymentId'));
    expect(source, contains('/admin/finance/payments/\$paymentId/review'));
    expect(source, contains('/admin/finance/summary'));
    expect(source, contains('/admin/finance/workspace'));
    expect(source, contains('/admin/finance/payment-methods'));
  });

  test('manual payment journey contains locked anti fraud and evidence steps', () {
    final source = File(
      'lib/features/financial/presentation/deal_financial_screen.dart',
    ).readAsStringSync();

    expect(source, contains('إتمام الدفع'));
    expect(source, contains('لا تحول إلى أي رقم آخر يرسله لك شخص عبر المحادثات'));
    expect(source, contains('بيانات الدفع المعتمدة تظهر في هذه الصفحة فقط'));
    expect(source, contains('نسخ الرقم'));
    expect(source, contains('نسخ المبلغ'));
    expect(source, contains('لقد أتممت التحويل'));
    expect(source, contains('إرسال للتحقق'));
    expect(source, contains('لا تدفع مرة أخرى لهذه العملية'));
  });

  test('wallet logos are bundled declared and mapped to their payment methods', () {
    expect(File('assets/payments/jeeb.png').existsSync(), isTrue);
    expect(File('assets/payments/kuraimi.png').existsSync(), isTrue);
    expect(File('assets/payments/jawali.png').existsSync(), isTrue);
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final models = File(
      'lib/features/financial/domain/financial_models.dart',
    ).readAsStringSync();
    expect(pubspec, contains('assets/payments/'));
    expect(models, contains("'assets/payments/jeeb.png'"));
    expect(models, contains("'assets/payments/kuraimi.png'"));
    expect(models, contains("'assets/payments/jawali.png'"));
  });

  test('advertiser financial account includes deals payouts and platform receivables', () {
    final source = File(
      'lib/features/financial/presentation/financial_account_screen.dart',
    ).readAsStringSync();

    expect(source, contains('ملخص الحساب'));
    expect(source, contains('مستحقات المنصة عليّ'));
    expect(source, contains('مستحق لي / التحويلات'));
    expect(source, contains('صفقاتي'));
    expect(source, contains('مدفوعاتي'));
    expect(source, contains('سداد مستحق المنصة'));
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

  test('general manager finance workspace exposes complete sections and filters', () {
    final source = File(
      'lib/features/admin/presentation/general_manager_finance_screens.dart',
    ).readAsStringSync();
    final hubs = File(
      'lib/features/admin/presentation/general_manager_finance_hubs.dart',
    ).readAsStringSync();

    expect(source, contains('إدارة طرق الدفع'));
    expect(source, contains('السماح بالدفع الكامل للصفقة'));
    expect(source, contains('السماح بالسعي / مستحقات المنصة فقط'));
    expect(source, contains('الصفقات والمعاملات'));
    expect(source, contains('المدفوعات الواردة'));
    expect(source, contains('التحويلات للمعلنين'));
    expect(source, contains('مستحقات المنصة'));
    expect(source, contains('المتأخر بعد 24 ساعة'));
    expect(source, contains('القيود المالية'));
    expect(source, contains('الاستردادات'));
    expect(source, contains('النزاعات'));
    expect(source, contains('سجل التدقيق المالي'));
    expect(source, contains("labelText: 'الفترة'"));
    expect(source, contains("labelText: 'نوع الصفقة'"));
    expect(source, contains("labelText: 'نوع المعلن'"));
    expect(source, contains("labelText: 'المحافظة'"));
    expect(hubs, contains('GeneralManagerHomeFinancialOverlay'));
    expect(hubs, contains('GeneralManagerAdministrationFinancialHubScreen'));
    expect(hubs, contains('GeneralManagerReportsFinancialHubScreen'));
  });
}

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding='utf-8')


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding='utf-8')


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, found {count}: {old[:100]!r}')
    write(path, text.replace(old, new, 1))


# Listing editor: rental finance fields, base price on edit, and public price display choice.
p = 'mobile_app/lib/features/properties/presentation/listing_editor_screen.dart'
replace_once(p,
"  final _price = TextEditingController();\n  final _area = TextEditingController();",
"  final _price = TextEditingController();\n  final _monthlyRent = TextEditingController();\n  final _rentalTermMonths = TextEditingController();\n  final _advanceMonths = TextEditingController();\n  final _area = TextEditingController();")
replace_once(p,
"  PropertySaiEnvelope? _saiEnvelope;\n  bool _saiBusy = false;",
"  PropertySaiEnvelope? _saiEnvelope;\n  bool _saiBusy = false;\n  String _priceDisplayMode = 'excludes_sai';")
replace_once(p,
"  bool? get _parkingValue =>\n      _parkingChoice == null ? null : _parkingChoice == 'yes';",
"  bool? get _parkingValue =>\n      _parkingChoice == null ? null : _parkingChoice == 'yes';\n  bool get _visitorPaysSai => const {'buyer', 'tenant'}.contains(\n        _saiEnvelope?.sai?.payer ?? _saiEnvelope?.management?.payer,\n      );\n  double? get _effectivePrice {\n    if (_purpose == 'rent') {\n      final monthly = double.tryParse(_monthlyRent.text.trim());\n      final advance = int.tryParse(_advanceMonths.text.trim());\n      if (monthly == null || monthly <= 0 || advance == null || advance <= 0) return null;\n      return monthly * advance;\n    }\n    return double.tryParse(_price.text.trim());\n  }\n  String get _priceSummaryText {\n    if (_purpose == 'rent') {\n      final monthly = _monthlyRent.text.trim();\n      final advance = _advanceMonths.text.trim();\n      return monthly.isEmpty ? '—' : '$monthly YER شهرياً${advance.isEmpty ? '' : ' · مقدم $advance شهر'}';\n    }\n    return '${_price.text.trim()} YER';\n  }")
replace_once(p,
"    _price.addListener(_onPriceChanged);",
"    _price.addListener(_onPriceChanged);\n    _monthlyRent.addListener(_onPriceChanged);\n    _advanceMonths.addListener(_onPriceChanged);")
replace_once(p,
"    _price.text = property.price.toStringAsFixed(0);",
"    _price.text = property.editablePrice.toStringAsFixed(0);\n    _monthlyRent.text = property.monthlyRent?.toStringAsFixed(0) ?? '';\n    _rentalTermMonths.text = property.rentalTermMonths?.toString() ?? '';\n    _advanceMonths.text = property.advanceMonths?.toString() ?? '';\n    _priceDisplayMode = property.priceDisplayMode ?? 'excludes_sai';")
replace_once(p,
"    _price.removeListener(_onPriceChanged);",
"    _price.removeListener(_onPriceChanged);\n    _monthlyRent.removeListener(_onPriceChanged);\n    _advanceMonths.removeListener(_onPriceChanged);")
replace_once(p,
"      _price,\n      _area,",
"      _price,\n      _monthlyRent,\n      _rentalTermMonths,\n      _advanceMonths,\n      _area,")
old_price = '''  Widget _priceStep() {
    final amountWords = arabicRiyalAmountInWords(_price.text) ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(
          title: 'السعر والتواصل',
          subtitle: 'حدد السعر ووسائل التواصل التي تريد إظهارها للمهتمين.',
        ),
        const SizedBox(height: AppSpacing.s16),
        AppTextField(
          controller: _price,
          label: 'السعر بالريال اليمني *',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          enabled: !_busy,
        ),
        if (amountWords.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s8),
          AppInlineMessage(
            title: 'المبلغ بالحروف',
            message: amountWords,
            tone: AppStatusTone.info,
          ),
        ],
        const SizedBox(height: AppSpacing.s12),
        AppTextField(
          controller: _phone,
          label: 'رقم الاتصال',
          keyboardType: TextInputType.phone,
          enabled: !_busy,
        ),
        const SizedBox(height: AppSpacing.s12),
        AppTextField(
          controller: _whatsapp,
          label: 'رقم واتساب',
          keyboardType: TextInputType.phone,
          enabled: !_busy,
        ),
      ],
    );
  }
'''
new_price = '''  Widget _priceStep() {
    final wordsSource = _purpose == 'rent' ? _monthlyRent.text : _price.text;
    final amountWords = arabicRiyalAmountInWords(wordsSource) ?? '';
    final initialAmount = _effectivePrice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionHeader(
          title: _purpose == 'rent' ? 'الإيجار والتواصل' : 'السعر والتواصل',
          subtitle: _purpose == 'rent'
              ? 'أدخل الإيجار الشهري ومدة التأجير وعدد أشهر المقدم.'
              : 'حدد السعر ووسائل التواصل التي تريد إظهارها للمهتمين.',
        ),
        const SizedBox(height: AppSpacing.s16),
        if (_purpose == 'sale')
          AppTextField(
            controller: _price,
            label: 'سعر البيع بالريال اليمني *',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            enabled: !_busy,
          )
        else ...[
          AppTextField(
            controller: _monthlyRent,
            label: 'الإيجار الشهري بالريال اليمني *',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            enabled: !_busy,
          ),
          const SizedBox(height: AppSpacing.s12),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: _rentalTermMonths,
                  label: 'مدة التأجير بالأشهر *',
                  keyboardType: TextInputType.number,
                  enabled: !_busy,
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: AppTextField(
                  controller: _advanceMonths,
                  label: 'أشهر المقدم *',
                  keyboardType: TextInputType.number,
                  enabled: !_busy,
                ),
              ),
            ],
          ),
          if (initialAmount != null) ...[
            const SizedBox(height: AppSpacing.s8),
            AppInlineMessage(
              title: 'المبلغ الأساسي عند البداية',
              message: '${initialAmount.toStringAsFixed(0)} YER قبل السعي',
              tone: AppStatusTone.info,
            ),
          ],
        ],
        if (amountWords.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s8),
          AppInlineMessage(
            title: _purpose == 'rent' ? 'الإيجار الشهري بالحروف' : 'المبلغ بالحروف',
            message: amountWords,
            tone: AppStatusTone.info,
          ),
        ],
        if (_isSaiReady && _visitorPaysSai) ...[
          const SizedBox(height: AppSpacing.s16),
          Text('طريقة عرض السعر للباحث', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.s8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'excludes_sai', label: Text('السعر + السعي')),
              ButtonSegment(value: 'includes_sai', label: Text('السعر شامل السعي')),
            ],
            selected: {_priceDisplayMode},
            onSelectionChanged: _busy ? null : (value) => setState(() => _priceDisplayMode = value.first),
          ),
          const SizedBox(height: AppSpacing.s8),
          const Text('سيظهر للباحث إجمالي السعي والطرف الذي يتحمله فقط، بدون إظهار أي تقسيم داخلي.'),
        ],
        const SizedBox(height: AppSpacing.s12),
        AppTextField(
          controller: _phone,
          label: 'رقم الاتصال',
          keyboardType: TextInputType.phone,
          enabled: !_busy,
        ),
        const SizedBox(height: AppSpacing.s12),
        AppTextField(
          controller: _whatsapp,
          label: 'رقم واتساب',
          keyboardType: TextInputType.phone,
          enabled: !_busy,
        ),
      ],
    );
  }
'''
replace_once(p, old_price, new_price)
replace_once(p,
"      final value = double.tryParse(_price.text.trim());\n      if (value == null || value <= 0) return 'أدخل سعراً صحيحاً أكبر من صفر.';",
"      if (_purpose == 'sale') {\n        final value = double.tryParse(_price.text.trim());\n        if (value == null || value <= 0) return 'أدخل سعراً صحيحاً أكبر من صفر.';\n      } else {\n        final monthly = double.tryParse(_monthlyRent.text.trim());\n        final term = int.tryParse(_rentalTermMonths.text.trim());\n        final advance = int.tryParse(_advanceMonths.text.trim());\n        if (monthly == null || monthly <= 0) return 'أدخل الإيجار الشهري بشكل صحيح.';\n        if (term == null || term < 1 || term > 24) return 'مدة التأجير يجب أن تكون من شهر إلى 24 شهراً.';\n        if (advance == null || advance < 1 || advance > term) return 'أشهر المقدم يجب أن تكون من شهر وحتى مدة التأجير.';\n      }")
replace_once(p,
"      price: double.parse(_price.text.trim()),\n      areaValue:",
"      price: _effectivePrice!,\n      priceDisplayMode: _visitorPaysSai ? _priceDisplayMode : 'excludes_sai',\n      monthlyRent: _purpose == 'rent' ? double.parse(_monthlyRent.text.trim()) : null,\n      rentalTermMonths: _purpose == 'rent' ? int.parse(_rentalTermMonths.text.trim()) : null,\n      advanceMonths: _purpose == 'rent' ? int.parse(_advanceMonths.text.trim()) : null,\n      areaValue:")
replace_once(p, "_SummaryRow(label: 'السعر', value: '${_price.text.trim()} YER'),", "_SummaryRow(label: 'السعر', value: _priceSummaryText),")
replace_once(p, "                  '${_price.text.trim()} YER',", "                  _priceSummaryText,")

# My Listings: explicit post-publication Sai oath action.
p = 'mobile_app/lib/features/properties/presentation/my_listings_screen.dart'
replace_once(p, "import '../../../core/widgets/app_components.dart';\n", "import '../../../core/widgets/app_components.dart';\nimport '../../financial/data/financial_repository.dart';\n")
replace_once(p,
"                            onDelete: item.canEdit\n                                ? () => _delete(context, ref, item)\n                                : null,",
"                            onDelete: item.canEdit\n                                ? () => _delete(context, ref, item)\n                                : null,\n                            onAttest: item.saiAttestationRequired\n                                ? () => _attestSai(context, ref, item)\n                                : null,")
insert_attest = '''  Future<void> _attestSai(
    BuildContext context,
    WidgetRef ref,
    PropertyDetails item,
  ) async {
    const oath = 'أقسم بالله أنني إذا تمت الصفقة عن طريق المنصة فسأقوم بسداد مستحقات المنصة من السعي حسب الشروط التي وافقت عليها عند نشر الإعلان.';
    final confirmed = await AppDialog.show<bool>(
          context,
          title: 'إقرار السعي للإعلان المنشور',
          content: const Text(oath),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ليس الآن')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('أقسم بذلك')),
          ],
        ) ?? false;
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(financialRepositoryProvider).attestSai(item.id);
      ref.read(propertyDataRevisionProvider.notifier).state++;
      ref.invalidate(myListingsProvider);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تسجيل إقرار السعي لهذا الإعلان.')));
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    }
  }

'''
replace_once(p, "  Future<void> _delete(\n", insert_attest + "  Future<void> _delete(\n")
replace_once(p,
"    required this.onDelete,\n  });",
"    required this.onDelete,\n    required this.onAttest,\n  });")
replace_once(p,
"  final VoidCallback? onDelete;\n",
"  final VoidCallback? onDelete;\n  final VoidCallback? onAttest;\n")
replace_once(p,
"                if (onDelete != null)\n                  TextButton.icon(",
"                if (onAttest != null)\n                  FilledButton.tonalIcon(\n                    onPressed: onAttest,\n                    icon: const Icon(Icons.verified_user_outlined),\n                    label: const Text('إقرار السعي'),\n                  ),\n                if (onDelete != null)\n                  TextButton.icon(")
replace_once(p,
"bool _needsAction(PropertyDetails item) =>\n    item.reviewStatus == 'draft' ||",
"bool _needsAction(PropertyDetails item) =>\n    item.saiAttestationRequired ||\n    item.reviewStatus == 'draft' ||")
old_next = "(String, String, AppStatusTone)? _nextAction(PropertyDetails property) =>\n    switch (property.reviewStatus) {"
new_next = "(String, String, AppStatusTone)? _nextAction(PropertyDetails property) {\n  if (property.saiAttestationRequired) {\n    return ('مطلوب إقرار السعي', 'الإعلان منشور. أكمل إقرار السعي المسجل على نفس نسخة الشروط.', AppStatusTone.warning);\n  }\n  return switch (property.reviewStatus) {"
replace_once(p, old_next, new_next)
replace_once(p, "      _ => null,\n    };\n\n(String, AppStatusTone) _listingState", "      _ => null,\n    };\n}\n\n(String, AppStatusTone) _listingState")

# Support inbox: payment-review task opens actual proof and decision flow.
p = 'mobile_app/lib/features/support/presentation/support_tasks_screen.dart'
replace_once(p, "import 'package:flutter/material.dart';\n", "import 'dart:typed_data';\n\nimport 'package:flutter/material.dart';\n")
replace_once(p, "import '../../account/data/auth_controller.dart';\n", "import '../../account/data/auth_controller.dart';\nimport '../../financial/data/financial_repository.dart';\nimport '../../financial/domain/financial_models.dart';\n")
replace_once(p,
"      case 'support_ticket':\n      case 'report':\n        await _supportCaseDialog(task);\n        break;",
"      case 'support_ticket':\n      case 'report':\n        await _supportCaseDialog(task);\n        break;\n      case 'payment_review':\n        await _paymentReviewDialog(task);\n        break;")
payment_dialog = '''  Future<void> _paymentReviewDialog(SupportTaskItem task) async {
    FinancialPayment payment;
    try {
      payment = await ref.read(financialRepositoryProvider).adminPayment(
            task.sourceId,
            actingAsAgent: widget.actingAsAgent,
          );
    } catch (error) {
      _message(friendlyApiError(error));
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('التحقق من إثبات الدفع'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(payment.propertyTitle ?? 'العقار', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('المبلغ: ${payment.amount.toStringAsFixed(0)} ${payment.currency}'),
                Text('الطريقة: ${payment.paymentMethod ?? '—'}'),
                if (payment.senderName != null) Text('اسم المرسل: ${payment.senderName}'),
                if (payment.senderPhone != null) Text('رقم المرسل: ${payment.senderPhone}'),
                if (payment.providerReference != null) Text('رقم العملية: ${payment.providerReference}'),
                const SizedBox(height: 12),
                if (payment.hasProof)
                  FutureBuilder<List<int>?>(
                    future: ref.read(financialRepositoryProvider).paymentProof(
                          payment.id,
                          actingAsAgent: widget.actingAsAgent,
                        ).then((response) => response.data),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                      final bytes = snapshot.data;
                      if (bytes == null || bytes.isEmpty) return const Text('تعذر عرض صورة الإثبات.');
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(Uint8List.fromList(bytes), fit: BoxFit.contain),
                      );
                    },
                  )
                else
                  const Text('لا يوجد إثبات مرفوع.'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إغلاق')),
          TextButton(onPressed: () async {
            final note = await _paymentReviewReason('طلب تصحيح الإثبات');
            if (note == null || !mounted) return;
            await _reviewPayment(task.sourceId, 'correction', note);
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          }, child: const Text('طلب تصحيح')),
          TextButton(onPressed: () async {
            final note = await _paymentReviewReason('رفض الإثبات');
            if (note == null || !mounted) return;
            await _reviewPayment(task.sourceId, 'reject', note);
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          }, child: const Text('رفض')),
          FilledButton(onPressed: () async {
            await _reviewPayment(task.sourceId, 'confirm', null);
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          }, child: const Text('تأكيد الدفع')),
        ],
      ),
    );
  }

  Future<String?> _paymentReviewReason(String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, maxLines: 3, decoration: const InputDecoration(labelText: 'السبب *')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
          FilledButton(onPressed: () {
            final value = controller.text.trim();
            if (value.length >= 3) Navigator.pop(dialogContext, value);
          }, child: const Text('حفظ')),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _reviewPayment(int paymentId, String decision, String? note) async {
    try {
      await ref.read(financialRepositoryProvider).reviewPayment(
            paymentId,
            decision,
            note: note,
            actingAsAgent: widget.actingAsAgent,
          );
      _message(decision == 'confirm' ? 'تم تأكيد عملية الدفع.' : decision == 'correction' ? 'تم طلب تصحيح الإثبات.' : 'تم رفض الإثبات.');
    } catch (error) {
      _message(friendlyApiError(error));
    }
  }

'''
replace_once(p, "  Future<void> _supportCaseDialog(SupportTaskItem task) async {\n", payment_dialog + "  Future<void> _supportCaseDialog(SupportTaskItem task) async {\n")

# General Manager Reports: replace placeholder with live financial summary.
p = 'mobile_app/lib/features/admin/presentation/general_manager_pages.dart'
replace_once(p, "import '../../account/data/auth_controller.dart';\n", "import '../../account/data/auth_controller.dart';\nimport '../../financial/data/financial_repository.dart';\n")
old_panel = '''            const _InfoPanel(
              icon: Icons.account_balance_wallet_outlined,
              title: 'المالية والتقارير',
              subtitle: 'ستُبنى كقسم مستقل لاحقًا وفق البيانات المالية الحقيقية. لا توجد مدفوعات أو أرباح وهمية هنا.',
            ),'''
new_panel = '''            const _SectionTitle('المالية'),
            const SizedBox(height: 8),
            FutureBuilder<Map<String, dynamic>>(
              future: ref.read(financialRepositoryProvider).adminSummary(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const _LoadingList(message: 'جاري تحميل الملخص المالي…');
                if (snapshot.hasError) return _InfoPanel(icon: Icons.info_outline, title: 'تعذر تحميل الملخص المالي', subtitle: friendlyApiError(snapshot.error!));
                final finance = snapshot.data ?? const <String, dynamic>{};
                int count(String key) => _asInt(finance[key]);
                String amount(String key) => _formatMoney(_asDouble(finance[key]));
                return Column(
                  children: [
                    _MetricGrid(items: [
                      _Metric('بانتظار التحقق', count('payments_waiting_review'), Icons.receipt_long_outlined),
                      _Metric('حسابات متأخرة', count('overdue_accounts'), Icons.warning_amber_outlined),
                      _Metric('نزاعات مفتوحة', count('open_disputes'), Icons.gavel_outlined),
                    ]),
                    const SizedBox(height: 8),
                    _DataList(rows: [
                      _DataRow('مدفوعات مؤكدة', amount('confirmed_payments_amount')),
                      _DataRow('مستحقات مفتوحة', amount('open_receivables_amount')),
                      _DataRow('مستحقات متأخرة', amount('overdue_receivables_amount')),
                      _DataRow('تحويلات معلقة للمعلنين', amount('pending_payouts_amount')),
                    ]),
                  ],
                );
              },
            ),'''
replace_once(p, old_panel, new_panel)

print('Financial V1 Flutter finalization patch applied')

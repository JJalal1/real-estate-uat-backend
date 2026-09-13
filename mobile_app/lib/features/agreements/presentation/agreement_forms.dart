import 'package:flutter/material.dart';

import '../domain/agreement_models.dart';

Future<Map<String, dynamic>?> showAgreementTermsSheet(
  BuildContext context, {
  AgreementRevision? current,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AgreementTermsForm(current: current),
  );
}

Future<Map<String, dynamic>?> showRentalContractTermsSheet(
  BuildContext context, {
  AgreementRevision? fromAgreement,
  RentalContractRevision? current,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _RentalContractTermsForm(
      fromAgreement: fromAgreement,
      current: current,
    ),
  );
}

class _AgreementTermsForm extends StatefulWidget {
  const _AgreementTermsForm({this.current});
  final AgreementRevision? current;

  @override
  State<_AgreementTermsForm> createState() => _AgreementTermsFormState();
}

class _AgreementTermsFormState extends State<_AgreementTermsForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _currency;
  late final TextEditingController _deposit;
  late final TextEditingController _conditions;
  late String _cadence;
  DateTime? _start;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    final current = widget.current;
    _amount = TextEditingController(
      text: current == null ? '' : _plainNumber(current.agreedAmount),
    );
    _currency = TextEditingController(text: current?.currency ?? 'YER');
    _deposit = TextEditingController(
      text: current?.securityDepositAmount == null
          ? ''
          : _plainNumber(current!.securityDepositAmount!),
    );
    _conditions = TextEditingController(text: current?.conditions ?? '');
    _cadence = current?.rentCadence ?? 'monthly';
    _start = current?.rentalStartDate;
    _end = current?.rentalEndDate;
  }

  @override
  void dispose() {
    _amount.dispose();
    _currency.dispose();
    _deposit.dispose();
    _conditions.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _start ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (value != null) setState(() => _start = value);
  }

  Future<void> _pickEnd() async {
    final base = _start ?? DateTime.now();
    final value = await showDatePicker(
      context: context,
      initialDate: _end ?? base.add(const Duration(days: 365)),
      firstDate: base.add(const Duration(days: 1)),
      lastDate: base.add(const Duration(days: 3650)),
    );
    if (value != null) setState(() => _end = value);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_start != null && _end != null && !_end!.isAfter(_start!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تاريخ نهاية الإيجار يجب أن يكون بعد البداية.')),
      );
      return;
    }
    Navigator.pop(context, <String, dynamic>{
      'agreed_amount': double.parse(_amount.text.trim()),
      'currency': _currency.text.trim().toUpperCase(),
      'rent_cadence': _cadence,
      if (_deposit.text.trim().isNotEmpty)
        'security_deposit_amount': double.parse(_deposit.text.trim()),
      if (_start != null) 'rental_start_date': _apiDate(_start!),
      if (_end != null) 'rental_end_date': _apiDate(_end!),
      if (_conditions.text.trim().isNotEmpty)
        'conditions': _conditions.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.current == null ? 'بدء اتفاق داخل التطبيق' : 'نسخة جديدة من الاتفاق',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'الاتفاق سجل داخل التطبيق بين الطرفين. أي تعديل جوهري ينشئ نسخة جديدة ويلغي أثر القبول السابق على النسخة الحالية.',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'المبلغ المتفق عليه'),
                  validator: _positiveNumber,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _currency,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'العملة (مثال YER)'),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    return RegExp(r'^[A-Za-z]{3,8}$').hasMatch(text)
                        ? null
                        : 'اكتب رمز عملة صحيحاً.';
                  },
                ),
                const SizedBox(height: 16),
                const Text('حقول الإيجار التالية تُستخدم فقط إذا كان العقار للإيجار.'),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _cadence,
                  decoration: const InputDecoration(labelText: 'دورية الإيجار'),
                  items: const [
                    DropdownMenuItem(value: 'monthly', child: Text('شهري')),
                    DropdownMenuItem(value: 'quarterly', child: Text('كل 3 أشهر')),
                    DropdownMenuItem(value: 'semiannual', child: Text('كل 6 أشهر')),
                    DropdownMenuItem(value: 'annual', child: Text('سنوي')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _cadence = value);
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _deposit,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'التأمين/الضمان المسجل (اختياري)',
                    helperText: 'تسجيل بند فقط — لا يتم تحصيل أو تحويل أي مبلغ.',
                  ),
                  validator: _optionalNonNegativeNumber,
                ),
                const SizedBox(height: 12),
                _DateRow(
                  label: 'بداية الإيجار المقترحة',
                  value: _start,
                  onPick: _pickStart,
                  onClear: _start == null ? null : () => setState(() => _start = null),
                ),
                const SizedBox(height: 8),
                _DateRow(
                  label: 'نهاية الإيجار المقترحة',
                  value: _end,
                  onPick: _pickEnd,
                  onClear: _end == null ? null : () => setState(() => _end = null),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _conditions,
                  minLines: 3,
                  maxLines: 7,
                  maxLength: 5000,
                  decoration: const InputDecoration(labelText: 'شروط أو ملاحظات إضافية'),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.description_outlined),
                  label: Text(widget.current == null ? 'إنشاء المسودة' : 'إنشاء النسخة الجديدة'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RentalContractTermsForm extends StatefulWidget {
  const _RentalContractTermsForm({this.fromAgreement, this.current});
  final AgreementRevision? fromAgreement;
  final RentalContractRevision? current;

  @override
  State<_RentalContractTermsForm> createState() => _RentalContractTermsFormState();
}

class _RentalContractTermsFormState extends State<_RentalContractTermsForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _currency;
  late final TextEditingController _deposit;
  late final TextEditingController _dueDay;
  late final TextEditingController _terms;
  late String _cadence;
  DateTime? _start;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    final current = widget.current;
    final agreement = widget.fromAgreement;
    _amount = TextEditingController(
      text: current != null
          ? _plainNumber(current.rentAmount)
          : agreement == null
              ? ''
              : _plainNumber(agreement.agreedAmount),
    );
    _currency = TextEditingController(text: current?.currency ?? agreement?.currency ?? 'YER');
    _deposit = TextEditingController(
      text: current?.securityDepositAmount != null
          ? _plainNumber(current!.securityDepositAmount!)
          : agreement?.securityDepositAmount == null
              ? ''
              : _plainNumber(agreement!.securityDepositAmount!),
    );
    _dueDay = TextEditingController(text: current?.paymentDueDay?.toString() ?? '');
    _terms = TextEditingController(text: current?.additionalTerms ?? agreement?.conditions ?? '');
    _cadence = current?.rentCadence ?? agreement?.rentCadence ?? 'monthly';
    _start = current?.startDate ?? agreement?.rentalStartDate;
    _end = current?.endDate ?? agreement?.rentalEndDate;
  }

  @override
  void dispose() {
    _amount.dispose();
    _currency.dispose();
    _deposit.dispose();
    _dueDay.dispose();
    _terms.dispose();
    super.dispose();
  }

  Future<void> _pick(bool start) async {
    final base = _start ?? DateTime.now().add(const Duration(days: 1));
    final value = await showDatePicker(
      context: context,
      initialDate: start ? (_start ?? base) : (_end ?? base.add(const Duration(days: 365))),
      firstDate: start ? DateTime.now().subtract(const Duration(days: 1)) : base.add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (value != null) setState(() => start ? _start = value : _end = value);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_start == null || _end == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حدد تاريخ بداية ونهاية الإيجار.')),
      );
      return;
    }
    if (!_end!.isAfter(_start!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تاريخ النهاية يجب أن يكون بعد البداية.')),
      );
      return;
    }
    Navigator.pop(context, <String, dynamic>{
      'rent_amount': double.parse(_amount.text.trim()),
      'currency': _currency.text.trim().toUpperCase(),
      'rent_cadence': _cadence,
      'start_date': _apiDate(_start!),
      'end_date': _apiDate(_end!),
      if (_deposit.text.trim().isNotEmpty)
        'security_deposit_amount': double.parse(_deposit.text.trim()),
      if (_dueDay.text.trim().isNotEmpty)
        'payment_due_day': int.parse(_dueDay.text.trim()),
      if (_terms.text.trim().isNotEmpty) 'additional_terms': _terms.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.current == null ? 'مسودة عقد إيجار داخل التطبيق' : 'نسخة جديدة من عقد الإيجار',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'هذا سجل اتفاق داخل التطبيق ولا يمثل توثيقاً حكومياً أو تسجيلاً رسمياً أو استشارة قانونية.',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'قيمة الإيجار'),
                  validator: _positiveNumber,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _currency,
                  decoration: const InputDecoration(labelText: 'العملة'),
                  validator: (value) => RegExp(r'^[A-Za-z]{3,8}$').hasMatch(value?.trim() ?? '')
                      ? null
                      : 'اكتب رمز عملة صحيحاً.',
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _cadence,
                  decoration: const InputDecoration(labelText: 'دورية الإيجار'),
                  items: const [
                    DropdownMenuItem(value: 'monthly', child: Text('شهري')),
                    DropdownMenuItem(value: 'quarterly', child: Text('كل 3 أشهر')),
                    DropdownMenuItem(value: 'semiannual', child: Text('كل 6 أشهر')),
                    DropdownMenuItem(value: 'annual', child: Text('سنوي')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _cadence = value);
                  },
                ),
                const SizedBox(height: 12),
                _DateRow(label: 'بداية الإيجار', value: _start, onPick: () => _pick(true)),
                const SizedBox(height: 8),
                _DateRow(label: 'نهاية الإيجار', value: _end, onPick: () => _pick(false)),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _deposit,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'التأمين/الضمان المسجل (اختياري)',
                    helperText: 'لا يتم تحصيل أو تحويل الأموال داخل هذه المرحلة.',
                  ),
                  validator: _optionalNonNegativeNumber,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _dueDay,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'يوم الاستحقاق من الشهر (1–28، اختياري)'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final day = int.tryParse(value.trim());
                    return day != null && day >= 1 && day <= 28 ? null : 'اختر يوماً من 1 إلى 28.';
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _terms,
                  minLines: 3,
                  maxLines: 8,
                  maxLength: 8000,
                  decoration: const InputDecoration(labelText: 'بنود إضافية'),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.home_work_outlined),
                  label: Text(widget.current == null ? 'إنشاء مسودة العقد' : 'إنشاء النسخة الجديدة'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({required this.label, required this.value, required this.onPick, this.onClear});
  final String label;
  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text(value == null ? label : '$label: ${_displayDate(value!)}'),
          ),
        ),
        if (onClear != null)
          IconButton(onPressed: onClear, icon: const Icon(Icons.close), tooltip: 'مسح التاريخ'),
      ],
    );
  }
}

String? _positiveNumber(String? value) {
  final number = double.tryParse(value?.trim() ?? '');
  return number != null && number > 0 ? null : 'اكتب مبلغاً أكبر من صفر.';
}

String? _optionalNonNegativeNumber(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final number = double.tryParse(value.trim());
  return number != null && number >= 0 ? null : 'اكتب مبلغاً صحيحاً أو اترك الحقل فارغاً.';
}

String _apiDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _displayDate(DateTime value) =>
    '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';

String _plainNumber(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2);

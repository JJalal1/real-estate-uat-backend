import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../financial/data/financial_repository.dart';
import '../../financial/domain/financial_models.dart';
import '../../regions/data/region_repository.dart';
import '../../regions/domain/region_models.dart';

class GeneralManagerPaymentMethodsScreen extends ConsumerStatefulWidget {
  const GeneralManagerPaymentMethodsScreen({super.key});

  @override
  ConsumerState<GeneralManagerPaymentMethodsScreen> createState() =>
      _GeneralManagerPaymentMethodsScreenState();
}

class _GeneralManagerPaymentMethodsScreenState
    extends ConsumerState<GeneralManagerPaymentMethodsScreen> {
  List<FinancialPaymentMethod> _methods = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    try {
      final rows =
          await ref.read(financialRepositoryProvider).adminPaymentMethods();
      if (!mounted) return;
      setState(() {
        _methods = rows;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyApiError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('إدارة طرق الدفع'),
            actions: [
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh))
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _Error(message: _error!, retry: _load)
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(14),
                            child: Text(
                                'بيانات المستفيد والحدود والتفعيل تُدار من الخادم. لا توجد مفاتيح مزود دفع داخل التطبيق، وهذه النسخة لا تنفذ تحويل أموال آليًا.'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._methods.map(_methodCard),
                      ],
                    ),
        ),
      );

  Widget _methodCard(FinancialPaymentMethod method) => Card(
        child: ListTile(
          leading: _logo(method),
          title: Text(method.name,
              style: const TextStyle(fontWeight: FontWeight.w900)),
          subtitle: Text(
              '${method.currency} • ${method.isEnabled ? 'مفعلة' : 'متوقفة'}\nدفع كامل: ${method.allowsFullPayment ? 'نعم' : 'لا'} • سعي فقط: ${method.allowsSaiOnly ? 'نعم' : 'لا'}'),
          isThreeLine: true,
          trailing: const Icon(Icons.edit_outlined),
          onTap: () => _edit(method),
        ),
      );

  Future<void> _edit(FinancialPaymentMethod method) async {
    final name = TextEditingController(text: method.name);
    final beneficiary = TextEditingController(text: method.beneficiaryName);
    final label = TextEditingController(text: method.destinationLabel);
    final destination = TextEditingController(text: method.destinationValue);
    final currency = TextEditingController(text: method.currency);
    final min = TextEditingController(text: method.minAmount?.toString() ?? '');
    final max = TextEditingController(text: method.maxAmount?.toString() ?? '');
    final instructions = TextEditingController(text: method.instructions ?? '');
    var enabled = method.isEnabled;
    var full = method.allowsFullPayment;
    var sai = method.allowsSaiOnly;
    var senderPhone = method.requiresSenderPhone;
    var providerRef = method.requiresProviderReference;

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Row(children: [
              _logo(method),
              const SizedBox(width: 8),
              Expanded(child: Text('إعداد ${method.name}')),
            ]),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم العرض')),
                  TextField(controller: beneficiary, decoration: const InputDecoration(labelText: 'اسم المستفيد')),
                  TextField(controller: label, decoration: const InputDecoration(labelText: 'وصف الرقم / الحساب')),
                  TextField(controller: destination, decoration: const InputDecoration(labelText: 'رقم الحساب / المحفظة')),
                  TextField(controller: currency, maxLength: 3, decoration: const InputDecoration(labelText: 'العملة')),
                  Row(children: [
                    Expanded(child: TextField(controller: min, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الحد الأدنى'))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: max, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الحد الأعلى'))),
                  ]),
                  TextField(controller: instructions, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'التعليمات')),
                  SwitchListTile(value: enabled, onChanged: (v) => setLocal(() => enabled = v), title: const Text('الوسيلة مفعلة')),
                  SwitchListTile(value: full, onChanged: (v) => setLocal(() => full = v), title: const Text('السماح بالدفع الكامل للصفقة')),
                  SwitchListTile(value: sai, onChanged: (v) => setLocal(() => sai = v), title: const Text('السماح بالسعي / مستحقات المنصة فقط')),
                  SwitchListTile(value: senderPhone, onChanged: (v) => setLocal(() => senderPhone = v), title: const Text('رقم المرسل مطلوب')),
                  SwitchListTile(value: providerRef, onChanged: (v) => setLocal(() => providerRef = v), title: const Text('رقم العملية مطلوب')),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('حفظ')),
            ],
          ),
        ),
      ),
    );
    if (save == true && mounted) {
      try {
        await ref.read(financialRepositoryProvider).updatePaymentMethod(method.id, {
          'name_ar': name.text.trim(),
          'beneficiary_name': beneficiary.text.trim(),
          'destination_label': label.text.trim(),
          'destination_value': destination.text.trim(),
          'currency': currency.text.trim().toUpperCase(),
          'min_amount': min.text.trim().isEmpty ? null : double.tryParse(min.text.trim()),
          'max_amount': max.text.trim().isEmpty ? null : double.tryParse(max.text.trim()),
          'instructions_ar': instructions.text.trim().isEmpty ? null : instructions.text.trim(),
          'is_enabled': enabled,
          'allows_full_payment': full,
          'allows_sai_only': sai,
          'requires_sender_phone': senderPhone,
          'requires_provider_reference': providerRef,
        });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث طريقة الدفع.')));
        await _load();
      } catch (error) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    }
    name.dispose(); beneficiary.dispose(); label.dispose(); destination.dispose(); currency.dispose(); min.dispose(); max.dispose(); instructions.dispose();
  }

  Widget _logo(FinancialPaymentMethod method) {
    final path = method.localAssetPath;
    return path == null
        ? const SizedBox(width: 42, height: 42, child: Icon(Icons.send_to_mobile_outlined))
        : Image.asset(path, width: 42, height: 42, fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox(width: 42, height: 42, child: Icon(Icons.account_balance_wallet_outlined)));
  }
}

class GeneralManagerFinanceWorkspaceScreen extends ConsumerStatefulWidget {
  const GeneralManagerFinanceWorkspaceScreen({super.key});

  @override
  ConsumerState<GeneralManagerFinanceWorkspaceScreen> createState() => _GeneralManagerFinanceWorkspaceScreenState();
}

class _GeneralManagerFinanceWorkspaceScreenState extends ConsumerState<GeneralManagerFinanceWorkspaceScreen> {
  Map<String, dynamic>? _data;
  List<GovernorateModel> _governorates = const [];
  bool _loading = true;
  String? _error;
  String _period = '30d';
  String? _transactionType;
  String? _advertiserType;
  int? _governorateId;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final values = await Future.wait([
        ref.read(financialRepositoryProvider).adminWorkspace(
          period: _period,
          transactionType: _transactionType,
          advertiserType: _advertiserType,
          governorateId: _governorateId,
        ),
        ref.read(regionRepositoryProvider).governorates(),
      ]);
      if (!mounted) return;
      setState(() {
        _data = values[0] as Map<String, dynamic>;
        _governorates = values[1] as List<GovernorateModel>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() { _loading = false; _error = friendlyApiError(error); });
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('المالية')),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _Error(message: _error!, retry: _load)
                  : RefreshIndicator(onRefresh: _load, child: _body()),
        ),
      );

  Widget _body() {
    final data = _data ?? const <String, dynamic>{};
    final summary = Map<String, dynamic>.from(data['summary'] as Map? ?? const {});
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _filters(),
        const SizedBox(height: 12),
        _metricGrid(summary),
        const SizedBox(height: 18),
        _section('الصفقات والمعاملات', 'deals', Icons.handshake_outlined),
        _section('المدفوعات الواردة', 'payments', Icons.payments_outlined),
        _section('التحويلات للمعلنين', 'payouts', Icons.account_balance_wallet_outlined),
        _section('مستحقات المنصة', 'receivables', Icons.receipt_long_outlined),
        _section('المتأخر بعد 24 ساعة', 'overdue', Icons.timer_off_outlined),
        _section('القيود المالية', 'holds', Icons.visibility_off_outlined),
        _section('الاستردادات', 'refunds', Icons.undo_outlined),
        _section('النزاعات', 'disputes', Icons.gavel_outlined),
        _section('سجل التدقيق المالي', 'audit_log', Icons.history_outlined),
      ],
    );
  }

  Widget _filters() => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 10, runSpacing: 8, children: [
            SizedBox(width: 150, child: DropdownButtonFormField<String>(
              value: _period,
              decoration: const InputDecoration(labelText: 'الفترة'),
              items: const [
                DropdownMenuItem(value: 'day', child: Text('اليوم')),
                DropdownMenuItem(value: '7d', child: Text('7 أيام')),
                DropdownMenuItem(value: '30d', child: Text('30 يومًا')),
                DropdownMenuItem(value: 'all', child: Text('كل الفترات')),
              ],
              onChanged: (v) { if (v != null) { _period = v; _load(); } },
            )),
            SizedBox(width: 150, child: DropdownButtonFormField<String?>(
              value: _transactionType,
              decoration: const InputDecoration(labelText: 'الصفقة'),
              items: const [
                DropdownMenuItem(value: null, child: Text('الكل')),
                DropdownMenuItem(value: 'sale', child: Text('بيع')),
                DropdownMenuItem(value: 'rent', child: Text('إيجار')),
              ],
              onChanged: (v) { _transactionType = v; _load(); },
            )),
            SizedBox(width: 160, child: DropdownButtonFormField<String?>(
              value: _advertiserType,
              decoration: const InputDecoration(labelText: 'نوع المعلن'),
              items: const [
                DropdownMenuItem(value: null, child: Text('الكل')),
                DropdownMenuItem(value: 'owner', child: Text('مالك')),
                DropdownMenuItem(value: 'broker', child: Text('دلال')),
                DropdownMenuItem(value: 'office', child: Text('مكتب')),
              ],
              onChanged: (v) { _advertiserType = v; _load(); },
            )),
            SizedBox(width: 190, child: DropdownButtonFormField<int?>(
              value: _governorateId,
              decoration: const InputDecoration(labelText: 'المحافظة'),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('كل المحافظات')),
                ..._governorates.map((g) => DropdownMenuItem<int?>(value: g.id, child: Text(g.nameAr))),
              ],
              onChanged: (v) { _governorateId = v; _load(); },
            )),
          ]),
        ),
      );

  Widget _metricGrid(Map<String, dynamic> s) => GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.8,
        children: [
          _metric('قيمة الصفقات', _money(s['gross_transaction_value']), Icons.monetization_on_outlined),
          _metric('إجمالي السعي', _money(s['total_sai_amount']), Icons.receipt_long_outlined),
          _metric('مستحق المنصة', _money(s['platform_entitlement_amount']), Icons.account_balance_outlined),
          _metric('بانتظار التحقق', '${s['payments_waiting_review'] ?? 0}', Icons.fact_check_outlined),
          _metric('مستحقات غير محصلة', _money(s['open_receivables_amount']), Icons.pending_actions_outlined),
          _metric('متأخر >24 ساعة', _money(s['overdue_receivables_amount']), Icons.timer_off_outlined),
          _metric('مستحق للمعلنين', _money(s['pending_payouts_amount']), Icons.account_balance_wallet_outlined),
          _metric('قيود مالية نشطة', '${s['active_financial_holds'] ?? 0}', Icons.visibility_off_outlined),
        ],
      );

  Widget _metric(String title, String value, IconData icon) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 20), const SizedBox(height: 5),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      );

  Widget _section(String title, String key, IconData icon) {
    final rows = _maps(_data?[key]);
    return Card(
      child: ExpansionTile(
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text('${rows.length} سجل'),
        children: rows.isEmpty
            ? const [Padding(padding: EdgeInsets.all(16), child: Text('لا توجد بيانات ضمن الفلاتر الحالية.'))]
            : rows.take(250).map((row) => ListTile(
                  dense: true,
                  title: Text(_rowTitle(row, key)),
                  subtitle: Text(_rowSubtitle(row, key), maxLines: 4, overflow: TextOverflow.ellipsis),
                )).toList(growable: false),
      ),
    );
  }

  String _rowTitle(Map<String, dynamic> row, String key) {
    if (key == 'deals') return '${row['property_title'] ?? 'صفقة'} • ${row['transaction_type'] == 'rent' ? 'إيجار' : 'بيع'}';
    if (key == 'payments') return '${row['reference'] ?? 'دفعة'} • ${row['status'] ?? ''}';
    if (key == 'payouts') return '${row['reference'] ?? 'تحويل'} • ${row['advertiser_name'] ?? ''}';
    if (key == 'receivables' || key == 'overdue') return '${row['reference'] ?? 'مستحق'} • ${row['advertiser_name'] ?? ''}';
    if (key == 'holds') return '${row['advertiser_name'] ?? 'معلن'} • ${row['released_at'] == null ? 'قيد نشط' : 'مرفوع'}';
    if (key == 'refunds') return '${row['reference'] ?? 'استرداد'} • ${row['status'] ?? ''}';
    if (key == 'disputes') return '${row['reference'] ?? 'نزاع'} • ${row['status'] ?? ''}';
    if (key == 'audit_log') return '${row['action'] ?? 'إجراء مالي'}';
    return '${row['reference'] ?? row['id'] ?? title}';
  }

  String _rowSubtitle(Map<String, dynamic> row, String key) {
    if (key == 'deals') return 'القيمة: ${_money(row['base_amount'], row['currency'])} • السعي: ${_money(row['sai_total_amount'], row['currency'])}\nالمعلن: ${row['advertiser_name'] ?? '-'} • المحافظة: ${row['governorate_name'] ?? '-'}';
    if (key == 'payments') return 'المبلغ: ${_money(row['required_amount'], row['currency'])} • الطريقة: ${row['payment_method'] ?? '-'}\n${row['property_title'] ?? ''}';
    if (key == 'payouts') return 'المبلغ: ${_money(row['amount'], row['currency'])} • الحالة: ${row['status'] ?? ''}';
    if (key == 'receivables' || key == 'overdue') return 'المتبقي: ${_money(row['remaining_amount'], row['currency'])} • الاستحقاق: ${row['due_at'] ?? '-'}\n${row['property_title'] ?? ''}';
    if (key == 'holds') return 'السبب: ${row['reason'] ?? '-'} • بدأ: ${row['started_at'] ?? '-'}';
    if (key == 'refunds') return 'المبلغ: ${_money(row['amount'], row['currency'])} • ${row['reason'] ?? ''}';
    if (key == 'disputes') return '${row['reason'] ?? ''}${row['resolution'] == null ? '' : '\nالحل: ${row['resolution']}'}';
    if (key == 'audit_log') return 'بواسطة: ${row['actor_name'] ?? 'النظام'} • ${row['created_at'] ?? ''}';
    return row.toString();
  }

  List<Map<String, dynamic>> _maps(dynamic value) => value is List
      ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(growable: false)
      : const [];
  String _money(dynamic value, [dynamic currency = 'YER']) {
    final number = value is num ? value.toDouble() : double.tryParse('${value ?? 0}') ?? 0;
    return '${number.toStringAsFixed(number == number.roundToDouble() ? 0 : 2)} ${currency ?? 'YER'}';
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: retry, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
          ]),
        ),
      );
}

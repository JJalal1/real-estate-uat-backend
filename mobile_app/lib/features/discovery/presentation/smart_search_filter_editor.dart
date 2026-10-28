import 'package:flutter/material.dart';
import '../../../core/widgets/app_components.dart';
import '../domain/smart_search_filters.dart';
import '../../properties/domain/property_schema.dart';

class SmartSearchFilterEditor extends StatefulWidget {
  const SmartSearchFilterEditor({required this.initial, this.focus, super.key});
  final SmartSearchFilters initial;
  final String? focus;
  @override
  State<SmartSearchFilterEditor> createState() => SmartSearchFilterEditorState();
}

class SmartSearchFilterEditorState extends State<SmartSearchFilterEditor> {
  static const _numbers = ['min_price', 'max_price', 'min_bedrooms', 'min_bathrooms', 'min_area_m2', 'max_area_m2'];
  late Map<String, dynamic> _values;
  late Map<String, TextEditingController> _text;
  String? _error;
  @override
  void initState() {
    super.initState(); _values = Map.of(widget.initial.values);
    _text = {for (final key in ['search', 'floor_number', ..._numbers]) key: TextEditingController(text: _values[key]?.toString() ?? '')};
  }
  @override
  void dispose() { for (final controller in _text.values) { controller.dispose(); } super.dispose(); }

  String _digits(String text) {
    const digits = {'٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4', '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9', '٫': '.', '٬': '', ',': ''};
    return text.trim().split('').map((char) => digits[char] ?? char).join();
  }
  void _save() {
    final next = Map<String, dynamic>.from(_values);
    for (final entry in _text.entries) {
      final text = entry.value.text.trim();
      if (text.isEmpty) { next.remove(entry.key); continue; }
      if (_numbers.contains(entry.key)) {
        final value = double.tryParse(_digits(text));
        final rooms = const ['min_bedrooms', 'min_bathrooms'].contains(entry.key);
        if (value == null || !value.isFinite || value < 0 || value > (rooms ? 50 : 1000000000000) || (rooms && value != value.roundToDouble())) {
          setState(() => _error = 'أدخل أرقامًا صحيحة للغرف والمساحة والميزانية.'); return;
        }
        next[entry.key] = rooms ? value.toInt() : value;
      } else { next[entry.key] = text; }
    }
    for (final pair in const [('min_price', 'max_price'), ('min_area_m2', 'max_area_m2')]) {
      if (next[pair.$1] is num && next[pair.$2] is num && (next[pair.$1] as num) > (next[pair.$2] as num)) {
        setState(() => _error = 'الحد الأدنى يجب ألا يتجاوز الحد الأعلى.'); return;
      }
    }
    if (next['search'] != widget.initial.values['search']) {
      next.remove('governorate');
      for (final key in SmartSearchFilters.mapFields) { next.remove(key); }
    }
    Navigator.of(context).pop(SmartSearchFilters.fromMap(next));
  }

  void _changed(VoidCallback change) {
    setState(() {
      change(); final clean = DynamicPropertySchema.filters({..._values, for (final e in _text.entries) if (e.value.text.isNotEmpty) e.key:e.value.text});
      _values = DynamicPropertySchema.filters(_values);
      for (final e in _text.entries) { if (!clean.containsKey(e.key)) e.value.clear(); }
    });
  }
  bool _applicable(String key) {
    const mapped = {'min_bedrooms':'bedrooms','min_bathrooms':'bathrooms','min_area_m2':'area_value','max_area_m2':'area_value'};
    return DynamicPropertySchema.applies(mapped[key] ?? key,_values);
  }
  bool _visible(String key) => _applicable(key) && (widget.focus == null || widget.focus == key ||
    (const ['budget', 'min_price', 'max_price'].contains(widget.focus) && const ['min_price', 'max_price', 'currency'].contains(key)) ||
    (const ['min_area_m2', 'max_area_m2'].contains(widget.focus) && const ['min_area_m2', 'max_area_m2'].contains(key)));

  Widget _field(String key, String label) => !_visible(key) ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(top: 12), child: TextField(
    key: ValueKey('filter-$key'), controller: _text[key], autofocus: widget.focus == key,
    maxLength: key == 'search' ? 120 : key == 'floor_number' ? 32 : 24,
    keyboardType: _numbers.contains(key) ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
    decoration: InputDecoration(labelText: label, counterText: '')));
  Widget _boolean(String key, String label) => !_visible(key) ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(top: 12), child: DropdownButtonFormField<bool>(
    value: _values[key] as bool?, isExpanded: true, isDense: false, itemHeight: null, decoration: InputDecoration(labelText: label),
    items: const [DropdownMenuItem(value: null, child: Text('لا يشترط')), DropdownMenuItem(value: true, child: Text('نعم')), DropdownMenuItem(value: false, child: Text('لا'))],
    onChanged: (value) => setState(() { if (value == null) { _values.remove(key); } else { _values[key] = value; } })));

  Widget _choices(String key, String label, Map<String, String> options, String allLabel) {
    if (!_visible(key)) return const SizedBox.shrink();
    final selected = _values[key];
    return Padding(key: ValueKey('filter-$key'), padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 6, children: [
          ChoiceChip(key: ValueKey('filter-$key-all'), label: Text(allLabel),
            selected: selected == null, showCheckmark: true,
            onSelected: (_) => _changed(() => _values.remove(key))),
          for (final option in options.entries)
            ChoiceChip(key: ValueKey('filter-$key-${option.key}'), label: Text(option.value),
              selected: selected == option.key, showCheckmark: true,
              onSelected: (_) => _changed(() {
                if (selected == option.key) { _values.remove(key); }
                else { _values[key] = option.key; }
              })),
        ]),
      ]));
  }

  Widget _minimumChoices(String key, String label, int last) {
    if (!_visible(key)) return const SizedBox.shrink();
    final raw = num.tryParse(_digits(_text[key]!.text));
    final selected = raw != null && raw == raw.roundToDouble() ? raw.toInt() : null;
    // The API is a single minimum, not a list of exact counts. Preserve a
    // previously saved minimum above the visible range until explicitly edited.
    final options = [for (var value = 1; value <= last; value++) value,
      if (selected != null && (selected < 1 || selected > last)) selected];
    return Padding(key: ValueKey('filter-$key'), padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 6, children: [
          ChoiceChip(key: ValueKey('filter-$key-all'), label: const Text('لا يشترط'),
            selected: _text[key]!.text.isEmpty, showCheckmark: true,
            onSelected: (_) => setState(() => _text[key]!.clear())),
          for (final value in options)
            ChoiceChip(key: ValueKey('filter-$key-$value'),
              label: Text('${arabicDigits('$value')}${value >= last ? '+' : ''}'),
              selected: selected == value, showCheckmark: true,
              onSelected: (_) => setState(() => _text[key]!.text = selected == value ? '' : '$value')),
        ]),
      ]));
  }

  @override
  Widget build(BuildContext context) {
    final type = _values['type'], rent = _values['purpose'] == 'rent';
    final advanced = <Widget>[
        _field('min_area_m2', 'أقل مساحة بالمتر المربع'), _field('max_area_m2', 'أقصى مساحة بالمتر المربع'),
        if (_visible('floor_number')) Padding(padding:const EdgeInsets.only(top:12),child:DropdownButtonFormField<String>(key:const ValueKey('filter-floor_number'),
          value:_text['floor_number']!.text.isEmpty ? null : _text['floor_number']!.text,isExpanded:true,isDense:false,itemHeight:null,decoration:const InputDecoration(labelText:'الدور'),
          items:[const DropdownMenuItem(value:null,child:Text('أي دور')),for(final e in DynamicPropertySchema.floorOptions.entries) DropdownMenuItem(value:e.key,child:Text(e.value)),
            if(_text['floor_number']!.text.isNotEmpty && !DynamicPropertySchema.floorOptions.containsKey(_text['floor_number']!.text)) DropdownMenuItem(value:_text['floor_number']!.text,child:Text(_text['floor_number']!.text))],
          onChanged:(v)=>setState(()=>_text['floor_number']!.text=v??''))),
        if (_visible('unit_occupies_entire_floor')) _boolean('unit_occupies_entire_floor', 'الوحدة تشغل الدور كاملًا'),
        if (_visible('has_elevator')) _boolean('has_elevator', 'مصعد'),
        if (type == 'land' && _visible('building_facade')) DropdownButtonFormField<String>(value: _values['building_facade'] as String?, isExpanded: true, isDense: false, itemHeight: null, decoration: const InputDecoration(labelText: 'واجهة الأرض'),
          items: [const DropdownMenuItem(value: null, child: Text('كل الواجهات')), for (final entry in SmartSearchFilters.facades.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value))],
          onChanged: (value) => setState(() { if (value == null) { _values.remove('building_facade'); } else { _values['building_facade'] = value; } })),
        if (_visible('has_parking')) ...[_boolean('has_parking', 'موقف'), const SizedBox(height: 12),
          if (_visible('building_facade')) DropdownButtonFormField<String>(value: _values['building_facade'] as String?, isExpanded: true, isDense: false, itemHeight: null, decoration: const InputDecoration(labelText: 'الواجهة'),
            items: [const DropdownMenuItem(value: null, child: Text('كل الواجهات')), for (final entry in SmartSearchFilters.facades.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value))],
            onChanged: (value) => setState(() { if (value == null) { _values.remove('building_facade'); } else { _values['building_facade'] = value; } }))],
    ];
    return Directionality(textDirection: TextDirection.rtl, child: Padding(
      padding: EdgeInsets.fromLTRB(18, 18, 18, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('شروط البحث', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 18),
        _choices('type', 'نوع العقار', SmartSearchFilters.types, 'كل الأنواع'),
        _choices('purpose', 'الغرض', const {'sale': 'بيع', 'rent': 'إيجار'}, 'بيع وإيجار'),
        _field('search', 'المحافظة أو المنطقة'),
        _field('min_price', rent ? 'من إيجار شهري' : 'أقل سعر'), _field('max_price', rent ? 'حتى إيجار شهري' : 'أعلى سعر'),
        const SizedBox(height: 12),
        if (_visible('currency')) DropdownButtonFormField<String>(key: const ValueKey('filter-currency'), value: _values['currency'] as String?, isExpanded: true, isDense: false, itemHeight: null, decoration: const InputDecoration(labelText: 'العملة'),
          items: const [DropdownMenuItem(value: null, child: Text('ريال يمني للميزانية')), DropdownMenuItem(value: 'YER', child: Text('ريال يمني')),
            DropdownMenuItem(value: 'USD', child: Text('دولار')), DropdownMenuItem(value: 'SAR', child: Text('ريال سعودي'))],
          onChanged: (value) => setState(() { if (value == null) { _values.remove('currency'); } else { _values['currency'] = value; } })),
        if (type == null || const ['apartment', 'house', 'villa'].contains(type)) ...[
          _minimumChoices('min_bedrooms', 'غرف النوم على الأقل', 6),
          _minimumChoices('min_bathrooms', 'دورات المياه على الأقل', 5),
        ],
        if (widget.focus == null) ExpansionTile(key: const ValueKey('filter-more'),
          tilePadding: EdgeInsets.zero, title: const Text('المزيد من الخيارات'),
          initiallyExpanded: const ['min_area_m2','max_area_m2','floor_number','unit_occupies_entire_floor','has_parking','building_facade']
            .any((key) => _values.containsKey(key)), children: advanced) else ...advanced,
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 20), AppButton(label: 'تطبيق الشروط', expand: true, onPressed: _save),
      ]))));
  }
}

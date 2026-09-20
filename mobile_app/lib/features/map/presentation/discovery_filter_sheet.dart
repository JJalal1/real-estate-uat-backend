import 'package:flutter/material.dart';

import '../../../core/design/app_design.dart';

class DiscoveryFilterResult {
  const DiscoveryFilterResult({
    this.purpose,
    this.type,
    this.minPrice,
    this.maxPrice,
    this.minBedrooms,
    this.minBathrooms,
    this.minArea,
    this.maxArea,
  });

  final String? purpose;
  final String? type;
  final double? minPrice;
  final double? maxPrice;
  final int? minBedrooms;
  final int? minBathrooms;
  final double? minArea;
  final double? maxArea;
}

class DiscoveryFilterSheet extends StatefulWidget {
  const DiscoveryFilterSheet({
    this.initialPurpose,
    this.initialType,
    this.initialMinPrice,
    this.initialMaxPrice,
    this.initialMinBedrooms,
    this.initialMinBathrooms,
    this.initialMinArea,
    this.initialMaxArea,
    super.key,
  });

  final String? initialPurpose;
  final String? initialType;
  final double? initialMinPrice;
  final double? initialMaxPrice;
  final int? initialMinBedrooms;
  final int? initialMinBathrooms;
  final double? initialMinArea;
  final double? initialMaxArea;

  @override
  State<DiscoveryFilterSheet> createState() => _DiscoveryFilterSheetState();
}

class _DiscoveryFilterSheetState extends State<DiscoveryFilterSheet> {
  late String? _purpose;
  late String? _type;
  late int? _minBedrooms;
  late int? _minBathrooms;
  late final TextEditingController _minPriceController;
  late final TextEditingController _maxPriceController;
  late final TextEditingController _minAreaController;
  late final TextEditingController _maxAreaController;

  String? _error;
  bool _submitting = false;
  bool _showMore = false;

  bool get _showRoomFilters =>
      _type == 'apartment' || _type == 'house' || _type == 'villa';

  @override
  void initState() {
    super.initState();
    _purpose = widget.initialPurpose;
    _type = widget.initialType;
    _minBedrooms = widget.initialMinBedrooms;
    _minBathrooms = widget.initialMinBathrooms;
    _minPriceController = TextEditingController(
      text: widget.initialMinPrice?.toStringAsFixed(0) ?? '',
    );
    _maxPriceController = TextEditingController(
      text: widget.initialMaxPrice?.toStringAsFixed(0) ?? '',
    );
    _minAreaController = TextEditingController(
      text: widget.initialMinArea?.toStringAsFixed(0) ?? '',
    );
    _maxAreaController = TextEditingController(
      text: widget.initialMaxArea?.toStringAsFixed(0) ?? '',
    );
    _showMore = widget.initialMinPrice != null ||
        widget.initialMaxPrice != null ||
        widget.initialMinBedrooms != null ||
        widget.initialMinBathrooms != null ||
        widget.initialMinArea != null ||
        widget.initialMaxArea != null;
  }

  @override
  void dispose() {
    _minPriceController.dispose();
    _maxPriceController.dispose();
    _minAreaController.dispose();
    _maxAreaController.dispose();
    super.dispose();
  }

  void _setType(String? value) {
    setState(() {
      _type = value;
      if (!_showRoomFilters) {
        _minBedrooms = null;
        _minBathrooms = null;
      }
    });
  }

  void _reset() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _purpose = null;
      _type = null;
      _minBedrooms = null;
      _minBathrooms = null;
      _minPriceController.clear();
      _maxPriceController.clear();
      _minAreaController.clear();
      _maxAreaController.clear();
      _error = null;
      _showMore = false;
    });
  }

  double? _parseOptionalDouble(TextEditingController controller) {
    final value = controller.text.trim();
    if (value.isEmpty) return null;
    return double.tryParse(value);
  }

  void _apply() {
    if (_submitting) return;
    FocusManager.instance.primaryFocus?.unfocus();

    final minPriceText = _minPriceController.text.trim();
    final maxPriceText = _maxPriceController.text.trim();
    final minAreaText = _minAreaController.text.trim();
    final maxAreaText = _maxAreaController.text.trim();

    final minPrice = _parseOptionalDouble(_minPriceController);
    final maxPrice = _parseOptionalDouble(_maxPriceController);
    final minArea = _parseOptionalDouble(_minAreaController);
    final maxArea = _parseOptionalDouble(_maxAreaController);

    final invalidNumber = (minPriceText.isNotEmpty && minPrice == null) ||
        (maxPriceText.isNotEmpty && maxPrice == null) ||
        (minAreaText.isNotEmpty && minArea == null) ||
        (maxAreaText.isNotEmpty && maxArea == null);
    if (invalidNumber) {
      setState(() => _error = 'تأكد من كتابة الأرقام بشكل صحيح.');
      return;
    }

    final hasNegative = (minPrice != null && minPrice < 0) ||
        (maxPrice != null && maxPrice < 0) ||
        (minArea != null && minArea < 0) ||
        (maxArea != null && maxArea < 0);
    if (hasNegative) {
      setState(() => _error = 'القيم لا يمكن أن تكون سالبة.');
      return;
    }

    if (minPrice != null && maxPrice != null && maxPrice < minPrice) {
      setState(() => _error = 'أعلى سعر يجب أن يكون أكبر من أقل سعر.');
      return;
    }

    if (minArea != null && maxArea != null && maxArea < minArea) {
      setState(() => _error = 'أكبر مساحة يجب أن تكون أكبر من أقل مساحة.');
      return;
    }

    setState(() {
      _error = null;
      _submitting = true;
    });

    Navigator.of(context).pop(
      DiscoveryFilterResult(
        purpose: _purpose,
        type: _type,
        minPrice: minPrice,
        maxPrice: maxPrice,
        minBedrooms: _showRoomFilters ? _minBedrooms : null,
        minBathrooms: _showRoomFilters ? _minBathrooms : null,
        minArea: minArea,
        maxArea: maxArea,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: EdgeInsetsDirectional.fromSTEB(
          AppLayout.compactPageGutter, AppSpacing.s8,
          AppLayout.compactPageGutter,
          MediaQuery.viewInsetsOf(context).bottom + AppSpacing.s24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppPageHeading(
              title: 'تصفية العقارات',
              subtitle: 'الفلاتر الأساسية أمامك، واضغط المزيد للخيارات التفصيلية.',
              actions: [AppButton(label: 'مسح', style: AppButtonStyle.text,
                  onPressed: _submitting ? null : _reset)],
            ),
            AppSectionCard(
              title: 'الغرض',
              child: Wrap(
                spacing: AppSpacing.s8,
                runSpacing: AppSpacing.s8,
                children: [
                  _choice('الكل', _purpose == null, () => setState(() => _purpose = null)),
                  _choice('للبيع', _purpose == 'sale', () => setState(() => _purpose = 'sale')),
                  _choice('للإيجار', _purpose == 'rent', () => setState(() => _purpose = 'rent')),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
            AppSectionCard(
              title: 'نوع العقار',
              child: Wrap(
                spacing: AppSpacing.s8,
                runSpacing: AppSpacing.s8,
                children: [
                  _choice('الكل', _type == null, () => _setType(null)),
                  _choice('شقة', _type == 'apartment', () => _setType('apartment')),
                  _choice('منزل', _type == 'house', () => _setType('house')),
                  _choice('فيلا', _type == 'villa', () => _setType('villa')),
                  _choice('أرض', _type == 'land', () => _setType('land')),
                  _choice('محل', _type == 'shop', () => _setType('shop')),
                  _choice('مكتب', _type == 'office', () => _setType('office')),
                  _choice('مزرعة', _type == 'farm', () => _setType('farm')),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
            AppButton(
              label: 'المزيد من الفلاتر',
              icon: _showMore ? Icons.expand_less : Icons.expand_more,
              style: AppButtonStyle.outlined,
              onPressed: () => setState(() => _showMore = !_showMore),
              expand: true,
            ),
            AnimatedCrossFade(
              duration: MediaQuery.disableAnimationsOf(context) ? AppMotion.instant : AppMotion.standard,
              crossFadeState: _showMore ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsetsDirectional.only(top: AppSpacing.s16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_showRoomFilters) ...[
                      AppSectionCard(
                        title: 'غرف النوم',
                        child: Wrap(
                          spacing: AppSpacing.s8, runSpacing: AppSpacing.s8,
                          children: [for (final number in [1, 2, 3, 4, 5])
                            _numberChoice(label: '$number+', value: _minBedrooms, number: number,
                                onChanged: (value) => setState(() => _minBedrooms = value))],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s16),
                      AppSectionCard(
                        title: 'الحمامات',
                        child: Wrap(
                          spacing: AppSpacing.s8, runSpacing: AppSpacing.s8,
                          children: [for (final number in [1, 2, 3, 4])
                            _numberChoice(label: '$number+', value: _minBathrooms, number: number,
                                onChanged: (value) => setState(() => _minBathrooms = value))],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s16),
                    ],
                    AppSectionCard(
                      title: 'المساحة (م²)',
                      child: AppFieldPair(
                        first: _numberField(_minAreaController, 'من'),
                        second: _numberField(_maxAreaController, 'إلى'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s16),
                    AppSectionCard(
                      title: 'السعر',
                      child: AppFieldPair(
                        first: _numberField(_minPriceController, 'أقل سعر'),
                        second: _numberField(_maxPriceController, 'أعلى سعر'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.s16),
              AppInlineMessage(message: _error!, tone: AppStatusTone.error, icon: Icons.error_outline),
            ],
            const SizedBox(height: AppSpacing.s24),
            AppButton(
              label: 'عرض العقارات',
              icon: Icons.search,
              onPressed: _submitting ? null : _apply,
              expand: true,
            ),
          ],
        ),
      );

  Widget _numberField(TextEditingController controller, String label) => TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label),
      );

  Widget _choice(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: _submitting ? null : (_) => onTap(),
    );
  }

  Widget _numberChoice({
    required String label,
    required int? value,
    required int number,
    required ValueChanged<int?> onChanged,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: value == number,
      onSelected: _submitting
          ? null
          : (_) => onChanged(value == number ? null : number),
    );
  }
}


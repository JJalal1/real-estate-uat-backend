from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

def edit(path, fn):
    p = ROOT / path
    s = p.read_text()
    n = fn(s)
    if n == s:
        raise SystemExit(f'No change made to {path}')
    p.write_text(n)


def rep(s, old, new, name):
    if old not in s:
        raise SystemExit(f'Missing pattern {name}')
    return s.replace(old, new, 1)


def listing(s):
    s = rep(s, "import '../../../core/network/api_error_message.dart';\n", "import '../../../core/formatting/arabic_amount_words.dart';\nimport '../../../core/network/api_error_message.dart';\n", 'format import')
    s = rep(s, "import '../domain/property_location_address.dart';\nimport 'property_location_picker_screen.dart';\n", "import '../domain/property_location_address.dart';\nimport '../domain/property_sai.dart';\nimport 'property_location_picker_screen.dart';\nimport 'property_sai_configuration_sheet.dart';\n", 'sai imports')
    s = rep(s, "  String? _ownershipProofPath;\n\n  PropertyDetails? get _existing => widget.existingProperty;\n  bool get _isEditing => _existing != null;\n", "  String? _ownershipProofPath;\n  PropertyDetails? _workingDraft;\n  PropertySaiEnvelope? _saiEnvelope;\n  bool _saiBusy = false;\n\n  PropertyDetails? get _existing => _workingDraft ?? widget.existingProperty;\n  bool get _startedAsEditing => widget.existingProperty != null;\n  bool get _isEditing => _existing != null;\n  bool get _isSaiReady {\n    final management = _saiEnvelope?.management;\n    if (management == null || !management.configured) return false;\n    if (!management.isProfessional) return true;\n    final requested = management.requestedBrokerRatePercent ?? 0;\n    return requested <= 0 || management.platformTermsStatus == 'accepted';\n  }\n\n  String get _saiDisplayText =>\n      _saiEnvelope?.sai?.displayText ??\n      _saiEnvelope?.management?.publicDisplayText ??\n      (_isSaiReady ? 'تم تحديد السعي' : 'لم يتم تحديد السعي بعد');\n", 'state')
    s = rep(s, "  void initState() {\n    super.initState();\n    final property = _existing;\n", "  void initState() {\n    super.initState();\n    _price.addListener(_onPriceChanged);\n    final property = _existing;\n", 'price listener')
    s = rep(s, "    _relationshipNote.text = property.ownerRelationshipNote ?? '';\n  }\n\n  @override\n  void dispose() {\n", "    _relationshipNote.text = property.ownerRelationshipNote ?? '';\n    unawaited(_refreshSai(property.id));\n  }\n\n  @override\n  void dispose() {\n    _price.removeListener(_onPriceChanged);\n", 'load sai dispose')
    s = rep(s, "                label: 'موقعي الحالي',\n                icon: Icons.my_location,\n                style: AppButtonStyle.tonal,\n", "                label: 'تحديد موقعي الحالي',\n                icon: Icons.my_location,\n", 'location button')
    s = rep(s, "                label: 'المساحة *',\n", "                label: 'عدد اللبن *',\n", 'area label')
    old_price = """  Widget _priceStep() {\n    return Column(\n      crossAxisAlignment: CrossAxisAlignment.start,\n      children: [\n"""
    new_price = """  Widget _priceStep() {\n    final amountWords = arabicYemeniRialAmountWords(_price.text);\n    return Column(\n      crossAxisAlignment: CrossAxisAlignment.start,\n      children: [\n"""
    s = rep(s, old_price, new_price, 'price step start')
    s = rep(s, """        AppTextField(\n          controller: _price,\n          label: 'السعر بالريال اليمني *',\n          keyboardType: const TextInputType.numberWithOptions(decimal: true),\n          enabled: !_busy,\n        ),\n        const SizedBox(height: AppSpacing.s12),\n""", """        AppTextField(\n          controller: _price,\n          label: 'السعر بالريال اليمني *',\n          keyboardType: const TextInputType.numberWithOptions(decimal: true),\n          enabled: !_busy,\n        ),\n        if (amountWords.isNotEmpty) ...[\n          const SizedBox(height: AppSpacing.s8),\n          AppInlineMessage(\n            title: 'المبلغ بالحروف',\n            message: amountWords,\n            tone: AppStatusTone.info,\n          ),\n        ],\n        const SizedBox(height: AppSpacing.s12),\n""", 'price words')
    s = rep(s, """        const SizedBox(height: AppSpacing.s20),\n        const AppSectionHeader(title: 'ملخص الإعلان'),\n""", """        const SizedBox(height: AppSpacing.s20),\n        const AppSectionHeader(\n          title: 'السعي',\n          subtitle: 'حدد السعي والطرف الذي يتحمله قبل إرسال الإعلان للمراجعة.',\n        ),\n        const SizedBox(height: AppSpacing.s8),\n        _saiConfigurationCard(),\n        const SizedBox(height: AppSpacing.s20),\n        const AppSectionHeader(title: 'ملخص الإعلان'),\n""", 'sai section')
    s = rep(s, """              _SummaryRow(label: 'الموقع', value: _composedAddress),\n              _SummaryRow(label: 'المساحة', value: '${_area.text.trim()} ${propertyAreaUnitLabel(_areaUnit)}'),\n""", """              _SummaryRow(label: 'الموقع', value: _composedAddress),\n              _SummaryRow(label: 'عدد اللبن', value: '${_area.text.trim()} ${propertyAreaUnitLabel(_areaUnit)}'),\n              _SummaryRow(label: 'السعي', value: _saiDisplayText),\n""", 'summary')
    marker = "\n  Widget _actions() {\n"
    method = r'''
  Widget _saiConfigurationCard() {
    final scheme = Theme.of(context).colorScheme;
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isSaiReady ? Icons.check_circle_rounded : Icons.payments_outlined,
                color: _isSaiReady ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text(
                  _saiDisplayText,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            _isSaiReady
                ? 'يمكنك تعديل اختيار السعي قبل الإرسال إذا احتجت.'
                : 'لن يتم إرسال الإعلان للمراجعة حتى يتم تحديد السعي المطلوب.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppSpacing.s12),
          AppButton(
            label: _isSaiReady ? 'تعديل السعي' : 'تحديد السعي',
            icon: Icons.payments_outlined,
            loading: _saiBusy,
            onPressed: _busy || _saiBusy ? null : _configureSai,
            expand: true,
          ),
        ],
      ),
    );
  }
'''
    if marker not in s: raise SystemExit('actions marker')
    s = s.replace(marker, method + marker, 1)
    pattern = re.compile(r"    return _BottomBar\(\n      children: \[\n        Expanded\(\n          child: AppButton\(\n            label: 'السابق',[\s\S]*?      \],\n    \);\n  \}\n\n  void _next\(\)", re.M)
    replacement = """    return _FinalActionsBar(\n      busy: _busy,\n      onPrevious: () => setState(() => _step--),\n      onPreview: _preview,\n      onSaveDraft: () => _persist(submit: false),\n      onSubmit: () => _persist(submit: true),\n    );\n  }\n\n  void _next()"""
    s, count = pattern.subn(replacement, s, count=1)
    if count != 1: raise SystemExit(f'final actions replacement count {count}')
    s = rep(s, "if (areaValue == null || areaValue <= 0) return 'أدخل مساحة صحيحة للعقار.';", "if (areaValue == null || areaValue <= 0) return 'أدخل عدداً صحيحاً للبن.';", 'area validation')
    s = rep(s, """    final core = _validateCore();\n    if (core != null) return core;\n\n    final existingImages""", """    final core = _validateCore();\n    if (core != null) return core;\n    if (!_isSaiReady) return 'حدد السعي والطرف الذي يتحمله قبل إرسال الإعلان للمراجعة.';\n\n    final existingImages""", 'sai validate')
    s = rep(s, """      ref.read(propertyDataRevisionProvider.notifier).state++;\n      await _clearUploadedTemporaryFiles();\n\n      if (submit) {\n""", """      if (mounted) setState(() => _workingDraft = draft);\n      ref.read(propertyDataRevisionProvider.notifier).state++;\n      await _clearUploadedTemporaryFiles();\n\n      if (submit) {\n""", 'working draft after save')
    s = rep(s, """          if (mounted) {\n            _message('تم حفظ الإعلان كمسودة، لكن تعذر إرساله للمراجعة: ${friendlyApiError(error)}');\n            await Future<void>.delayed(const Duration(milliseconds: 900));\n            if (mounted) _finish(draft);\n          }\n          return;\n""", """          if (mounted) {\n            final message = friendlyApiError(error);\n            _message('تم حفظ الإعلان كمسودة، لكن تعذر إرساله للمراجعة: $message');\n            if (message.contains('السعي')) {\n              await _refreshSai(draft.id);\n            }\n          }\n          return;\n""", 'submit failure stay')
    s = rep(s, """  void _finish(PropertyDetails property) {\n    if (_isEditing) {\n""", """  void _finish(PropertyDetails property) {\n    if (_startedAsEditing) {\n""", 'finish origin')
    s = rep(s, """                _SummaryRow(label: 'المساحة', value: '${_area.text.trim()} ${propertyAreaUnitLabel(_areaUnit)}'),\n                _SummaryRow(label: 'الموقع', value: _composedAddress),\n""", """                _SummaryRow(label: 'عدد اللبن', value: '${_area.text.trim()} ${propertyAreaUnitLabel(_areaUnit)}'),\n                _SummaryRow(label: 'السعي', value: _saiDisplayText),\n                _SummaryRow(label: 'الموقع', value: _composedAddress),\n""", 'preview summary')
    insert_before = """  Future<void> _pickImages() async {\n"""
    extra = r'''  void _onPriceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshSai(int propertyId) async {
    try {
      final envelope = await ref.read(propertyRepositoryProvider).sai(propertyId);
      if (mounted) setState(() => _saiEnvelope = envelope);
    } catch (_) {
      // Sai configuration remains explicitly available in the final step.
    }
  }

  Future<PropertyDetails?> _ensureDraftForSai() async {
    final validation = _validateCore();
    if (validation != null) {
      _message(validation);
      return null;
    }
    final repository = ref.read(propertyRepositoryProvider);
    final current = _existing;
    final draft = current == null
        ? await repository.createListing(
            _input(),
            imagePaths: _imagePaths,
            submitForReview: false,
            ownershipProofPath: _ownershipProofPath,
          )
        : await repository.updateListing(
            current.id,
            _input(),
            imagePaths: _imagePaths,
            replaceImages: _replaceImages,
            submitForReview: false,
            ownershipProofPath: _ownershipProofPath,
          );
    if (mounted) setState(() => _workingDraft = draft);
    ref.read(propertyDataRevisionProvider.notifier).state++;
    await _clearUploadedTemporaryFiles();
    return draft;
  }

  Future<void> _configureSai() async {
    setState(() => _saiBusy = true);
    try {
      final draft = await _ensureDraftForSai();
      if (draft == null || !mounted) return;
      final repository = ref.read(propertyRepositoryProvider);
      final ready = await showPropertySaiConfigurationSheet(
        context,
        repository: repository,
        propertyId: draft.id,
        purpose: _purpose,
      );
      if (!mounted) return;
      await _refreshSai(draft.id);
      if (!ready && mounted) {
        _message('لم يتم تأكيد السعي. أكمل بيانات السعي قبل إرسال الإعلان للمراجعة.');
      }
    } catch (error) {
      if (mounted) _message(friendlyApiError(error));
    } finally {
      if (mounted) setState(() => _saiBusy = false);
    }
  }

'''
    s = rep(s, insert_before, extra + insert_before, 'sai methods')
    return s

edit('mobile_app/lib/features/properties/presentation/listing_editor_screen.dart', listing)


def add_final_bar(s):
    marker = "class _SummaryRow extends StatelessWidget {"
    widget = r'''class _FinalActionsBar extends StatelessWidget {
  const _FinalActionsBar({
    required this.busy,
    required this.onPrevious,
    required this.onPreview,
    required this.onSaveDraft,
    required this.onSubmit,
  });

  final bool busy;
  final VoidCallback onPrevious;
  final VoidCallback onPreview;
  final VoidCallback onSaveDraft;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: AppElevation.floating,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppLayout.compactPageGutter,
            AppSpacing.s8,
            AppLayout.compactPageGutter,
            AppSpacing.s12,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 390;
              final secondary = <Widget>[
                Expanded(
                  child: AppButton(
                    label: 'معاينة',
                    icon: Icons.visibility_outlined,
                    style: AppButtonStyle.outlined,
                    onPressed: busy ? null : onPreview,
                    expand: true,
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: AppButton(
                    label: 'حفظ مسودة',
                    icon: Icons.save_outlined,
                    style: AppButtonStyle.tonal,
                    loading: busy,
                    onPressed: busy ? null : onSaveDraft,
                    expand: true,
                  ),
                ),
              ];
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppButton(
                    label: 'إرسال للمراجعة',
                    icon: Icons.send_outlined,
                    loading: busy,
                    onPressed: busy ? null : onSubmit,
                    expand: true,
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  if (compact) ...[
                    AppButton(
                      label: 'حفظ مسودة',
                      icon: Icons.save_outlined,
                      style: AppButtonStyle.tonal,
                      loading: busy,
                      onPressed: busy ? null : onSaveDraft,
                      expand: true,
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    AppButton(
                      label: 'معاينة',
                      icon: Icons.visibility_outlined,
                      style: AppButtonStyle.outlined,
                      onPressed: busy ? null : onPreview,
                      expand: true,
                    ),
                  ] else
                    Row(children: secondary),
                  AppButton(
                    label: 'السابق',
                    style: AppButtonStyle.text,
                    onPressed: busy ? null : onPrevious,
                    expand: true,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

'''
    return rep(s, marker, widget + marker, 'final bar class')

edit('mobile_app/lib/features/properties/presentation/listing_editor_screen.dart', add_final_bar)


def bookings(s):
    return rep(s, 'FilledButton.tonalIcon(\n                        onPressed: () => onAction(\'confirm\')', 'FilledButton.icon(\n                        onPressed: () => onAction(\'confirm\')', 'confirm primary')
edit('mobile_app/lib/features/bookings/presentation/bookings_screen.dart', bookings)


def favorites(s):
    s = rep(s, 'class FavoritesScreen extends ConsumerStatefulWidget {\n  const FavoritesScreen({super.key});\n', "class FavoritesScreen extends ConsumerStatefulWidget {\n  const FavoritesScreen({super.key, this.startInCompareMode = false});\n\n  final bool startInCompareMode;\n", 'favorites ctor')
    s = rep(s, '  bool _compareMode = false;\n\n  @override\n  Widget build', "  late bool _compareMode;\n\n  @override\n  void initState() {\n    super.initState();\n    _compareMode = widget.startInCompareMode;\n  }\n\n  @override\n  Widget build", 'favorites init')
    return s
edit('mobile_app/lib/features/properties/presentation/favorites_screen.dart', favorites)


def router(s):
    s = rep(s, "import '../features/messages/presentation/notifications_screen.dart';\n", "import '../features/messages/presentation/notifications_screen.dart';\nimport '../features/map/presentation/map_screen.dart';\n", 'map import')
    s = rep(s, "import '../features/properties/presentation/add_property_wizard_screen.dart';\n", "import '../features/properties/presentation/add_property_wizard_screen.dart';\nimport '../features/properties/presentation/favorites_screen.dart';\n", 'favorites import')
    target = """      GoRoute(\n        path: '/my-listings',\n        builder: (context, state) => const Stage6AuthGate(\n          child: MyListingsScreen(),\n        ),\n      ),\n"""
    addition = target + """      GoRoute(\n        path: '/favorites',\n        builder: (context, state) => Stage6AuthGate(\n          child: FavoritesScreen(\n            startInCompareMode: state.uri.queryParameters['compare'] == '1',\n          ),\n        ),\n      ),\n      GoRoute(\n        path: '/property-market',\n        builder: (context, state) => const MapScreen(),\n      ),\n"""
    return rep(s, target, addition, 'routes')
edit('mobile_app/lib/router/app_router.dart', router)


def services(s):
    s = rep(s, "onTap: () => context.go('/'),", "onTap: () => context.push('/property-market'),", 'market route')
    s = rep(s, "onTap: () => context.push('/favorites'),", "onTap: () => context.push('/favorites?compare=1'),", 'compare route')
    return s
edit('mobile_app/lib/features/services/presentation/services_screen.dart', services)


def repository(s):
    return rep(s, "queryParameters: {'page': page, 'per_page': 50},", "queryParameters: {'page': page, 'per_page': 50, 'view': 'workspace'},", 'workspace query')
edit('mobile_app/lib/features/properties/data/property_repository.dart', repository)


def controller(s):
    old = """        $page = Property::query()\n            ->with('images')\n            ->where('user_id', $user->id)\n            ->latest('id')\n            ->paginate($perPage);\n\n        return response()->json([\n            'data' => collect($page->items())\n                ->map(fn (Property $property) => $this->detailData($property, $request))\n                ->values(),\n"""
    new = """        $workspaceView = $request->input('view') === 'workspace';\n        $page = Property::query()\n            ->with($workspaceView ? ['images', 'documents'] : ['images'])\n            ->where('user_id', $user->id)\n            ->latest('id')\n            ->paginate($perPage);\n\n        return response()->json([\n            'data' => collect($page->items())\n                ->map(fn (Property $property) => $workspaceView\n                    ? $this->mineWorkspaceData($property, $request)\n                    : $this->detailData($property, $request))\n                ->values(),\n"""
    s = rep(s, old, new, 'mine workspace')
    marker = """    private function detailData(Property $property, Request $request): array\n"""
    helper = r'''    private function mineWorkspaceData(Property $property, Request $request): array
    {
        $property->loadMissing(['images', 'documents']);
        return array_merge($this->summaryData($property, $request), [
            'description' => $property->description,
            'contact_phone' => $property->contact_phone,
            'contact_whatsapp' => $property->contact_whatsapp,
            'review_status' => $property->review_status,
            'geo_cell_id' => $property->geo_cell_id,
            'property_asset_id' => $property->property_asset_id,
            'last_review_reason' => $property->last_review_reason,
            'proof_document_count' => $property->documents->count(),
            'can_submit' => in_array($property->review_status, ['draft', 'returned_for_correction'], true),
            'can_edit' => ! in_array($property->review_status, ['submitted', 'under_review', 'rejected_blocked'], true),
            'is_owner' => true,
            'ownership_document_type' => $property->ownership_document_type,
            'document_owner_name' => $property->document_owner_name,
            'owner_relationship_type' => $property->owner_relationship_type,
            'owner_relationship_note' => $property->owner_relationship_note,
            'ownership_proof_present' => $property->documents->contains(
                fn (ListingDocument $document) => $document->kind === 'ownership_proof'
            ),
            'images' => $property->images
                ->map(fn (PropertyImage $image) => [
                    'id' => $image->id,
                    'url' => $this->imageUrl($image, $request),
                    'is_primary' => (bool) $image->is_primary,
                    'sort_order' => (int) $image->sort_order,
                ])
                ->values(),
        ]);
    }

'''
    return rep(s, marker, helper + marker, 'mine helper')
edit('backend-api-runtime/app/Http/Controllers/Api/PropertyController.php', controller)

# Add a focused formatter test.
test = ROOT / 'mobile_app/test/arabic_amount_words_test.dart'
test.write_text("""import 'package:flutter_test/flutter_test.dart';\n\nimport 'package:real_estate_app/core/formatting/arabic_amount_words.dart';\n\nvoid main() {\n  test('writes Yemeni rial price in Arabic words', () {\n    expect(arabicYemeniRialAmountWords('1250000'), contains('مليون'));\n    expect(arabicYemeniRialAmountWords('1250000'), endsWith('ريال يمني'));\n    expect(arabicYemeniRialAmountWords('٠'), isEmpty);\n  });\n}\n""")

# Update accepted mobile baseline hashes in the UAT workflow after modifying guarded files.
workflow = ROOT / '.github/workflows/build-uat-apk.yml'
w = workflow.read_text()
import subprocess
for rel in [
    'mobile_app/lib/core/network/api_client.dart',
    'mobile_app/lib/router/app_router.dart',
    'mobile_app/lib/features/services/presentation/services_screen.dart',
]:
    new_hash = subprocess.check_output(['git', 'hash-object', rel], cwd=ROOT, text=True).strip()
    pattern = re.compile(r'(check_hash "' + re.escape(rel) + r'" \\\n\s+")([0-9a-f]+)(")')
    w, count = pattern.subn(lambda m: m.group(1) + new_hash + m.group(3), w, count=1)
    if count != 1:
        raise SystemExit(f'Could not update baseline hash for {rel}')
workflow.write_text(w)

print('Advertiser listing fixes patched successfully')

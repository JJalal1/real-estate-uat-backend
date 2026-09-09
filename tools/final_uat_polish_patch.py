from pathlib import Path


def replace_once(path_str, old, new):
    path = Path(path_str)
    source = path.read_text()
    if new in source:
        return
    if old not in source:
        raise AssertionError(f"Expected patch marker not found in {path_str}: {old[:120]!r}")
    path.write_text(source.replace(old, new, 1))


def replace_between(path_str, start, end, replacement):
    path = Path(path_str)
    source = path.read_text()
    start_i = source.find(start)
    end_i = source.find(end, start_i)
    if start_i < 0 or end_i < 0:
        raise AssertionError(f"Block markers missing in {path_str}: {start!r} -> {end!r}")
    path.write_text(source[:start_i] + replacement + "\n\n" + source[end_i:])


# Property gallery: full-screen, swipe and zoom using only real uploaded images.
details_path = 'mobile_app/lib/features/properties/presentation/property_details_screen.dart'
gallery_block = r'''class _Gallery extends StatelessWidget {
  const _Gallery({
    required this.images,
    required this.index,
    required this.onChanged,
  });

  final List<PropertyImageItem> images;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (images.isEmpty)
              const AppPropertyMedia(height: double.infinity)
            else
              PageView.builder(
                itemCount: images.length,
                onPageChanged: onChanged,
                itemBuilder: (context, imageIndex) => Semantics(
                  button: true,
                  label: 'فتح صورة العقار ${imageIndex + 1} من ${images.length}',
                  child: InkWell(
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => _FullscreenGallery(
                          images: images,
                          initialIndex: imageIndex,
                        ),
                      ),
                    ),
                    child: AppPropertyMedia(
                      imageUrl: images[imageIndex].url,
                      height: double.infinity,
                    ),
                  ),
                ),
              ),
            if (images.isNotEmpty)
              PositionedDirectional(
                top: AppSpacing.s12,
                end: AppSpacing.s12,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: AppSpacing.s10,
                      vertical: AppSpacing.s6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .58),
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fullscreen_rounded, color: Colors.white, size: 18),
                        SizedBox(width: AppSpacing.s4),
                        Text(
                          'تكبير الصور',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (images.isNotEmpty)
              PositionedDirectional(
                bottom: AppSpacing.s12,
                end: AppSpacing.s12,
                child: Container(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: AppSpacing.s12,
                    vertical: AppSpacing.s4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .inverseSurface
                        .withValues(alpha: .86),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    '${index + 1}/${images.length}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onInverseSurface,
                        ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FullscreenGallery extends StatefulWidget {
  const _FullscreenGallery({required this.images, required this.initialIndex});

  final List<PropertyImageItem> images;
  final int initialIndex;

  @override
  State<_FullscreenGallery> createState() => _FullscreenGalleryState();
}

class _FullscreenGalleryState extends State<_FullscreenGallery> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: widget.images.length,
                onPageChanged: (value) => setState(() => _index = value),
                itemBuilder: (context, imageIndex) => Center(
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Image.network(
                      widget.images[imageIndex].url,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 52),
                      ),
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const Center(child: CircularProgressIndicator());
                      },
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                top: AppSpacing.s8,
                start: AppSpacing.s8,
                child: IconButton.filled(
                  tooltip: 'إغلاق الصور',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
              PositionedDirectional(
                bottom: AppSpacing.s16,
                start: 0,
                end: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .58),
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    child: Text(
                      '${_index + 1}/${widget.images.length} • اسحب للتنقل واضغط بإصبعين للتكبير',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}'''
replace_between(details_path, 'class _Gallery extends StatelessWidget {', 'class _AdvertiserCard extends StatelessWidget {', gallery_block)

advertiser_block = r'''class _AdvertiserCard extends StatelessWidget {
  const _AdvertiserCard({
    required this.property,
    required this.onCommunity,
  });

  final PropertyDetails property;
  final VoidCallback onCommunity;

  @override
  Widget build(BuildContext context) {
    final advertiser = property.advertiser!;
    final verified = advertiser.verificationStatus == 'approved';
    final signals = <_AdvertiserTrustSignal>[
      if (advertiser.verificationFlag('identity_reviewed'))
        const _AdvertiserTrustSignal(Icons.badge_outlined, 'هوية المعلن متحققة'),
      if (advertiser.verificationFlag('relationship_document_reviewed'))
        const _AdvertiserTrustSignal(Icons.home_work_outlined, 'علاقة المالك بالعقار متحققة'),
      if (advertiser.verificationFlag('professional_document_reviewed'))
        const _AdvertiserTrustSignal(Icons.workspace_premium_outlined, 'بيانات مهنية متحققة'),
      if (advertiser.verificationFlag('commercial_register_reviewed'))
        const _AdvertiserTrustSignal(Icons.business_outlined, 'السجل التجاري متحقق'),
      if (advertiser.verificationFlag('office_documents_reviewed'))
        const _AdvertiserTrustSignal(Icons.domain_verification_outlined, 'بيانات المكتب متحققة'),
      if (advertiser.verificationFlag('office_location_registered'))
        const _AdvertiserTrustSignal(Icons.location_on_outlined, 'موقع المكتب مسجل'),
    ];

    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                child: Icon(
                  verified ? Icons.verified_user_outlined : Icons.person_outline,
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      advertiser.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      verified ? advertiser.verificationLabel : 'معلن غير موثق',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              AppStatusBadge(
                label: verified ? 'موثق' : 'غير موثق',
                tone: verified ? AppStatusTone.success : AppStatusTone.warning,
                icon: verified ? Icons.verified_outlined : Icons.info_outline,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(
            verified
                ? 'تم التحقق من صفة المعلن داخل المنصة. إشارات الثقة أدناه مبنية على بيانات تحقق فعلية وليست شارات دعائية.'
                : 'لم يكتمل توثيق هذا المعلن داخل المنصة. استخدم المراسلة والمعاينة داخل التطبيق قبل اتخاذ أي قرار.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          if (signals.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s12),
            Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              children: signals
                  .map(
                    (signal) => Chip(
                      avatar: Icon(signal.icon, size: 18),
                      label: Text(signal.label),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: AppSpacing.s12),
          Row(
            children: [
              Expanded(
                child: Text(
                  advertiser.ratingCount == 0
                      ? 'لا توجد تقييمات للمعلن بعد'
                      : 'التقييم ${advertiser.ratingAverage.toStringAsFixed(1)} من 5 (${advertiser.ratingCount})',
                ),
              ),
              Text('${property.commentsCount} تعليق ظاهر'),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          AppButton(
            label: 'التعليقات والتقييم والبلاغات',
            icon: Icons.rate_review_outlined,
            style: AppButtonStyle.tonal,
            onPressed: onCommunity,
            expand: true,
          ),
        ],
      ),
    );
  }
}

class _AdvertiserTrustSignal {
  const _AdvertiserTrustSignal(this.icon, this.label);
  final IconData icon;
  final String label;
}'''
replace_between(details_path, 'class _AdvertiserCard extends StatelessWidget {', 'class _PropertyPrimaryActions extends StatelessWidget {', advertiser_block)

# Professional workspace: make real actions the first thing professionals see.
workspace_path = 'mobile_app/lib/features/services/presentation/professional_workspace_screen.dart'
replace_once(
    workspace_path,
    "  Widget build(BuildContext context) {\n    return ListView(",
    """  Widget build(BuildContext context) {
    final priorities = <_WorkspacePriority>[
      if (data.unreadConversations > 0)
        _WorkspacePriority(
          icon: Icons.mark_chat_unread_outlined,
          title: 'رد على ${data.unreadConversations} محادثات غير مقروءة',
          subtitle: 'العميل ينتظر ردك؛ افتح صندوق الرسائل وابدأ بالأحدث.',
          route: '/messages',
          tone: AppStatusTone.warning,
        ),
      if (data.corrections.isNotEmpty)
        _WorkspacePriority(
          icon: Icons.edit_note_outlined,
          title: 'صحح ${data.corrections.length} إعلانات معادة للتعديل',
          subtitle: 'راجع سبب الإعادة وعدّل نفس الإعلان قبل إعادة الإرسال.',
          route: '/my-listings',
          tone: AppStatusTone.warning,
        ),
      if (data.activeViewings > 0)
        _WorkspacePriority(
          icon: Icons.event_available_outlined,
          title: 'تابع ${data.activeViewings} معاينات نشطة',
          subtitle: 'راجع الموعد والحالة والطرف الآخر قبل الانتقال للخطوة التالية.',
          route: '/bookings',
          tone: AppStatusTone.info,
        ),
      if (data.activeAgreements > 0)
        _WorkspacePriority(
          icon: Icons.handshake_outlined,
          title: 'راجع ${data.activeAgreements} اتفاقات نشطة',
          subtitle: 'تأكد من آخر revision وحالة القبول قبل أي متابعة.',
          route: '/agreements',
          tone: AppStatusTone.info,
        ),
      if (data.staleListings.isNotEmpty)
        _WorkspacePriority(
          icon: Icons.update_rounded,
          title: 'راجع ${data.staleListings.length} إعلانات قديمة',
          subtitle: 'أكد التوفر وحدّث المعلومات حتى تبقى الإعلانات دقيقة.',
          route: '/my-listings',
          tone: AppStatusTone.info,
        ),
    ];

    return ListView(""",
)
replace_once(
    workspace_path,
    """        const SizedBox(height: AppSpacing.s24),
        const AppSectionHeader(title: 'نشاط العملاء'),""",
    """        const SizedBox(height: AppSpacing.s24),
        AppSectionHeader(
          title: 'يحتاج إجراء الآن',
          subtitle: priorities.isEmpty
              ? 'لا توجد عناصر عاجلة حالياً. استمر في متابعة نشاط العملاء.'
              : 'مرتبة من بياناتك الفعلية؛ ابدأ بالأعلى ثم انتقل لما بعده.',
        ),
        const SizedBox(height: AppSpacing.s8),
        if (priorities.isEmpty)
          const AppSurface(
            child: AppListRow(
              title: 'أنت متابع كل شيء',
              subtitle: 'لا توجد محادثات غير مقروءة أو إعلانات تحتاج تصحيحاً الآن.',
              leading: Icon(Icons.task_alt_rounded),
            ),
          )
        else
          AppSurface(
            padding: EdgeInsets.zero,
            child: Column(
              children: priorities
                  .map(
                    (item) => AppListRow(
                      title: item.title,
                      subtitle: item.subtitle,
                      leading: Icon(item.icon),
                      trailing: AppStatusBadge(label: 'إجراء', tone: item.tone),
                      onTap: () => context.push(item.route),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        const SizedBox(height: AppSpacing.s24),
        const AppSectionHeader(title: 'ملخص نشاط العملاء'),""",
)
replace_once(
    workspace_path,
    'class _Metric extends StatelessWidget {',
    """class _WorkspacePriority {
  const _WorkspacePriority({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
  final AppStatusTone tone;
}

class _Metric extends StatelessWidget {""",
)

# Persistent local discovery history without adding a dependency.
history_path = Path('mobile_app/lib/features/map/data/property_discovery_history_store.dart')
history_path.parent.mkdir(parents=True, exist_ok=True)
history_path.write_text(r'''import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class PropertyDiscoveryHistory {
  const PropertyDiscoveryHistory({
    this.recentSearches = const <String>[],
    this.lastFilters = const <String, dynamic>{},
  });

  final List<String> recentSearches;
  final Map<String, dynamic> lastFilters;
}

class PropertyDiscoveryHistoryStore {
  const PropertyDiscoveryHistoryStore();

  static const _fileName = 'property_discovery_history_v1.json';
  static const _maxRecent = 5;

  Future<PropertyDiscoveryHistory> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const PropertyDiscoveryHistory();
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return const PropertyDiscoveryHistory();
      final recentRaw = raw['recent_searches'];
      final filtersRaw = raw['last_filters'];
      final recent = recentRaw is List
          ? recentRaw
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .take(_maxRecent)
              .toList(growable: false)
          : const <String>[];
      final filters = filtersRaw is Map
          ? Map<String, dynamic>.from(filtersRaw)
          : const <String, dynamic>{};
      return PropertyDiscoveryHistory(
        recentSearches: recent,
        lastFilters: filters,
      );
    } catch (_) {
      return const PropertyDiscoveryHistory();
    }
  }

  Future<void> record({
    required String query,
    required Map<String, dynamic> filters,
  }) async {
    try {
      final current = await load();
      final normalized = query.trim();
      final recent = <String>[
        if (normalized.isNotEmpty) normalized,
        ...current.recentSearches.where(
          (value) => value.toLowerCase() != normalized.toLowerCase(),
        ),
      ].take(_maxRecent).toList(growable: false);
      final file = await _file();
      await file.writeAsString(
        jsonEncode(<String, dynamic>{
          'recent_searches': recent,
          'last_filters': filters,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }),
        flush: true,
      );
    } catch (_) {
      // Discovery history is a convenience only; never block search on local I/O.
    }
  }

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/$_fileName');
  }
}
''')

map_path = 'mobile_app/lib/features/map/presentation/map_screen.dart'
replace_once(
    map_path,
    "import '../domain/map_screen_coordinate_space.dart';\n",
    "import '../domain/map_screen_coordinate_space.dart';\nimport '../data/property_discovery_history_store.dart';\n",
)
replace_once(
    map_path,
    """  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';
""",
    """  final TextEditingController _searchController = TextEditingController();
  final PropertyDiscoveryHistoryStore _historyStore = const PropertyDiscoveryHistoryStore();
  String _searchText = '';
  List<String> _recentSearches = const <String>[];
""",
)
replace_once(
    map_path,
    """  void initState() {
    super.initState();
    _loadCurrentLocation();
  }
""",
    """  void initState() {
    super.initState();
    unawaited(_restoreDiscoveryHistory());
    _loadCurrentLocation();
  }
""",
)
replace_once(
    map_path,
    """  @override
  void dispose() {
    _styleLoadTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }
""",
    """  @override
  void dispose() {
    _styleLoadTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _restoreDiscoveryHistory() async {
    final history = await _historyStore.load();
    if (!mounted) return;
    final filters = history.lastFilters;
    final search = filters['search']?.toString().trim() ?? '';
    setState(() {
      _recentSearches = history.recentSearches;
      _filterPurpose = _historyString(filters['purpose']);
      _filterType = _historyString(filters['type']);
      _filterMinPrice = _historyDouble(filters['min_price']);
      _filterMaxPrice = _historyDouble(filters['max_price']);
      _filterMinBedrooms = _historyInt(filters['min_bedrooms']);
      _filterMinBathrooms = _historyInt(filters['min_bathrooms']);
      _filterMinArea = _historyDouble(filters['min_area_m2']);
      _filterMaxArea = _historyDouble(filters['max_area_m2']);
      _searchText = search;
      _searchController.text = search;
    });
  }

  String? _historyString(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  double? _historyDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  int? _historyInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Map<String, dynamic> _discoveryHistorySnapshot() => <String, dynamic>{
        if (_filterPurpose != null) 'purpose': _filterPurpose,
        if (_filterType != null) 'type': _filterType,
        if (_filterMinPrice != null) 'min_price': _filterMinPrice,
        if (_filterMaxPrice != null) 'max_price': _filterMaxPrice,
        if (_filterMinBedrooms != null) 'min_bedrooms': _filterMinBedrooms,
        if (_filterMinBathrooms != null) 'min_bathrooms': _filterMinBathrooms,
        if (_filterMinArea != null) 'min_area_m2': _filterMinArea,
        if (_filterMaxArea != null) 'max_area_m2': _filterMaxArea,
        if (_searchText.trim().isNotEmpty) 'search': _searchText.trim(),
      };

  void _persistDiscoveryHistory() {
    unawaited(
      _historyStore.record(
        query: _searchText,
        filters: _discoveryHistorySnapshot(),
      ),
    );
  }
""",
)
replace_once(
    map_path,
    """  void _setQuickPurpose(String? purpose) {
    setState(() {
      _filterPurpose = _filterPurpose == purpose ? null : purpose;
      _selected = null;
      _lastMarkerSignature = '';
    });
  }
""",
    """  void _setQuickPurpose(String? purpose) {
    setState(() {
      _filterPurpose = _filterPurpose == purpose ? null : purpose;
      _selected = null;
      _lastMarkerSignature = '';
    });
    _persistDiscoveryHistory();
  }
""",
)
replace_once(
    map_path,
    """  void _setQuickType(String? type) {
    setState(() {
      _filterType = _filterType == type ? null : type;
      if (!_typeUsesRooms(_filterType)) {
        _filterMinBedrooms = null;
        _filterMinBathrooms = null;
      }
      _selected = null;
      _lastMarkerSignature = '';
    });
  }
""",
    """  void _setQuickType(String? type) {
    setState(() {
      _filterType = _filterType == type ? null : type;
      if (!_typeUsesRooms(_filterType)) {
        _filterMinBedrooms = null;
        _filterMinBathrooms = null;
      }
      _selected = null;
      _lastMarkerSignature = '';
    });
    _persistDiscoveryHistory();
  }
""",
)
replace_once(
    map_path,
    """  void _resetFilters() {
    setState(() {
      _filterPurpose = null;
      _filterType = null;
      _filterMinPrice = null;
      _filterMaxPrice = null;
      _filterMinBedrooms = null;
      _filterMinBathrooms = null;
      _filterMinArea = null;
      _filterMaxArea = null;
      _selected = null;
      _lastMarkerSignature = '';
    });
  }
""",
    """  void _resetFilters() {
    setState(() {
      _filterPurpose = null;
      _filterType = null;
      _filterMinPrice = null;
      _filterMaxPrice = null;
      _filterMinBedrooms = null;
      _filterMinBathrooms = null;
      _filterMinArea = null;
      _filterMaxArea = null;
      _selected = null;
      _lastMarkerSignature = '';
    });
    _persistDiscoveryHistory();
  }
""",
)
replace_once(
    map_path,
    """      _selected = null;
      _lastMarkerSignature = '';
    });
  }

  Future<void> _showSearchSheet(List<PropertyMarker> items) async {""",
    """      _selected = null;
      _lastMarkerSignature = '';
    });
    _persistDiscoveryHistory();
  }

  Future<void> _showSearchSheet(List<PropertyMarker> items) async {""",
)
replace_once(
    map_path,
    """      builder: (context) => _SearchSheet(
        initialValue: _searchController.text,
        suggestions: _searchSuggestions(items),
      ),
""",
    """      builder: (context) => _SearchSheet(
        initialValue: _searchController.text,
        suggestions: _searchSuggestions(items),
        recentSearches: _recentSearches,
      ),
""",
)
replace_once(
    map_path,
    """    setState(() {
      _searchText = normalized;
      _selected = null;
      _lastMarkerSignature = '';
    });
  }

  List<String> _searchSuggestions""",
    """    setState(() {
      _searchText = normalized;
      if (normalized.isNotEmpty) {
        _recentSearches = <String>[
          normalized,
          ..._recentSearches.where(
            (value) => value.toLowerCase() != normalized.toLowerCase(),
          ),
        ].take(5).toList(growable: false);
      }
      _selected = null;
      _lastMarkerSignature = '';
    });
    _persistDiscoveryHistory();
  }

  List<String> _searchSuggestions""",
)
# Clear-search chip should persist the cleared search too.
replace_once(
    map_path,
    """                          _searchController.clear();
                          setState(() => _searchText = '');
""",
    """                          _searchController.clear();
                          setState(() => _searchText = '');
                          _persistDiscoveryHistory();
""",
)
replace_once(
    map_path,
    """class _SearchSheet extends StatefulWidget {
  const _SearchSheet({required this.initialValue, required this.suggestions});

  final String initialValue;
  final List<String> suggestions;
""",
    """class _SearchSheet extends StatefulWidget {
  const _SearchSheet({
    required this.initialValue,
    required this.suggestions,
    required this.recentSearches,
  });

  final String initialValue;
  final List<String> suggestions;
  final List<String> recentSearches;
""",
)
replace_once(
    map_path,
    """          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 10),
""",
    """          if (query.isEmpty && widget.recentSearches.isNotEmpty) ...[
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'بحثت مؤخراً',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            const SizedBox(height: 7),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: widget.recentSearches
                  .map(
                    (value) => ActionChip(
                      avatar: const Icon(Icons.history_rounded, size: 18),
                      label: Text(value),
                      onPressed: () => Navigator.of(context).pop(value),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 10),
""",
)
# Result count language is decision-oriented rather than inventory wording.
path = Path(map_path)
source = path.read_text().replace("'${items.length} إعلان'", "'${items.length} نتيجة'")
path.write_text(source)

# Mobile-side request timing correlation with backend X-Request-ID.
api_client_path = 'mobile_app/lib/core/network/api_client.dart'
replace_once(
    api_client_path,
    "import 'package:dio/dio.dart';",
    "import 'dart:developer' as developer;\n\nimport 'package:dio/dio.dart';",
)
replace_once(
    api_client_path,
    """  dio.interceptors.add(_NearbyRequestCacheInterceptor());
  return dio;
});
""",
    """  dio.interceptors.add(_NearbyRequestCacheInterceptor());
  dio.interceptors.add(_RequestTimingInterceptor());
  return dio;
});
""",
)
replace_once(
    api_client_path,
    'class _CachedNearbyResponse {',
    r'''class _RequestTimingInterceptor extends Interceptor {
  static const _startedAtKey = '_request_started_at_us';
  static const _slowRequestMs = 1500;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startedAtKey] = DateTime.now().microsecondsSinceEpoch;
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _report(
      response.requestOptions,
      statusCode: response.statusCode,
      requestId: response.headers.value('x-request-id'),
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _report(
      err.requestOptions,
      statusCode: err.response?.statusCode,
      requestId: err.response?.headers.value('x-request-id'),
      failed: true,
    );
    handler.next(err);
  }

  void _report(
    RequestOptions options, {
    int? statusCode,
    String? requestId,
    bool failed = false,
  }) {
    if (!ApiEnvironmentConfig.isUat) return;
    final startedAt = options.extra[_startedAtKey];
    if (startedAt is! int) return;
    final durationMs =
        ((DateTime.now().microsecondsSinceEpoch - startedAt) / 1000).round();
    if (!failed && durationMs < _slowRequestMs && (statusCode ?? 0) < 500) {
      return;
    }
    developer.log(
      'api_request method=${options.method} path=${options.path} '
      'status=${statusCode ?? 0} duration_ms=$durationMs '
      'request_id=${requestId ?? '-'}',
      name: 'real_estate.network',
      level: failed || (statusCode ?? 0) >= 500 ? 1000 : 900,
    );
  }
}

class _CachedNearbyResponse {''',
)

# Laravel request observability. Never log bodies, query values, auth headers or user PII.
middleware = Path('backend-api-runtime/app/Http/Middleware/RequestObservability.php')
middleware.write_text(r'''<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Symfony\Component\HttpFoundation\Response;

class RequestObservability
{
    public function handle(Request $request, Closure $next): Response
    {
        $startedAt = hrtime(true);
        $requestId = (string) Str::uuid();
        $request->attributes->set('request_id', $requestId);

        /** @var Response $response */
        $response = $next($request);
        $response->headers->set('X-Request-ID', $requestId);

        if ($request->is('api/health') || $request->is('up')) {
            return $response;
        }

        $durationMs = round((hrtime(true) - $startedAt) / 1_000_000, 1);
        $status = $response->getStatusCode();
        $slowThresholdMs = max(250, (int) env('OBSERVABILITY_SLOW_REQUEST_MS', 1500));

        if ($status >= 500 || $durationMs >= $slowThresholdMs) {
            $context = [
                'request_id' => $requestId,
                'method' => $request->getMethod(),
                'path' => '/'.$request->path(),
                'status' => $status,
                'duration_ms' => $durationMs,
            ];

            if ($status >= 500) {
                Log::error('api_request_failed', $context);
            } else {
                Log::warning('api_request_slow', $context);
            }
        }

        return $response;
    }
}
''')

bootstrap_path = 'backend-api-runtime/bootstrap/app.php'
replace_once(
    bootstrap_path,
    "use App\\Http\\Middleware\\FastRenderHealthProbe;\n",
    "use App\\Http\\Middleware\\FastRenderHealthProbe;\nuse App\\Http\\Middleware\\RequestObservability;\n",
)
replace_once(
    bootstrap_path,
    """        $middleware->prepend(FastRenderHealthProbe::class);
        $middleware->alias([""",
    """        $middleware->prepend(FastRenderHealthProbe::class);
        $middleware->append(RequestObservability::class);
        $middleware->alias([""",
)

# Focused tests/contracts.
Path('backend-api-runtime/tests/Unit/RequestObservabilityTest.php').write_text(r'''<?php

namespace Tests\Unit;

use App\Http\Middleware\RequestObservability;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;
use Tests\TestCase;

class RequestObservabilityTest extends TestCase
{
    public function test_it_adds_a_request_id_without_exposing_request_data(): void
    {
        $request = Request::create('/api/test-observability', 'GET', ['private' => 'do-not-log']);
        $middleware = new RequestObservability();

        $response = $middleware->handle(
            $request,
            fn () => new Response('ok', 200),
        );

        $requestId = $response->headers->get('X-Request-ID');
        $this->assertNotEmpty($requestId);
        $this->assertSame($requestId, $request->attributes->get('request_id'));
    }
}
''')

Path('mobile_app/test/final_uat_polish_contract_test.dart').write_text(r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('property gallery and trust UI expose only real product capabilities', () {
    final source = File(
      'lib/features/properties/presentation/property_details_screen.dart',
    ).readAsStringSync();

    expect(source, contains('_FullscreenGallery'));
    expect(source, contains('InteractiveViewer'));
    expect(source, contains('هوية المعلن متحققة'));
    expect(source, contains("verificationFlag('identity_reviewed')"));
    expect(source, isNot(contains('مشاهدات العقار')));
  });

  test('professional workspace prioritizes real next actions', () {
    final source = File(
      'lib/features/services/presentation/professional_workspace_screen.dart',
    ).readAsStringSync();

    expect(source, contains('يحتاج إجراء الآن'));
    expect(source, contains('unreadConversations'));
    expect(source, contains('activeViewings'));
    expect(source, contains('activeAgreements'));
    expect(source, contains('corrections.length'));
    expect(source, contains('staleListings.length'));
  });

  test('discovery remembers recent searches and reports result count clearly', () {
    final mapSource = File(
      'lib/features/map/presentation/map_screen.dart',
    ).readAsStringSync();
    final historySource = File(
      'lib/features/map/data/property_discovery_history_store.dart',
    ).readAsStringSync();

    expect(mapSource, contains('بحثت مؤخراً'));
    expect(mapSource, contains('_restoreDiscoveryHistory'));
    expect(mapSource, contains("'${items.length} نتيجة'"));
    expect(historySource, contains('property_discovery_history_v1.json'));
    expect(historySource, contains('recent_searches'));
    expect(historySource, contains('last_filters'));
  });

  test('UAT network observability correlates slow calls without request payloads', () {
    final source = File('lib/core/network/api_client.dart').readAsStringSync();
    expect(source, contains('_RequestTimingInterceptor'));
    expect(source, contains('x-request-id'));
    expect(source, contains('duration_ms='));
    expect(source, isNot(contains('queryParameters.toString')));
  });
}
''')

print('Final UAT polish patch applied.')

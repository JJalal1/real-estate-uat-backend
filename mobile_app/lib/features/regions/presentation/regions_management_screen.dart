import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../account/data/auth_controller.dart';
import '../data/region_repository.dart';
import '../domain/region_models.dart';

class RegionsManagementScreen extends ConsumerStatefulWidget {
  const RegionsManagementScreen({super.key});

  @override
  ConsumerState<RegionsManagementScreen> createState() =>
      _RegionsManagementScreenState();
}

class _RegionsManagementScreenState
    extends ConsumerState<RegionsManagementScreen> {
  static const _style = 'https://tiles.openfreemap.org/styles/liberty';
  static const _fallback = LatLng(15.3694, 44.1910);

  MapLibreMapController? _map;
  bool _styleLoaded = false;
  bool _loading = true;
  String? _error;
  List<GovernorateModel> _governorates = const [];
  List<RegionCell> _cells = const [];
  final _searchController = TextEditingController();
  int? _selectedGovernorateId;
  bool _drawing = false;
  RegionCell? _editingCell;
  final List<LatLng> _draft = [];

  bool get _canRegions {
    final user = ref.read(authControllerProvider).asData?.value;
    return user?.isPlatformOwner == true ||
        user?.hasPermission('regions.manage') == true;
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(regionRepositoryProvider);
      final govs =
          _canRegions ? await repo.governorates() : <GovernorateModel>[];
      final selected =
          _selectedGovernorateId ?? (govs.isEmpty ? null : govs.first.id);
      final cells = _canRegions
          ? await repo.cells(
              governorateId: selected,
              search: _searchController.text,
            )
          : <RegionCell>[];
      if (!mounted) {
        return;
      }
      setState(() {
        _governorates = govs;
        _selectedGovernorateId = selected;
        _cells = cells;
        _loading = false;
      });
      await _syncMap();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = friendlyApiError(error);
      });
    }
  }

  void _onMapCreated(MapLibreMapController controller) => _map = controller;

  Future<void> _onStyleLoaded() async {
    _styleLoaded = true;
    await _syncMap();
  }

  void _onMapClick(math.Point<double> _, LatLng point) {
    if (!_drawing || !_canRegions) {
      return;
    }
    setState(() => _draft.add(point));
    _syncMap();
  }

  Future<void> _syncMap() async {
    final map = _map;
    if (map == null || !_styleLoaded) {
      return;
    }
    try {
      await map.clearFills();
      await map.clearLines();
      await map.clearCircles();
      for (final cell in _cells.where((cell) => cell.boundary.length >= 3)) {
        final ring = [...cell.boundary, cell.boundary.first];
        await map.addFill(FillOptions(
          geometry: [ring],
          fillColor: '#E5E7EB',
          fillOpacity: cell.isActive ? 0.42 : 0.18,
        ));
        await map.addLine(LineOptions(
          geometry: ring,
          lineColor: '#6B7280',
          lineWidth: 2.0,
        ));
      }
      if (_draft.isNotEmpty) {
        for (final point in _draft) {
          await map.addCircle(CircleOptions(
            geometry: point,
            circleRadius: 6,
            circleColor: '#0B8A55',
            circleStrokeColor: '#FFFFFF',
            circleStrokeWidth: 2,
          ));
        }
        if (_draft.length >= 2) {
          await map.addLine(LineOptions(
            geometry: _draft.length >= 3 ? [..._draft, _draft.first] : _draft,
            lineColor: '#0B8A55',
            lineWidth: 3,
          ));
        }
        if (_draft.length >= 3) {
          await map.addFill(FillOptions(
            geometry: [
              [..._draft, _draft.first]
            ],
            fillColor: '#95D5B2',
            fillOpacity: 0.28,
          ));
        }
      }
    } catch (_) {
      // Map drawing is visual assistance only; server validation remains authoritative.
    }
  }

  void _startNewCell() {
    if (_selectedGovernorateId == null) {
      _message('أنشئ محافظة أو اختر محافظة أولاً.');
      return;
    }
    setState(() {
      _drawing = true;
      _editingCell = null;
      _draft.clear();
    });
    _syncMap();
  }

  void _startRedraw(RegionCell cell) {
    setState(() {
      _drawing = true;
      _editingCell = cell;
      _draft
        ..clear()
        ..addAll(cell.boundary);
    });
    _syncMap();
  }

  void _undoPoint() {
    if (_draft.isEmpty) {
      return;
    }
    setState(() => _draft.removeLast());
    _syncMap();
  }

  void _cancelDrawing() {
    setState(() {
      _drawing = false;
      _editingCell = null;
      _draft.clear();
    });
    _syncMap();
  }

  Future<void> _saveDraft() async {
    if (_draft.length < 3) {
      _message('حدد ثلاث نقاط على الأقل لرسم الخلية.');
      return;
    }
    try {
      final repo = ref.read(regionRepositoryProvider);
      if (_editingCell != null) {
        await repo.updateCellBoundary(cell: _editingCell!, points: _draft);
      } else {
        final details = await _cellDetailsDialog();
        if (details == null || _selectedGovernorateId == null) {
          return;
        }
        await repo.createCell(
          governorateId: _selectedGovernorateId!,
          code: details.$1,
          nameAr: details.$2,
          nameEn: details.$3,
          points: _draft,
        );
      }
      _cancelDrawing();
      await _load();
      _message('تم حفظ حدود الخلية بنجاح.');
    } catch (error) {
      _message(friendlyApiError(error));
    }
  }

  Future<(String, String, String?)?> _cellDetailsDialog() async {
    final code = TextEditingController();
    final nameAr = TextEditingController();
    final nameEn = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('بيانات الخلية'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: code,
                textDirection: TextDirection.ltr,
                decoration:
                    const InputDecoration(labelText: 'رمز الخلية مثل SANA_A1')),
            TextField(
                controller: nameAr,
                decoration:
                    const InputDecoration(labelText: 'اسم الخلية بالعربية')),
            TextField(
                controller: nameEn,
                decoration: const InputDecoration(
                    labelText: 'الاسم الإنجليزي - اختياري')),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (accepted != true ||
        code.text.trim().isEmpty ||
        nameAr.text.trim().isEmpty) {
      return null;
    }
    final en = nameEn.text.trim();
    return (code.text.trim(), nameAr.text.trim(), en.isEmpty ? null : en);
  }

  Future<void> _createGovernorate() async {
    final code = TextEditingController();
    final ar = TextEditingController();
    final en = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إضافة محافظة'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: code,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'الرمز')),
            TextField(
                controller: ar,
                decoration: const InputDecoration(labelText: 'الاسم بالعربية')),
            TextField(
                controller: en,
                decoration: const InputDecoration(
                    labelText: 'الاسم بالإنجليزية - اختياري')),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('إضافة')),
          ],
        ),
      ),
    );
    if (accepted != true ||
        code.text.trim().isEmpty ||
        ar.text.trim().isEmpty) {
      return;
    }
    try {
      await ref.read(regionRepositoryProvider).createGovernorate(
            code: code.text.trim(),
            nameAr: ar.text.trim(),
            nameEn: en.text.trim().isEmpty ? null : en.text.trim(),
          );
      await _load();
    } catch (error) {
      _message(friendlyApiError(error));
    }
  }

  void _message(String text) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _showProperties(RegionCell cell) async {
    try {
      final properties =
          await ref.read(regionRepositoryProvider).cellProperties(cell.id);
      await _syncMap();
      final map = _map;
      if (map != null && _styleLoaded) {
        for (final property in properties) {
          if (property.latitude == null || property.longitude == null) continue;
          await map.addCircle(CircleOptions(
            geometry: LatLng(property.latitude!, property.longitude!),
            circleRadius: 6,
            circleColor: '#0B8A55',
            circleStrokeColor: '#FFFFFF',
            circleStrokeWidth: 2,
          ));
        }
      }
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: SizedBox(
              height: MediaQuery.of(context).size.height * .62,
              child: Column(children: [
                ListTile(
                  title: Text('العقارات داخل ${cell.nameAr}',
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text(
                      '${properties.length} عقار • الأخضر على الخريطة يمثل موقع العقار'),
                  trailing: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close)),
                ),
                const Divider(height: 1),
                Expanded(
                  child: properties.isEmpty
                      ? const Center(
                          child: Text('لا توجد عقارات مرتبطة بهذه المنطقة.'))
                      : ListView.builder(
                          itemCount: properties.length,
                          itemBuilder: (_, index) {
                            final property = properties[index];
                            return ListTile(
                              leading: const Icon(Icons.home_work_outlined),
                              title: Text(property.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800)),
                              subtitle: Text(
                                  '${property.ownerName ?? 'مستخدم'} • ${property.status} • ${property.address}'),
                              trailing: Text(property.price.toStringAsFixed(0)),
                            );
                          },
                        ),
                ),
              ]),
            ),
          ),
        ),
      );
    } catch (error) {
      _message(friendlyApiError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المحافظات والمربعات'),
          actions: [
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh))
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, textAlign: TextAlign.center)))
                : Column(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: Row(children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _selectedGovernorateId,
                            decoration:
                                const InputDecoration(labelText: 'المحافظة'),
                            items: _governorates
                                .map((g) => DropdownMenuItem(
                                    value: g.id, child: Text(g.nameAr)))
                                .toList(),
                            onChanged: (value) async {
                              setState(() => _selectedGovernorateId = value);
                              await _load();
                            },
                          ),
                        ),
                        if (_canRegions) ...[
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                              onPressed: _createGovernorate,
                              icon: const Icon(Icons.add_location_alt_outlined),
                              tooltip: 'إضافة محافظة'),
                        ],
                      ]),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Text(
                        'هذه المناطق لإدارة البيانات الجغرافية والعناوين فقط، ولا يتم تعيين دلال لمنطقة أو مربع.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _load(),
                        decoration: InputDecoration(
                          labelText: 'بحث عن منطقة بالاسم أو الرمز',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: IconButton(
                              onPressed: _load,
                              icon: const Icon(Icons.arrow_forward)),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 300,
                      child: Stack(children: [
                        MapLibreMap(
                          styleString: _style,
                          initialCameraPosition:
                              const CameraPosition(target: _fallback, zoom: 11),
                          onMapCreated: _onMapCreated,
                          onStyleLoadedCallback: _onStyleLoaded,
                          onMapClick: _onMapClick,
                          compassEnabled: true,
                          myLocationEnabled: false,
                        ),
                      ]),
                    ),
                    if (_canRegions)
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: _drawing
                            ? Wrap(spacing: 8, runSpacing: 8, children: [
                                FilledButton.icon(
                                    onPressed: _saveDraft,
                                    icon: const Icon(Icons.save_outlined),
                                    label: Text(_editingCell == null
                                        ? 'حفظ الخلية'
                                        : 'حفظ الحدود الجديدة')),
                                OutlinedButton.icon(
                                    onPressed: _undoPoint,
                                    icon: const Icon(Icons.undo),
                                    label: const Text('تراجع نقطة')),
                                TextButton.icon(
                                    onPressed: _cancelDrawing,
                                    icon: const Icon(Icons.close),
                                    label: const Text('إلغاء الرسم')),
                                Chip(label: Text('${_draft.length} نقطة')),
                              ])
                            : FilledButton.icon(
                                onPressed: _startNewCell,
                                icon: const Icon(Icons.draw_outlined),
                                label:
                                    const Text('رسم خلية جديدة على الخريطة')),
                      ),
                    Expanded(
                      child: _cells.isEmpty
                          ? const Center(
                              child: Text('لا توجد خلايا في هذه المحافظة بعد.'))
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
                              itemCount: _cells.length,
                              itemBuilder: (context, index) {
                                final cell = _cells[index];
                                return Card(
                                  child: ExpansionTile(
                                    leading: const CircleAvatar(
                                      backgroundColor: Color(0xFFE5E7EB),
                                      child: Icon(Icons.grid_view_outlined,
                                          color: AppTheme.brandStrong),
                                    ),
                                    title: Text(cell.nameAr,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900)),
                                    subtitle: Text(
                                        '${cell.code} • ${cell.propertiesCount} عقار • ${cell.publishedPropertiesCount} منشور'),
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            12, 0, 12, 12),
                                        child: Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              OutlinedButton.icon(
                                                  onPressed: () =>
                                                      _showProperties(cell),
                                                  icon: const Icon(
                                                      Icons.home_work_outlined),
                                                  label: const Text(
                                                      'العقارات داخل المنطقة')),
                                              if (_canRegions)
                                                OutlinedButton.icon(
                                                    onPressed: () =>
                                                        _startRedraw(cell),
                                                    icon: const Icon(Icons
                                                        .edit_location_alt_outlined),
                                                    label: const Text(
                                                        'إعادة رسم الحدود')),
                                            ]),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ]),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

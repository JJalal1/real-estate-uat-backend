import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../account/data/auth_controller.dart';
import '../data/region_repository.dart';
import '../domain/region_models.dart';

/// Neutral regions workspace for the platform owner.
///
/// This intentionally does not expose the historical regional broker assignment
/// model. Regions are managed only as geographic/operational entities.
class PlatformRegionsScreen extends ConsumerStatefulWidget {
  const PlatformRegionsScreen({super.key});

  @override
  ConsumerState<PlatformRegionsScreen> createState() =>
      _PlatformRegionsScreenState();
}

class _PlatformRegionsScreenState
    extends ConsumerState<PlatformRegionsScreen> {
  static const _style = 'https://tiles.openfreemap.org/styles/liberty';
  static const _fallback = LatLng(15.3694, 44.1910);

  bool _loading = true;
  String? _error;
  int? _governorateId;
  String _search = '';
  List<GovernorateModel> _governorates = const [];
  List<RegionCell> _cells = const [];
  MapLibreMapController? _map;
  bool _styleLoaded = false;

  bool get _canManage {
    final user = ref.read(authControllerProvider).asData?.value;
    return user?.isPlatformOwner == true ||
        user?.hasPermission('regions.manage') == true;
  }

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load({int? governorateId}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!_canManage) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'لا توجد صلاحية لإدارة المناطق.';
          });
        }
        return;
      }
      final repo = ref.read(regionRepositoryProvider);
      final governorates = await repo.governorates();
      final selected = governorateId ??
          _governorateId ??
          (governorates.isEmpty ? null : governorates.first.id);
      final cells = selected == null
          ? <RegionCell>[]
          : await repo.cells(governorateId: selected);
      if (!mounted) return;
      setState(() {
        _governorates = governorates;
        _governorateId = selected;
        _cells = cells;
        _loading = false;
      });
      await _syncMap();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyApiError(error);
      });
    }
  }

  List<RegionCell> get _visibleCells {
    final query = _search.trim().toLowerCase();
    if (query.isEmpty) return _cells;
    return _cells
        .where(
          (cell) =>
              cell.nameAr.toLowerCase().contains(query) ||
              cell.code.toLowerCase().contains(query) ||
              (cell.nameEn?.toLowerCase().contains(query) ?? false),
        )
        .toList(growable: false);
  }

  void _onMapCreated(MapLibreMapController controller) {
    _map = controller;
  }

  Future<void> _onStyleLoaded() async {
    _styleLoaded = true;
    await _syncMap();
  }

  Future<void> _syncMap() async {
    final map = _map;
    if (map == null || !_styleLoaded) return;
    try {
      await map.clearFills();
      await map.clearLines();
      final points = <LatLng>[];
      for (final cell in _visibleCells.where((item) => item.boundary.length >= 3)) {
        final ring = [...cell.boundary, cell.boundary.first];
        points.addAll(cell.boundary);
        await map.addFill(
          FillOptions(
            geometry: [ring],
            fillColor: cell.isActive ? '#95D5B2' : '#E5E7EB',
            fillOpacity: cell.isActive ? 0.34 : 0.18,
          ),
        );
        await map.addLine(
          LineOptions(
            geometry: ring,
            lineColor: cell.isActive ? '#147D57' : '#6B7280',
            lineWidth: 2.0,
          ),
        );
      }
      if (points.isNotEmpty) {
        final lat = points.fold<double>(0, (sum, p) => sum + p.latitude) /
            points.length;
        final lng = points.fold<double>(0, (sum, p) => sum + p.longitude) /
            points.length;
        await map.animateCamera(CameraUpdate.newLatLngZoom(LatLng(lat, lng), 8));
      }
    } catch (_) {
      // Map rendering is visual only; API data remains the source of truth.
    }
  }

  Future<void> _toggleActive(RegionCell cell, bool active) async {
    try {
      await ref.read(regionRepositoryProvider).setCellActive(cell, active);
      _message(active ? 'تم تفعيل المنطقة.' : 'تم إيقاف المنطقة.');
      await _load(governorateId: _governorateId);
    } catch (error) {
      _message(friendlyApiError(error));
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المناطق والخريطة'),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loading ? null : () => _load(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _errorState()
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                      children: [
                        _introCard(),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          value: _governorateId,
                          decoration: const InputDecoration(
                            labelText: 'المحافظة',
                            prefixIcon: Icon(Icons.location_city_outlined),
                          ),
                          items: _governorates
                              .map(
                                (gov) => DropdownMenuItem(
                                  value: gov.id,
                                  child: Text('${gov.nameAr} (${gov.cellsCount})'),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) {
                            if (value != null) _load(governorateId: value);
                          },
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'البحث في المناطق',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: (value) {
                            setState(() => _search = value);
                            _syncMap();
                          },
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: SizedBox(
                            height: 280,
                            child: MapLibreMap(
                              styleString: _style,
                              initialCameraPosition: const CameraPosition(
                                target: _fallback,
                                zoom: 6,
                              ),
                              onMapCreated: _onMapCreated,
                              onStyleLoadedCallback: _onStyleLoaded,
                              myLocationEnabled: false,
                              compassEnabled: true,
                              rotateGesturesEnabled: true,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'المناطق',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Chip(label: Text('${_visibleCells.length} منطقة')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_visibleCells.isEmpty)
                          const Card(
                            child: Padding(
                              padding: EdgeInsets.all(18),
                              child: Text('لا توجد مناطق مطابقة.'),
                            ),
                          )
                        else
                          ..._visibleCells.map(
                            (cell) => Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: cell.isActive
                                      ? AppTheme.brandSoft
                                      : Colors.grey.shade200,
                                  child: Icon(
                                    Icons.place_outlined,
                                    color: cell.isActive
                                        ? AppTheme.brandStrong
                                        : Colors.grey.shade700,
                                  ),
                                ),
                                title: Text(
                                  cell.nameAr,
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                                subtitle: Text(
                                  '${cell.governorateName} • ${cell.code} • ${cell.isActive ? 'نشطة' : 'متوقفة'}',
                                ),
                                trailing: Switch(
                                  value: cell.isActive,
                                  onChanged: _canManage
                                      ? (value) => _toggleActive(cell, value)
                                      : null,
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

  Widget _introCard() => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: AppTheme.brandSoft,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.map_outlined, color: AppTheme.brandStrong),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'إدارة جغرافية محايدة للمحافظات والمناطق. لا توجد حصرية أو تسلسل هرمي للدلالين حسب المنطقة.',
                style: TextStyle(height: 1.45, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );

  Widget _errorState() => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          const Icon(Icons.error_outline, size: 50),
          const SizedBox(height: 10),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      );
}

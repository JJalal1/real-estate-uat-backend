import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

import 'marketplace_repository.dart';

class DiscoveryLocationPreferences {
  const DiscoveryLocationPreferences({this.permissionResolved = false, this.introductionShown = false, this.manual, this.lastPublicRegion});
  final bool permissionResolved;
  final bool introductionShown;
  final HomeLocation? manual;
  final HomeLocation? lastPublicRegion;
}

/// Only public city centers are persisted, never the device GPS fix.
class DiscoveryLocationStore {
  Future<void> _writes = Future.value();
  Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/discovery_location_v1.json');
  Future<DiscoveryLocationPreferences> load() async {
    try {
      final data = jsonDecode(await (await _file()).readAsString());
      if (data is! Map) return const DiscoveryLocationPreferences();
      final row = data['manual'];
      final valid = row is Map && row['latitude'] is num && row['longitude'] is num &&
        (row['latitude'] as num).isFinite && (row['longitude'] as num).isFinite &&
        (row['latitude'] as num).abs() <= 90 && (row['longitude'] as num).abs() <= 180 && row['governorate'] is String;
      final last = data['last_public_region'];
      final validLast = last is Map && last['latitude'] is num && last['longitude'] is num &&
        (last['latitude'] as num).isFinite && (last['longitude'] as num).isFinite &&
        (last['latitude'] as num).abs() <= 90 && (last['longitude'] as num).abs() <= 180 && last['governorate'] is String;
      return DiscoveryLocationPreferences(permissionResolved: data['permission_resolved'] == true,
        introductionShown: data['introduction_shown'] == true || data['permission_resolved'] == true || valid,
        manual: valid ? HomeLocation.fromJson(Map<String,dynamic>.from(row)) : null,
        lastPublicRegion: validLast ? HomeLocation(latitude: (last['latitude'] as num).toDouble(),
          longitude: (last['longitude'] as num).toDouble(), governorate: last['governorate'] as String,
          label: last['label']?.toString() ?? 'المنطقة') : null);
    } catch (_) { return const DiscoveryLocationPreferences(); }
  }
  Future<void> save(DiscoveryLocationPreferences preferences) {
    final manual = preferences.manual;
    final last = preferences.lastPublicRegion;
    final data = {'permission_resolved': preferences.permissionResolved,
      'introduction_shown': preferences.introductionShown,
      if (last != null) 'last_public_region': {'latitude': last.latitude, 'longitude': last.longitude,
        'governorate': last.governorate, 'label': last.label},
      if (manual != null) 'manual': {'latitude': manual.latitude, 'longitude': manual.longitude,
        'governorate': manual.governorate, 'label': manual.label}};
    return _writes = _writes.then((_) async {
      try { await (await _file()).writeAsString(jsonEncode(data), flush: true); } catch (_) {}
    });
  }
}

class DiscoveryLocationAccess {
  Future<LocationPermission> permission() => Geolocator.checkPermission();
  Future<LocationPermission> requestPermission() => Geolocator.requestPermission();
  Future<HomeLocation> locate() async {
    if (!await Geolocator.isLocationServiceEnabled()) throw StateError('Location disabled');
    final position = await Geolocator.getCurrentPosition(locationSettings:
      const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 8)));
    return HomeLocation(latitude: position.latitude, longitude: position.longitude, label: 'موقعي', device: true);
  }
}

class DiscoveryLocationCoordinator {
  DiscoveryLocationCoordinator(this._store, this._access, this._read, this._write);
  final DiscoveryLocationStore _store;
  final DiscoveryLocationAccess _access;
  final HomeLocation Function() _read;
  final void Function(HomeLocation) _write;
  bool _resolved = false;
  bool _introductionShown = false;
  HomeLocation? _manual;
  HomeLocation? _lastPublicRegion;
  int _selection = 0;
  Future<void>? _initialization;
  Future<void>? _deviceRequest;

  Future<void> initialize() => _initialization ??= _initialize();
  Future<void> _initialize() async {
    final selection = _selection;
    final saved = await _store.load();
    _resolved = saved.permissionResolved;
    _introductionShown = saved.introductionShown || saved.permissionResolved;
    if (selection != _selection) return;
    _lastPublicRegion = saved.lastPublicRegion;
    _manual = _read().manual ? _read() : saved.manual;
    if (_manual != null) { _write(_manual!); return; }
    if (_lastPublicRegion != null) _write(_lastPublicRegion!);
    // The OS sheet is opened only by useDevice().
  }
  bool get shouldOfferChoice => !_introductionShown && !_resolved && _manual == null;
  Future<void> markIntroductionShown() async { _introductionShown = true; await _save(); }
  Future<void> selectManual(HomeLocation location) async {
    _selection++;
    _introductionShown = true;
    _manual = location;
    _write(location);
    await _save();
  }
  Future<void> useDevice() => _runDevice(automatic: false);
  Future<void> rememberPublicRegion(String governorate, List<HomeLocation> registry) async {
    if (_manual != null || !_read().device) return;
    for (final region in registry) {
      if (region.governorate != governorate) continue;
      if (_lastPublicRegion?.governorate == governorate) return;
      _lastPublicRegion = HomeLocation(latitude: region.latitude, longitude: region.longitude,
        governorate: region.governorate, label: region.label);
      await _save();
      return;
    }
  }
  Future<void> _runDevice({required bool automatic}) => _deviceRequest ??= _device(automatic: automatic).whenComplete(() { _deviceRequest = null; });
  Future<void> _device({required bool automatic}) async {
    _introductionShown = true;
    final selection = _selection;
    var permission = await _access.permission();
    if (selection != _selection) return;
    if (permission == LocationPermission.denied && (!automatic || !_resolved)) {
      _resolved = true;
      await _save(); // Persist the decision attempt before opening the OS sheet.
      if (selection != _selection) return;
      permission = await _access.requestPermission();
    } else if (!_resolved) { _resolved = true; await _save(); }
    if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) throw StateError('Location denied');
    final location = await _access.locate();
    if (selection != _selection) return;
    _manual = null;
    _write(location);
    await _save();
  }
  Future<void> _save() => _store.save(DiscoveryLocationPreferences(permissionResolved: _resolved,
    introductionShown: _introductionShown, manual: _manual, lastPublicRegion: _lastPublicRegion));
}

final discoveryLocationStoreProvider = Provider<DiscoveryLocationStore>((ref) => DiscoveryLocationStore());
final discoveryLocationAccessProvider = Provider<DiscoveryLocationAccess>((ref) => DiscoveryLocationAccess());
final discoveryLocationCoordinatorProvider = Provider<DiscoveryLocationCoordinator>((ref) => DiscoveryLocationCoordinator(
  ref.watch(discoveryLocationStoreProvider), ref.watch(discoveryLocationAccessProvider),
  () => ref.read(homeLocationProvider), (location) => ref.read(homeLocationProvider.notifier).state = location));

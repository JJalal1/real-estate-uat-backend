import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

// Actions only: permission decisions remain in the existing OS/plugin flows.
final appPermissionSettingsProvider = Provider<Future<bool> Function()>((ref) => Geolocator.openAppSettings);
final locationServiceSettingsProvider = Provider<Future<bool> Function()>((ref) => Geolocator.openLocationSettings);

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('login and registration are separate routes', () {
    final router = File('lib/router/app_router.dart').readAsStringSync();
    expect(router, contains("path: '/login'"));
    expect(router, contains("path: '/register'"));
    expect(router, contains('P02LoginScreen'));
    expect(router, contains('P02RegisterScreen'));
  });

  test('login never creates a new account implicitly', () {
    final login = File(
      'lib/features/account/presentation/p02/p02_login_screen.dart',
    ).readAsStringSync();
    expect(login, contains("intent: 'login'"));
    expect(login, isNot(contains("intent: 'continue'")));
  });

  test('registration is explicit and explains duplicate-number behavior', () {
    final register = File(
      'lib/features/account/presentation/p02/p02_register_screen.dart',
    ).readAsStringSync();
    expect(register, contains("intent: 'register'"));
    expect(register, contains('إذا كان الرقم مسجلاً مسبقاً'));
  });

  test('revised visual system uses restrained real-estate palette', () {
    final theme = File('lib/core/theme/app_theme.dart').readAsStringSync();
    expect(theme, contains('0xFF123C4A'));
    expect(theme, contains('0xFF0B7D78'));
    expect(theme, contains('0xFFC99A3D'));
    expect(theme, contains('SnackBarBehavior.floating'));
  });

  test('property facts use icons including parking and garden', () {
    final map =
        File('lib/features/map/presentation/map_screen.dart').readAsStringSync();
    final details = File(
      'lib/features/properties/presentation/property_details_screen.dart',
    ).readAsStringSync();
    expect(map, contains('Icons.bed_outlined'));
    expect(map, contains('Icons.bathtub_outlined'));
    expect(map, contains('Icons.local_parking_outlined'));
    expect(map, contains('Icons.park_outlined'));
    expect(details, contains("label: 'حديقة'"));
  });
}

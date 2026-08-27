import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/network/api_client.dart';

void main() {
  test('local API configuration still accepts the loopback development URL',
      () {
    expect(
      ApiEnvironmentConfig.resolveBaseUrl(
        environmentOverride: 'local',
        baseUrlOverride: 'http://127.0.0.1:8000/api',
      ),
      'http://127.0.0.1:8000/api',
    );
    expect(
      ApiEnvironmentConfig.connectTimeoutFor('local'),
      const Duration(seconds: 15),
    );
  });

  test('UAT requires HTTPS non-loopback API and allows cold-start timeout', () {
    expect(
      ApiEnvironmentConfig.resolveBaseUrl(
        environmentOverride: 'uat',
        baseUrlOverride: 'https://uat.example.test/api/',
      ),
      'https://uat.example.test/api',
    );
    expect(
      ApiEnvironmentConfig.connectTimeoutFor('uat'),
      const Duration(seconds: 75),
    );
    expect(
      ApiEnvironmentConfig.receiveTimeoutFor('uat'),
      const Duration(seconds: 45),
    );
    expect(
      () => ApiEnvironmentConfig.resolveBaseUrl(
        environmentOverride: 'uat',
        baseUrlOverride: 'http://uat.example.test/api',
      ),
      throwsStateError,
    );
    expect(
      () => ApiEnvironmentConfig.resolveBaseUrl(
        environmentOverride: 'uat',
        baseUrlOverride: 'https://127.0.0.1/api',
      ),
      throwsStateError,
    );
  });

  test('UAT deployment source never embeds cloud secrets', () {
    final filesystems = File('../backend-api-runtime/config/filesystems.php')
        .readAsStringSync();
    final services =
        File('../backend-api-runtime/config/services.php').readAsStringSync();

    expect(filesystems, contains("env('AWS_SECRET_ACCESS_KEY')"));
    expect(filesystems, isNot(contains('AWS_SECRET_ACCESS_KEY=')));
    expect(services, contains("env('UAT_TEST_OTP_CODE')"));
    expect(services, isNot(contains('UAT_TEST_OTP_CODE=')));
  });
}

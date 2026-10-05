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

  test('UAT uses only the approved Frankfurt API and cold-start timeout', () {
    expect(
      ApiEnvironmentConfig.resolveBaseUrl(
        environmentOverride: 'uat',
        baseUrlOverride:
            'https://real-estate-uat-api-frankfurt.onrender.com/api/',
      ),
      'https://real-estate-uat-api-frankfurt.onrender.com/api',
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

  for (final rejected in [
    'https://localhost/api',
    'https://127.0.0.1/api',
    'https://10.0.2.2/api',
    'https://[::1]/api',
    'http://real-estate-uat-api-frankfurt.onrender.com/api',
    'ftp://real-estate-uat-api-frankfurt.onrender.com/api',
    'https://real-estate-uat-api.onrender.com/api',
    'https://uat.example.test/api',
    'https://real-estate-uat-api-frankfurt.onrender.com.evil.test/api',
    'https://user@real-estate-uat-api-frankfurt.onrender.com/api',
    'https://real-estate-uat-api-frankfurt.onrender.com:443/api',
    'https://real-estate-uat-api-frankfurt.onrender.com/other',
    'https://real-estate-uat-api-frankfurt.onrender.com/api?target=oregon',
    'https://real-estate-uat-api-frankfurt.onrender.com/api#other',
    'https://real-estate-uat-api-frankfurt.onrender.com/api//',
    'not-an-absolute-url',
  ]) {
    test('UAT rejects $rejected', () {
      expect(
        () => ApiEnvironmentConfig.resolveBaseUrl(
          environmentOverride: 'uat',
          baseUrlOverride: rejected,
        ),
        throwsStateError,
      );
    });
  }

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

import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/network/api_client.dart';

void main() {
  test('compiled UAT build points only to the Render HTTPS API', () {
    expect(ApiEnvironmentConfig.environment, 'uat');
    expect(
      ApiEnvironmentConfig.configuredBaseUrl,
      'https://real-estate-uat-api-frankfurt.onrender.com/api',
    );
    expect(
      ApiEnvironmentConfig.resolveBaseUrl(),
      'https://real-estate-uat-api-frankfurt.onrender.com/api',
    );
    expect(ApiEnvironmentConfig.isUat, isTrue);
    expect(
      ApiEnvironmentConfig.connectTimeoutFor(),
      const Duration(seconds: 75),
    );
  });
}

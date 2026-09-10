import 'package:flutter_test/flutter_test.dart';
import 'package:zedbiz/core/config/app_config.dart';

void main() {
  test('production requires an explicit HTTPS URL without secrets', () {
    for (final url in [
      '',
      'http://api.example.com',
      'https://localhost',
      'https://user:pass@api.example.com',
      'https://api.example.com?token=secret',
    ]) {
      expect(
        () => AppConfig.resolve(url, environment: 'production'),
        throwsStateError,
      );
    }
    expect(
      AppConfig.resolve(
        'https://api.example.com',
        environment: 'production',
      ).apiBaseUrl.host,
      'api.example.com',
    );
    expect(AppConfig.resolve('').apiBaseUrl.scheme, 'http');
  });
}

import 'package:flutter/foundation.dart';

class AppConfig {
  const AppConfig({required this.apiBaseUrl});

  final Uri apiBaseUrl;

  factory AppConfig.fromEnvironment() {
    const configuredUrl = String.fromEnvironment('API_BASE_URL');
    const environment = String.fromEnvironment(
      'APP_ENV',
      defaultValue: 'development',
    );
    return AppConfig.resolve(configuredUrl, environment: environment);
  }

  factory AppConfig.resolve(
    String configuredUrl, {
    String environment = 'development',
  }) {
    if (![
      'development',
      'test',
      'staging',
      'production',
    ].contains(environment)) {
      throw StateError('APP_ENV is invalid.');
    }
    final production = environment == 'production' || environment == 'staging';
    if (production && configuredUrl.isEmpty) {
      throw StateError('Production requires an explicit HTTPS API_BASE_URL.');
    }
    final fallback = kIsWeb ? 'http://localhost:8000' : 'http://10.0.2.2:8000';
    final value = configuredUrl.isEmpty ? fallback : configuredUrl;
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw StateError('API_BASE_URL must be an absolute HTTP(S) URL.');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw StateError('API_BASE_URL must use HTTP or HTTPS.');
    }
    if (uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (production &&
            (uri.scheme != 'https' ||
                ['localhost', '127.0.0.1', '10.0.2.2'].contains(uri.host)))) {
      throw StateError(
        'Production requires a public HTTPS API URL without credentials.',
      );
    }
    return AppConfig(apiBaseUrl: uri);
  }
}

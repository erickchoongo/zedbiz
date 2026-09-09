import 'package:flutter/foundation.dart';

class AppConfig {
  const AppConfig({required this.apiBaseUrl});

  final Uri apiBaseUrl;

  factory AppConfig.fromEnvironment() {
    const configuredUrl = String.fromEnvironment('API_BASE_URL');
    final fallback = kIsWeb ? 'http://localhost:8000' : 'http://10.0.2.2:8000';
    final value = configuredUrl.isEmpty ? fallback : configuredUrl;
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw StateError('API_BASE_URL must be an absolute HTTP(S) URL.');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw StateError('API_BASE_URL must use HTTP or HTTPS.');
    }
    return AppConfig(apiBaseUrl: uri);
  }
}

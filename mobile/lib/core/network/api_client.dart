import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:zedbiz/core/network/api_exception.dart';
import 'package:zedbiz/core/storage/token_storage.dart';

class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this.tokenStorage,
    this.requestTimeout = const Duration(
      seconds: int.fromEnvironment(
        'API_REQUEST_TIMEOUT_SECONDS',
        defaultValue: 15,
      ),
    ),
    http.Client? client,
  }) : _client = client ?? http.Client();

  final Uri baseUrl;
  final TokenStorage tokenStorage;
  final Duration requestTimeout;
  final http.Client _client;
  Future<bool>? _refreshInProgress;

  Future<Map<String, dynamic>> getJson(
    String path, {
    bool authenticated = true,
  }) async {
    final response = await _request('GET', path, authenticated: authenticated);
    return _decodeMap(response);
  }

  Future<List<dynamic>> getJsonList(String path) async {
    final response = await _request('GET', path);
    final payload = _decode(response);
    if (payload is! List<dynamic>) {
      throw const ApiException('The service returned an invalid response.');
    }
    return payload;
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = true,
  }) async {
    final response = await _request(
      'POST',
      path,
      body: body,
      authenticated: authenticated,
    );
    return _decodeMap(response);
  }

  Future<Map<String, dynamic>> patchJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _request('PATCH', path, body: body);
    return _decodeMap(response);
  }

  Future<void> postWithoutResponse(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = true,
  }) async {
    await _request('POST', path, body: body, authenticated: authenticated);
  }

  Future<http.Response> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
    bool mayRefresh = true,
  }) async {
    final tokens = authenticated ? await tokenStorage.read() : null;
    if (authenticated && tokens == null) throw const SessionExpiredException();
    final response = await _send(
      method,
      path,
      body: body,
      accessToken: tokens?.accessToken,
    );
    if (response.statusCode == 401 && authenticated && mayRefresh) {
      final refreshed = await _refreshOnce();
      if (!refreshed) throw const SessionExpiredException();
      return _request(
        method,
        path,
        body: body,
        authenticated: true,
        mayRefresh: false,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        _errorMessage(response),
        statusCode: response.statusCode,
      );
    }
    return response;
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? accessToken,
  }) {
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (accessToken != null) headers['Authorization'] = 'Bearer $accessToken';
    final uri = baseUrl.resolve(path);
    final encodedBody = body == null ? null : jsonEncode(body);
    return switch (method) {
      'GET' => _client.get(uri, headers: headers),
      'POST' => _client.post(uri, headers: headers, body: encodedBody),
      'PATCH' => _client.patch(uri, headers: headers, body: encodedBody),
      _ => throw ArgumentError.value(method, 'method'),
    }.timeout(requestTimeout);
  }

  Future<bool> _refreshOnce() {
    return _refreshInProgress ??= _performRefresh().whenComplete(
      () => _refreshInProgress = null,
    );
  }

  Future<bool> _performRefresh() async {
    final tokens = await tokenStorage.read();
    if (tokens == null) return false;
    try {
      final response = await _send(
        'POST',
        '/api/v1/auth/refresh',
        body: {'refresh_token': tokens.refreshToken},
      );
      if (response.statusCode != 200) {
        if (response.statusCode == 401 || response.statusCode == 403) {
          await tokenStorage.clear();
        }
        if (response.statusCode >= 500) {
          throw ApiException(
            'Authentication service temporarily unavailable.',
            statusCode: response.statusCode,
          );
        }
        return false;
      }
      final payload = _decodeMap(response);
      await tokenStorage.write(
        StoredTokens(
          accessToken: payload['access_token'] as String,
          refreshToken: payload['refresh_token'] as String,
        ),
      );
      return true;
    } on Object {
      // A connection failure does not invalidate the saved refresh session.
      rethrow;
    }
  }

  Map<String, dynamic> _decodeMap(http.Response response) {
    final payload = _decode(response);
    if (payload is! Map<String, dynamic>) {
      throw const ApiException('The service returned an invalid response.');
    }
    return payload;
  }

  Object? _decode(http.Response response) {
    if (response.body.isEmpty) return null;
    try {
      return jsonDecode(response.body);
    } on FormatException {
      throw const ApiException('The service returned an invalid response.');
    }
  }

  String _errorMessage(http.Response response) {
    try {
      final payload = jsonDecode(response.body);
      if (payload is Map<String, dynamic> && payload['detail'] is String) {
        return payload['detail'] as String;
      }
    } on FormatException {
      // Fall through to a non-sensitive generic message.
    }
    return 'The request could not be completed.';
  }
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zedbiz/core/network/api_client.dart';
import 'package:zedbiz/core/network/api_exception.dart';
import 'package:zedbiz/core/storage/token_storage.dart';

class MemoryTokenStorage implements TokenStorage {
  MemoryTokenStorage(this.tokens);
  StoredTokens? tokens;
  bool cleared = false;

  @override
  Future<void> clear() async {
    tokens = null;
    cleared = true;
  }

  @override
  Future<StoredTokens?> read() async => tokens;

  @override
  Future<void> write(StoredTokens value) async => tokens = value;
}

void main() {
  test(
    'authenticated client refreshes once and retries with the new access token',
    () async {
      final storage = MemoryTokenStorage(
        const StoredTokens(
          accessToken: 'old-access',
          refreshToken: 'old-refresh',
        ),
      );
      var protectedCalls = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/auth/refresh') {
          expect(jsonDecode(request.body)['refresh_token'], 'old-refresh');
          return http.Response(
            jsonEncode({
              'access_token': 'new-access',
              'refresh_token': 'new-refresh',
            }),
            200,
          );
        }
        protectedCalls++;
        if (protectedCalls == 1) {
          expect(request.headers['Authorization'], 'Bearer old-access');
          return http.Response(jsonEncode({'detail': 'expired'}), 401);
        }
        expect(request.headers['Authorization'], 'Bearer new-access');
        return http.Response(jsonEncode({'id': 'user-1'}), 200);
      });
      final api = ApiClient(
        baseUrl: Uri.parse('https://api.example.test'),
        tokenStorage: storage,
        client: client,
      );

      final response = await api.getJson('/api/v1/auth/me');

      expect(response['id'], 'user-1');
      expect(protectedCalls, 2);
      expect(storage.tokens!.refreshToken, 'new-refresh');
    },
  );

  test('failed refresh clears storage and does not loop', () async {
    final storage = MemoryTokenStorage(
      const StoredTokens(accessToken: 'expired', refreshToken: 'revoked'),
    );
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response(jsonEncode({'detail': 'unauthorized'}), 401);
    });
    final api = ApiClient(
      baseUrl: Uri.parse('https://api.example.test'),
      tokenStorage: storage,
      client: client,
    );

    await expectLater(
      api.getJson('/api/v1/auth/me'),
      throwsA(isA<SessionExpiredException>()),
    );
    expect(calls, 2);
    expect(storage.cleared, isTrue);
  });
}

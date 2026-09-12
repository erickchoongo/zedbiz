import 'dart:convert';
import 'dart:async';

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
    'slow hosted response waits without retrying or clearing credentials',
    () async {
      final storage = MemoryTokenStorage(
        const StoredTokens(accessToken: 'access', refreshToken: 'refresh'),
      );
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return http.Response('{"status":"ok"}', 200);
      });
      final api = ApiClient(
        baseUrl: Uri.parse('https://api.example.test'),
        tokenStorage: storage,
        client: client,
        requestTimeout: const Duration(seconds: 1),
      );
      expect((await api.getJson('/api/v1/health'))['status'], 'ok');
      expect(calls, 1);
      expect(storage.cleared, false);
    },
  );

  test(
    'timeout remains transient and does not clear refresh credentials',
    () async {
      final storage = MemoryTokenStorage(
        const StoredTokens(accessToken: 'access', refreshToken: 'refresh'),
      );
      final response = Completer<http.Response>();
      var calls = 0;
      final api = ApiClient(
        baseUrl: Uri.parse('https://api.example.test'),
        tokenStorage: storage,
        client: MockClient((request) {
          calls++;
          return response.future;
        }),
        requestTimeout: const Duration(milliseconds: 5),
      );
      await expectLater(
        api.getJson('/api/v1/auth/me'),
        throwsA(isA<TimeoutException>()),
      );
      expect(calls, 1);
      expect(storage.cleared, false);
      response.complete(http.Response('{}', 200));
    },
  );
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

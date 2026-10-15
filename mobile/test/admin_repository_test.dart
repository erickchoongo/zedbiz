import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zedbiz/features/admin/data/admin_repository.dart';
import 'package:zedbiz/core/network/api_client.dart';
import 'package:zedbiz/core/storage/token_storage.dart';

import 'api_client_test.dart' show MemoryTokenStorage;

void main() {
  for (final invalid in [
    {'total': -1, 'page': 1, 'page_size': 100, 'items': []},
    {'total': 1, 'page': 0, 'page_size': 100, 'items': []},
    {'total': 1, 'page': 1, 'page_size': 100, 'items': []},
    {
      'total': 1,
      'page': 1,
      'page_size': 100,
      'items': [
        {'id': 'b'},
      ],
    },
  ]) {
    test(
      'malformed pagination or model surfaces a failure: $invalid',
      () async {
        final api = ApiClient(
          baseUrl: Uri.parse('https://example.test'),
          tokenStorage: MemoryTokenStorage(
            const StoredTokens(accessToken: 'a', refreshToken: 'r'),
          ),
          client: MockClient(
            (r) async => http.Response(jsonEncode(invalid), 200),
          ),
        );
        await expectLater(
          AdminRepository(api).listBusinesses(),
          throwsA(isA<Object>()),
        );
      },
    );
  }

  test('admin listing traverses pages and maps payment state', () async {
    final pages = <String>[];
    final api = ApiClient(
      baseUrl: Uri.parse('https://example.test'),
      tokenStorage: MemoryTokenStorage(
        const StoredTokens(accessToken: 'a', refreshToken: 'r'),
      ),
      client: MockClient((r) async {
        pages.add(r.url.queryParameters['page']!);
        return http.Response(
          jsonEncode({
            'total': 2,
            'page': pages.length,
            'page_size': 100,
            'items': [
              {
                'id': pages.length.toString(),
                'name': 'Business',
                'onboarding_status': 'COMPLETED',
                'onboarding_payment_status': 'WAIVED',
                'subscription_status': 'ACTIVE',
              },
            ],
          }),
          200,
        );
      }),
    );
    final result = await AdminRepository(api).listBusinesses();
    expect(pages, ['1', '2']);
    expect(result.length, 2);
    expect(result.first.onboardingPaymentStatus, 'WAIVED');
  });
  test(
    'commercial actions keep existing protected endpoints and payloads',
    () async {
      final requests = <http.Request>[];
      final api = ApiClient(
        baseUrl: Uri.parse('https://example.test'),
        tokenStorage: MemoryTokenStorage(
          const StoredTokens(accessToken: 'a', refreshToken: 'r'),
        ),
        client: MockClient((r) async {
          requests.add(r);
          return http.Response('{}', 200);
        }),
      );
      final repo = AdminRepository(api);
      await repo.updateOnboarding('b', {'payment_status': 'WAIVED'});
      await repo.activate('b', method: 'CASH', reference: 'receipt-1');
      await repo.renew('b', method: 'BANK_TRANSFER', reference: 'receipt-2');
      expect(requests.map((r) => r.url.path), [
        '/api/v1/admin/businesses/b/onboarding',
        '/api/v1/admin/businesses/b/subscription/activate',
        '/api/v1/admin/businesses/b/subscription/renew',
      ]);
      expect(requests.first.method, 'PATCH');
      expect(jsonDecode(requests[1].body), {
        'payment_method': 'CASH',
        'payment_reference': 'receipt-1',
      });
      expect(
        requests.every((r) => r.headers['Authorization'] == 'Bearer a'),
        true,
      );
    },
  );
}

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zedbiz/core/offline/local_database.dart';
import 'package:zedbiz/core/offline/offline_client.dart';
import 'package:zedbiz/core/network/api_exception.dart';

import 'offline_sync_test.dart' show Tokens, seed, expense;

void main() {
  test(
    'revoked membership removes cached data but preserves pending writes',
    () async {
      final db = LocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await seed(db);
      final api = OfflineClient(
        baseUrl: Uri.parse('http://localhost'),
        tokenStorage: Tokens(),
        db: db,
        client: MockClient((_) async => http.Response('[]', 200)),
      );
      api.online = false;
      await api.postJson('/api/v1/businesses/b/expenses', expense('saved'));
      api.online = true;
      await api.getJsonList('/api/v1/businesses');
      expect(await db.readCache('u', 'b', 'catalog'), isNull);
      expect(await db.operation('u', 'b', 'saved'), isNotNull);
      api.online = false;
      await expectLater(
        api.getJson('/api/v1/businesses/b/products'),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        api.postJson('/api/v1/businesses/b/expenses', expense('blocked')),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test(
    'global denial clears identity and closes session even with empty queue',
    () async {
      final db = LocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await seed(db);
      final tokens = Tokens();
      var invalidated = false;
      final api = OfflineClient(
        baseUrl: Uri.parse('http://localhost'),
        tokenStorage: tokens,
        db: db,
        client: MockClient(
          (_) async => http.Response('{"detail":"Denied"}', 401),
        ),
      );
      api.sessionInvalidated = () => invalidated = true;
      await api.verifySessionAccess();
      expect(invalidated, isTrue);
      expect(await tokens.read(), isNull);
      expect(await db.readCache('u', '', '/api/v1/auth/me'), isNull);
      expect(await db.readCache('u', 'b', 'catalog'), isNull);
    },
  );

  test(
    'expired offline authorization cannot read cached protected data',
    () async {
      final db = LocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await seed(
        db,
        at: DateTime.now().toUtc().subtract(const Duration(days: 2)),
      );
      final api = OfflineClient(
        baseUrl: Uri.parse('http://localhost'),
        tokenStorage: Tokens(),
        db: db,
      )..online = false;
      await expectLater(
        api.getJson('/api/v1/auth/me'),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        api.getJson('/api/v1/businesses/b/products'),
        throwsA(isA<ApiException>()),
      );
    },
  );
}

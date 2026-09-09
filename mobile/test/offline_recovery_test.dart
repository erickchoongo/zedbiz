import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zedbiz/app/app_controller.dart';
import 'package:zedbiz/core/network/api_exception.dart';
import 'package:zedbiz/core/offline/local_database.dart';
import 'package:zedbiz/core/offline/offline_client.dart';
import 'package:zedbiz/core/offline/sync_status_screen.dart';
import 'package:zedbiz/features/businesses/domain/business_summary.dart';
import 'package:zedbiz/features/products/data/product_repository.dart';
import 'package:zedbiz/features/products/presentation/products_screen.dart';
import 'package:zedbiz/features/sales/data/sale_repository.dart';
import 'package:zedbiz/features/sales/presentation/sales_screen.dart';

import 'helpers/fakes.dart';
import 'offline_sync_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'full catalogue pagination reaches item 101 and searches offline',
    () async {
      final db = LocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final pages = <int>[];
      final api = OfflineClient(
        baseUrl: Uri.parse('http://test'),
        tokenStorage: fixture.Tokens(),
        db: db,
        client: MockClient((request) async {
          final page = int.parse(request.url.queryParameters['page']!);
          pages.add(page);
          return http.Response(
            jsonEncode({
              'items': List.generate(
                page == 1 ? 100 : 1,
                (i) => {
                  ...fixture.product,
                  'id': '${(page - 1) * 100 + i}',
                  'name': 'Product ${(page - 1) * 100 + i}',
                },
              ),
              'total': 101,
            }),
            200,
          );
        }),
      );
      await api.refreshProducts('b');
      api.online = false;
      final result = await api.products('b', {'search': 'Product 100'});
      expect(pages, [1, 2]);
      expect(result['total'], 1);
    },
  );
  test(
    'SQLite leases exclude another runner and expiration preserves queue',
    () async {
      final db = LocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      expect(await db.acquireLease('u', 'b', 'first'), isTrue);
      expect(await db.acquireLease('u', 'b', 'second'), isFalse);
      expect(await db.acquireLease('u', 'different', 'second'), isTrue);
      await db.customStatement('UPDATE sync_leases SET expires_at=0');
      expect(await db.acquireLease('u', 'b', 'second'), isTrue);
      await db.releaseLease('u', 'b', 'first');
      expect(await db.acquireLease('u', 'b', 'third'), isFalse);
    },
  );
  test(
    'temporary refresh outage preserves credentials and queued expense',
    () async {
      final db = LocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await fixture.seed(db);
      final storage = fixture.Tokens();
      var refresh = 0;
      final api = OfflineClient(
        baseUrl: Uri.parse('http://test'),
        tokenStorage: storage,
        db: db,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/refresh')) {
            refresh++;
            return http.Response('{}', 503);
          }
          return http.Response('{}', 401);
        }),
      )..online = false;
      await api.postJson(
        '/api/v1/businesses/b/expenses',
        fixture.expense('refresh-expense'),
      );
      await api.syncPendingOperations('b', manual: true);
      expect(refresh, 1);
      expect(storage.value, isNotNull);
      expect((await db.operations('u', 'b')).single.state, SyncState.pending);
    },
  );
  test('local UUID rejects changed payload; pending history works without server history cache', () async {
    final db = LocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await fixture.seed(db);
    final api = fixture.client(db, fixture.Server());
    await api.postJson(
      '/api/v1/businesses/b/expenses',
      fixture.expense('stable-expense'),
    );
    await expectLater(
      api.postJson('/api/v1/businesses/b/expenses', {
        ...fixture.expense('stable-expense'),
        'amount': '80.00',
      }),
      throwsA(isA<ApiException>()),
    );
    final history = await api.getJson(
      '/api/v1/businesses/b/expenses?page=1&page_size=20',
    );
    expect(history['items'].length, 1);
    expect(history['items'][0]['local_sync_state'], 'pending');
  });
  testWidgets(
    'cached sale form blocks credit, saves offline, and shows provisional confirmation',
    (tester) async {
      final db = LocalDatabase(NativeDatabase.memory());
      await fixture.seed(db);
      final api = fixture.client(db, fixture.Server());
      final c =
          AppController(
              offline: api,
              monitorConnectivity: false,
              authGateway: FakeAuthGateway(),
              businessGateway: FakeBusinessGateway(),
              commercialGateway: FakeCommercialGateway(),
              adminGateway: FakeAdminGateway(),
              productGateway: ProductRepository(api),
              saleGateway: SaleRepository(api),
            )
            ..selectedBusiness = const BusinessSummary(
              id: 'b',
              name: 'Shop',
              role: BusinessRole.owner,
              currency: 'ZMW',
              timezone: 'Africa/Lusaka',
            )
            ..currentUser = testUser;
      await tester.pumpWidget(MaterialApp(home: NewSaleScreen(controller: c)));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Rice'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('continue-sale')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(
              find.widgetWithText(ChoiceChip, 'Customer Credit'),
            )
            .onSelected,
        isNull,
      );
      expect(
        find.text('Customer Credit requires an internet connection.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Internal notes (optional)'),
        'Keep this internal',
      );
      await tester.tap(find.byKey(const Key('complete-sale')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Sale saved on this device — waiting to sync.'),
        findsOneWidget,
      );
      expect((await db.operations('u', 'b')).length, 1);
      expect(
        (await db.operations('u', 'b')).single.payload['notes'],
        'Keep this internal',
      );
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await db.close();
    },
  );
  testWidgets(
    'cached products disable stock administration and aggregate freshness is explicit',
    (tester) async {
      final db = LocalDatabase(NativeDatabase.memory());
      await fixture.seed(db);
      final api = fixture.client(db, fixture.Server());
      final c =
          AppController(
              offline: api,
              monitorConnectivity: false,
              authGateway: FakeAuthGateway(),
              businessGateway: FakeBusinessGateway(),
              commercialGateway: FakeCommercialGateway(),
              adminGateway: FakeAdminGateway(),
              productGateway: ProductRepository(api),
            )
            ..selectedBusiness = const BusinessSummary(
              id: 'b',
              name: 'Shop',
              role: BusinessRole.owner,
              currency: 'ZMW',
              timezone: 'Africa/Lusaka',
            );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProductsScreen(controller: c, writable: true)),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Rice'), findsOneWidget);
      expect(find.text('Add product'), findsNothing);
      await db.cache('u', 'b', '/api/v1/businesses/b/dashboard?range=today', {
        'total': '250.00',
      });
      await db.invalidate('u', 'b');
      await tester.pumpWidget(
        MaterialApp(
          home: CacheFreshness(
            client: api,
            path: '/api/v1/businesses/b/dashboard?range=today',
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Last updated'), findsOneWidget);
      expect(
        find.textContaining('Pending transactions are separate'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await db.close();
    },
  );
}

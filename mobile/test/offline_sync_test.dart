import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zedbiz/core/network/api_exception.dart';
import 'package:zedbiz/core/offline/local_database.dart';
import 'package:zedbiz/core/offline/offline_client.dart';
import 'package:zedbiz/core/offline/sync_status_screen.dart';
import 'package:zedbiz/core/storage/token_storage.dart';
import 'package:zedbiz/features/sales/application/receipt_export.dart';
import 'package:zedbiz/features/sales/domain/sale.dart';

String token(String user) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': user})))}.signature';

class Tokens implements TokenStorage {
  StoredTokens? value = StoredTokens(
    accessToken: token('u'),
    refreshToken: 'refresh',
  );
  @override
  Future<StoredTokens?> read() async => value;
  @override
  Future<void> clear() async {
    value = null;
  }

  @override
  Future<void> write(StoredTokens tokens) async {
    value = tokens;
  }
}

final product = <String, dynamic>{
  'id': 'p',
  'name': 'Rice',
  'selling_price': '250.00',
  'stock_quantity': '10.000',
  'low_stock_threshold': '1.000',
  'track_inventory': true,
  'is_active': true,
  'is_low_stock': false,
  'sale_version': 'a' * 64,
};
Map<String, dynamic> sale(String id) => {
  'client_operation_id': id,
  'items': [
    {'product_id': 'p', 'quantity': '1.000'},
  ],
  'payment_method': 'CASH',
  'discount_amount': '0.00',
};
Map<String, dynamic> expense(String id) => {
  'client_operation_id': id,
  'category': 'TRANSPORT',
  'description': 'Delivery',
  'amount': '79.99',
  'expense_date': '2026-09-08',
  'payment_method': 'CASH',
};
Future<void> seed(LocalDatabase db, {DateTime? at}) async {
  await db.cache('u', '', '/api/v1/auth/me', {
    'id': 'u',
    'full_name': 'Owner',
  }, at: at);
  await db.cache('u', 'b', '/api/v1/businesses/b', {
    'id': 'b',
    'name': 'Shop',
    'role': 'OWNER',
    'currency': 'ZMW',
  }, at: at);
  await db.cache('u', 'b', '/api/v1/businesses/b/commercial-status', {
    'subscription_status': 'ACTIVE',
    'writes_allowed': true,
  }, at: at);
  await db.cache('u', 'b', 'catalog', [product], at: at);
}

class Server {
  bool disconnected = true, loseResponse = false;
  int? reject;
  final accepted = <String, Map<String, dynamic>>{};
  final requests = <String>[];
  int deductions = 0;
  Future<http.Response> call(http.Request r) async {
    if (disconnected) throw http.ClientException('offline');
    final path = r.url.path;
    if (path == '/api/v1/auth/me') {
      return json({'id': 'u', 'full_name': 'Owner'});
    }
    if (r.method == 'POST') {
      final p = jsonDecode(r.body) as Map<String, dynamic>;
      final id = p['client_operation_id'] as String;
      requests.add(id);
      if (reject != null) {
        return json({
          'detail': reject == 409
              ? 'Product price changed'
              : 'Permission or subscription restriction',
        }, reject!);
      }
      final result = accepted.putIfAbsent(id, () {
        if (path.endsWith('/sales')) deductions++;
        return {
          ...p,
          'id': 'server-$id',
          'business_id': 'b',
          'sale_number': 'ZB-20260908-${accepted.length + 1}',
          'status': path.endsWith('/sales') ? 'COMPLETED' : 'RECORDED',
          'total_amount': '250.00',
          'subtotal': '250.00',
          'sold_at': '2026-09-08T10:00:00Z',
          'created_at': '2026-09-08T10:00:00Z',
          'sold_by_name': 'Owner',
          'recorded_by_name': 'Owner',
          'recorded_by_user_id': 'u',
          'items': [],
        };
      });
      if (loseResponse) {
        loseResponse = false;
        disconnected = true;
        throw http.ClientException('response lost');
      }
      return json(result, 201);
    }
    if (path == '/api/v1/businesses') {
      return json([
        {'id': 'b', 'name': 'Shop', 'role': 'OWNER', 'currency': 'ZMW'},
      ]);
    }
    if (path.endsWith('commercial-status')) {
      return json({'subscription_status': 'ACTIVE', 'writes_allowed': true});
    }
    if (path.endsWith('/products')) {
      return json({
        'items': [
          {...product, 'stock_quantity': '${10 - deductions}.000'},
        ],
        'total': 1,
        'page': 1,
        'page_size': 100,
      });
    }
    if (path.contains('/server-')) {
      return json(
        accepted[path.split('/').last.replaceFirst('server-', '')] ?? {},
      );
    }
    return json({'items': [], 'total': 0, 'page': 1, 'page_size': 20});
  }

  http.Response json(Object data, [int status = 200]) => http.Response(
    jsonEncode(data),
    status,
    headers: {'content-type': 'application/json'},
  );
}

OfflineClient client(LocalDatabase db, Server server, {Tokens? tokens}) =>
    OfflineClient(
      baseUrl: Uri.parse('http://test'),
      tokenStorage: tokens ?? Tokens(),
      db: db,
      client: MockClient(server.call),
    )..online = false;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'SQLite v1 creation, upsert, exact strings, scope and persistent restart',
    () async {
      final dir = await Directory.systemTemp.createTemp('zedbiz-db-test');
      final file = File('${dir.path}/test.sqlite');
      var db = LocalDatabase(NativeDatabase(file));
      await seed(db);
      final server = Server();
      final api = client(db, server);
      final p = sale('sale-1');
      p['items'][0]['quantity'] = '1.250';
      await api.postJson('/api/v1/businesses/b/sales', p);
      await api.postJson('/api/v1/businesses/b/expenses', expense('expense-1'));
      expect((await db.operations('u', 'b')).length, 2);
      expect(await db.operations('another', 'b'), isEmpty);
      expect(await db.operations('u', 'other'), isEmpty);
      await db.close();
      db = LocalDatabase(NativeDatabase(file));
      expect(db.schemaVersion, 1);
      final queue = await db.operations('u', 'b');
      expect(queue.first.payload['items'][0]['quantity'], '1.250');
      expect(queue.last.payload['amount'], '79.99');
      expect(queue.first.payloadVersion, 1);
      expect(
        (await db.readCache('u', 'b', 'catalog'))!.updatedAt,
        isA<DateTime>(),
      );
      expect(await db.readCache('another', 'b', 'catalog'), isNull);
      await db.cache('u', 'b', 'catalog', [
        {...product, 'name': 'Changed'},
      ]);
      expect(
        ((await db.readCache('u', 'b', 'catalog'))!.data as List)
            .single['name'],
        'Changed',
      );
      await db.close();
      await dir.delete(recursive: true);
    },
  );
  test('K250 offline sale projection, restart, lost response, identical retry and exact acceptance', () async {
    final db = LocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await seed(db);
    final server = Server();
    var api = client(db, server);
    final pending = await api.postJson(
      '/api/v1/businesses/b/sales',
      sale('s1'),
    );
    expect(pending['local_sync_state'], 'pending');
    expect(pending['sale_number'], startsWith('Pending #'));
    expect(
      (await api.products('b', {}))['items'][0]['stock_quantity'],
      '9.000',
    );
    api = client(db, server);
    server.disconnected = false;
    server.loseResponse = true;
    await api.syncPendingOperations('b', manual: true);
    expect((await db.operations('u', 'b')).single.state, SyncState.pending);
    expect(server.accepted.length, 1);
    server.disconnected = false;
    await api.syncPendingOperations('b', manual: true);
    final synced = (await db.operations('u', 'b')).single;
    expect(synced.state, SyncState.synced);
    expect(synced.serverId, 'server-s1');
    expect(server.requests, ['s1', 's1']);
    expect(server.deductions, 1);
    expect(
      (await api.products('b', {}))['items'][0]['stock_quantity'],
      '9.000',
    );
    final detail = await api.getJson('/api/v1/businesses/b/sales/local-s1');
    expect(detail['sale_number'], startsWith('ZB-'));
    expect(detail['local_sync_state'], isNull);
  });
  test(
    'expense restart and single flight preserve deterministic operation order',
    () async {
      final db = LocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await seed(db);
      final server = Server();
      var api = client(db, server);
      await api.postJson('/api/v1/businesses/b/sales', sale('first-sale'));
      await api.postJson(
        '/api/v1/businesses/b/expenses',
        expense('second-expense'),
      );
      api = client(db, server);
      server.disconnected = false;
      await Future.wait([
        api.syncPendingOperations('b', manual: true),
        api.syncPendingOperations('b', manual: true),
      ]);
      expect(server.requests, ['first-sale', 'second-expense']);
      expect(
        (await db.operations(
          'u',
          'b',
        )).every((o) => o.state == SyncState.synced),
        isTrue,
      );
    },
  );
  for (final code in [402, 403, 404, 409, 422]) {
    test(
      'HTTP $code stops automatic retry and restores projected stock',
      () async {
        final db = LocalDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        await seed(db);
        final server = Server();
        final api = client(db, server);
        await api.postJson('/api/v1/businesses/b/sales', sale('rejected-sale'));
        server.disconnected = false;
        server.reject = code;
        await api.syncPendingOperations('b', manual: true);
        expect((await db.operations('u', 'b')).single.needsReview, isTrue);
        await api.syncPendingOperations('b', manual: true);
        expect(server.requests.length, 1);
        expect(
          (await api.products('b', {}))['items'][0]['stock_quantity'],
          '10.000',
        );
      },
    );
  }
  test(
    'stale authorization, credit, repayment and stock writes blocked offline',
    () async {
      final db = LocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await seed(db, at: DateTime.now().subtract(const Duration(hours: 25)));
      final api = client(db, Server());
      await expectLater(
        api.postJson('/api/v1/businesses/b/sales', sale('stale-sale')),
        throwsA(isA<ApiException>()),
      );
      for (final path in [
        '/api/v1/businesses/b/debts/d/payments',
        '/api/v1/businesses/b/products/p/stock/add',
      ]) {
        await expectLater(api.postJson(path, {}), throwsA(isA<ApiException>()));
      }
      await expectLater(
        api.postJson('/api/v1/businesses/b/sales', {
          ...sale('credit-sale'),
          'payment_method': 'CUSTOMER_DEBT',
        }),
        throwsA(isA<ApiException>()),
      );
      expect(await db.operations('u', 'b'), isEmpty);
    },
  );
  test('logout hides queue and correct account resumes; missing auth preserves operations', () async {
    final db = LocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await seed(db);
    final storage = Tokens(), server = Server();
    final api = client(db, server, tokens: storage);
    await api.postJson(
      '/api/v1/businesses/b/expenses',
      expense('private-expense'),
    );
    await storage.clear();
    await api.syncPendingOperations('b');
    expect(api.sessionRequired, isTrue);
    expect((await db.operations('u', 'b')).length, 1);
    await storage.write(
      StoredTokens(accessToken: token('other'), refreshToken: 'other'),
    );
    expect(await db.operations(await api.account(), 'b'), isEmpty);
    await expectLater(
      api.getJson('/api/v1/businesses/b/commercial-status'),
      throwsA(isA<ApiException>()),
    );
  });
  test(
    'unsupported payload retained for review and cancellation is guarded',
    () async {
      final db = LocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await seed(db);
      final server = Server();
      final api = client(db, server);
      await api.postJson(
        '/api/v1/businesses/b/expenses',
        expense('old-expense'),
      );
      await db.customStatement('UPDATE sync_operations SET payload_version=99');
      server.disconnected = false;
      await api.syncPendingOperations('b', manual: true);
      final op = (await db.operations('u', 'b')).single;
      expect(op.state, SyncState.failed);
      expect(server.requests, isEmpty);
      await api.cancel(op);
      expect((await db.operations('u', 'b')).single.state, SyncState.cancelled);
    },
  );
  testWidgets(
    'offline banner, pending count, Sync Status and provisional receipt',
    (tester) async {
      final db = LocalDatabase(NativeDatabase.memory());
      await seed(db);
      final api = client(db, Server());
      await api.postJson('/api/v1/businesses/b/sales', sale('pending-sale'));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncBanner(client: api, business: 'b'),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Offline — changes will sync later'), findsOneWidget);
      expect(find.textContaining('1 items waiting'), findsOneWidget);
      final receipt = ReceiptData.fromJson(
        await api.getJson(
          '/api/v1/businesses/b/sales/local-pending-sale/receipt',
        ),
      );
      expect(
        ReceiptExport.lines(receipt).join('\n'),
        contains('PROVISIONAL RECEIPT'),
      );
      await tester.pumpWidget(const SizedBox());
      await db.close();
    },
  );
}

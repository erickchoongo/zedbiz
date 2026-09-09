import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:zedbiz/core/network/api_client.dart';
import 'package:zedbiz/core/offline/local_database.dart';
import 'package:zedbiz/core/offline/offline_client.dart';
import 'package:zedbiz/core/storage/token_storage.dart';
import 'package:zedbiz/features/products/data/product_repository.dart';
import 'package:zedbiz/features/sales/application/receipt_export.dart';
import 'package:zedbiz/features/sales/domain/sale.dart';

class LiveBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

class LiveTokens implements TokenStorage {
  LiveTokens(this.value);
  StoredTokens? value;
  @override
  Future<StoredTokens?> read() async => value;
  @override
  Future<void> write(StoredTokens tokens) async {
    value = tokens;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class SwitchableTransport extends http.BaseClient {
  final delegate = http.Client();
  bool disconnected = false, loseNextWrite = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (disconnected) throw http.ClientException('Simulated disconnection');
    final result = await delegate.send(request);
    if (loseNextWrite &&
        request.method == 'POST' &&
        !request.url.path.endsWith('/reconcile')) {
      await result.stream.drain<void>();
      loseNextWrite = false;
      disconnected = true;
      throw http.ClientException(
        'Simulated lost response after real server acceptance',
      );
    }
    return result;
  }

  @override
  void close() => delegate.close();
}

void main() {
  LiveBinding();
  final fixturePath = Platform.environment['ZEDBIZ_LIVE_FIXTURE'];
  test(
    'real PostgreSQL API + persistent SQLite: disconnect, restart, sync, lost response, price/stock conflict and PDF',
    () async {
      final fixture = jsonDecode(
        await File(fixturePath!).readAsString(),
      ) as Map<String, dynamic>;
      final bid = fixture['business_id'] as String,
          user = fixture['user_id'] as String,
          pid = fixture['product_id'] as String;
      final base = '/api/v1/businesses/$bid';
      final tokens = LiveTokens(
        StoredTokens(
          accessToken: fixture['access_token'] as String,
          refreshToken: fixture['refresh_token'] as String,
        ),
      );
      final wire = SwitchableTransport();
      addTearDown(wire.close);
      final dir = await Directory.systemTemp.createTemp('zedbiz-live-sqlite');
      var db = LocalDatabase(NativeDatabase(File('${dir.path}/local.sqlite')));
      OfflineClient make() => OfflineClient(
        baseUrl: Uri.parse(fixture['url'] as String),
        tokenStorage: tokens,
        db: db,
        client: wire,
      );
      var api = make();
      await api.getJson('/api/v1/auth/me');
      await api.refreshCore(bid);
      wire.disconnected = true;
      api.online = false;
      expect((await api.products(bid, {'search': 'Rice'}))['total'], 1);
      expect(
        await api.getJson('$base/dashboard?range=today'),
        contains('period'),
      );
      expect(
        (await api.getJson('$base/customers?page=1&page_size=20'))['items'],
        isNotEmpty,
      );
      final id = newOperationId();
      Map<String, dynamic> sale(String operation) => {
        'client_operation_id': operation,
        'items': [
          {'product_id': pid, 'quantity': '1.000'},
        ],
        'payment_method': 'CASH',
        'discount_amount': '0.00',
      };
      final pending = await api.postJson('$base/sales', sale(id));
      expect(pending['total_amount'], '250.00');
      expect(
        (await api.products(bid, {}))['items'][0]['stock_quantity'],
        '9.000',
      );
      await db.close();
      db = LocalDatabase(NativeDatabase(File('${dir.path}/local.sqlite')));
      api = make()..online = false;
      expect((await db.operations(user, bid)).single.id, id);
      wire.disconnected = false;
      await api.syncPendingOperations(bid, manual: true);
      final accepted = (await db.operations(user, bid)).single;
      expect(accepted.state, SyncState.synced);
      final history = await api.getJson('$base/sales?page=1&page_size=20');
      expect(history['total'], 1);
      expect(history['items'][0]['sale_number'], startsWith('ZB-'));
      final movements = await api.getJson(
        '$base/products/$pid/inventory-movements',
      );
      expect(
        (movements['items'] as List)
            .where((m) => m['movement_type'] == 'SALE')
            .length,
        1,
      );
      final eid = newOperationId();
      wire.disconnected = true;
      api.online = false;
      await api.postJson('$base/expenses', {
        'client_operation_id': eid,
        'category': 'TRANSPORT',
        'description': 'Live verification expense',
        'amount': '79.99',
        'payment_method': 'CASH',
        'expense_date': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 2))
            .toIso8601String()
            .substring(0, 10),
      });
      await db.close();
      db = LocalDatabase(NativeDatabase(File('${dir.path}/local.sqlite')));
      api = make()..online = false;
      wire.disconnected = false;
      wire.loseNextWrite = true;
      await api.syncPendingOperations(bid, manual: true);
      expect((await db.operation(user, bid, eid))!.state, SyncState.pending);
      wire.disconnected = false;
      await api.syncPendingOperations(bid, manual: true);
      expect(
        (await api.getJson('$base/expenses?page=1&page_size=20'))['total'],
        1,
      );
      final dashboard = await api.getJson('$base/dashboard?range=today');
      expect(dashboard['gross_sales'], '250.00');
      expect(dashboard['sales_count'], 1);
      expect(dashboard['gross_profit'], '100.00');
      expect(dashboard['total_expenses'], '79.99');
      expect(dashboard['net_operating_result'], '20.01');
      final salesReport = await api.getJson('$base/reports/sales?range=today');
      expect(salesReport['gross_sales'], '250.00');
      expect(salesReport['sales_count'], 1);
      final raw = ApiClient(baseUrl: api.baseUrl, tokenStorage: tokens);
      wire.disconnected = true;
      api.online = false;
      final priceId = newOperationId();
      await api.postJson('$base/sales', sale(priceId));
      await raw.patchJson('$base/products/$pid', {'selling_price': '300.00'});
      wire.disconnected = false;
      await api.syncPendingOperations(bid, manual: true);
      expect(
        (await db.operation(user, bid, priceId))!.state,
        SyncState.conflict,
      );
      final attempts = (await db.operation(user, bid, priceId))!.attempts;
      await api.syncPendingOperations(bid, manual: true);
      expect((await db.operation(user, bid, priceId))!.attempts, attempts);
      wire.disconnected = true;
      api.online = false;
      final stockId = newOperationId();
      await api.postJson('$base/sales', sale(stockId));
      await raw.postJson('$base/products/$pid/stock/adjust', {
        'client_operation_id': newOperationId(),
        'target_quantity': '0.000',
        'reason': 'Live verification conflict',
      });
      wire.disconnected = false;
      await api.syncPendingOperations(bid, manual: true);
      expect(
        (await db.operation(user, bid, stockId))!.state,
        SyncState.conflict,
      );
      final receipt = ReceiptData.fromJson(
        await api.getJson('$base/sales/${accepted.serverId}/receipt'),
      );
      final pdf = await ReceiptExport().generate(receipt);
      expect(pdf.length, greaterThan(1000));
      expect(
        ReceiptExport.lines(receipt).join('\n'),
        isNot(contains('profit')),
      );
      await File('${fixture['output_directory']}/m8-live-receipt.pdf')
          .writeAsBytes(pdf);
      await db.close();
      await dir.delete(recursive: true);
    },
    skip: fixturePath == null
        ? 'Run backend/scripts/verify_m8_postgres.py for disposable live verification.'
        : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

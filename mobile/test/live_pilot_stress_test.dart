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

import 'live_offline_integration_test.dart' as live;

class PilotTransport extends live.SwitchableTransport {
  bool loseExpense = true;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!disconnected &&
        loseExpense &&
        request.method == 'POST' &&
        request.url.path.endsWith('/expenses')) {
      loseExpense = false;
      loseNextWrite = true;
    }
    return super.send(request);
  }
}

void main() {
  live.LiveBinding();
  final fixturePath = Platform.environment['ZEDBIZ_LIVE_FIXTURE'];
  test(
    'pilot: 20 sales, 10 expenses, review isolation, restart, expired access and lost responses',
    () async {
      final f = jsonDecode(
        await File(fixturePath!).readAsString(),
      ) as Map<String, dynamic>;
      final user = f['user_id'] as String,
          business = f['business_id'] as String,
          product = f['product_id'] as String;
      final base = '/api/v1/businesses/$business';
      final tokens = live.LiveTokens(
        StoredTokens(
          accessToken: f['access_token'],
          refreshToken: f['refresh_token'],
        ),
      );
      final wire = PilotTransport();
      addTearDown(wire.close);
      final directory = await Directory.systemTemp.createTemp(
        'zedbiz-pilot-queue-',
      );
      var db = LocalDatabase(
        NativeDatabase(File('${directory.path}/queue.sqlite')),
      );
      OfflineClient open() => OfflineClient(
        baseUrl: Uri.parse(f['url']),
        tokenStorage: tokens,
        db: db,
        client: wire,
      );
      var api = open();
      await api.getJson('/api/v1/auth/me');
      await api.getJsonList('/api/v1/businesses');
      await api.refreshCore(business);
      final raw = ApiClient(baseUrl: api.baseUrl, tokenStorage: tokens);
      final conflictProduct = await raw.postJson('$base/products', {
        'name': 'Review item',
        'selling_price': '10.00',
        'opening_stock': '2.000',
      });
      await api.refreshProducts(business);
      final beforeSales =
          (await api.getJson('$base/sales?page=1&page_size=20'))['total']
              as int;
      final beforeExpenses =
          (await api.getJson('$base/expenses?page=1&page_size=20'))['total']
              as int;
      wire.disconnected = true;
      api.online = false;
      final ids = <String>[];
      Future<void> queueSale(String pid) async {
        final id = newOperationId();
        ids.add(id);
        await api.postJson('$base/sales', {
          'client_operation_id': id,
          'items': [
            {'product_id': pid, 'quantity': '1.000'},
          ],
          'payment_method': 'CASH',
          'discount_amount': '0.00',
        });
      }

      await queueSale(conflictProduct['id']);
      for (var i = 0; i < 20; i++) {
        await queueSale(product);
      }
      for (var i = 0; i < 10; i++) {
        final id = newOperationId();
        ids.add(id);
        await api.postJson('$base/expenses', {
          'client_operation_id': id,
          'amount': '2.50',
          'category': 'TRANSPORT',
          'description': 'Pilot offline expense $i',
          'expense_date': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 2))
              .toIso8601String()
              .substring(0, 10),
          'payment_method': 'CASH',
        });
      }
      expect((await db.operations(user, business)).length, 31);
      await db.close();
      db = LocalDatabase(
        NativeDatabase(File('${directory.path}/queue.sqlite')),
      );
      api = open()..online = false;
      expect((await db.operations(user, business)).length, 31);
      await raw.patchJson('$base/products/${conflictProduct['id']}', {
        'selling_price': '11.00',
      });
      final stored = (await tokens.read())!;
      await tokens.write(
        StoredTokens(
          accessToken:
              'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': user, 'exp': 0})))}.signature',
          refreshToken: stored.refreshToken,
        ),
      );
      wire.disconnected = false;
      // Exercise access-token refresh while work is pending, before simulating
      // lost financial responses (refresh tokens themselves rotate once).
      await raw.getJson('/api/v1/auth/me');
      wire.loseNextWrite = true;
      for (var pass = 0; pass < 4; pass++) {
        wire.disconnected = false;
        await Future.wait(
          List.generate(
            10,
            (_) => api.syncPendingOperations(business, manual: true),
          ),
        );
      }
      final operations = await db.operations(user, business);
      expect(operations.where((o) => o.state == SyncState.synced).length, 30);
      expect(operations.where((o) => o.state == SyncState.conflict).length, 1);
      final review = operations.singleWhere(
        (o) => o.state == SyncState.conflict,
      );
      final attempts = review.attempts;
      await api.syncPendingOperations(business, manual: true);
      expect(
        (await db.operation(user, business, review.id))!.attempts,
        attempts,
      );
      expect(
        (await raw.getJson('$base/sales?page=1&page_size=100'))['total'],
        beforeSales + 20,
      );
      expect(
        (await raw.getJson('$base/expenses?page=1&page_size=100'))['total'],
        beforeExpenses + 10,
      );
      expect(await db.operations('other-account', business), isEmpty);
      expect(await db.operations(user, 'other-business'), isEmpty);
      final confirmed = operations.firstWhere(
        (op) =>
            op.type == OperationType.createSale && op.state == SyncState.synced,
      );
      final receipt = ReceiptData.fromJson(
        await raw.getJson('$base/sales/${confirmed.serverId}/receipt'),
      );
      final receiptText = ReceiptExport.lines(receipt).join('\n');
      expect(receiptText, isNot(contains('profit')));
      expect(receiptText, isNot(contains('cost')));
      final pdf = await ReceiptExport().generate(receipt);
      expect(pdf.length, greaterThan(1000));
      await File('${f['output_directory']}/${ReceiptExport.filename(receipt)}')
          .writeAsBytes(pdf);
      await File('${f['output_directory']}/m9-offline-operation-ids.json')
          .writeAsString(jsonEncode(ids));
      await db.close();
      await directory.delete(recursive: true);
    },
    skip: fixturePath == null
        ? 'Run verify_m9_postgres.py with a disposable PostgreSQL database.'
        : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

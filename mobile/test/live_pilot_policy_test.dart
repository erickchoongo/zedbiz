import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zedbiz/core/offline/local_database.dart';
import 'package:zedbiz/core/offline/offline_client.dart';
import 'package:zedbiz/core/storage/token_storage.dart';
import 'package:zedbiz/features/products/data/product_repository.dart';

import 'live_offline_integration_test.dart' as live;

void main() {
  live.LiveBinding();
  final path = Platform.environment['ZEDBIZ_LIVE_FIXTURE'];
  test(
    'queued intent survives authoritative subscription/membership/product rejection',
    () async {
      final f =
          jsonDecode(await File(path!).readAsString()) as Map<String, dynamic>;
      final db = LocalDatabase(NativeDatabase(File(f['cache_file'])));
      final tokens = live.LiveTokens(
        StoredTokens(
          accessToken: f['access_token'],
          refreshToken: f['refresh_token'],
        ),
      );
      final wire = live.SwitchableTransport();
      final api = OfflineClient(
        baseUrl: Uri.parse(f['url']),
        tokenStorage: tokens,
        db: db,
        client: wire,
      );
      final business = f['business_id'] as String,
          user = f['user_id'] as String;
      if (f['phase'] == 'capture') {
        await api.getJson('/api/v1/auth/me');
        await api.getJsonList('/api/v1/businesses');
        await api.getJson('/api/v1/businesses/$business/commercial-status');
        await api.refreshProducts(business);
        wire.disconnected = true;
        api.online = false;
        await api.postJson('/api/v1/businesses/$business/sales', {
          'client_operation_id': newOperationId(),
          'items': [
            {'product_id': f['product_id'], 'quantity': '1.000'},
          ],
          'payment_method': 'CASH',
        });
        expect(
          (await db.operations(user, business)).single.state,
          SyncState.pending,
        );
      } else {
        await api.syncPendingOperations(business, manual: true);
        final op = (await db.operations(user, business)).single;
        expect(op.needsReview, true);
        expect(
          op.state,
          f['scenario'] == 'expired' ? SyncState.failed : SyncState.conflict,
        );
        final attempts = op.attempts;
        await api.syncPendingOperations(business, manual: true);
        expect((await db.operations(user, business)).single.attempts, attempts);
        expect(await db.operations('other-account', business), isEmpty);
      }
      await db.close();
      wire.close();
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: path == null
        ? 'Run verify_m9_postgres.py for authoritative state-change tests.'
        : false,
  );
}

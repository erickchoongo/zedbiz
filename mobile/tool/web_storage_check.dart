// Compile separately for browser verification; never included by main.dart.
import 'dart:js_interop';

import 'package:drift/wasm.dart';
import 'package:zedbiz/core/offline/local_database.dart';

@JS('document.body.textContent')
external set resultText(String value);

Future<void> main() async {
  try {
    final result = await WasmDatabase.open(
      databaseName: 'zedbiz_m8_browser_check',
      sqlite3Uri: Uri.base.resolve('sqlite3.wasm'),
      driftWorkerUri: Uri.base.resolve('drift_worker.dart.js'),
    );
    if (result.chosenImplementation == WasmStorageImplementation.inMemory ||
        result.chosenImplementation ==
            WasmStorageImplementation.unsafeIndexedDb) {
      throw StateError('Durable browser storage unavailable');
    }
    final db = LocalDatabase(result.resolvedExecutor);
    if (Uri.base.queryParameters['phase'] != 'read') {
      await db.cache('account-a', 'business-a', 'products', [
        {'price': '79.99', 'quantity': '1.250'},
      ]);
      await db.enqueue(
        'account-a',
        'business-a',
        OperationType.createExpense,
        {'client_operation_id': 'browser-expense', 'amount': '79.99'},
        {'amount': '79.99'},
      );
    }
    final records = await db.operations('account-a', 'business-a');
    if (records.length != 1 ||
        records.single.payload['amount'] != '79.99' ||
        records.single.state != SyncState.pending) {
      throw StateError('Queue persistence failed');
    }
    if ((await db.operations('account-b', 'business-a')).isNotEmpty ||
        (await db.operations('account-a', 'business-b')).isNotEmpty) {
      throw StateError('Scope isolation failed');
    }
    final cache = await db.readCache('account-a', 'business-a', 'products');
    if ((cache!.data as List).single['quantity'] != '1.250') {
      throw StateError('Quantity changed');
    }
    await db.close();
    resultText = 'Passed: persistent browser SQLite, exact values, account/business isolation, durable queue.';
  } on Object catch (error) {
    resultText = 'Failed: $error';
  }
}

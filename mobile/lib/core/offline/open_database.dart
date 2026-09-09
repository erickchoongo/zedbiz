import 'package:drift_flutter/drift_flutter.dart';

import 'local_database.dart';

LocalDatabase openLocalDatabase() {
  late LocalDatabase database;
  database = LocalDatabase(
    driftDatabase(
      name: 'zedbiz_offline_v1',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.dart.js'),
        onResult: (result) {
          database.durableStorage =
              result.chosenImplementation !=
                  WasmStorageImplementation.inMemory &&
              result.chosenImplementation !=
                  WasmStorageImplementation.unsafeIndexedDb;
        },
      ),
    ),
  );
  return database;
}

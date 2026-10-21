import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

enum SyncState { pending, syncing, synced, failed, conflict, cancelled }

enum OperationType { createSale, createExpense }

String canonicalJson(Object? value) {
  Object? sort(Object? v) {
    if (v is Map) {
      final keys = v.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: sort(v[key])};
    }
    if (v is List) return v.map(sort).toList();
    return v;
  }

  return jsonEncode(sort(value));
}

String fingerprint(Object? value) =>
    sha256.convert(utf8.encode(canonicalJson(value))).toString();

Map<String, dynamic> decodeQueuedMap(String value) {
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map<String, dynamic>) return decoded;
  } on FormatException {
    /* Preserve incompatible data for review. */
  }
  return {'_invalid_local_payload': true};
}

class CachedRead {
  CachedRead(this.data, this.updatedAt, this.stale);
  final Object? data;
  final DateTime updatedAt;
  final bool stale;
}

class QueuedOperation {
  QueuedOperation(QueryRow row)
    : userId = row.read<String>('user_id'),
      businessId = row.read<String>('business_id'),
      id = row.read<String>('client_operation_id'),
      type = OperationType.values.byName(row.read<String>('operation_type')),
      state = SyncState.values.byName(row.read<String>('state')),
      payloadVersion = row.read<int>('payload_version'),
      payload = decodeQueuedMap(row.read<String>('payload_json')),
      preview = decodeQueuedMap(row.read<String>('preview_json')),
      attempts = row.read<int>('attempt_count'),
      nextRetry = row.readNullable<int>('next_retry_at'),
      error = row.readNullable<String>('last_error_message'),
      serverId = row.readNullable<String>('server_resource_id'),
      createdAt = DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('created_at'),
        isUtc: true,
      );
  final String userId, businessId, id;
  final OperationType type;
  final SyncState state;
  final int payloadVersion, attempts;
  final int? nextRetry;
  final String? error, serverId;
  final Map<String, dynamic> payload, preview;
  final DateTime createdAt;
  bool get reservesStock =>
      state == SyncState.pending || state == SyncState.syncing;
  bool get needsReview =>
      state == SyncState.failed || state == SyncState.conflict;
}

/// Drift owns connection lifecycle, transactions and versioned SQLite migrations.
/// SQL is explicit to keep the small cache/queue schema independent of API models.
class LocalDatabase extends GeneratedDatabase {
  LocalDatabase(super.executor);
  bool durableStorage = true;
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement(
        'CREATE TABLE sync_leases(user_id TEXT NOT NULL,business_id TEXT NOT NULL,owner TEXT NOT NULL,expires_at INTEGER NOT NULL,PRIMARY KEY(user_id,business_id))',
      );
      await customStatement('''CREATE TABLE cached_reads (
        user_id TEXT NOT NULL, business_id TEXT NOT NULL, cache_key TEXT NOT NULL,
        data_json TEXT NOT NULL, updated_at INTEGER NOT NULL, stale INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(user_id, business_id, cache_key))''');
      await customStatement('''CREATE TABLE sync_operations (
        user_id TEXT NOT NULL, business_id TEXT NOT NULL, client_operation_id TEXT NOT NULL,
        operation_type TEXT NOT NULL CHECK(operation_type IN ('createSale','createExpense')),
        payload_version INTEGER NOT NULL DEFAULT 1, payload_json TEXT NOT NULL,
        payload_fingerprint TEXT NOT NULL, preview_json TEXT NOT NULL,
        state TEXT NOT NULL CHECK(state IN ('pending','syncing','synced','failed','conflict','cancelled')),
        attempt_count INTEGER NOT NULL DEFAULT 0, last_attempt_at INTEGER,
        next_retry_at INTEGER, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
        last_error_code TEXT, last_error_message TEXT, server_resource_id TEXT,
        PRIMARY KEY(user_id, business_id, client_operation_id))''');
      await customStatement(
        'CREATE INDEX queue_order ON sync_operations(user_id,business_id,created_at,client_operation_id)',
      );
    },
    onUpgrade: (_, from, to) async => throw StateError(
      'Unsupported local schema upgrade $from to $to; database retained.',
    ),
  );

  Future<void> cache(
    String user,
    String business,
    String key,
    Object? data, {
    DateTime? at,
  }) => customStatement(
    'INSERT INTO cached_reads VALUES (?,?,?,?,?,0) ON CONFLICT(user_id,business_id,cache_key) DO UPDATE SET data_json=excluded.data_json,updated_at=excluded.updated_at,stale=0',
    [
      user,
      business,
      key,
      jsonEncode(data),
      (at ?? DateTime.now().toUtc()).millisecondsSinceEpoch,
    ],
  );
  Future<CachedRead?> readCache(
    String user,
    String business,
    String key,
  ) async {
    final rows = await customSelect(
      'SELECT * FROM cached_reads WHERE user_id=? AND business_id=? AND cache_key=?',
      variables: [Variable(user), Variable(business), Variable(key)],
    ).get();
    if (rows.isEmpty) return null;
    final row = rows.single;
    return CachedRead(
      jsonDecode(row.read<String>('data_json')),
      DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('updated_at'),
        isUtc: true,
      ),
      row.read<int>('stale') != 0,
    );
  }

  Future<void> invalidate(String user, String business) => customStatement(
    'UPDATE cached_reads SET stale=1 WHERE user_id=? AND business_id=?',
    [user, business],
  );
  Future<void> clearBusinessCache(String user, String business) =>
      customStatement(
        'DELETE FROM cached_reads WHERE user_id=? AND business_id=?',
        [user, business],
      );

  /// Cached authorization/data can be revoked without deleting queued writes.
  Future<void> clearAccountCache(String user) =>
      customStatement('DELETE FROM cached_reads WHERE user_id=?', [user]);

  Future<void> retainBusinessCaches(
    String user,
    List<String> businesses,
  ) => customStatement(
    "DELETE FROM cached_reads WHERE user_id=? AND business_id<>''"
    '${businesses.isEmpty ? '' : ' AND business_id NOT IN (${List.filled(businesses.length, '?').join(',')})'}',
    [user, ...businesses],
  );

  Future<void> enqueue(
    String user,
    String business,
    OperationType type,
    Map<String, dynamic> payload,
    Map<String, dynamic> preview,
  ) async {
    final id = payload['client_operation_id'] as String;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await transaction(() async {
      final existing = await operation(user, business, id);
      if (existing != null) {
        if (fingerprint(existing.payload) != fingerprint(payload)) {
          throw StateError('Operation already saved with different data.');
        }
        return;
      }
      await customStatement(
        '''INSERT INTO sync_operations
        (user_id,business_id,client_operation_id,operation_type,payload_json,payload_fingerprint,preview_json,state,created_at,updated_at)
        VALUES (?,?,?,?,?,?,?,'pending',?,?)''',
        [
          user,
          business,
          id,
          type.name,
          canonicalJson(payload),
          fingerprint(payload),
          jsonEncode(preview),
          now,
          now,
        ],
      );
    });
  }

  Future<List<QueuedOperation>> operations(
    String user,
    String business,
  ) async => (await customSelect(
    'SELECT * FROM sync_operations WHERE user_id=? AND business_id=? ORDER BY created_at,client_operation_id',
    variables: [Variable(user), Variable(business)],
  ).get()).map(QueuedOperation.new).toList();
  Future<QueuedOperation?> operation(
    String user,
    String business,
    String id,
  ) async {
    final rows = await customSelect(
      'SELECT * FROM sync_operations WHERE user_id=? AND business_id=? AND client_operation_id=?',
      variables: [Variable(user), Variable(business), Variable(id)],
    ).get();
    return rows.isEmpty ? null : QueuedOperation(rows.single);
  }

  Future<void> recover(String user, String business) => customStatement(
    "UPDATE sync_operations SET state='pending' WHERE user_id=? AND business_id=? AND state='syncing'",
    [user, business],
  );
  Future<bool> acquireLease(String user, String business, String owner) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return await customUpdate(
          'INSERT INTO sync_leases VALUES (?,?,?,?) ON CONFLICT(user_id,business_id) DO UPDATE SET owner=excluded.owner,expires_at=excluded.expires_at WHERE sync_leases.expires_at<?',
          variables: [
            Variable(user),
            Variable(business),
            Variable(owner),
            Variable(now + 120000),
            Variable(now),
          ],
        ) ==
        1;
  }

  Future<void> renewLease(String user, String business, String owner) =>
      customStatement(
        'UPDATE sync_leases SET expires_at=? WHERE user_id=? AND business_id=? AND owner=?',
        [DateTime.now().millisecondsSinceEpoch + 120000, user, business, owner],
      );
  Future<void> releaseLease(String user, String business, String owner) =>
      customStatement(
        'DELETE FROM sync_leases WHERE user_id=? AND business_id=? AND owner=?',
        [user, business, owner],
      );
  Future<void> transition(
    QueuedOperation op,
    SyncState state, {
    String? error,
    String? code,
    String? serverId,
    DateTime? retryAt,
  }) async {
    const allowed = {
      SyncState.pending: {
        SyncState.syncing,
        SyncState.cancelled,
        SyncState.failed,
      },
      SyncState.syncing: {
        SyncState.synced,
        SyncState.pending,
        SyncState.failed,
        SyncState.conflict,
      },
      SyncState.failed: {SyncState.cancelled},
      SyncState.conflict: {SyncState.cancelled},
    };
    if (!(allowed[op.state]?.contains(state) ?? false)) {
      throw StateError('Invalid queue transition');
    }
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await customStatement(
      '''UPDATE sync_operations SET state=?,updated_at=?,last_error_message=?,last_error_code=?,server_resource_id=COALESCE(?,server_resource_id),next_retry_at=?,
      attempt_count=attempt_count+?,last_attempt_at=CASE WHEN ?=1 THEN ? ELSE last_attempt_at END
      WHERE user_id=? AND business_id=? AND client_operation_id=? AND state=?''',
      [
        state.name,
        now,
        error,
        code,
        serverId,
        retryAt?.millisecondsSinceEpoch,
        state == SyncState.syncing ? 1 : 0,
        state == SyncState.syncing ? 1 : 0,
        now,
        op.userId,
        op.businessId,
        op.id,
        op.state.name,
      ],
    );
  }

  Future<void> prune(String user, String business) => customStatement(
    "DELETE FROM sync_operations WHERE user_id=? AND business_id=? AND state IN ('synced','cancelled') AND updated_at<?",
    [
      user,
      business,
      DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch,
    ],
  );
}

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:zedbiz/core/network/api_client.dart';
import 'package:zedbiz/core/network/api_exception.dart';
import 'package:zedbiz/features/commercial/domain/money.dart';
import 'package:zedbiz/features/products/domain/product.dart';

import 'local_database.dart';

/// Read-through cache and two explicit domain mutation dispatchers.
/// No arbitrary REST requests are persisted or replayed.
class OfflineClient extends ApiClient {
  OfflineClient({
    required super.baseUrl,
    required super.tokenStorage,
    required this.db,
    super.client,
    this.authorizationValidity = const Duration(
      hours: int.fromEnvironment('OFFLINE_AUTH_HOURS', defaultValue: 24),
    ),
  });
  final LocalDatabase db;
  final Duration authorizationValidity;
  final ValueNotifier<int> changes = ValueNotifier(0);
  bool online = true, syncing = false, sessionRequired = false;
  DateTime? lastCacheRead, lastSync;
  String? selectedBusiness;
  void Function(List<Map<String, dynamic>>)? membershipsVerified;
  Future<void>? _flight;
  Future<void>? _catalogFlight;
  String? _catalogBusiness;
  final Map<String, bool> _requested = {};
  void changed() => changes.value++;

  Future<String> account() async {
    final tokens = await tokenStorage.read();
    if (tokens == null) throw const SessionExpiredException();
    try {
      // Namespace only. Server verification and the cached /me identity are
      // required separately; decoding a token never grants authorization.
      final claims = jsonDecode(
        utf8.decode(
          base64Url.decode(
            base64Url.normalize(tokens.accessToken.split('.')[1]),
          ),
        ),
      ) as Map<String, dynamic>;
      return claims['sub'] as String;
    } on Object {
      throw const SessionExpiredException();
    }
  }

  String businessOf(String path) {
    final parts = Uri.parse(path).pathSegments;
    return parts.length >= 4 && parts[2] == 'businesses' ? parts[3] : '';
  }

  bool cacheable(String path) =>
      path == '/api/v1/auth/me' ||
      path == '/api/v1/businesses' ||
      RegExp(
        r'^/api/v1/businesses/[^/]+(?:/(commercial-status|products|customers|sales|debts|expenses|dashboard|reports|inventory)(?:/|\?|$)|$)',
      ).hasMatch(path);
  bool transient(Object e) =>
      e is TimeoutException ||
      e is http.ClientException ||
      (e is ApiException && [429, 500, 502, 503, 504].contains(e.statusCode));
  Future<void> requireOnline({
    String message = 'This action requires an internet connection.',
  }) async {
    if (!online) throw ApiException(message);
  }

  Future<Object?> _read(String path, Future<Object?> Function() request) async {
    final user = await account();
    final business = businessOf(path);
    if (!online && cacheable(path)) {
      final cached = await db.readCache(user, business, path);
      if (cached != null) {
        lastCacheRead = cached.updatedAt;
        return cached.data;
      }
      throw ApiException(
        path.contains('/reports/')
            ? 'Connect to the internet to load this report.'
            : 'Connect to the internet to load this information.',
      );
    }
    try {
      final data = await request();
      // Do not file an old response under an account that signed in meanwhile.
      if (await account() != user) throw const SessionExpiredException();
      online = true;
      sessionRequired = false;
      if (cacheable(path)) await db.cache(user, business, path, data);
      changed();
      return data;
    } on Object catch (e) {
      if (!transient(e)) {
        if (e is ApiException && [401, 403, 404].contains(e.statusCode)) {
          if (business.isNotEmpty) await db.clearBusinessCache(user, business);
        }
        rethrow;
      }
      online = false;
      final cached = cacheable(path)
          ? await db.readCache(user, business, path)
          : null;
      lastCacheRead = cached?.updatedAt;
      changed();
      if (cached == null) {
        throw ApiException(
          path.contains('/reports/')
              ? 'Connect to the internet to load this report.'
              : 'Connect to the internet to load this information.',
        );
      }
      return cached.data;
    }
  }

  @override
  Future<List<dynamic>> getJsonList(String path) async {
    final result =
        (await _read(path, () => super.getJsonList(path))) as List<dynamic>;
    if (path == '/api/v1/businesses' && online) {
      final user = await account();
      for (final b in result.cast<Map<String, dynamic>>()) {
        final key = '/api/v1/businesses/${b['id']}';
        final previous = await db.readCache(user, b['id'] as String, key);
        if (previous != null && (previous.data as Map)['role'] != b['role']) {
          await db.clearBusinessCache(user, b['id'] as String);
        }
        await db.cache(user, b['id'] as String, key, b);
      }
      membershipsVerified?.call(result.cast<Map<String, dynamic>>());
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    bool authenticated = true,
  }) async {
    if (!authenticated) return super.getJson(path, authenticated: false);
    final business = businessOf(path);
    final uri = Uri.parse(path);
    if (business.isNotEmpty && uri.path.endsWith('/products')) {
      return products(business, uri.queryParameters);
    }
    final user = await account();
    final parts = uri.pathSegments;
    if (parts.length >= 6 &&
        ['sales', 'expenses'].contains(parts[4]) &&
        parts[5].startsWith('local-')) {
      final op = await db.operation(user, business, parts[5].substring(6));
      if (op == null) throw const ApiException('Local transaction not found.');
      if (op.payloadVersion != 1 ||
          op.preview['_invalid_local_payload'] == true) {
        throw const ApiException(
          'This transaction needs review in Sync Status.',
        );
      }
      if (op.state == SyncState.synced) {
        return getJson(path.replaceFirst(parts[5], op.serverId!));
      }
      if (parts.last == 'receipt') return provisionalReceipt(op);
      return {...op.preview, 'local_sync_state': op.state.name};
    }
    Map<String, dynamic> result;
    try {
      result = Map<String, dynamic>.from(
        (await _read(path, () => super.getJson(path))) as Map,
      );
    } on ApiException {
      if (online ||
          parts.length != 5 ||
          !['sales', 'expenses'].contains(parts[4]) ||
          (uri.queryParameters['page'] ?? '1') != '1') {
        rethrow;
      }
      final type = parts[4] == 'sales'
          ? OperationType.createSale
          : OperationType.createExpense;
      if (!(await db.operations(
        user,
        business,
      )).any((o) => o.type == type && o.state != SyncState.cancelled)) {
        rethrow;
      }
      result = {'items': <dynamic>[], 'total': 0, 'page': 1, 'page_size': 20};
    }
    if (parts.length == 5 &&
        ['sales', 'expenses'].contains(parts[4]) &&
        (uri.queryParameters['page'] ?? '1') == '1') {
      final type = parts[4] == 'sales'
          ? OperationType.createSale
          : OperationType.createExpense;
      final serverOperations = (result['items'] as List)
          .map((i) => i['client_operation_id'])
          .toSet();
      final pending = (await db.operations(user, business)).where(
        (o) =>
            o.type == type &&
            o.payloadVersion == 1 &&
            o.preview['_invalid_local_payload'] != true &&
            uri.queryParameters['status'] == null &&
            (uri.queryParameters['category'] == null ||
                o.preview['category'] == uri.queryParameters['category']) &&
            o.state != SyncState.synced &&
            o.state != SyncState.cancelled &&
            !serverOperations.contains(o.id),
      );
      final search = (uri.queryParameters['search'] ?? '').toLowerCase();
      final local = pending
          .where(
            (o) =>
                search.isEmpty ||
                '${o.preview['sale_number']} ${o.preview['description']}'
                    .toLowerCase()
                    .contains(search),
          )
          .map((o) => {...o.preview, 'local_sync_state': o.state.name})
          .toList();
      result['items'] = [...local, ...result['items'] as List];
      result['total'] = (result['total'] as int) + local.length;
    }
    return result;
  }

  Future<void> refreshProducts(String business) async {
    if (_catalogFlight != null) {
      await _catalogFlight;
      if (_catalogBusiness == business) return;
    }
    _catalogBusiness = business;
    _catalogFlight = _fetchProducts(business);
    try {
      await _catalogFlight;
    } finally {
      _catalogFlight = null;
    }
  }

  Future<void> _fetchProducts(String business) async {
    final user = await account();
    final items = <Map<String, dynamic>>[];
    for (var page = 1; ; page++) {
      final data = await super.getJson(
        '/api/v1/businesses/$business/products?page=$page&page_size=100',
      );
      final batch = (data['items'] as List).cast<Map<String, dynamic>>();
      items.addAll(batch);
      if (items.length >= (data['total'] as int)) break;
      if (batch.isEmpty) {
        throw const ApiException(
          'Product catalogue changed during refresh. Please refresh again.',
          statusCode: 503,
        );
      }
    }
    if (await account() != user) throw const SessionExpiredException();
    await db.cache(user, business, 'catalog', items);
    online = true;
  }

  Future<Map<String, dynamic>> products(
    String business,
    Map<String, String> query,
  ) async {
    final user = await account();
    try {
      if (online) await refreshProducts(business);
    } on Object catch (e) {
      if (!transient(e)) rethrow;
      online = false;
    }
    final cache = await db.readCache(user, business, 'catalog');
    if (cache == null) {
      throw const ApiException('Connect to the internet to load products.');
    }
    lastCacheRead = cache.updatedAt;
    final reserved = <String, int>{};
    for (final op in await db.operations(user, business)) {
      if (op.type != OperationType.createSale ||
          !op.reservesStock ||
          op.payloadVersion != 1 ||
          op.payload['items'] is! List) {
        continue;
      }
      for (final item in op.payload['items'] as List) {
        reserved.update(
          item['product_id'] as String,
          (n) => n + Quantity.parse(item['quantity'] as String).thousandths,
          ifAbsent: () =>
              Quantity.parse(item['quantity'] as String).thousandths,
        );
      }
    }
    var items = (cache.data as List)
        .cast<Map<String, dynamic>>()
        .map((p) {
          final copy = Map<String, dynamic>.from(p);
          if (p['track_inventory'] == true) {
            final quantity = max(
              0,
              Quantity.parse(p['stock_quantity'] as String).thousandths -
                  (reserved[p['id']] ?? 0),
            );
            copy['stock_quantity'] = Quantity.fromThousandths(quantity)
                .apiValue;
            copy['is_low_stock'] =
                p['is_active'] == true &&
                quantity <=
                    Quantity.parse(p['low_stock_threshold'] as String)
                        .thousandths;
          }
          return copy;
        })
        .where((p) {
          final term = (query['search'] ?? '').toLowerCase();
          return (term.isEmpty ||
                  '${p['name']} ${p['sku'] ?? ''} ${p['barcode'] ?? ''}'
                      .toLowerCase()
                      .contains(term)) &&
              (query['low_stock'] != 'true' || p['is_low_stock'] == true);
        })
        .toList();
    final page = int.tryParse(query['page'] ?? '1') ?? 1,
        size = int.tryParse(query['page_size'] ?? '20') ?? 20;
    changed();
    return {
      'items': items.skip((page - 1) * size).take(size).toList(),
      'page': page,
      'page_size': size,
      'total': items.length,
    };
  }

  Future<void> verifyCapture(
    String user,
    String business,
    OperationType type,
    Map<String, dynamic> payload,
  ) async {
    final member = await db.readCache(
      user,
      business,
      '/api/v1/businesses/$business',
    );
    final commercial = await db.readCache(
      user,
      business,
      '/api/v1/businesses/$business/commercial-status',
    );
    if (!db.durableStorage) {
      throw const ApiException(
        'This browser cannot safely preserve offline transactions. Use the Android app or a browser with persistent storage.',
      );
    }
    final now = DateTime.now().toUtc();
    bool recent(CachedRead? c) =>
        c != null &&
        !now.isBefore(c.updatedAt) &&
        now.difference(c.updatedAt) <= authorizationValidity;
    if (!recent(member) || !recent(commercial)) {
      throw const ApiException(
        'Connect to the internet to verify your subscription before recording new transactions.',
      );
    }
    final status = commercial!.data as Map;
    final role = (member!.data as Map)['role'];
    if (!['OWNER', 'MANAGER', 'CASHIER'].contains(role)) {
      throw const ApiException('Your permission needs verification.');
    }
    if (!['ACTIVE', 'GRACE_PERIOD'].contains(status['subscription_status']) ||
        status['writes_allowed'] != true) {
      throw const ApiException(
        'Your subscription does not allow new transactions.',
      );
    }
    if (type == OperationType.createExpense &&
        role == 'CASHIER' &&
        payload['notes'] != null) {
      throw const ApiException('Cashiers cannot add internal expense notes.');
    }
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = true,
  }) async {
    final parts = Uri.parse(path).pathSegments;
    final eligible =
        authenticated &&
        parts.length == 5 &&
        parts[2] == 'businesses' &&
        ['sales', 'expenses'].contains(parts[4]);
    if (!eligible || body['payment_method'] == 'CUSTOMER_DEBT') {
      if (authenticated) {
        await requireOnline(
          message: body['payment_method'] == 'CUSTOMER_DEBT'
              ? 'Customer Credit requires an internet connection.'
              : 'This action requires an internet connection.',
        );
      }
      try {
        final result = await super.postJson(
          path,
          body,
          authenticated: authenticated,
        );
        if (authenticated && businessOf(path).isNotEmpty) {
          await db.invalidate(await account(), businessOf(path));
        }
        online = true;
        changed();
        return result;
      } on Object catch (e) {
        if (transient(e)) {
          online = false;
          changed();
        }
        rethrow;
      }
    }
    final user = await account(), business = parts[3];
    final type = parts[4] == 'sales'
        ? OperationType.createSale
        : OperationType.createExpense;
    final existing = await db.operation(
      user,
      business,
      body['client_operation_id'] as String,
    );
    if (existing != null) {
      final retry = jsonDecode(jsonEncode(body)) as Map<String, dynamic>;
      if (type == OperationType.createSale) {
        for (final item in retry['items'] as List) {
          final originals = (existing.payload['items'] as List).where(
            (i) => i['product_id'] == item['product_id'],
          );
          if (originals.isNotEmpty) {
            item['sale_version'] ??= originals.first['sale_version'];
          }
        }
      }
      if (fingerprint(retry) != fingerprint(existing.payload)) {
        throw const ApiException(
          'This operation was already saved with different data. Review the saved transaction.',
        );
      }
      if (existing.state == SyncState.synced) {
        return getJson('$path/${existing.serverId}');
      }
      return {...existing.preview, 'local_sync_state': existing.state.name};
    }
    await db.transaction(() async {
      await verifyCapture(user, business, type, body);
      final payload = jsonDecode(jsonEncode(body)) as Map<String, dynamic>;
      final preview = await makePreview(user, business, type, payload);
      await db.enqueue(user, business, type, payload, preview);
    });
    changed();
    if (online) {
      await syncPendingOperations(business, manual: true);
    }
    final saved = (await db.operation(
      user,
      business,
      body['client_operation_id'] as String,
    ))!;
    if (saved.state == SyncState.synced) {
      return getJson('$path/${saved.serverId}');
    }
    return {...saved.preview, 'local_sync_state': saved.state.name};
  }

  @override
  Future<Map<String, dynamic>> patchJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    await requireOnline();
    final result = await super.patchJson(path, body);
    if (businessOf(path).isNotEmpty) {
      await db.invalidate(await account(), businessOf(path));
    }
    return result;
  }

  Future<Map<String, dynamic>> makePreview(
    String user,
    String business,
    OperationType type,
    Map<String, dynamic> payload,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String(),
        id = payload['client_operation_id'] as String;
    final person = await db.readCache(user, '', '/api/v1/auth/me');
    final name = (person?.data as Map?)?['full_name'] ?? 'Team member';
    if (type == OperationType.createExpense) {
      final amount = Money.parse(payload['amount'] as String, 'ZMW');
      if (amount.minorUnits <= 0) {
        throw const ApiException('Expense amount must be greater than zero.');
      }
      return {
        ...payload,
        'id': 'local-$id',
        'business_id': business,
        'status': 'RECORDED',
        'created_at': now,
        'recorded_by_user_id': user,
        'recorded_by_name': name,
        'local_sync_state': 'pending',
      };
    }
    final catalog = await db.readCache(user, business, 'catalog');
    if (catalog == null) {
      throw const ApiException(
        'Connect to the internet to load products before recording a sale.',
      );
    }
    final products = {
      for (final p in (catalog.data as List).cast<Map<String, dynamic>>())
        p['id']: p,
    };
    final reserved = <String, int>{};
    for (final op in await db.operations(user, business)) {
      if (op.type == OperationType.createSale &&
          op.reservesStock &&
          op.payloadVersion == 1 &&
          op.payload['items'] is List) {
        for (final i in op.payload['items'] as List) {
          reserved.update(
            i['product_id'] as String,
            (q) => q + Quantity.parse(i['quantity'] as String).thousandths,
            ifAbsent: () => Quantity.parse(i['quantity'] as String).thousandths,
          );
        }
      }
    }
    final lines = <Map<String, dynamic>>[];
    var subtotal = Money.fromMinorUnits(0, 'ZMW');
    for (final item in payload['items'] as List) {
      final p = products[item['product_id']];
      if (p == null || p['is_active'] != true || p['sale_version'] == null) {
        throw const ApiException(
          'Refresh products before recording this sale.',
        );
      }
      if (item['sale_version'] != null &&
          item['sale_version'] != p['sale_version']) {
        throw const ApiException('Product price changed. Review your cart.');
      }
      item['sale_version'] = p['sale_version'];
      final q = Quantity.parse(item['quantity'] as String);
      final used = reserved[item['product_id']] ?? 0;
      if (q.thousandths <= 0 ||
          (p['track_inventory'] == true &&
              q.thousandths + used >
                  Quantity.parse(p['stock_quantity'] as String).thousandths)) {
        throw const ApiException(
          'Insufficient projected stock. Review your cart.',
        );
      }
      reserved[item['product_id'] as String] = used + q.thousandths;
      final price = Money.parse(p['selling_price'] as String, 'ZMW');
      final total = price.multiplyThousandths(q.thousandths);
      subtotal = subtotal + total;
      lines.add({
        'product_name_snapshot': p['name'],
        'sku_snapshot': p['sku'],
        'quantity': q.apiValue,
        'unit_selling_price': price.decimal,
        'line_subtotal': total.decimal,
      });
    }
    final discount = Money.parse(
      payload['discount_amount'] as String? ?? '0.00',
      'ZMW',
    );
    if (discount.minorUnits > subtotal.minorUnits) {
      throw const ApiException('Discount cannot exceed subtotal.');
    }
    return {
      ...payload,
      'id': 'local-$id',
      'business_id': business,
      'sale_number': 'Pending #${id.substring(0, min(8, id.length))}',
      'status': 'COMPLETED',
      'subtotal': subtotal.decimal,
      'total_amount': (subtotal - discount).decimal,
      'discount_amount': discount.decimal,
      'sold_at': now,
      'sold_by_name': name,
      'items': lines,
      'local_sync_state': 'pending',
    };
  }

  Future<Map<String, dynamic>> provisionalReceipt(QueuedOperation op) async {
    final b =
        (await db.readCache(
              op.userId,
              op.businessId,
              '/api/v1/businesses/${op.businessId}',
            ))?.data
            as Map?;
    final p = op.preview;
    return {
      ...p,
      'business_name': b?['name'] ?? 'Business',
      'business_phone': b?['phone_number'],
      'business_location': b?['location'],
      'currency': b?['currency'] ?? 'ZMW',
      'seller_name': p['sold_by_name'],
      'local_sync_state': op.state.name,
      'items': (p['items'] as List)
          .map(
            (i) => {
              'product_name': i['product_name_snapshot'],
              'sku': i['sku_snapshot'],
              'quantity': i['quantity'],
              'unit_price': i['unit_selling_price'],
              'line_total': i['line_subtotal'],
            },
          )
          .toList(),
    };
  }

  Future<void> syncPendingOperations(String business, {bool manual = false}) {
    _requested[business] = manual || (_requested[business] ?? false);
    return _flight ??= _drain().whenComplete(() => _flight = null);
  }

  Future<void> _drain() async {
    while (_requested.isNotEmpty) {
      final business = _requested.keys.first;
      final manual = _requested.remove(business)!;
      await _sync(business, manual);
    }
  }

  Future<void> _sync(String business, bool manual) async {
    String user;
    try {
      user = await account();
    } on SessionExpiredException {
      sessionRequired = true;
      changed();
      return;
    }
    final lease =
        '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}';
    if (!await db.acquireLease(user, business, lease)) return;
    syncing = true;
    changed();
    try {
      if (manual || !online) {
        await super.getJson('/api/v1/auth/me');
        online = true;
        sessionRequired = false;
      }
      await db.recover(user, business);
      for (var op in await db.operations(user, business)) {
        await db.renewLease(user, business, lease);
        if (await account() != user) break;
        if (op.state != SyncState.pending) continue;
        if (!manual &&
            op.nextRetry != null &&
            op.nextRetry! > DateTime.now().millisecondsSinceEpoch) {
          break;
        }
        if (op.payloadVersion != 1 ||
            op.payload['_invalid_local_payload'] == true ||
            op.payload['client_operation_id'] != op.id) {
          await db.transition(
            op,
            SyncState.failed,
            error: 'This saved transaction needs an app upgrade or support review.',
            code: 'PAYLOAD_VERSION',
          );
          continue;
        }
        await db.transition(op, SyncState.syncing);
        op = (await db.operation(user, business, op.id))!;
        Map<String, dynamic> response;
        try {
          // Explicit domain dispatch; original business and UUID always retained.
          final collection = switch (op.type) {
            OperationType.createSale => 'sales',
            OperationType.createExpense => 'expenses',
          };
          Map<String, dynamic>? recovered;
          if (op.attempts > 1) {
            try {
              recovered = await super.postJson(
                '/api/v1/businesses/${op.businessId}/$collection/reconcile',
                op.payload,
              );
            } on ApiException catch (e) {
              if (e.statusCode != 404) rethrow;
            }
          }
          response =
              recovered ??
              await super.postJson(
                '/api/v1/businesses/${op.businessId}/$collection',
                op.payload,
              );
          online = true;
        } on Object catch (e) {
          if (e is ApiException && e.statusCode == 401) {
            sessionRequired = true;
            await db.transition(
              op,
              SyncState.pending,
              error: 'Sign in to synchronize saved transactions.',
              code: 'AUTH_REQUIRED',
            );
            break;
          }
          if (transient(e)) {
            online = false;
            final seconds = min(900, 5 * (1 << min(op.attempts, 8)));
            await db.transition(
              op,
              SyncState.pending,
              error: 'Connection interrupted. Saved safely; retry later.',
              code: 'CONNECTION',
              retryAt: DateTime.now().add(Duration(seconds: seconds)),
            );
            break;
          }
          await db.transition(
            op,
            e is ApiException && [404, 409].contains(e.statusCode)
                ? SyncState.conflict
                : SyncState.failed,
            error: e is ApiException
                ? e.message
                : 'The saved transaction needs review.',
            code: e is ApiException
                ? 'HTTP_${e.statusCode}'
                : 'INVALID_RESPONSE',
          );
          continue;
        }
        // Persist acceptance before cache refresh. A refresh failure must never
        // reinterpret an accepted write as a failed transaction.
        final collection = op.type == OperationType.createSale
            ? 'sales'
            : 'expenses';
        await db.transaction(() async {
          final historyKey =
              '/api/v1/businesses/$business/$collection?page=1&page_size=20';
          final history = await db.readCache(user, business, historyKey);
          final old = history?.data as Map?;
          final rows = (old?['items'] as List? ?? [])
              .where(
                (item) =>
                    item['id'] != response['id'] &&
                    item['client_operation_id'] != op.id,
              )
              .toList();
          final alreadyPresent =
              (old?['items'] as List? ?? []).length != rows.length;
          await db.cache(user, business, historyKey, {
            'items': [response, ...rows].take(20).toList(),
            'total': (old?['total'] as int? ?? 0) + (alreadyPresent ? 0 : 1),
            'page': 1,
            'page_size': 20,
          });
          await db.cache(
            user,
            business,
            '/api/v1/businesses/$business/$collection/${response['id']}',
            response,
          );
          await db.transition(
            op,
            SyncState.synced,
            serverId: response['id'] as String,
          );
          if (op.type == OperationType.createSale) {
            final catalog = await db.readCache(user, business, 'catalog');
            if (catalog != null) {
              final products = (catalog.data as List)
                  .cast<Map<String, dynamic>>();
              for (final item in op.payload['items'] as List) {
                for (final p in products.where(
                  (p) =>
                      p['id'] == item['product_id'] &&
                      p['track_inventory'] == true,
                )) {
                  p['stock_quantity'] = Quantity.fromThousandths(
                    max(
                      0,
                      Quantity.parse(p['stock_quantity'] as String)
                              .thousandths -
                          Quantity.parse(item['quantity'] as String)
                              .thousandths,
                    ),
                  ).apiValue;
                }
              }
              await db.cache(
                user,
                business,
                'catalog',
                products,
                at: catalog.updatedAt,
              );
            }
          }
          await db.invalidate(user, business);
        });
        changed();
      }
      if (online && await account() == user) {
        await refreshCore(business);
        if (!online || await account() != user) return;
        lastSync = DateTime.now().toUtc();
        await db.cache(
          user,
          business,
          'last_sync',
          lastSync!.toIso8601String(),
        );
        await db.prune(user, business);
      }
    } on SessionExpiredException {
      sessionRequired = true;
    } on Object catch (e) {
      if (transient(e)) online = false;
    } finally {
      await db.releaseLease(user, business, lease);
      syncing = false;
      changed();
    }
  }

  Future<void> refreshCore(String business) async {
    await getJsonList('/api/v1/businesses');
    await getJson('/api/v1/businesses/$business/commercial-status');
    await refreshProducts(business);
    for (final collection in ['customers', 'debts', 'sales', 'expenses']) {
      final path =
          '/api/v1/businesses/$business/$collection?page=1&page_size=20';
      final page = await getJson(path);
      for (final item in page['items'] as List) {
        final id = item['id'] as String;
        if (id.startsWith('local-')) continue;
        await getJson('/api/v1/businesses/$business/$collection/$id');
        if (collection == 'debts') {
          await getJson(
            '/api/v1/businesses/$business/debts/$id/payments?page=1&page_size=20',
          );
        }
        if (collection == 'sales') {
          await getJson('/api/v1/businesses/$business/sales/$id/receipt');
        }
      }
    }
    for (final range in ['today', 'week', 'month']) {
      await getJson('/api/v1/businesses/$business/dashboard?range=$range');
    }
    await getJson('/api/v1/businesses/$business/debts/summary');
  }

  Future<void> cancel(QueuedOperation op) async {
    if (await account() != op.userId || syncing) {
      throw const ApiException('Wait until synchronization finishes.');
    }
    // A lost response may already have committed. Never cancel ambiguous attempts.
    if (op.attempts > 0 && (!op.needsReview || op.attempts > 1)) {
      throw const ApiException(
        'This transaction may already be accepted. Connect and sync to check its status before cancelling.',
      );
    }
    await db.transition(op, SyncState.cancelled);
    changed();
  }
}

import 'dart:math';

import 'package:zedbiz/core/network/api_client.dart';
import 'package:zedbiz/features/products/domain/product.dart';

abstract interface class ProductGateway {
  Future<ProductPage> list(
    String businessId, {
    int page = 1,
    String? search,
    bool lowStock = false,
  });
  Future<Product> create(String businessId, Map<String, dynamic> payload);
  Future<Map<String, dynamic>> stock(
    String businessId,
    String productId,
    String action,
    Map<String, dynamic> payload,
  );
  Future<List<InventoryMovement>> history(String businessId, String productId);
  Future<Product> setActive(String businessId, String productId, bool active);
}

class UnavailableProductGateway implements ProductGateway {
  const UnavailableProductGateway();
  Never _fail() => throw StateError('Products are not configured.');
  @override
  Future<ProductPage> list(
    String businessId, {
    int page = 1,
    String? search,
    bool lowStock = false,
  }) async => _fail();
  @override
  Future<Product> create(
    String businessId,
    Map<String, dynamic> payload,
  ) async => _fail();
  @override
  Future<Map<String, dynamic>> stock(
    String businessId,
    String productId,
    String action,
    Map<String, dynamic> payload,
  ) async => _fail();
  @override
  Future<List<InventoryMovement>> history(
    String businessId,
    String productId,
  ) async => _fail();
  @override
  Future<Product> setActive(
    String businessId,
    String productId,
    bool active,
  ) async => _fail();
}

class ProductRepository implements ProductGateway {
  ProductRepository(this._api);
  final ApiClient _api;
  String _base(String id) => '/api/v1/businesses/$id/products';
  @override
  Future<ProductPage> list(
    String id, {
    int page = 1,
    String? search,
    bool lowStock = false,
  }) async {
    final query = <String, String>{'page': '$page', 'page_size': '20'};
    if (lowStock) query['low_stock'] = 'true';
    if (search?.trim().isNotEmpty == true) query['search'] = search!.trim();
    final path = Uri(path: _base(id), queryParameters: query).toString();
    return ProductPage.fromJson(await _api.getJson(path));
  }

  @override
  Future<Product> create(String id, Map<String, dynamic> payload) async =>
      Product.fromJson(await _api.postJson(_base(id), payload));
  @override
  Future<Map<String, dynamic>> stock(
    String id,
    String productId,
    String action,
    Map<String, dynamic> payload,
  ) => _api.postJson('${_base(id)}/$productId/stock/$action', payload);
  @override
  Future<List<InventoryMovement>> history(String id, String productId) async {
    final json = await _api.getJson(
      '${_base(id)}/$productId/inventory-movements',
    );
    return (json['items'] as List)
        .map((e) => InventoryMovement.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Product> setActive(String id, String productId, bool active) async =>
      Product.fromJson(
        await _api.postJson(
          '${_base(id)}/$productId/${active ? 'reactivate' : 'deactivate'}',
          {},
        ),
      );
}

String newOperationId() {
  final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String h(int from, int to) => bytes
      .sublist(from, to)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${h(0, 4)}-${h(4, 6)}-${h(6, 8)}-${h(8, 10)}-${h(10, 16)}';
}

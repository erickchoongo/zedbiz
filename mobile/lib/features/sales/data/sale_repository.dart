import 'package:zedbiz/core/network/api_client.dart';
import 'package:zedbiz/features/sales/domain/sale.dart';

class SalePage {
  const SalePage(this.items, this.page, this.pageSize, this.total);
  final List<SaleSummary> items;
  final int page, pageSize, total;
}

abstract interface class SaleGateway {
  Future<SalePage> list(
    String businessId,
    String currency, {
    int page = 1,
    String? search,
    String? status,
  });
  Future<SaleDetail> create(
    String businessId,
    String currency,
    Map<String, dynamic> payload,
  );
  Future<SaleDetail> detail(String businessId, String saleId, String currency);
  Future<ReceiptData> receipt(String businessId, String saleId);
  Future<SaleDetail> voidSale(
    String businessId,
    String saleId,
    String currency, {
    required String operationId,
    required String reason,
  });
}

class UnavailableSaleGateway implements SaleGateway {
  const UnavailableSaleGateway();
  Never _fail() => throw StateError('Sales are not configured.');
  @override
  Future<SalePage> list(
    String a,
    String b, {
    int page = 1,
    String? search,
    String? status,
  }) async => _fail();
  @override
  Future<SaleDetail> create(String a, String b, Map<String, dynamic> c) async =>
      _fail();
  @override
  Future<SaleDetail> detail(String a, String b, String c) async => _fail();
  @override
  Future<ReceiptData> receipt(String a, String b) async => _fail();
  @override
  Future<SaleDetail> voidSale(
    String a,
    String b,
    String c, {
    required String operationId,
    required String reason,
  }) async => _fail();
}

class SaleRepository implements SaleGateway {
  SaleRepository(this._api);
  final ApiClient _api;
  String _base(String id) => '/api/v1/businesses/$id/sales';
  @override
  Future<SalePage> list(
    String id,
    String currency, {
    int page = 1,
    String? search,
    String? status,
  }) async {
    final q = <String, String>{'page': '$page', 'page_size': '20'};
    if (search?.trim().isNotEmpty == true) q['search'] = search!.trim();
    if (status != null) q['status'] = status;
    final json = await _api.getJson(
      Uri(path: _base(id), queryParameters: q).toString(),
    );
    return SalePage(
      (json['items'] as List)
          .map((e) => SaleSummary.fromJson(e as Map<String, dynamic>, currency))
          .toList(),
      json['page'] as int,
      json['page_size'] as int,
      json['total'] as int,
    );
  }

  @override
  Future<SaleDetail> create(
    String id,
    String currency,
    Map<String, dynamic> payload,
  ) async =>
      SaleDetail.fromJson(await _api.postJson(_base(id), payload), currency);
  @override
  Future<SaleDetail> detail(String id, String saleId, String currency) async =>
      SaleDetail.fromJson(await _api.getJson('${_base(id)}/$saleId'), currency);
  @override
  Future<ReceiptData> receipt(String id, String saleId) async =>
      ReceiptData.fromJson(await _api.getJson('${_base(id)}/$saleId/receipt'));
  @override
  Future<SaleDetail> voidSale(
    String id,
    String saleId,
    String currency, {
    required String operationId,
    required String reason,
  }) async => SaleDetail.fromJson(
    await _api.postJson('${_base(id)}/$saleId/void', {
      'client_operation_id': operationId,
      'reason': reason,
    }),
    currency,
  );
}

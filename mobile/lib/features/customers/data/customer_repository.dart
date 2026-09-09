import 'package:zedbiz/core/network/api_client.dart';
import 'package:zedbiz/features/customers/domain/customer.dart';

abstract interface class CustomerGateway {
  Future<CustomerPage> list(
    String businessId,
    String currency, {
    int page = 1,
    String? search,
    bool? active,
    bool outstandingOnly = false,
  });

  Future<CustomerDetail> create(
    String businessId,
    String currency,
    Map<String, dynamic> payload,
  );

  Future<CustomerDetail> detail(
    String businessId,
    String customerId,
    String currency,
  );

  Future<CustomerDetail> update(
    String businessId,
    String customerId,
    String currency,
    Map<String, dynamic> payload,
  );

  Future<CustomerDetail> setActive(
    String businessId,
    String customerId,
    String currency,
    bool active,
  );
}

class UnavailableCustomerGateway implements CustomerGateway {
  const UnavailableCustomerGateway();

  Never _fail() => throw StateError('Customers are not configured.');

  @override
  Future<CustomerPage> list(
    String businessId,
    String currency, {
    int page = 1,
    String? search,
    bool? active,
    bool outstandingOnly = false,
  }) async => _fail();

  @override
  Future<CustomerDetail> create(
    String businessId,
    String currency,
    Map<String, dynamic> payload,
  ) async => _fail();

  @override
  Future<CustomerDetail> detail(
    String businessId,
    String customerId,
    String currency,
  ) async => _fail();

  @override
  Future<CustomerDetail> update(
    String businessId,
    String customerId,
    String currency,
    Map<String, dynamic> payload,
  ) async => _fail();

  @override
  Future<CustomerDetail> setActive(
    String businessId,
    String customerId,
    String currency,
    bool active,
  ) async => _fail();
}

class CustomerRepository implements CustomerGateway {
  CustomerRepository(this._api);

  final ApiClient _api;

  String _base(String businessId) => '/api/v1/businesses/$businessId/customers';

  @override
  Future<CustomerPage> list(
    String businessId,
    String currency, {
    int page = 1,
    String? search,
    bool? active,
    bool outstandingOnly = false,
  }) async {
    final query = <String, String>{'page': '$page', 'page_size': '20'};
    if (search?.trim().isNotEmpty == true) {
      query['search'] = search!.trim();
    }
    if (active != null) query['is_active'] = '$active';
    if (outstandingOnly) query['outstanding_only'] = 'true';
    final path = Uri(
      path: _base(businessId),
      queryParameters: query,
    ).toString();
    return CustomerPage.fromJson(await _api.getJson(path), currency);
  }

  @override
  Future<CustomerDetail> create(
    String businessId,
    String currency,
    Map<String, dynamic> payload,
  ) async => CustomerDetail.fromJson(
    await _api.postJson(_base(businessId), payload),
    currency,
  );

  @override
  Future<CustomerDetail> detail(
    String businessId,
    String customerId,
    String currency,
  ) async => CustomerDetail.fromJson(
    await _api.getJson('${_base(businessId)}/$customerId'),
    currency,
  );

  @override
  Future<CustomerDetail> update(
    String businessId,
    String customerId,
    String currency,
    Map<String, dynamic> payload,
  ) async => CustomerDetail.fromJson(
    await _api.patchJson('${_base(businessId)}/$customerId', payload),
    currency,
  );

  @override
  Future<CustomerDetail> setActive(
    String businessId,
    String customerId,
    String currency,
    bool active,
  ) async => CustomerDetail.fromJson(
    await _api.postJson(
      '${_base(businessId)}/$customerId/${active ? 'reactivate' : 'deactivate'}',
      const {},
    ),
    currency,
  );
}

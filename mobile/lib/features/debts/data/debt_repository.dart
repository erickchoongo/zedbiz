import 'package:zedbiz/core/network/api_client.dart';
import 'package:zedbiz/features/debts/domain/debt.dart';

abstract interface class DebtGateway {
  Future<DebtPage> list(
    String businessId,
    String currency, {
    int page = 1,
    String? search,
    String? status,
    bool overdueOnly = false,
    String? customerId,
  });

  Future<DebtMetrics> summary(String businessId, String currency);

  Future<DebtDetail> detail(String businessId, String debtId, String currency);

  Future<DebtPaymentPage> payments(
    String businessId,
    String debtId,
    String currency, {
    int page = 1,
  });

  Future<RepaymentResult> recordPayment(
    String businessId,
    String debtId,
    String currency,
    Map<String, dynamic> payload,
  );

  Future<DebtReminder> reminder(
    String businessId,
    String debtId,
    String currency,
  );
}

class UnavailableDebtGateway implements DebtGateway {
  const UnavailableDebtGateway();

  Never _fail() => throw StateError('Customer credit is not configured.');

  @override
  Future<DebtPage> list(
    String businessId,
    String currency, {
    int page = 1,
    String? search,
    String? status,
    bool overdueOnly = false,
    String? customerId,
  }) async => _fail();

  @override
  Future<DebtMetrics> summary(String businessId, String currency) async =>
      _fail();

  @override
  Future<DebtDetail> detail(
    String businessId,
    String debtId,
    String currency,
  ) async => _fail();

  @override
  Future<DebtPaymentPage> payments(
    String businessId,
    String debtId,
    String currency, {
    int page = 1,
  }) async => _fail();

  @override
  Future<RepaymentResult> recordPayment(
    String businessId,
    String debtId,
    String currency,
    Map<String, dynamic> payload,
  ) async => _fail();

  @override
  Future<DebtReminder> reminder(
    String businessId,
    String debtId,
    String currency,
  ) async => _fail();
}

class DebtRepository implements DebtGateway {
  DebtRepository(this._api);

  final ApiClient _api;

  String _base(String businessId) => '/api/v1/businesses/$businessId/debts';

  @override
  Future<DebtPage> list(
    String businessId,
    String currency, {
    int page = 1,
    String? search,
    String? status,
    bool overdueOnly = false,
    String? customerId,
  }) async {
    final query = <String, String>{'page': '$page', 'page_size': '20'};
    if (search?.trim().isNotEmpty == true) {
      query['search'] = search!.trim();
    }
    if (status != null) query['status'] = status;
    if (overdueOnly) query['overdue_only'] = 'true';
    if (customerId != null) query['customer_id'] = customerId;
    final path = Uri(
      path: _base(businessId),
      queryParameters: query,
    ).toString();
    return DebtPage.fromJson(await _api.getJson(path), currency);
  }

  @override
  Future<DebtMetrics> summary(String businessId, String currency) async =>
      DebtMetrics.fromJson(
        await _api.getJson('${_base(businessId)}/summary'),
        currency,
      );

  @override
  Future<DebtDetail> detail(
    String businessId,
    String debtId,
    String currency,
  ) async => DebtDetail.fromJson(
    await _api.getJson('${_base(businessId)}/$debtId'),
    currency,
  );

  @override
  Future<DebtPaymentPage> payments(
    String businessId,
    String debtId,
    String currency, {
    int page = 1,
  }) async {
    final path = Uri(
      path: '${_base(businessId)}/$debtId/payments',
      queryParameters: {'page': '$page', 'page_size': '20'},
    ).toString();
    return DebtPaymentPage.fromJson(await _api.getJson(path), currency);
  }

  @override
  Future<RepaymentResult> recordPayment(
    String businessId,
    String debtId,
    String currency,
    Map<String, dynamic> payload,
  ) async => RepaymentResult.fromJson(
    await _api.postJson('${_base(businessId)}/$debtId/payments', payload),
    currency,
  );

  @override
  Future<DebtReminder> reminder(
    String businessId,
    String debtId,
    String currency,
  ) async => DebtReminder.fromJson(
    await _api.getJson('${_base(businessId)}/$debtId/reminder'),
    currency,
  );
}

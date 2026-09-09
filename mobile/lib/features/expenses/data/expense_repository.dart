import 'package:zedbiz/core/network/api_client.dart';
import 'package:zedbiz/features/expenses/domain/expense.dart';

abstract interface class ExpenseGateway {
  Future<ExpensePage> list(
    String businessId,
    String currency, {
    int page = 1,
    String? search,
    ExpenseCategory? category,
    ExpenseStatus? status,
    DateTime? dateFrom,
    DateTime? dateTo,
  });
  Future<ExpenseRecord> create(
    String businessId,
    String currency,
    Map<String, dynamic> payload,
  );
  Future<ExpenseRecord> detail(
    String businessId,
    String expenseId,
    String currency,
  );
  Future<ExpenseRecord> voidExpense(
    String businessId,
    String expenseId,
    String currency,
    Map<String, dynamic> payload,
  );
}

class UnavailableExpenseGateway implements ExpenseGateway {
  const UnavailableExpenseGateway();
  Never _fail() => throw StateError('Expenses are not configured.');
  @override
  Future<ExpenseRecord> create(
    String a,
    String b,
    Map<String, dynamic> c,
  ) async => _fail();
  @override
  Future<ExpenseRecord> detail(String a, String b, String c) async => _fail();
  @override
  Future<ExpensePage> list(
    String a,
    String b, {
    int page = 1,
    String? search,
    ExpenseCategory? category,
    ExpenseStatus? status,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async => _fail();
  @override
  Future<ExpenseRecord> voidExpense(
    String a,
    String b,
    String c,
    Map<String, dynamic> d,
  ) async => _fail();
}

class ExpenseRepository implements ExpenseGateway {
  ExpenseRepository(this._api);
  final ApiClient _api;
  String _base(String id) => '/api/v1/businesses/$id/expenses';

  @override
  Future<ExpensePage> list(
    String businessId,
    String currency, {
    int page = 1,
    String? search,
    ExpenseCategory? category,
    ExpenseStatus? status,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final query = <String, String>{'page': '$page', 'page_size': '20'};
    if (search?.trim().isNotEmpty == true) query['search'] = search!.trim();
    if (category != null) query['category'] = expenseCategoryApi(category);
    if (status != null) query['status'] = status.name.toUpperCase();
    if (dateFrom != null) {
      query['date_from'] = dateFrom.toIso8601String().substring(0, 10);
    }
    if (dateTo != null) {
      query['date_to'] = dateTo.toIso8601String().substring(0, 10);
    }
    final path = Uri(
      path: _base(businessId),
      queryParameters: query,
    ).toString();
    return ExpensePage.fromJson(await _api.getJson(path), currency);
  }

  @override
  Future<ExpenseRecord> create(
    String businessId,
    String currency,
    Map<String, dynamic> payload,
  ) async => ExpenseRecord.fromJson(
    await _api.postJson(_base(businessId), payload),
    currency,
  );

  @override
  Future<ExpenseRecord> detail(
    String businessId,
    String expenseId,
    String currency,
  ) async => ExpenseRecord.fromJson(
    await _api.getJson('${_base(businessId)}/$expenseId'),
    currency,
  );

  @override
  Future<ExpenseRecord> voidExpense(
    String businessId,
    String expenseId,
    String currency,
    Map<String, dynamic> payload,
  ) async => ExpenseRecord.fromJson(
    await _api.postJson('${_base(businessId)}/$expenseId/void', payload),
    currency,
  );
}

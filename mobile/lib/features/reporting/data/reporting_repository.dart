import 'package:zedbiz/core/network/api_client.dart';
import 'package:zedbiz/features/reporting/domain/report.dart';

abstract interface class ReportingGateway {
  Future<DashboardData> dashboard(
    String businessId,
    ReportRange range, {
    DateTime? dateFrom,
    DateTime? dateTo,
  });
  Future<SalesReport> sales(
    String businessId,
    ReportRange range, {
    DateTime? dateFrom,
    DateTime? dateTo,
  });
  Future<ExpensesReport> expenses(
    String businessId,
    ReportRange range, {
    DateTime? dateFrom,
    DateTime? dateTo,
  });
  Future<PerformanceReport> performance(
    String businessId,
    ReportRange range, {
    DateTime? dateFrom,
    DateTime? dateTo,
  });
}

class UnavailableReportingGateway implements ReportingGateway {
  const UnavailableReportingGateway();
  Never _fail() => throw StateError('Reports are not configured.');
  @override
  Future<DashboardData> dashboard(
    String a,
    ReportRange b, {
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async => _fail();
  @override
  Future<ExpensesReport> expenses(
    String a,
    ReportRange b, {
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async => _fail();
  @override
  Future<PerformanceReport> performance(
    String a,
    ReportRange b, {
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async => _fail();
  @override
  Future<SalesReport> sales(
    String a,
    ReportRange b, {
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async => _fail();
}

class ReportingRepository implements ReportingGateway {
  ReportingRepository(this._api);
  final ApiClient _api;
  String _base(String id) => '/api/v1/businesses/$id';
  String _query(
    String path,
    ReportRange range,
    DateTime? dateFrom,
    DateTime? dateTo,
  ) {
    final query = range == ReportRange.custom
        ? {
            'date_from': dateFrom!.toIso8601String().substring(0, 10),
            'date_to': dateTo!.toIso8601String().substring(0, 10),
          }
        : {'range': range.name};
    return Uri(path: path, queryParameters: query).toString();
  }

  @override
  Future<DashboardData> dashboard(
    String id,
    ReportRange range, {
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async => DashboardData.fromJson(
    await _api.getJson(
      _query('${_base(id)}/dashboard', range, dateFrom, dateTo),
    ),
  );
  @override
  Future<SalesReport> sales(
    String id,
    ReportRange range, {
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async => SalesReport.fromJson(
    await _api.getJson(
      _query('${_base(id)}/reports/sales', range, dateFrom, dateTo),
    ),
  );
  @override
  Future<ExpensesReport> expenses(
    String id,
    ReportRange range, {
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async => ExpensesReport.fromJson(
    await _api.getJson(
      _query('${_base(id)}/reports/expenses', range, dateFrom, dateTo),
    ),
  );
  @override
  Future<PerformanceReport> performance(
    String id,
    ReportRange range, {
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async => PerformanceReport.fromJson(
    await _api.getJson(
      _query('${_base(id)}/reports/performance', range, dateFrom, dateTo),
    ),
  );
}

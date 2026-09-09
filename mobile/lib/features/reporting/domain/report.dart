import 'package:zedbiz/features/commercial/domain/money.dart';
import 'package:zedbiz/features/expenses/domain/expense.dart';

enum ReportRange { today, yesterday, week, month, custom }

String reportRangeLabel(ReportRange value) => switch (value) {
  ReportRange.today => 'Today',
  ReportRange.yesterday => 'Yesterday',
  ReportRange.week => 'Week',
  ReportRange.month => 'Month',
  ReportRange.custom => 'Custom',
};

class ReportPeriod {
  const ReportPeriod({
    required this.range,
    required this.dateFrom,
    required this.dateTo,
    required this.timezone,
  });

  factory ReportPeriod.fromJson(Map<String, dynamic> json) => ReportPeriod(
    range: json['range'] as String,
    dateFrom: DateTime.parse(json['date_from'] as String),
    dateTo: DateTime.parse(json['date_to'] as String),
    timezone: json['timezone'] as String,
  );

  final String range;
  final DateTime dateFrom;
  final DateTime dateTo;
  final String timezone;
}

class DashboardSale {
  const DashboardSale({
    required this.id,
    required this.number,
    required this.total,
    required this.paymentMethod,
    required this.soldAt,
    required this.status,
  });

  factory DashboardSale.fromJson(Map<String, dynamic> json, String currency) =>
      DashboardSale(
        id: json['id'] as String,
        number: json['sale_number'] as String,
        total: Money.parse(json['total_amount'] as String, currency),
        paymentMethod: json['payment_method'] as String,
        soldAt: DateTime.parse(json['sold_at'] as String),
        status: json['status'] as String,
      );

  final String id;
  final String number;
  final Money total;
  final String paymentMethod;
  final DateTime soldAt;
  final String status;
}

class DashboardExpense {
  const DashboardExpense({
    required this.id,
    required this.description,
    required this.category,
    required this.amount,
    required this.expenseDate,
    required this.paymentMethod,
  });

  factory DashboardExpense.fromJson(
    Map<String, dynamic> json,
    String currency,
  ) => DashboardExpense(
    id: json['id'] as String,
    description: json['description'] as String,
    category: expenseCategoryFromApi(json['category'] as String),
    amount: Money.parse(json['amount'] as String, currency),
    expenseDate: DateTime.parse(json['expense_date'] as String),
    paymentMethod: json['payment_method'] as String,
  );

  final String id;
  final String description;
  final ExpenseCategory category;
  final Money amount;
  final DateTime expenseDate;
  final String paymentMethod;
}

class DashboardData {
  const DashboardData({
    required this.period,
    required this.grossSales,
    required this.salesCount,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.recentSales,
    required this.recentExpenses,
    this.grossProfit,
    this.totalExpenses,
    this.afterExpenses,
    this.currentOutstandingDebt,
    this.overdueDebt,
  });

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    final currency = json['currency'] as String;
    Money? optional(String key) =>
        json[key] == null ? null : Money.parse(json[key] as String, currency);
    return DashboardData(
      period: ReportPeriod.fromJson(json['period'] as Map<String, dynamic>),
      grossSales: Money.parse(json['gross_sales'] as String, currency),
      salesCount: json['sales_count'] as int,
      grossProfit: optional('gross_profit'),
      totalExpenses: optional('total_expenses'),
      afterExpenses: optional('net_operating_result'),
      currentOutstandingDebt: optional('outstanding_customer_debt'),
      overdueDebt: optional('overdue_customer_debt'),
      lowStockCount: json['low_stock_count'] as int,
      outOfStockCount: json['out_of_stock_count'] as int,
      recentSales: (json['recent_sales'] as List<dynamic>)
          .map(
            (item) =>
                DashboardSale.fromJson(item as Map<String, dynamic>, currency),
          )
          .toList(),
      recentExpenses: json['recent_expenses'] == null
          ? null
          : (json['recent_expenses'] as List<dynamic>)
                .map(
                  (item) => DashboardExpense.fromJson(
                    item as Map<String, dynamic>,
                    currency,
                  ),
                )
                .toList(),
    );
  }

  final ReportPeriod period;
  final Money grossSales;
  final int salesCount;
  final Money? grossProfit;
  final Money? totalExpenses;
  final Money? afterExpenses;
  final Money? currentOutstandingDebt;
  final Money? overdueDebt;
  final int lowStockCount;
  final int outOfStockCount;
  final List<DashboardSale> recentSales;
  final List<DashboardExpense>? recentExpenses;
}

class ReportBreakdown {
  const ReportBreakdown({
    required this.label,
    required this.count,
    required this.amount,
  });
  final String label;
  final int count;
  final Money amount;
}

class DailyTotal {
  const DailyTotal({
    required this.date,
    required this.count,
    required this.amount,
  });
  final DateTime date;
  final int count;
  final Money amount;
}

class TopProduct {
  const TopProduct({
    required this.name,
    required this.quantity,
    required this.revenue,
  });
  final String name;
  final String quantity;
  final Money revenue;
}

class SalesReport {
  const SalesReport({
    required this.period,
    required this.grossSales,
    required this.salesCount,
    required this.averageSale,
    required this.paymentBreakdown,
    required this.salesByDay,
    required this.topProducts,
    this.grossProfit,
  });

  factory SalesReport.fromJson(Map<String, dynamic> json) {
    final currency = json['currency'] as String;
    return SalesReport(
      period: ReportPeriod.fromJson(json['period'] as Map<String, dynamic>),
      grossSales: Money.parse(json['gross_sales'] as String, currency),
      salesCount: json['sales_count'] as int,
      averageSale: Money.parse(json['average_sale_value'] as String, currency),
      grossProfit: json['gross_profit'] == null
          ? null
          : Money.parse(json['gross_profit'] as String, currency),
      paymentBreakdown: (json['payment_breakdown'] as List<dynamic>)
          .map(
            (item) => ReportBreakdown(
              label: (item as Map<String, dynamic>)['payment_method'] as String,
              count: item['sales_count'] as int,
              amount: Money.parse(item['amount'] as String, currency),
            ),
          )
          .toList(),
      salesByDay: (json['sales_by_day'] as List<dynamic>)
          .map(
            (item) => DailyTotal(
              date: DateTime.parse(
                (item as Map<String, dynamic>)['date'] as String,
              ),
              count: item['sales_count'] as int,
              amount: Money.parse(item['amount'] as String, currency),
            ),
          )
          .toList(),
      topProducts: (json['top_products'] as List<dynamic>)
          .map(
            (item) => TopProduct(
              name: (item as Map<String, dynamic>)['product_name'] as String,
              quantity: item['quantity'] as String,
              revenue: Money.parse(item['revenue'] as String, currency),
            ),
          )
          .toList(),
    );
  }

  final ReportPeriod period;
  final Money grossSales;
  final int salesCount;
  final Money averageSale;
  final Money? grossProfit;
  final List<ReportBreakdown> paymentBreakdown;
  final List<DailyTotal> salesByDay;
  final List<TopProduct> topProducts;
}

class ExpensesReport {
  const ExpensesReport({
    required this.period,
    required this.totalExpenses,
    required this.expenseCount,
    required this.categoryBreakdown,
    required this.paymentBreakdown,
    required this.expensesByDay,
    required this.largestExpenses,
  });

  factory ExpensesReport.fromJson(Map<String, dynamic> json) {
    final currency = json['currency'] as String;
    ReportBreakdown breakdown(Map<String, dynamic> item, String labelKey) =>
        ReportBreakdown(
          label: item[labelKey] as String,
          count: item['expense_count'] as int,
          amount: Money.parse(item['amount'] as String, currency),
        );
    return ExpensesReport(
      period: ReportPeriod.fromJson(json['period'] as Map<String, dynamic>),
      totalExpenses: Money.parse(json['total_expenses'] as String, currency),
      expenseCount: json['expense_count'] as int,
      categoryBreakdown: (json['category_breakdown'] as List<dynamic>)
          .map((item) => breakdown(item as Map<String, dynamic>, 'category'))
          .toList(),
      paymentBreakdown: (json['payment_breakdown'] as List<dynamic>)
          .map(
            (item) => breakdown(item as Map<String, dynamic>, 'payment_method'),
          )
          .toList(),
      expensesByDay: (json['expenses_by_day'] as List<dynamic>)
          .map(
            (item) => DailyTotal(
              date: DateTime.parse(
                (item as Map<String, dynamic>)['date'] as String,
              ),
              count: item['expense_count'] as int,
              amount: Money.parse(item['amount'] as String, currency),
            ),
          )
          .toList(),
      largestExpenses: (json['largest_expenses'] as List<dynamic>)
          .map(
            (item) => DashboardExpense.fromJson(
              item as Map<String, dynamic>,
              currency,
            ),
          )
          .toList(),
    );
  }

  final ReportPeriod period;
  final Money totalExpenses;
  final int expenseCount;
  final List<ReportBreakdown> categoryBreakdown;
  final List<ReportBreakdown> paymentBreakdown;
  final List<DailyTotal> expensesByDay;
  final List<DashboardExpense> largestExpenses;
}

class PerformanceReport {
  const PerformanceReport({
    required this.period,
    required this.grossSales,
    required this.grossProfit,
    required this.totalExpenses,
    required this.afterExpenses,
    required this.grossMarginPercent,
  });

  factory PerformanceReport.fromJson(Map<String, dynamic> json) {
    final currency = json['currency'] as String;
    return PerformanceReport(
      period: ReportPeriod.fromJson(json['period'] as Map<String, dynamic>),
      grossSales: Money.parse(json['gross_sales'] as String, currency),
      grossProfit: Money.parse(json['gross_profit'] as String, currency),
      totalExpenses: Money.parse(json['expenses'] as String, currency),
      afterExpenses: Money.parse(
        json['net_operating_result'] as String,
        currency,
      ),
      grossMarginPercent: json['gross_margin_percentage'] as String,
    );
  }

  final ReportPeriod period;
  final Money grossSales;
  final Money grossProfit;
  final Money totalExpenses;
  final Money afterExpenses;
  final String grossMarginPercent;
}

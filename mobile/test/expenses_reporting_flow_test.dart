import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zedbiz/app/app_controller.dart';
import 'package:zedbiz/core/network/api_exception.dart';
import 'package:zedbiz/features/businesses/domain/business_summary.dart';
import 'package:zedbiz/features/commercial/domain/money.dart';
import 'package:zedbiz/features/expenses/data/expense_repository.dart';
import 'package:zedbiz/features/expenses/domain/expense.dart';
import 'package:zedbiz/features/expenses/presentation/expenses_screen.dart';
import 'package:zedbiz/features/reporting/data/reporting_repository.dart';
import 'package:zedbiz/features/reporting/domain/report.dart';
import 'package:zedbiz/features/reporting/presentation/dashboard_screen.dart';
import 'package:zedbiz/features/reporting/presentation/reports_screen.dart';

import 'helpers/fakes.dart';

ExpenseRecord expenseRecord({String id = 'expense-1'}) => ExpenseRecord(
  id: id,
  businessId: testBusinessA.id,
  category: ExpenseCategory.utilities,
  description: 'Power bill',
  amount: Money.parse('75.50', 'ZMW'),
  paymentMethod: ExpensePaymentMethod.mtnMoney,
  expenseDate: DateTime(2026, 9, 3),
  recordedByUserId: testUser.id,
  recordedByName: testUser.fullName,
  status: ExpenseStatus.recorded,
  createdAt: DateTime.utc(2026, 9, 3),
);

class FakeExpenseGateway implements ExpenseGateway {
  final List<Map<String, dynamic>> payloads = [];
  bool failCreates = false;

  @override
  Future<ExpenseRecord> create(
    String businessId,
    String currency,
    Map<String, dynamic> payload,
  ) async {
    payloads.add({...payload});
    if (failCreates) throw const ApiException('Temporary failure');
    return expenseRecord();
  }

  @override
  Future<ExpenseRecord> detail(
    String businessId,
    String expenseId,
    String currency,
  ) async => expenseRecord(id: expenseId);

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
  }) async => ExpensePage(items: [expenseRecord()], page: 1, total: 1);

  @override
  Future<ExpenseRecord> voidExpense(
    String businessId,
    String expenseId,
    String currency,
    Map<String, dynamic> payload,
  ) async => expenseRecord(id: expenseId);
}

DashboardData dashboardData({bool privileged = true}) => DashboardData(
  period: ReportPeriod(
    range: 'today',
    dateFrom: DateTime(2026, 9, 3),
    dateTo: DateTime(2026, 9, 3),
    timezone: 'Africa/Lusaka',
  ),
  grossSales: Money.parse('450.00', 'ZMW'),
  salesCount: 2,
  grossProfit: privileged ? Money.parse('270.00', 'ZMW') : null,
  totalExpenses: privileged ? Money.parse('300.00', 'ZMW') : null,
  afterExpenses: privileged ? Money.parse('-30.00', 'ZMW') : null,
  currentOutstandingDebt: privileged ? Money.parse('100.00', 'ZMW') : null,
  overdueDebt: privileged ? Money.parse('0.00', 'ZMW') : null,
  lowStockCount: 2,
  outOfStockCount: 1,
  recentSales: const [],
  recentExpenses: privileged ? const [] : null,
);

class FakeReportingGateway implements ReportingGateway {
  FakeReportingGateway({DashboardData? data}) : data = data ?? dashboardData();

  final DashboardData data;
  final List<ReportRange> dashboardRanges = [];

  @override
  Future<DashboardData> dashboard(
    String businessId,
    ReportRange range, {
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    dashboardRanges.add(range);
    return data;
  }

  @override
  Future<ExpensesReport> expenses(
    String businessId,
    ReportRange range, {
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async => ExpensesReport(
    period: data.period,
    totalExpenses: Money.parse('300.00', 'ZMW'),
    expenseCount: 1,
    categoryBreakdown: [
      ReportBreakdown(
        label: 'UTILITIES',
        count: 1,
        amount: Money.parse('300.00', 'ZMW'),
      ),
    ],
    paymentBreakdown: [
      ReportBreakdown(
        label: 'CASH',
        count: 1,
        amount: Money.parse('300.00', 'ZMW'),
      ),
    ],
    expensesByDay: const [],
    largestExpenses: const [],
  );
  @override
  Future<PerformanceReport> performance(
    String businessId,
    ReportRange range, {
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async => PerformanceReport(
    period: data.period,
    grossSales: Money.parse('1500.00', 'ZMW'),
    grossProfit: Money.parse('900.00', 'ZMW'),
    totalExpenses: Money.parse('300.00', 'ZMW'),
    afterExpenses: Money.parse('600.00', 'ZMW'),
    grossMarginPercent: '60.00',
  );
  @override
  Future<SalesReport> sales(
    String businessId,
    ReportRange range, {
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async => SalesReport(
    period: data.period,
    grossSales: Money.parse('1500.00', 'ZMW'),
    salesCount: 2,
    averageSale: Money.parse('750.00', 'ZMW'),
    grossProfit: Money.parse('900.00', 'ZMW'),
    paymentBreakdown: [
      ReportBreakdown(
        label: 'CUSTOMER_DEBT',
        count: 1,
        amount: Money.parse('500.00', 'ZMW'),
      ),
    ],
    salesByDay: const [],
    topProducts: [
      TopProduct(
        name: 'Report Item',
        quantity: '3.000',
        revenue: Money.parse('1500.00', 'ZMW'),
      ),
    ],
  );
}

AppController controller({
  ExpenseGateway expenseGateway = const UnavailableExpenseGateway(),
  ReportingGateway reportingGateway = const UnavailableReportingGateway(),
  BusinessSummary business = testBusinessA,
}) {
  final result = AppController(
    authGateway: FakeAuthGateway(),
    businessGateway: FakeBusinessGateway(),
    commercialGateway: FakeCommercialGateway(),
    adminGateway: FakeAdminGateway(),
    expenseGateway: expenseGateway,
    reportingGateway: reportingGateway,
  );
  result.currentUser = testUser;
  result.selectedBusiness = business;
  result.commercialStatus = activeCommercialStatus;
  return result;
}

void main() {
  test('Money supports a signed After Expenses result exactly', () {
    final value = Money.parse('-30.01', 'ZMW');
    expect(value.minorUnits, -3001);
    expect(value.decimal, '-30.01');
    expect(
      (Money.parse('20.00', 'ZMW') - Money.parse('50.01', 'ZMW')).minorUnits,
      value.minorUnits,
    );
  });

  testWidgets('expense form keeps one operation ID across a retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = FakeExpenseGateway()..failCreates = true;
    await tester.pumpWidget(
      MaterialApp(
        home: ExpenseFormScreen(
          controller: controller(expenseGateway: gateway),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('expense-description')),
      'Power bill',
    );
    await tester.enterText(find.byKey(const Key('expense-amount')), '75.50');
    await tester.tap(find.byKey(const Key('submit-expense')));
    await tester.pumpAndSettle();
    expect(find.text('Temporary failure'), findsOneWidget);
    gateway.failCreates = false;
    await tester.tap(find.byKey(const Key('submit-expense')));
    await tester.pumpAndSettle();
    expect(gateway.payloads, hasLength(2));
    expect(
      gateway.payloads[0]['client_operation_id'],
      gateway.payloads[1]['client_operation_id'],
    );
  });

  testWidgets('dashboard shows role-shaped metrics and reloads period', (
    tester,
  ) async {
    final gateway = FakeReportingGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardScreen(
            controller: controller(reportingGateway: gateway),
            writable: true,
            onOpenSales: () {},
            onOpenProducts: () {},
            onNewSale: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('K450.00'), findsOneWidget);
    expect(find.text('K-30.00'), findsOneWidget);
    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    expect(gateway.dashboardRanges, [ReportRange.today, ReportRange.week]);
  });

  testWidgets('cashier report hub hides profit and expense reports', (
    tester,
  ) async {
    const cashier = BusinessSummary(
      id: 'business-a',
      name: 'Brown Tech',
      role: BusinessRole.cashier,
      currency: 'ZMW',
      timezone: 'Africa/Lusaka',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReportsScreen(
          controller: controller(business: cashier),
          writable: true,
        ),
      ),
    );
    expect(find.text('Sales report'), findsOneWidget);
    expect(find.text('Expense report'), findsNothing);
    expect(find.text('Performance'), findsNothing);
    expect(find.text('Customer credit'), findsOneWidget);
    expect(find.text('Inventory'), findsOneWidget);
  });

  testWidgets('cashier dashboard omits management financial values', (
    tester,
  ) async {
    const cashier = BusinessSummary(
      id: 'business-a',
      name: 'Brown Tech',
      role: BusinessRole.cashier,
      currency: 'ZMW',
      timezone: 'Africa/Lusaka',
    );
    final gateway = FakeReportingGateway(
      data: dashboardData(privileged: false),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardScreen(
            controller: controller(
              business: cashier,
              reportingGateway: gateway,
            ),
            writable: true,
            onOpenSales: () {},
            onOpenProducts: () {},
            onNewSale: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Gross sales'), findsOneWidget);
    expect(find.text('Gross profit'), findsNothing);
    expect(find.text('After expenses'), findsNothing);
    expect(find.text('Customer credit'), findsNothing);
    expect(find.text('Recent expenses'), findsNothing);
  });

  testWidgets('expired expense list remains readable without add controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ExpensesScreen(
          controller: controller(expenseGateway: FakeExpenseGateway()),
          writable: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Expenses are read-only'), findsOneWidget);
    expect(find.text('Power bill'), findsOneWidget);
    expect(find.byKey(const Key('add-expense')), findsNothing);
  });

  testWidgets(
    'expense void action is visible only to writable management roles',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ExpenseDetailScreen(
            controller: controller(expenseGateway: FakeExpenseGateway()),
            expense: expenseRecord(),
            writable: true,
          ),
        ),
      );
      expect(find.byKey(const Key('void-expense')), findsOneWidget);

      const cashier = BusinessSummary(
        id: 'business-a',
        name: 'Brown Tech',
        role: BusinessRole.cashier,
        currency: 'ZMW',
        timezone: 'Africa/Lusaka',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ExpenseDetailScreen(
            controller: controller(
              business: cashier,
              expenseGateway: FakeExpenseGateway(),
            ),
            expense: expenseRecord(),
            writable: true,
          ),
        ),
      );
      expect(find.byKey(const Key('void-expense')), findsNothing);
    },
  );

  testWidgets(
    'owner report views show sales, expense, and cautious performance values',
    (tester) async {
      final gateway = FakeReportingGateway();
      await tester.pumpWidget(
        MaterialApp(
          home: ReportsScreen(
            controller: controller(reportingGateway: gateway),
            writable: true,
          ),
        ),
      );
      await tester.tap(find.text('Sales report'));
      await tester.pumpAndSettle();
      expect(find.text('K1500.00'), findsWidgets);
      expect(find.text('CUSTOMER DEBT'), findsOneWidget);
      expect(find.text('Report Item'), findsOneWidget);
      expect(find.text('Custom'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Expense report'));
      await tester.pumpAndSettle();
      expect(find.text('K300.00'), findsWidgets);
      expect(find.text('UTILITIES'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Performance'));
      await tester.pumpAndSettle();
      expect(find.text('K600.00'), findsOneWidget);
      expect(find.textContaining('not a formal accounting'), findsOneWidget);
    },
  );
}

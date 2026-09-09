import 'package:zedbiz/core/offline/sync_status_screen.dart';
import 'package:flutter/material.dart';
import 'package:zedbiz/app/app_controller.dart';
import 'package:zedbiz/core/network/api_exception.dart';
import 'package:zedbiz/features/businesses/domain/business_summary.dart';
import 'package:zedbiz/features/debts/presentation/debts_screen.dart';
import 'package:zedbiz/features/products/presentation/products_screen.dart';
import 'package:zedbiz/features/reporting/domain/report.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({
    required this.controller,
    required this.writable,
    super.key,
  });
  final AppController controller;
  final bool writable;

  @override
  Widget build(BuildContext context) {
    final privileged =
        controller.selectedBusiness!.role != BusinessRole.cashier;
    return Scaffold(
      appBar: AppBar(title: const Text('Business reports')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Understand sales, costs, customer credit, and stock from the records in ZedBiz.',
          ),
          _tile(
            context,
            icon: Icons.trending_up,
            title: 'Sales report',
            subtitle: 'Sales totals, payment methods, daily activity, and top products.',
            kind: _ReportKind.sales,
          ),
          if (privileged)
            _tile(
              context,
              icon: Icons.payments_outlined,
              title: 'Expense report',
              subtitle: 'Recorded costs by category, payment method, and day.',
              kind: _ReportKind.expenses,
            ),
          if (privileged)
            _tile(
              context,
              icon: Icons.insights_outlined,
              title: 'Performance',
              subtitle:
                  'Gross sales, gross profit, expenses, and After Expenses.',
              kind: _ReportKind.performance,
            ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Customer credit'),
              subtitle: const Text(
                'Outstanding and overdue customer balances.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      DebtsScreen(controller: controller, writable: writable),
                ),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('Inventory'),
              subtitle: const Text(
                'Current products, stock levels, and low-stock warnings.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('Inventory report')),
                    body: ProductsScreen(
                      controller: controller,
                      writable: false,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required _ReportKind kind,
  }) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _ReportDetail(controller: controller, kind: kind),
        ),
      ),
    ),
  );
}

enum _ReportKind { sales, expenses, performance }

class _ReportDetail extends StatefulWidget {
  const _ReportDetail({required this.controller, required this.kind});
  final AppController controller;
  final _ReportKind kind;

  @override
  State<_ReportDetail> createState() => _ReportDetailState();
}

class _ReportDetailState extends State<_ReportDetail> {
  ReportRange _range = ReportRange.today;
  Object? _report;
  String? _error;
  bool _loading = true;
  DateTimeRange? _customDates;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final id = widget.controller.selectedBusiness!.id;
      final report = switch (widget.kind) {
        _ReportKind.sales => await widget.controller.reportingGateway.sales(
          id,
          _range,
          dateFrom: _customDates?.start,
          dateTo: _customDates?.end,
        ),
        _ReportKind.expenses =>
          await widget.controller.reportingGateway.expenses(
            id,
            _range,
            dateFrom: _customDates?.start,
            dateTo: _customDates?.end,
          ),
        _ReportKind.performance =>
          await widget.controller.reportingGateway.performance(
            id,
            _range,
            dateFrom: _customDates?.start,
            dateTo: _customDates?.end,
          ),
      };
      if (mounted) setState(() => _report = report);
    } on Object catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error is ApiException
            ? error.message
            : 'Could not load this report.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_title)),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CacheFreshness(
            client: widget.controller.offline,
            path: Uri(
              path:
                  '/api/v1/businesses/${widget.controller.selectedBusiness!.id}/reports/${widget.kind.name}',
              queryParameters:
                  _range == ReportRange.custom && _customDates != null
                  ? {
                      'date_from': _customDates!.start
                          .toIso8601String()
                          .substring(0, 10),
                      'date_to': _customDates!.end.toIso8601String().substring(
                        0,
                        10,
                      ),
                    }
                  : {'range': _range.name},
            ).toString(),
          ),
          SegmentedButton<ReportRange>(
            segments: const [
              ButtonSegment(value: ReportRange.today, label: Text('Today')),
              ButtonSegment(value: ReportRange.week, label: Text('Week')),
              ButtonSegment(value: ReportRange.month, label: Text('Month')),
              ButtonSegment(value: ReportRange.custom, label: Text('Custom')),
            ],
            selected: {_range},
            onSelectionChanged: (value) async {
              final selected = value.single;
              if (selected == ReportRange.custom) {
                final dates = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  initialDateRange: _customDates,
                );
                if (dates == null) return;
                setState(() => _customDates = dates);
              }
              setState(() => _range = selected);
              _load();
            },
          ),
          if (_range == ReportRange.custom && _customDates != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${_date(_customDates!.start)} – ${_date(_customDates!.end)}',
              ),
            ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                title: Text(_error!),
                trailing: IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ),
          if (_report case final SalesReport report) _sales(report),
          if (_report case final ExpensesReport report) _expenses(report),
          if (_report case final PerformanceReport report) _performance(report),
        ],
      ),
    ),
  );

  String get _title => switch (widget.kind) {
    _ReportKind.sales => 'Sales report',
    _ReportKind.expenses => 'Expense report',
    _ReportKind.performance => 'Performance',
  };

  Widget _sales(SalesReport report) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _summary([
        ('Gross sales', 'K${report.grossSales.decimal}'),
        ('Sales', '${report.salesCount}'),
        ('Average sale', 'K${report.averageSale.decimal}'),
        if (report.grossProfit != null)
          ('Gross profit', 'K${report.grossProfit!.decimal}'),
      ]),
      _heading('By payment method'),
      ...report.paymentBreakdown.map(_breakdown),
      _heading('Sales by day'),
      ...report.salesByDay.map(
        (item) => ListTile(
          title: Text(_date(item.date)),
          subtitle: Text('${item.count} sales'),
          trailing: Text('K${item.amount.decimal}'),
        ),
      ),
      _heading('Top products'),
      ...report.topProducts.map(
        (item) => ListTile(
          title: Text(item.name),
          subtitle: Text('${item.quantity} sold'),
          trailing: Text('K${item.revenue.decimal}'),
        ),
      ),
    ],
  );

  Widget _expenses(ExpensesReport report) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _summary([
        ('Total expenses', 'K${report.totalExpenses.decimal}'),
        ('Records', '${report.expenseCount}'),
      ]),
      _heading('By category'),
      ...report.categoryBreakdown.map(_breakdown),
      _heading('By payment method'),
      ...report.paymentBreakdown.map(_breakdown),
      _heading('Expenses by day'),
      ...report.expensesByDay.map(
        (item) => ListTile(
          title: Text(_date(item.date)),
          subtitle: Text('${item.count} expenses'),
          trailing: Text('K${item.amount.decimal}'),
        ),
      ),
      _heading('Largest expenses'),
      ...report.largestExpenses.map(
        (item) => ListTile(
          title: Text(item.description),
          subtitle: Text(_date(item.expenseDate)),
          trailing: Text('K${item.amount.decimal}'),
        ),
      ),
    ],
  );

  Widget _performance(PerformanceReport report) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _summary([
        ('Gross sales', 'K${report.grossSales.decimal}'),
        ('Gross profit', 'K${report.grossProfit.decimal}'),
        ('Expenses', 'K${report.totalExpenses.decimal}'),
        ('After Expenses', 'K${report.afterExpenses.decimal}'),
        ('Gross margin', '${report.grossMarginPercent}%'),
      ]),
      const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'After Expenses is a simplified management metric, not a formal accounting net-profit statement.',
          ),
        ),
      ),
    ],
  );

  Widget _summary(List<(String, String)> values) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: values
            .map(
              (value) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(value.$1),
                    Text(
                      value.$2,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    ),
  );

  Widget _breakdown(ReportBreakdown item) => ListTile(
    title: Text(item.label.replaceAll('_', ' ')),
    subtitle: Text('${item.count} records'),
    trailing: Text('K${item.amount.decimal}'),
  );

  Widget _heading(String value) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Text(value, style: Theme.of(context).textTheme.titleLarge),
  );
}

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

import 'package:flutter/material.dart';
import 'package:zedbiz/core/offline/sync_status_screen.dart';
import 'package:zedbiz/app/app_controller.dart';
import 'package:zedbiz/core/network/api_exception.dart';
import 'package:zedbiz/features/commercial/domain/commercial_status.dart';
import 'package:zedbiz/features/reporting/domain/report.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    required this.controller,
    required this.writable,
    required this.onOpenSales,
    required this.onOpenProducts,
    required this.onNewSale,
    super.key,
  });

  final AppController controller;
  final bool writable;
  final VoidCallback onOpenSales;
  final VoidCallback onOpenProducts;
  final VoidCallback onNewSale;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  ReportRange _range = ReportRange.today;
  DashboardData? _data;
  bool _loading = true;
  String? _error;

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
      final business = widget.controller.selectedBusiness!;
      final result = await widget.controller.reportingGateway.dashboard(
        business.id,
        _range,
      );
      if (mounted) setState(() => _data = result);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is ApiException
            ? error.message
            : 'Could not load the dashboard.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final data = _data;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CacheFreshness(
            client: controller.offline,
            path:
                '/api/v1/businesses/${controller.selectedBusiness!.id}/dashboard?range=${_range.name}',
          ),
          Text('${controller.selectedBusiness!.name} is ready'),
          if (controller.commercialStatus?.subscriptionState ==
              SubscriptionState.gracePeriod)
            const Card(
              child: ListTile(
                title: Text('Your subscription has expired'),
                subtitle: Text(
                  'Business changes remain available during the 7-day grace period.',
                ),
              ),
            ),
          if (controller.commercialStatus?.subscriptionState ==
                  SubscriptionState.expired ||
              controller.commercialStatus?.subscriptionState ==
                  SubscriptionState.cancelled)
            const Card(
              child: ListTile(
                leading: Icon(Icons.lock_outline),
                title: Text('Subscription renewal required'),
                subtitle: Text(
                  'Historical information remains available in read-only mode.',
                ),
              ),
            ),
          Text(
            'Founder Plan ${widget.writable ? 'Active' : 'Read-only'}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text('Welcome back, ${controller.currentUser!.fullName}.'),
          Align(
            alignment: Alignment.centerLeft,
            child: Chip(
              label: Text(controller.selectedBusiness!.role.name.toUpperCase()),
            ),
          ),
          SegmentedButton<ReportRange>(
            segments: const [
              ButtonSegment(value: ReportRange.today, label: Text('Today')),
              ButtonSegment(value: ReportRange.week, label: Text('Week')),
              ButtonSegment(value: ReportRange.month, label: Text('Month')),
            ],
            selected: {_range},
            onSelectionChanged: (value) {
              setState(() => _range = value.single);
              _load();
            },
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
          if (data != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _metric(
                  context,
                  'Gross sales',
                  'K${data.grossSales.decimal}',
                  Icons.trending_up,
                ),
                _metric(
                  context,
                  'Sales',
                  '${data.salesCount}',
                  Icons.receipt_long_outlined,
                ),
                if (data.grossProfit != null)
                  _metric(
                    context,
                    'Gross profit',
                    'K${data.grossProfit!.decimal}',
                    Icons.savings_outlined,
                  ),
                if (data.totalExpenses != null)
                  _metric(
                    context,
                    'Expenses',
                    'K${data.totalExpenses!.decimal}',
                    Icons.payments_outlined,
                  ),
                if (data.afterExpenses != null)
                  _metric(
                    context,
                    'After expenses',
                    'K${data.afterExpenses!.decimal}',
                    Icons.insights_outlined,
                  ),
                if (data.currentOutstandingDebt != null)
                  _metric(
                    context,
                    'Customer credit',
                    'K${data.currentOutstandingDebt!.decimal}',
                    Icons.account_balance_wallet_outlined,
                  ),
                _metric(
                  context,
                  'Low stock',
                  '${data.lowStockCount}',
                  Icons.warning_amber,
                ),
                _metric(
                  context,
                  'Out of stock',
                  '${data.outOfStockCount}',
                  Icons.remove_shopping_cart_outlined,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Recent sales', style: Theme.of(context).textTheme.titleLarge),
            if (data.recentSales.isEmpty)
              const Text('No completed sales in this period.'),
            ...data.recentSales.map(
              (sale) => ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: Text(sale.number),
                subtitle: Text(
                  '${sale.paymentMethod.replaceAll('_', ' ')} • ${_dateTime(sale.soldAt)}',
                ),
                trailing: Text('K${sale.total.decimal}'),
                onTap: widget.onOpenSales,
              ),
            ),
            if (data.recentExpenses != null) ...[
              Text(
                'Recent expenses',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (data.recentExpenses!.isEmpty)
                const Text('No recorded expenses in this period.'),
              ...data.recentExpenses!.map(
                (expense) => ListTile(
                  leading: const Icon(Icons.payments_outlined),
                  title: Text(expense.description),
                  subtitle: Text(
                    '${expense.paymentMethod.replaceAll('_', ' ')} • ${_date(expense.expenseDate)}',
                  ),
                  trailing: Text('K${expense.amount.decimal}'),
                ),
              ),
            ],
          ],
          const SizedBox(height: 12),
          if (widget.writable)
            FilledButton.icon(
              key: const Key('home-new-sale'),
              onPressed: widget.onNewSale,
              icon: const Icon(Icons.point_of_sale),
              label: const Text('SALE'),
            ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Sales'),
              subtitle: const Text(
                'Record a sale, issue a receipt, or review history.',
              ),
              onTap: widget.onOpenSales,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('Products & inventory'),
              subtitle: const Text(
                'Track stock, low-stock alerts, and every inventory movement.',
              ),
              onTap: widget.onOpenProducts,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) => SizedBox(
    width: MediaQuery.sizeOf(context).width < 500
        ? (MediaQuery.sizeOf(context).width - 40) / 2
        : 210,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            Text(label),
          ],
        ),
      ),
    ),
  );
}

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

String _dateTime(DateTime value) {
  final zambia = value.toUtc().add(const Duration(hours: 2));
  return '${_date(zambia)} ${zambia.hour.toString().padLeft(2, '0')}:${zambia.minute.toString().padLeft(2, '0')}';
}

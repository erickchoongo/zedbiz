import 'package:flutter/material.dart';
import 'package:zedbiz/app/app_controller.dart';
import 'package:zedbiz/core/network/api_exception.dart';
import 'package:zedbiz/core/offline/sync_status_screen.dart';
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final business = controller.selectedBusiness!;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text(
            'WELCOME BACK',
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.3,
              fontWeight: FontWeight.w700,
              color: colors.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            controller.currentUser!.fullName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'Here is how ${business.name} is doing.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _StatusPill(
                icon: Icons.workspace_premium_outlined,
                label: 'Founder Plan · ${widget.writable ? 'Active' : 'Read-only'}',
              ),
              _StatusPill(
                icon: Icons.badge_outlined,
                label: business.role.name.toUpperCase(),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Subscription notices are important and remain fully visible.
          if (controller.commercialStatus?.subscriptionState ==
              SubscriptionState.gracePeriod)
            const Card(
              child: ListTile(
                leading: Icon(Icons.warning_amber_rounded),
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

          // Keep cache timestamps and server-total disclosures available,
          // without permanently taking space above the business summary.
          Card(
            elevation: 0,
            color: colors.surfaceContainerLow,
            margin: EdgeInsets.zero,
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 12),
              leading: Icon(
                Icons.info_outline_rounded,
                color: colors.onSurfaceVariant,
                size: 19,
              ),
              title: const Text('Data freshness & offline information'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              children: [
                CacheFreshness(
                  client: controller.offline,
                  path:
                      '/api/v1/businesses/${business.id}/dashboard?range=${_range.name}',
                ),
                const SizedBox(height: 4),
                const Text(
                  'Pending offline transactions are not included in server totals until confirmed.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: Text(
                  'Overview',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ReportRange>(
              showSelectedIcon: false,
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
          ),
          const SizedBox(height: 14),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Card(
              color: colors.errorContainer,
              child: ListTile(
                title: Text(_error!),
                trailing: IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Retry dashboard',
                ),
              ),
            ),
          if (data != null) ...[
            const SizedBox(height: 5),
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 10.0;
                final columns = constraints.maxWidth >= 700 ? 4 : 2;
                final width =
                    (constraints.maxWidth - spacing * (columns - 1)) / columns;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    _metric(context, 'Gross sales', 'K${data.grossSales.decimal}',
                        Icons.trending_up_rounded, width),
                    _metric(context, 'Sales', '${data.salesCount}',
                        Icons.receipt_long_outlined, width),
                    if (data.grossProfit != null)
                      _metric(context, 'Gross profit',
                          'K${data.grossProfit!.decimal}', Icons.savings_outlined, width),
                    if (data.totalExpenses != null)
                      _metric(context, 'Expenses',
                          'K${data.totalExpenses!.decimal}', Icons.payments_outlined, width),
                    if (data.afterExpenses != null)
                      _metric(context, 'After expenses',
                          'K${data.afterExpenses!.decimal}', Icons.insights_outlined, width),
                    if (data.currentOutstandingDebt != null)
                      _metric(context, 'Customer credit',
                          'K${data.currentOutstandingDebt!.decimal}',
                          Icons.account_balance_wallet_outlined, width),
                    _metric(context, 'Low stock', '${data.lowStockCount}',
                        Icons.warning_amber_rounded, width),
                    _metric(context, 'Out of stock', '${data.outOfStockCount}',
                        Icons.remove_shopping_cart_outlined, width),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            _sectionTitle(context, 'Recent sales',
                action: 'View all', onPressed: widget.onOpenSales),
            const SizedBox(height: 10),
            if (data.recentSales.isEmpty)
              _emptyCard(context, 'No completed sales in this period.'),
            ...data.recentSales.map(
              (sale) => Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                color: colors.surfaceContainerLow,
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.receipt_long_outlined),
                  ),
                  title: Text(sale.number,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${sale.paymentMethod.replaceAll('_', ' ')} • ${_dateTime(sale.soldAt)}',
                  ),
                  trailing: Text(
                    'K${sale.total.decimal}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onTap: widget.onOpenSales,
                ),
              ),
            ),
            if (data.recentExpenses != null) ...[
              const SizedBox(height: 14),
              _sectionTitle(context, 'Recent expenses'),
              const SizedBox(height: 10),
              if (data.recentExpenses!.isEmpty)
                _emptyCard(context, 'No recorded expenses in this period.'),
              ...data.recentExpenses!.map(
                (expense) => Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 8),
                  color: colors.surfaceContainerLow,
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.payments_outlined),
                    ),
                    title: Text(expense.description,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${expense.paymentMethod.replaceAll('_', ' ')} • ${_date(expense.expenseDate)}',
                    ),
                    trailing: Text(
                      'K${expense.amount.decimal}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
          ],
          const SizedBox(height: 20),
          _sectionTitle(context, 'Quick actions'),
          const SizedBox(height: 10),
          if (widget.writable) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('home-new-sale'),
                onPressed: widget.onNewSale,
                icon: const Icon(Icons.add_shopping_cart_rounded),
                label: const Text('New sale'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          _quickAction(
            context,
            title: 'Sales',
            subtitle: 'Record a sale, issue a receipt, or review history.',
            icon: Icons.receipt_long_outlined,
            onTap: widget.onOpenSales,
          ),
          const SizedBox(height: 8),
          _quickAction(
            context,
            title: 'Products & inventory',
            subtitle: 'Track stock, low-stock alerts, and inventory movements.',
            icon: Icons.inventory_2_outlined,
            onTap: widget.onOpenProducts,
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
    double width,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SizedBox(
      width: width,
      child: Container(
        constraints: const BoxConstraints(minHeight: 122),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colors.primary, size: 22),
            const SizedBox(height: 10),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title,
      {String? action, VoidCallback? onPressed}) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (action != null)
          TextButton(onPressed: onPressed, child: Text(action)),
      ],
    );
  }

  Widget _emptyCard(BuildContext context, String message) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(message, style: TextStyle(color: colors.onSurfaceVariant)),
    );
  }

  Widget _quickAction(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.surfaceContainerLow,
      child: ListTile(
        leading: Icon(icon, color: colors.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: colors.primary),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

String _dateTime(DateTime value) {
  final zambia = value.toUtc().add(const Duration(hours: 2));
  return '${_date(zambia)} ${zambia.hour.toString().padLeft(2, '0')}:${zambia.minute.toString().padLeft(2, '0')}';
}

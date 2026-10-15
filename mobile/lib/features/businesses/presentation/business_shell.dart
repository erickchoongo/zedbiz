import 'package:zedbiz/core/offline/sync_status_screen.dart';
import 'package:zedbiz/core/diagnostics/pilot_diagnostics_screen.dart';
import 'package:flutter/material.dart';
import 'package:zedbiz/app/app_controller.dart';
import 'package:zedbiz/features/products/presentation/products_screen.dart';
import 'package:zedbiz/features/customers/presentation/customers_screen.dart';
import 'package:zedbiz/features/debts/presentation/debts_screen.dart';
import 'package:zedbiz/features/expenses/presentation/expenses_screen.dart';
import 'package:zedbiz/features/reporting/presentation/dashboard_screen.dart';
import 'package:zedbiz/features/reporting/presentation/reports_screen.dart';
import 'package:zedbiz/features/sales/presentation/sales_screen.dart';

class BusinessShell extends StatefulWidget {
  const BusinessShell({
    required this.controller,
    required this.writable,
    super.key,
  });
  final AppController controller;
  final bool writable;
  @override
  State<BusinessShell> createState() => _BusinessShellState();
}

class _BusinessShellState extends State<BusinessShell> {
  int index = 0;
  @override
  Widget build(BuildContext context) {
    final business = widget.controller.selectedBusiness!;
    final pages = [
      DashboardScreen(
        controller: widget.controller,
        writable: widget.writable,
        onOpenSales: () => setState(() => index = 1),
        onOpenProducts: () => setState(() => index = 2),
        onNewSale: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NewSaleScreen(controller: widget.controller),
          ),
        ),
      ),
      SalesScreen(controller: widget.controller, writable: widget.writable),
      ProductsScreen(controller: widget.controller, writable: widget.writable),
      _More(controller: widget.controller, writable: widget.writable),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          index == 0
              ? business.name
              : index == 1
              ? 'Sales'
              : index == 2
              ? 'Products'
              : 'More',
        ),
        actions: [
          if (widget.controller.currentUser?.isPlatformAdmin == true)
            IconButton(
              onPressed: widget.controller.openAdmin,
              icon: const Icon(Icons.admin_panel_settings),
              tooltip: 'ZedBiz admin',
            ),
          IconButton(
            onPressed: widget.controller.busy ? null : widget.controller.logout,
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: Column(
        children: [
          if (widget.controller.offline != null)
            SyncBanner(
              client: widget.controller.offline!,
              business: business.id,
            ),
          Expanded(
            child: IndexedStack(index: index, children: pages),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (v) => setState(() => index = v),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Sales',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Products',
          ),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }
}

class _More extends StatelessWidget {
  const _More({required this.controller, required this.writable});
  final AppController controller;
  final bool writable;
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      if (controller.currentUser?.isPlatformAdmin == true)
        ListTile(
          leading: const Icon(Icons.admin_panel_settings),
          title: const Text('ZedBiz admin'),
          onTap: controller.openAdmin,
        ),

      ListTile(
        key: const Key('more-expenses'),
        leading: const Icon(Icons.payments_outlined),
        title: const Text('Expenses'),
        subtitle: const Text('Record and review business costs.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ExpensesScreen(controller: controller, writable: writable),
          ),
        ),
      ),
      ListTile(
        key: const Key('more-reports'),
        leading: const Icon(Icons.insights_outlined),
        title: const Text('Business reports'),
        subtitle: const Text(
          'Sales, expenses, performance, credit, and stock.',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ReportsScreen(controller: controller, writable: writable),
          ),
        ),
      ),
      ListTile(
        key: const Key('more-customers'),
        leading: const Icon(Icons.people_outline),
        title: const Text('Customers'),
        subtitle: const Text('Contacts, balances, and customer history.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                CustomersScreen(controller: controller, writable: writable),
          ),
        ),
      ),
      ListTile(
        key: const Key('more-customer-credit'),
        leading: const Icon(Icons.account_balance_wallet_outlined),
        title: const Text('Customer Credit'),
        subtitle: const Text('See money owed and record repayments.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                DebtsScreen(controller: controller, writable: writable),
          ),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.swap_horiz),
        title: const Text('Switch business'),
        onTap: controller.showBusinessList,
      ),
      ListTile(
        key: const Key('more-pilot-diagnostics'),
        leading: const Icon(Icons.info_outline),
        title: const Text('Pilot diagnostics'),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PilotDiagnosticsScreen(controller: controller),
          ),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.logout),
        title: const Text('Sign out'),
        onTap: controller.logout,
      ),
    ],
  );
}

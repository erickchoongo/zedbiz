
import 'package:flutter/material.dart';

import 'package:zedbiz/app/app_controller.dart';
import 'package:zedbiz/core/diagnostics/pilot_diagnostics_screen.dart';
import 'package:zedbiz/core/offline/sync_status_screen.dart';
import 'package:zedbiz/features/customers/presentation/customers_screen.dart';
import 'package:zedbiz/features/debts/presentation/debts_screen.dart';
import 'package:zedbiz/features/expenses/presentation/expenses_screen.dart';
import 'package:zedbiz/features/products/presentation/products_screen.dart';
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final pages = [
      DashboardScreen(
        controller: widget.controller,
        writable: widget.writable,
        onOpenSales: () => setState(() => index = 1),
        onOpenProducts: () => setState(() => index = 2),
        onNewSale: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NewSaleScreen(
              controller: widget.controller,
            ),
          ),
        ),
      ),
      SalesScreen(
        controller: widget.controller,
        writable: widget.writable,
      ),
      ProductsScreen(
        controller: widget.controller,
        writable: widget.writable,
      ),
      _More(
        controller: widget.controller,
        writable: widget.writable,
      ),
    ];

    final title = switch (index) {
      0 => business.name,
      1 => 'Sales',
      2 => 'Products',
      _ => 'More',
    };

    final subtitle = switch (index) {
      0 => 'Business workspace',
      1 => 'Manage your sales',
      2 => 'Manage your inventory',
      _ => 'Business & account',
    };

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 76,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                index == 0
                    ? Icons.storefront_outlined
                    : index == 1
                        ? Icons.receipt_long_outlined
                        : index == 2
                            ? Icons.inventory_2_outlined
                            : Icons.dashboard_customize_outlined,
                color: colors.primary,
                size: 23,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        // Keep platform administration one tap away on Home.
        // Permissions continue to be enforced by AppController.openAdmin.
        actions: [
          if (index == 0 &&
              widget.controller.currentUser?.isPlatformAdmin == true)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: IconButton.filledTonal(
                key: const Key('home-admin-shortcut'),
                tooltip: 'ZedBiz admin',
                onPressed: widget.controller.openAdmin,
                icon: const Icon(Icons.admin_panel_settings_outlined),
              ),
            ),
        ],
      ),

      body: Column(
        children: [
          // Compact synchronization control
          if (widget.controller.offline != null)
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(
                  bottom: BorderSide(
                    color: colors.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
              ),
              child: SyncBanner(
                client: widget.controller.offline!,
                business: business.id,
              ),
            ),

          // Preserve all existing page functionality.
          Expanded(
            child: IndexedStack(
              index: index,
              children: pages,
            ),
          ),
        ],
      ),

      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(
            top: BorderSide(
              color: colors.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: index,
          backgroundColor: colors.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          indicatorColor: colors.primaryContainer,
          onDestinationSelected: (value) {
            setState(() => index = value);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long_rounded),
              label: 'Sales',
            ),
            NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2_rounded),
              label: 'Products',
            ),
            NavigationDestination(
              icon: Icon(Icons.more_horiz_rounded),
              selectedIcon: Icon(Icons.more_rounded),
              label: 'More',
            ),
          ],
        ),
      ),
    );
  }
}

class _More extends StatelessWidget {
  const _More({
    required this.controller,
    required this.writable,
  });

  final AppController controller;
  final bool writable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
      children: [
        // Business identity card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colors.primaryContainer.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: colors.primary,
                child: const Icon(
                  Icons.storefront_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.selectedBusiness?.name ?? 'My business',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Business settings and management',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 26),

        _SectionHeading(title: 'BUSINESS MANAGEMENT'),

        const SizedBox(height: 12),

        _MenuGroup(
          children: [
            _MenuTile(
              itemKey: const Key('more-expenses'),
              icon: Icons.payments_outlined,
              title: 'Expenses',
              subtitle: 'Record and review business costs.',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ExpensesScreen(
                    controller: controller,
                    writable: writable,
                  ),
                ),
              ),
            ),
            _MenuTile(
              itemKey: const Key('more-reports'),
              icon: Icons.insights_outlined,
              title: 'Business reports',
              subtitle: 'Sales, expenses, performance, credit, and stock.',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ReportsScreen(
                    controller: controller,
                    writable: writable,
                  ),
                ),
              ),
            ),
            _MenuTile(
              itemKey: const Key('more-customers'),
              icon: Icons.people_outline_rounded,
              title: 'Customers',
              subtitle: 'Contacts, balances, and customer history.',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CustomersScreen(
                    controller: controller,
                    writable: writable,
                  ),
                ),
              ),
            ),
            _MenuTile(
              itemKey: const Key('more-customer-credit'),
              icon: Icons.account_balance_wallet_outlined,
              title: 'Customer Credit',
              subtitle: 'See money owed and record repayments.',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DebtsScreen(
                    controller: controller,
                    writable: writable,
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 26),

        _SectionHeading(title: 'ACCOUNT & SYSTEM'),

        const SizedBox(height: 12),

        _MenuGroup(
          children: [
            if (controller.currentUser?.isPlatformAdmin == true)
              _MenuTile(
                icon: Icons.admin_panel_settings_outlined,
                title: 'ZedBiz admin',
                subtitle: 'Platform administration.',
                onTap: controller.openAdmin,
              ),

            _MenuTile(
              icon: Icons.swap_horiz_rounded,
              title: 'Switch business',
              subtitle: 'Manage another business workspace.',
              onTap: controller.showBusinessList,
            ),

            _MenuTile(
              itemKey: const Key('more-pilot-diagnostics'),
              icon: Icons.info_outline_rounded,
              title: 'Pilot diagnostics',
              subtitle: 'System diagnostics and information.',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PilotDiagnosticsScreen(
                    controller: controller,
                  ),
                ),
              ),
            ),

            _MenuTile(
              icon: Icons.logout_rounded,
              title: 'Sign out',
              subtitle: 'Securely leave your account.',
              destructive: true,
              onTap: controller.busy ? null : controller.logout,
            ),
          ],
        ),
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _MenuGroup extends StatelessWidget {
  const _MenuGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 0.6,
                indent: 62,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    this.itemKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final Key? itemKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground =
        destructive ? colors.error : colors.onSurface;

    return ListTile(
      key: itemKey,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 7,
      ),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: destructive
              ? colors.errorContainer.withValues(alpha: 0.55)
              : colors.primaryContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: destructive ? colors.error : colors.primary,
          size: 21,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: colors.onSurfaceVariant,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        size: 20,
        color: colors.onSurfaceVariant,
      ),
    );
  }
}


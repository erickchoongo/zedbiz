import 'package:zedbiz/features/sales/application/receipt_export.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zedbiz/app/app_controller.dart';
import 'package:zedbiz/core/network/api_exception.dart';
import 'package:zedbiz/features/businesses/domain/business_summary.dart';
import 'package:zedbiz/features/customers/domain/customer.dart';
import 'package:zedbiz/features/customers/presentation/customers_screen.dart';
import 'package:zedbiz/features/products/domain/product.dart';
import 'package:zedbiz/features/products/data/product_repository.dart';
import 'package:zedbiz/features/sales/application/sale_cart_controller.dart';
import 'package:zedbiz/features/sales/domain/sale.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({
    required this.controller,
    required this.writable,
    super.key,
  });
  final AppController controller;
  final bool writable;
  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  final search = TextEditingController();
  List<SaleSummary> items = [];
  bool loading = true;
  String? error, statusFilter;
  int page = 1, total = 0;
  bool get canVoid =>
      widget.controller.selectedBusiness!.role != BusinessRole.cashier;
  @override
  void initState() {
    super.initState();
    load(reset: true);
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load({bool reset = false}) async {
    if (reset) page = 1;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final b = widget.controller.selectedBusiness!;
      final result = await widget.controller.saleGateway.list(
        b.id,
        b.currency,
        page: page,
        search: search.text,
        status: statusFilter,
      );
      if (mounted) {
        setState(() {
          items = reset ? result.items : [...items, ...result.items];
          total = result.total;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(
          () => error = e is ApiException ? e.message : 'Could not load sales.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      body: RefreshIndicator(
        onRefresh: () => load(reset: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!widget.writable) ...[
                      Card(
                        color: colors.surfaceContainerLow,
                        child: const ListTile(
                          leading: Icon(Icons.lock_outline),
                          title: Text('Sales are read-only'),
                          subtitle: Text(
                            'Historical sales and receipts remain available.',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      'Sales history',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Find transactions and review your receipts.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: search,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => load(reset: true),
                      decoration: InputDecoration(
                        hintText: 'Search sale number',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: IconButton(
                          tooltip: 'Search sales',
                          onPressed: () => load(reset: true),
                          icon: const Icon(Icons.arrow_forward_rounded),
                        ),
                        filled: true,
                        fillColor: colors.surfaceContainerLow,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('All sales'),
                          selected: statusFilter == null,
                          onSelected: (_) {
                            setState(() => statusFilter = null);
                            load(reset: true);
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Completed'),
                          selected: statusFilter == 'COMPLETED',
                          onSelected: (_) {
                            setState(() => statusFilter = 'COMPLETED');
                            load(reset: true);
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Voided'),
                          selected: statusFilter == 'VOIDED',
                          onSelected: (_) {
                            setState(() => statusFilter = 'VOIDED');
                            load(reset: true);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Transactions',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (!loading && error == null)
                          Text(
                            '$total total',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (loading) ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 12),
                    ],
                    if (error != null) ...[
                      Card(
                        color: colors.errorContainer,
                        child: ListTile(
                          leading: Icon(
                            Icons.error_outline,
                            color: colors.onErrorContainer,
                          ),
                          title: Text(error!),
                          trailing: IconButton(
                            tooltip: 'Retry loading sales',
                            onPressed: () => load(reset: true),
                            icon: const Icon(Icons.refresh),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (!loading && error == null && items.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 40,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.receipt_long_outlined,
                              color: colors.primary,
                              size: 44,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No sales recorded yet',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Complete a sale to see it here.',
                              style: theme.textTheme.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    for (final sale in items) ...[
                      Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 10),
                        color: colors.surfaceContainerLow,
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: InkWell(
                          onTap: () => _detail(sale.id),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: colors.primaryContainer,
                                        borderRadius: BorderRadius.circular(13),
                                      ),
                                      child: Icon(
                                        sale.status == SaleStatus.voided
                                            ? Icons.block_outlined
                                            : Icons.receipt_long_outlined,
                                        color: sale.status == SaleStatus.voided
                                            ? colors.error
                                            : colors.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            sale.number,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.titleSmall
                                                ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            _date(sale.soldAt),
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color: colors.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          'K${sale.total.decimal}',
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          sale.status == SaleStatus.voided
                                              ? 'VOIDED'
                                              : sale.localSyncState == null
                                                  ? sale.status.name.toUpperCase()
                                                  : sale.localSyncState!
                                                      .toUpperCase(),
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            color: sale.status ==
                                                    SaleStatus.voided
                                                ? colors.error
                                                : sale.localSyncState != null
                                                    ? colors.tertiary
                                                    : colors.primary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 13),
                                Divider(
                                  height: 1,
                                  color: colors.outlineVariant,
                                ),
                                const SizedBox(height: 11),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 6,
                                  children: [
                                    _SaleMeta(
                                      icon: Icons.payments_outlined,
                                      label: paymentLabel(sale.paymentMethod),
                                    ),
                                    _SaleMeta(
                                      icon: Icons.person_outline_rounded,
                                      label: sale.seller,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (items.length < total) ...[
                      const SizedBox(height: 8),
                      Center(
                        child: OutlinedButton.icon(
                          onPressed: loading
                              ? null
                              : () {
                                  page++;
                                  load();
                                },
                          icon: const Icon(Icons.expand_more_rounded),
                          label: const Text('Load more'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: widget.writable
          ? FloatingActionButton.extended(
              heroTag: 'new-sale-fab',
              key: const Key('new-sale'),
              onPressed: _newSale,
              icon: const Icon(Icons.point_of_sale),
              label: const Text('NEW SALE'),
            )
          : null,
    );
  }

  Future<void> _newSale() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NewSaleScreen(controller: widget.controller),
      ),
    );
    load(reset: true);
  }

  Future<void> _detail(String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SaleDetailScreen(
          controller: widget.controller,
          saleId: id,
          writable: widget.writable,
          canVoid: canVoid,
        ),
      ),
    );
    load(reset: true);
  }

  String _date(DateTime value) {
    final z = value.toUtc().add(const Duration(hours: 2));
    return '${z.day.toString().padLeft(2, '0')}/${z.month.toString().padLeft(2, '0')}/${z.year} ${z.hour.toString().padLeft(2, '0')}:${z.minute.toString().padLeft(2, '0')}';
  }
}

class _SaleMeta extends StatelessWidget {
  const _SaleMeta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: colors.onSurfaceVariant),
        const SizedBox(width: 5),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class NewSaleScreen extends StatefulWidget {
  const NewSaleScreen({required this.controller, super.key});
  final AppController controller;
  @override
  State<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends State<NewSaleScreen> {
  late final SaleCartController cart;
  final search = TextEditingController();
  List<Product> products = [];
  bool loading = false;
  String? productError;
  @override
  void initState() {
    super.initState();
    final b = widget.controller.selectedBusiness!;
    cart = SaleCartController(
      gateway: widget.controller.saleGateway,
      businessId: b.id,
      currency: b.currency,
    )..addListener(_changed);
    _find();
  }

  @override
  void dispose() {
    cart.removeListener(_changed);
    cart.dispose();
    search.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _find() async {
    setState(() {
      loading = true;
      productError = null;
    });
    try {
      final page = await widget.controller.productGateway.list(
        widget.controller.selectedBusiness!.id,
        search: search.text,
      );
      if (mounted) {
        setState(() => products = page.items.where((p) => p.isActive).toList());
      }
    } on Object catch (e) {
      if (mounted) {
        setState(
          () => productError = e is ApiException
              ? e.message
              : 'Could not search products.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('New sale')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          key: const Key('sale-product-search'),
          controller: search,
          onSubmitted: (_) => _find(),
          decoration: InputDecoration(
            labelText: 'Search products, services, SKU or barcode',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              onPressed: _find,
              icon: const Icon(Icons.arrow_forward),
            ),
          ),
        ),
        if (loading) const LinearProgressIndicator(),
        if (productError != null)
          Text(
            productError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ...products.map((p) {
          final unavailable =
              p.trackInventory && p.stockQuantity.thousandths == 0;
          return ListTile(
            leading: Icon(
              p.trackInventory
                  ? Icons.inventory_2_outlined
                  : Icons.miscellaneous_services,
            ),
            title: Text(p.name),
            subtitle: Text(
              'K${p.sellingPrice}${p.trackInventory ? ' • ${p.stockQuantity.display} available' : ' • Service'}',
            ),
            trailing: FilledButton.tonal(
              onPressed: unavailable ? null : () => _add(p),
              child: Text(unavailable ? 'Out of stock' : 'Add'),
            ),
          );
        }),
        const Divider(),
        Text('Cart', style: Theme.of(context).textTheme.titleLarge),
        if (cart.lines.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('Search above and add an item.'),
          ),
        ...cart.lines.map(
          (line) => Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          line.product.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'K${line.product.sellingPrice} × ${line.quantity.display} = K${line.total(cart.currency).decimal}',
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => cart.decrement(line.product),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  TextButton(
                    onPressed: () => _quantity(line),
                    child: Text(line.quantity.display),
                  ),
                  IconButton(
                    onPressed: () => _increment(line.product),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                  IconButton(
                    onPressed: () => cart.remove(line.product.id),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(),
        _amount('Subtotal', cart.subtotal.decimal),
        _amount('Discount', cart.discount.decimal),
        _amount('TOTAL', cart.total.decimal, bold: true),
        if (cart.errorMessage != null)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(cart.errorMessage!),
            ),
          ),
        FilledButton.icon(
          key: const Key('continue-sale'),
          onPressed: cart.lines.isEmpty || cart.busy ? null : _payment,
          icon: const Icon(Icons.payment),
          label: const Text('CONTINUE'),
        ),
      ],
    ),
  );
  Widget _amount(String label, String value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null,
        ),
        Text(
          'K$value',
          style: bold ? Theme.of(context).textTheme.titleLarge : null,
        ),
      ],
    ),
  );
  void _add(Product p) {
    try {
      cart.add(p);
    } on StateError catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _increment(Product p) {
    try {
      cart.add(p);
    } on StateError catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _quantity(CartLine line) async {
    final c = TextEditingController(text: line.quantity.display);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${line.product.name} quantity'),
        content: TextField(
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          controller: c,
          decoration: const InputDecoration(
            labelText: 'Quantity (up to 3 decimals)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (value == null) return;
    try {
      cart.setQuantity(line.product, Quantity.parse(value));
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is StateError ? e.message : 'Enter a valid quantity.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _payment() async {
    final reference = TextEditingController(text: cart.paymentReference);
    final discount = TextEditingController(text: cart.discount.decimal);
    final notes = TextEditingController(text: cart.notes);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Payment'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: 8,
                    children: SalePaymentMethod.values
                        .map(
                          (method) => ChoiceChip(
                            label: Text(paymentLabel(method)),
                            selected: cart.paymentMethod == method,
                            onSelected:
                                method == SalePaymentMethod.customerDebt &&
                                    !widget.controller.online
                                ? null
                                : (_) {
                                    cart.setPayment(method);
                                    setDialog(() {});
                                  },
                          ),
                        )
                        .toList(),
                  ),
                  if (!widget.controller.online)
                    const Text(
                      'Customer Credit requires an internet connection.',
                    ),
                  if (cart.paymentMethod == SalePaymentMethod.customerDebt) ...[
                    const SizedBox(height: 12),
                    Card(
                      child: ListTile(
                        key: const Key('credit-customer'),
                        leading: const Icon(Icons.person_outline),
                        title: Text(
                          cart.selectedCustomer?.name ?? 'Select customer *',
                        ),
                        subtitle: Text(
                          cart.selectedCustomer?.phoneNumber ??
                              'Required for Customer Credit',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          final selected = await _pickCustomer();
                          if (selected == null) return;
                          cart.selectCustomer(selected);
                          setDialog(() {});
                        },
                      ),
                    ),
                    ListTile(
                      key: const Key('credit-due-date'),
                      leading: const Icon(Icons.event_outlined),
                      title: const Text('Due date (optional)'),
                      subtitle: Text(
                        cart.dueDate == null
                            ? 'No due date'
                            : _dateOnly(cart.dueDate!),
                      ),
                      trailing: cart.dueDate == null
                          ? const Icon(Icons.chevron_right)
                          : IconButton(
                              tooltip: 'Clear due date',
                              onPressed: () {
                                cart.setDueDate(null);
                                setDialog(() {});
                              },
                              icon: const Icon(Icons.close),
                            ),
                      onTap: () async {
                        final selected = await _pickDueDate();
                        if (selected == null) return;
                        cart.setDueDate(selected);
                        setDialog(() {});
                      },
                    ),
                  ],
                  TextField(
                    controller: reference,
                    decoration: const InputDecoration(
                      labelText: 'Payment reference (optional)',
                    ),
                  ),
                  TextField(
                    controller: discount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Discount amount',
                    ),
                  ),
                  TextField(
                    controller: notes,
                    maxLength: 1000,
                    decoration: const InputDecoration(
                      labelText: 'Internal notes (optional)',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Back'),
            ),
            FilledButton(
              key: const Key('complete-sale'),
              onPressed:
                  cart.busy ||
                      (cart.paymentMethod == SalePaymentMethod.customerDebt &&
                          cart.selectedCustomer == null)
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('COMPLETE SALE'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) return;
    try {
      cart.setDiscount(discount.text);
      cart.paymentReference = reference.text;
      cart.notes = notes.text;
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is StateError ? e.message : 'Invalid discount.'),
          ),
        );
      }
      return;
    }
    final result = await cart.complete();
    if (result != null && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              SaleSuccessScreen(controller: widget.controller, sale: result),
        ),
      );
      if (mounted) Navigator.pop(context);
    }
  }

  Future<CustomerSummary?> _pickCustomer() =>
      showModalBottomSheet<CustomerSummary>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => CustomerPickerSheet(
          controller: widget.controller,
          allowCreate: true,
        ),
      );

  Future<DateTime?> _pickDueDate() {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: cart.dueDate ?? now.add(const Duration(days: 30)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: 'Customer credit due date',
    );
  }

  String _dateOnly(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
}

class SaleSuccessScreen extends StatelessWidget {
  const SaleSuccessScreen({
    required this.controller,
    required this.sale,
    super.key,
  });
  final AppController controller;
  final SaleDetail sale;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        sale.localSyncState == null
            ? 'Sale recorded'
            : 'Sale saved on this device',
      ),
      automaticallyImplyLeading: false,
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 72),
            Text(
              sale.localSyncState == null
                  ? 'Sale recorded'
                  : 'Sale saved on this device — waiting to sync.',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(
              'K${sale.total.decimal}',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            Text(sale.number),
            if (sale.localSyncState != null)
              Text(sale.localSyncState!.toUpperCase()),
            if (sale.paymentMethod == SalePaymentMethod.customerDebt) ...[
              const SizedBox(height: 12),
              Text('Customer: ${sale.customerName ?? 'Customer'}'),
              Text(
                'Amount owed: K${(sale.debtOutstandingAmount ?? sale.total).decimal}',
              ),
              if (sale.debtDueDate != null)
                Text(
                  'Due: ${sale.debtDueDate!.day.toString().padLeft(2, '0')}/${sale.debtDueDate!.month.toString().padLeft(2, '0')}/${sale.debtDueDate!.year}',
                ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ReceiptScreen(controller: controller, saleId: sale.id),
                ),
              ),
              icon: const Icon(Icons.receipt_long),
              label: const Text('VIEW RECEIPT'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => NewSaleScreen(controller: controller),
                ),
              ),
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('NEW SALE'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('DONE'),
            ),
          ],
        ),
      ),
    ),
  );
}

class SaleDetailScreen extends StatefulWidget {
  const SaleDetailScreen({
    required this.controller,
    required this.saleId,
    required this.writable,
    required this.canVoid,
    super.key,
  });
  final AppController controller;
  final String saleId;
  final bool writable, canVoid;
  @override
  State<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends State<SaleDetailScreen> {
  SaleDetail? sale;
  String? error;
  String? _voidOperationId;
  String? _pendingVoidReason;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final b = widget.controller.selectedBusiness!;
      final value = await widget.controller.saleGateway.detail(
        b.id,
        widget.saleId,
        b.currency,
      );
      if (mounted) setState(() => sale = value);
    } on Object catch (e) {
      if (mounted) {
        setState(
          () => error = e is ApiException ? e.message : 'Could not load sale.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = sale;
    return Scaffold(
      appBar: AppBar(title: Text(value?.number ?? 'Sale')),
      body: value == null
          ? Center(
              child: error == null
                  ? const CircularProgressIndicator()
                  : Text(error!),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (value.status == SaleStatus.voided)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: ListTile(
                      leading: const Icon(Icons.block),
                      title: const Text('VOIDED'),
                      subtitle: Text(
                        '${value.voidReason}\n${value.voidedBy ?? ''} ${value.voidedAt == null ? '' : _date(value.voidedAt!)}',
                      ),
                    ),
                  ),
                ...value.items.map(
                  (line) => ListTile(
                    title: Text(line.name),
                    subtitle: Text(
                      '${line.quantity.display} × K${line.unitPrice.decimal}${line.unitCost == null ? '' : '\nCost K${line.lineCost!.decimal}'}',
                    ),
                    trailing: Text('K${line.lineTotal.decimal}'),
                  ),
                ),
                const Divider(),
                _row('Subtotal', value.subtotal.decimal),
                _row('Discount', value.discount.decimal),
                _row('TOTAL', value.total.decimal, bold: true),
                if (value.totalCost != null)
                  _row('Cost', value.totalCost!.decimal),
                if (value.grossProfit != null)
                  _row('Gross profit', value.grossProfit!.decimal),
                ListTile(
                  title: const Text('Payment'),
                  subtitle: Text(
                    '${paymentLabel(value.paymentMethod)}${value.paymentReference == null ? '' : ' • ${value.paymentReference}'}',
                  ),
                ),
                if (value.paymentMethod == SalePaymentMethod.customerDebt)
                  ListTile(
                    title: const Text('Customer'),
                    subtitle: Text(
                      '${value.customerName ?? 'Customer'}${value.debtOutstandingAmount == null ? '' : '\nOwes K${value.debtOutstandingAmount!.decimal}'}${value.debtDueDate == null ? '' : '\nDue ${value.debtDueDate!.day.toString().padLeft(2, '0')}/${value.debtDueDate!.month.toString().padLeft(2, '0')}/${value.debtDueDate!.year}'}',
                    ),
                    isThreeLine: true,
                  ),
                ListTile(
                  title: const Text('Seller'),
                  subtitle: Text(value.seller),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReceiptScreen(
                        controller: widget.controller,
                        saleId: value.id,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('VIEW RECEIPT'),
                ),
                if (value.localSyncState == null &&
                    widget.controller.online &&
                    widget.writable &&
                    widget.canVoid &&
                    value.status == SaleStatus.completed)
                  OutlinedButton.icon(
                    onPressed: _void,
                    icon: const Icon(Icons.block),
                    label: const Text('VOID SALE'),
                  ),
              ],
            ),
    );
  }

  Widget _row(String label, String amount, {bool bold = false}) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null,
      ),
      Text(
        'K$amount',
        style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null,
      ),
    ],
  );
  Future<void> _void() async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Void this sale?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This will restore stock for tracked items and keep the original sale in your records.',
            ),
            TextField(
              controller: reason,
              decoration: const InputDecoration(labelText: 'Reason (required)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('VOID SALE'),
          ),
        ],
      ),
    );
    if (confirmed != true || reason.text.trim().isEmpty) return;
    try {
      final b = widget.controller.selectedBusiness!;
      final cleanedReason = reason.text.trim();
      if (_pendingVoidReason != cleanedReason) {
        _voidOperationId = newOperationId();
        _pendingVoidReason = cleanedReason;
      }
      sale = await widget.controller.saleGateway.voidSale(
        b.id,
        widget.saleId,
        b.currency,
        operationId: _voidOperationId!,
        reason: cleanedReason,
      );
      _voidOperationId = null;
      _pendingVoidReason = null;
      setState(() {});
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is ApiException ? e.message : 'Could not void sale.',
            ),
          ),
        );
      }
    }
  }

  String _date(DateTime value) {
    final z = value.toUtc().add(const Duration(hours: 2));
    return '${z.day}/${z.month}/${z.year} ${z.hour.toString().padLeft(2, '0')}:${z.minute.toString().padLeft(2, '0')}';
  }
}

class ReceiptScreen extends StatefulWidget {
  const ReceiptScreen({
    required this.controller,
    required this.saleId,
    super.key,
  });
  final AppController controller;
  final String saleId;
  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  ReceiptData? receipt;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final value = await widget.controller.saleGateway.receipt(
        widget.controller.selectedBusiness!.id,
        widget.saleId,
      );
      if (mounted) setState(() => receipt = value);
    } on Object catch (e) {
      if (mounted) {
        setState(
          () =>
              error = e is ApiException ? e.message : 'Could not load receipt.',
        );
      }
    }
  }

  String textReceipt(ReceiptData r) {
    final lines = <String>[
      r.businessName,
      if (r.phone != null) r.phone!,
      if (r.location != null) r.location!,
      '',
      'SALES RECEIPT',
      r.saleNumber,
      _date(r.soldAt),
      '',
      ...r.items.expand(
        (item) => [
          item.name,
          '${item.quantity.display} × K${item.unitPrice.decimal}    K${item.lineTotal.decimal}',
        ],
      ),
      '',
      'Subtotal    K${r.subtotal.decimal}',
      'Discount    K${r.discount.decimal}',
      'TOTAL       K${r.total.decimal}',
      '',
      'Payment: ${paymentLabel(r.paymentMethod)}',
      if (r.customerName != null) 'Customer: ${r.customerName}',
      if (r.dueDate != null) 'Due date: ${_dateOnly(r.dueDate!)}',
      if (r.reference != null) 'Reference: ${r.reference}',
      '',
      'Thank you',
    ];
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final r = receipt;
    return Scaffold(
      appBar: AppBar(title: const Text('Sales Receipt')),
      body: r == null
          ? Center(
              child: error == null
                  ? const CircularProgressIndicator()
                  : Text(error!),
            )
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Center(
                  child: Text(
                    r.businessName,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                if (r.phone != null) Center(child: Text(r.phone!)),
                if (r.location != null) Center(child: Text(r.location!)),
                const SizedBox(height: 16),
                const Center(
                  child: Text(
                    'SALES RECEIPT',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (r.localSyncState != null)
                  const Text('PROVISIONAL RECEIPT — PENDING SYNC'),
                Center(child: Text(r.saleNumber)),
                Center(child: Text(_date(r.soldAt))),
                if (r.status == SaleStatus.voided)
                  const Center(child: Chip(label: Text('VOIDED'))),
                const Divider(),
                ...r.items.map(
                  (item) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(item.name),
                    subtitle: Text(
                      '${item.quantity.display} × K${item.unitPrice.decimal}',
                    ),
                    trailing: Text('K${item.lineTotal.decimal}'),
                  ),
                ),
                const Divider(),
                _row('Subtotal', r.subtotal.decimal),
                _row('Discount', r.discount.decimal),
                _row('TOTAL', r.total.decimal, bold: true),
                Text('Payment: ${paymentLabel(r.paymentMethod)}'),
                if (r.customerName != null) Text('Customer: ${r.customerName}'),
                if (r.dueDate != null)
                  Text('Due date: ${_dateOnly(r.dueDate!)}'),
                if (r.reference != null) Text('Reference: ${r.reference}'),
                const SizedBox(height: 20),
                const Center(child: Text('Thank you')),
                FilledButton.icon(
                  onPressed: () => _exportReceipt(r, true),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Share Receipt PDF'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _exportReceipt(r, false),
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Export PDF'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: ReceiptExport.lines(r).join('\n')),
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Receipt copied. You can paste it into a sharing app.',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.share),
                  label: const Text('SHARE'),
                ),
              ],
            ),
    );
  }

  Future<void> _exportReceipt(ReceiptData receipt, bool share) async {
    try {
      final service = ReceiptExport();
      if (share) {
        await service.share(receipt);
      } else {
        await service.export(receipt);
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'PDF sharing is unavailable. You can copy the receipt text.',
            ),
          ),
        );
      }
    }
  }

  Widget _row(String label, String amount, {bool bold = false}) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null,
      ),
      Text(
        'K$amount',
        style: bold ? Theme.of(context).textTheme.titleLarge : null,
      ),
    ],
  );
  String _date(DateTime value) {
    final z = value.toUtc().add(const Duration(hours: 2));
    return '${z.day.toString().padLeft(2, '0')}/${z.month.toString().padLeft(2, '0')}/${z.year} ${z.hour.toString().padLeft(2, '0')}:${z.minute.toString().padLeft(2, '0')}';
  }

  String _dateOnly(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
}
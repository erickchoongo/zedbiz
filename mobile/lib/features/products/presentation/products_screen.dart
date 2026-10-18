import 'package:flutter/material.dart';
import 'package:zedbiz/app/app_controller.dart';
import 'package:zedbiz/core/network/api_exception.dart';
import 'package:zedbiz/features/businesses/domain/business_summary.dart';
import 'package:zedbiz/features/products/data/product_repository.dart';
import 'package:zedbiz/features/products/domain/product.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({
    required this.controller,
    required this.writable,
    super.key,
  });
  final AppController controller;
  final bool writable;
  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _search = TextEditingController();
  List<Product> _items = [];
  bool _loading = true;
  String? _error;
  bool get _canEdit =>
      widget.controller.online &&
      widget.writable &&
      widget.controller.selectedBusiness!.role != BusinessRole.cashier;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.controller.productGateway.list(
        widget.controller.selectedBusiness!.id,
        search: _search.text,
      );
      if (mounted) setState(() => _items = page.items);
    } on Object catch (e) {
      if (mounted) {
        setState(
          () => _error = e is ApiException
              ? e.message
              : 'Could not load products.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 96),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Products & inventory',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Browse your catalogue and monitor stock levels.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _search,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _load(),
                      decoration: InputDecoration(
                        hintText: 'Search products, SKU or barcode',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: IconButton(
                          tooltip: 'Search products',
                          onPressed: _load,
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
                    const SizedBox(height: 18),
                    if (!widget.writable) ...[
                      Card(
                        color: colors.errorContainer,
                        child: const ListTile(
                          leading: Icon(Icons.lock_outline),
                          title: Text('Read-only inventory'),
                          subtitle: Text(
                            'Renew the subscription to make changes.',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Catalogue',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (!_loading)
                          Text(
                            '${_items.length} shown',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_loading) ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 12),
                    ],
                    if (_error != null) ...[
                      Card(
                        color: colors.errorContainer,
                        child: ListTile(
                          title: Text(_error!),
                          trailing: IconButton(
                            tooltip: 'Retry loading products',
                            onPressed: _load,
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (!_loading && _error == null && _items.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 48,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.inventory_2_outlined,
                              size: 48,
                              color: colors.primary,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No products found',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _search.text.trim().isEmpty
                                  ? 'Add a product or service to start your catalogue.'
                                  : 'Try a different product name, SKU or barcode.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    for (final product in _items) ...[
                      _ProductCard(
                        product: product,
                        onTap: () => _open(product),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _canEdit
          ? FloatingActionButton.extended(
              heroTag: 'add-product-fab',
              onPressed: _add,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add product'),
            )
          : null,
    );
  }

  Future<void> _add() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _AddProductDialog(controller: widget.controller),
    );
    if (created == true) _load();
  }

  Future<void> _open(Product product) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(
          controller: widget.controller,
          product: product,
          writable: _canEdit,
        ),
      ),
    );
    _load();
  }
}

/// Presentation only: product loading and inventory actions stay unchanged.
class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final outOfStock = product.trackInventory &&
        product.stockQuantity.thousandths == 0;
    final lowStock = product.trackInventory &&
        product.isLowStock && !outOfStock;

    final stockLabel = !product.isActive
        ? 'Inactive'
        : !product.trackInventory
            ? 'Service'
            : outOfStock
                ? 'Out of stock'
                : lowStock
                    ? 'Low stock'
                    : '${product.stockQuantity.display} in stock';

    final warning = !product.isActive || outOfStock || lowStock;
    final statusColor = warning ? colors.error : colors.primary;
    final statusBackground = warning
        ? colors.errorContainer.withValues(alpha: 0.50)
        : colors.primaryContainer.withValues(alpha: 0.55);

    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  product.trackInventory
                      ? Icons.inventory_2_outlined
                      : Icons.miscellaneous_services_outlined,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      product.sku == null || product.sku!.isEmpty
                          ? 'No SKU'
                          : 'SKU: ${product.sku}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusBackground,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        stockLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'K${product.sellingPrice}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddProductDialog extends StatefulWidget {
  const _AddProductDialog({required this.controller});
  final AppController controller;
  @override
  State<_AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<_AddProductDialog> {
  final _form = GlobalKey<FormState>();
  final name = TextEditingController(),
      sku = TextEditingController(),
      price = TextEditingController(),
      cost = TextEditingController(text: '0.00'),
      opening = TextEditingController(text: '0'),
      threshold = TextEditingController(text: '0');
  bool tracked = true, busy = false;
  String? error;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add product or service'),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(name, 'Name', required: true),
              _field(sku, 'SKU (optional)'),
              _field(price, 'Selling price', money: true),
              _field(cost, 'Cost price', money: true),
              SwitchListTile(
                value: tracked,
                onChanged: (v) => setState(() => tracked = v),
                title: const Text('Track inventory'),
              ),
              if (tracked) ...[
                _field(opening, 'Opening stock', quantity: true),
                _field(threshold, 'Low-stock alert at', quantity: true),
              ],
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: busy ? null : _save,
        child: Text(busy ? 'Saving…' : 'Save'),
      ),
    ],
  );
  Widget _field(
    TextEditingController c,
    String label, {
    bool required = false,
    bool money = false,
    bool quantity = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      controller: c,
      keyboardType: (money || quantity)
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(labelText: label),
      validator: (v) {
        if ((required || money) && (v?.trim().isEmpty ?? true)) {
          return 'Required';
        }
        if (money && !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(v!.trim())) {
          return 'Use up to 2 decimal places';
        }
        if (quantity) {
          try {
            Quantity.parse(v!);
          } on FormatException catch (e) {
            return e.message;
          }
        }
        return null;
      },
    ),
  );
  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.controller.productGateway.create(
        widget.controller.selectedBusiness!.id,
        {
          'name': name.text.trim(),
          'sku': sku.text.trim().isEmpty ? null : sku.text.trim(),
          'cost_price': cost.text.trim(),
          'selling_price': price.text.trim(),
          'track_inventory': tracked,
          'opening_stock': tracked
              ? Quantity.parse(opening.text).apiValue
              : '0.000',
          'low_stock_threshold': tracked
              ? Quantity.parse(threshold.text).apiValue
              : '0.000',
          'client_operation_id': newOperationId(),
        },
      );
      if (mounted) Navigator.pop(context, true);
    } on Object catch (e) {
      setState(
        () => error = e is ApiException ? e.message : 'Could not save product.',
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({
    required this.controller,
    required this.product,
    required this.writable,
    super.key,
  });
  final AppController controller;
  final Product product;
  final bool writable;
  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late Product product = widget.product;
  List<InventoryMovement>? history;
  String? error;
  @override
  void initState() {
    super.initState();
    _history();
  }

  Future<void> _history() async {
    try {
      final value = await widget.controller.productGateway.history(
        widget.controller.selectedBusiness!.id,
        product.id,
      );
      if (mounted) setState(() => history = value);
    } catch (_) {
      if (mounted) setState(() => history = []);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(product.name)),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'ZMW ${product.sellingPrice}',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        Text(
          product.trackInventory
              ? '${product.stockQuantity.display} in stock'
              : 'Service • stock not tracked',
        ),
        if (product.isLowStock)
          const Chip(
            avatar: Icon(Icons.warning_amber),
            label: Text('Low stock'),
          ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (widget.controller.online &&
            widget.writable &&
            product.trackInventory &&
            product.isActive)
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => _stock('add'),
                icon: const Icon(Icons.add),
                label: const Text('Add stock'),
              ),
              OutlinedButton(
                onPressed: () => _stock('adjust'),
                child: const Text('Adjust'),
              ),
              OutlinedButton(
                onPressed: () => _stock('damaged'),
                child: const Text('Damaged'),
              ),
              OutlinedButton(
                onPressed: () => _stock('lost'),
                child: const Text('Lost'),
              ),
            ],
          ),
        if (widget.controller.online && widget.writable)
          TextButton.icon(
            onPressed: _toggle,
            icon: Icon(
              product.isActive ? Icons.archive_outlined : Icons.unarchive,
            ),
            label: Text(product.isActive ? 'Deactivate' : 'Reactivate'),
          ),
        const Divider(),
        Text(
          'Inventory history',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (history == null) const LinearProgressIndicator(),
        ...(history ?? const <InventoryMovement>[]).map(
          (m) => ListTile(
            leading: Icon(
              m.delta.startsWith('-')
                  ? Icons.remove_circle_outline
                  : Icons.add_circle_outline,
            ),
            title: Text(m.label),
            subtitle: Text(
              '${m.actor} • ${_date(m.createdAt)}${m.reason == null ? '' : '\n${m.reason}'}',
            ),
            trailing: Text(
              '${m.delta}\n→ ${m.after}',
              textAlign: TextAlign.end,
            ),
          ),
        ),
      ],
    ),
  );
  Future<void> _stock(String action) async {
    final q = TextEditingController();
    final reason = TextEditingController();
    final operationId = newOperationId();
    final reduction = action == 'damaged' || action == 'lost';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${action[0].toUpperCase()}${action.substring(1)} stock'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: q,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: action == 'adjust' ? 'Target quantity' : 'Quantity',
              ),
            ),
            if (action != 'add')
              TextField(
                controller: reason,
                decoration: const InputDecoration(
                  labelText: 'Reason (required)',
                ),
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
            child: Text(reduction ? 'Confirm reduction' : 'Apply'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final quantity = Quantity.parse(q.text).apiValue;
      final payload = <String, dynamic>{
        action == 'adjust' ? 'target_quantity' : 'quantity': quantity,
        'client_operation_id': operationId,
      };
      if (action != 'add') payload['reason'] = reason.text.trim();
      await widget.controller.productGateway.stock(
        widget.controller.selectedBusiness!.id,
        product.id,
        action,
        payload,
      );
      final page = await widget.controller.productGateway.list(
        widget.controller.selectedBusiness!.id,
        search: product.name,
      );
      if (page.items.isNotEmpty) product = page.items.first;
      await _history();
      setState(() => error = null);
    } on Object catch (e) {
      setState(
        () => error = e is ApiException
            ? e.message
            : 'Stock change failed. Retry safely.',
      );
    }
  }

  Future<void> _toggle() async {
    try {
      product = await widget.controller.productGateway.setActive(
        widget.controller.selectedBusiness!.id,
        product.id,
        !product.isActive,
      );
      setState(() => error = null);
    } on Object catch (e) {
      setState(
        () =>
            error = e is ApiException ? e.message : 'Could not update product.',
      );
    }
  }

  String _date(DateTime value) {
    final z = value.toUtc().add(const Duration(hours: 2));
    return '${z.day.toString().padLeft(2, '0')}/${z.month.toString().padLeft(2, '0')}/${z.year}';
  }
}
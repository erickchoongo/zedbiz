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
  Widget build(BuildContext context) => Scaffold(
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              labelText: 'Search products, SKU or barcode',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: _load,
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
          ),
          if (!widget.writable)
            const Card(
              child: ListTile(
                leading: Icon(Icons.lock_outline),
                title: Text('Read-only inventory'),
                subtitle: Text('Renew the subscription to make changes.'),
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
          if (!_loading && _error == null && _items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Column(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 56),
                  SizedBox(height: 12),
                  Text('No products yet'),
                  Text('Add a product or service to start your catalogue.'),
                ],
              ),
            ),
          ..._items.map(
            (p) => Card(
              child: ListTile(
                onTap: () => _open(p),
                leading: CircleAvatar(
                  child: Icon(
                    p.trackInventory
                        ? Icons.inventory_2
                        : Icons.miscellaneous_services,
                  ),
                ),
                title: Text(p.name),
                subtitle: Text(
                  '${p.sku ?? 'No SKU'} • ZMW ${p.sellingPrice}${p.trackInventory ? ' • ${p.stockQuantity.display} in stock' : ''}',
                ),
                trailing: p.isLowStock
                    ? const Tooltip(
                        message: 'Low stock',
                        child: Icon(Icons.warning_amber, color: Colors.orange),
                      )
                    : const Icon(Icons.chevron_right),
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
            icon: const Icon(Icons.add),
            label: const Text('Add product'),
          )
        : null,
  );
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

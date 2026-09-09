import 'package:zedbiz/core/offline/sync_status_screen.dart';
import 'package:flutter/material.dart';
import 'package:zedbiz/app/app_controller.dart';
import 'package:zedbiz/core/network/api_exception.dart';
import 'package:zedbiz/features/businesses/domain/business_summary.dart';
import 'package:zedbiz/features/customers/domain/customer.dart';
import 'package:zedbiz/features/debts/domain/debt.dart';
import 'package:zedbiz/features/debts/presentation/debts_screen.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({
    required this.controller,
    required this.writable,
    super.key,
  });

  final AppController controller;
  final bool writable;

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _search = TextEditingController();
  List<CustomerSummary> _items = const [];
  bool _loading = true, _outstandingOnly = false;
  bool? _active = true;
  String? _error;
  int _page = 1, _total = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) _page = 1;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final business = widget.controller.selectedBusiness!;
      final result = await widget.controller.customerGateway.list(
        business.id,
        business.currency,
        page: _page,
        search: _search.text,
        active: _active,
        outstandingOnly: _outstandingOnly,
      );
      if (!mounted) return;
      setState(() {
        _items = reset ? result.items : [..._items, ...result.items];
        _total = result.total;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is ApiException
            ? error.message
            : 'Could not load customers.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Customers')),
    body: RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CacheFreshness(
            client: widget.controller.offline,
            path:
                '/api/v1/businesses/${widget.controller.selectedBusiness!.id}/customers?page=1&page_size=20',
          ),
          if (!widget.writable)
            const Card(
              child: ListTile(
                leading: Icon(Icons.lock_outline),
                title: Text('Customers are read-only'),
                subtitle: Text('Customer and credit history remain available.'),
              ),
            ),
          TextField(
            key: const Key('customer-search'),
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _load(reset: true),
            decoration: InputDecoration(
              labelText: 'Search name, phone or email',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: () => _load(reset: true),
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _filter('All', _active == null && !_outstandingOnly, () {
                _active = null;
                _outstandingOnly = false;
              }),
              _filter('Active', _active == true && !_outstandingOnly, () {
                _active = true;
                _outstandingOnly = false;
              }),
              _filter('Inactive', _active == false, () {
                _active = false;
                _outstandingOnly = false;
              }),
              _filter('Owing', _outstandingOnly, () {
                _active = true;
                _outstandingOnly = true;
              }),
            ],
          ),
          if (_loading && _items.isEmpty) const LinearProgressIndicator(),
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                title: Text(_error!),
                trailing: IconButton(
                  onPressed: () => _load(reset: true),
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ),
          if (!_loading && _error == null && _items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(36),
              child: Column(
                children: [
                  Icon(Icons.people_outline, size: 56),
                  SizedBox(height: 12),
                  Text('No customers yet'),
                  Text('Add a customer when you sell on credit.'),
                ],
              ),
            ),
          ..._items.map(
            (customer) => Card(
              child: ListTile(
                key: Key('customer-${customer.id}'),
                onTap: () => _open(customer.id),
                leading: CircleAvatar(
                  child: Text(
                    customer.name.trim().isEmpty
                        ? '?'
                        : customer.name.trim()[0].toUpperCase(),
                  ),
                ),
                title: Row(
                  children: [
                    Expanded(child: Text(customer.name)),
                    if (!customer.isActive) const Chip(label: Text('INACTIVE')),
                  ],
                ),
                subtitle: Text(
                  '${customer.phoneNumber ?? customer.email ?? 'No contact details'}\nOwes K${customer.totalOutstanding.decimal}',
                ),
                isThreeLine: true,
                trailing: customer.totalOverdue.minorUnits > 0
                    ? const Chip(
                        avatar: Icon(Icons.schedule, size: 16),
                        label: Text('OVERDUE'),
                      )
                    : const Icon(Icons.chevron_right),
              ),
            ),
          ),
          if (_items.length < _total)
            OutlinedButton(
              onPressed: _loading
                  ? null
                  : () {
                      _page++;
                      _load();
                    },
              child: const Text('Load more'),
            ),
        ],
      ),
    ),
    floatingActionButton: widget.writable
        ? FloatingActionButton.extended(
            heroTag: 'add-customer-fab',
            key: const Key('add-customer'),
            onPressed: _add,
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('ADD CUSTOMER'),
          )
        : null,
  );

  Widget _filter(String label, bool selected, VoidCallback update) =>
      ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(update);
          _load(reset: true);
        },
      );

  Future<void> _add() async {
    final created = await showDialog<CustomerDetail>(
      context: context,
      builder: (_) => AddCustomerDialog(controller: widget.controller),
    );
    if (created != null) _load(reset: true);
  }

  Future<void> _open(String id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerDetailScreen(
          controller: widget.controller,
          customerId: id,
          writable: widget.writable,
        ),
      ),
    );
    _load(reset: true);
  }
}

class AddCustomerDialog extends StatefulWidget {
  const AddCustomerDialog({required this.controller, this.existing, super.key});

  final AppController controller;
  final CustomerDetail? existing;

  @override
  State<AddCustomerDialog> createState() => _AddCustomerDialogState();
}

class _AddCustomerDialogState extends State<AddCustomerDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _notes;
  bool _busy = false;
  String? _error;

  bool get _canUseNotes =>
      widget.controller.selectedBusiness!.role != BusinessRole.cashier;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name);
    _phone = TextEditingController(text: widget.existing?.phoneNumber);
    _email = TextEditingController(text: widget.existing?.email);
    _notes = TextEditingController(text: widget.existing?.notes);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? 'Add customer' : 'Edit customer'),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('customer-name'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name *'),
                validator: (value) => value?.trim().isEmpty ?? true
                    ? 'Customer name is required.'
                    : null,
              ),
              TextFormField(
                key: const Key('customer-phone'),
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone (optional)',
                  hintText: '097xxxxxxx',
                ),
                validator: customerPhoneError,
              ),
              TextFormField(
                key: const Key('customer-email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email (optional)',
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return null;
                  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)
                      ? null
                      : 'Enter a valid email address.';
                },
              ),
              if (_canUseNotes)
                TextFormField(
                  key: const Key('customer-notes'),
                  controller: _notes,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Internal notes (optional)',
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('save-customer'),
        onPressed: _busy ? null : _save,
        child: Text(_busy ? 'Saving…' : 'Save'),
      ),
    ],
  );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final business = widget.controller.selectedBusiness!;
    final payload = <String, dynamic>{
      'name': _name.text.trim(),
      'phone_number': _optional(_phone.text),
      'email': _optional(_email.text),
      if (_canUseNotes) 'notes': _optional(_notes.text),
    };
    try {
      final existing = widget.existing;
      final result = existing == null
          ? await widget.controller.customerGateway.create(
              business.id,
              business.currency,
              payload,
            )
          : await widget.controller.customerGateway.update(
              business.id,
              existing.id,
              business.currency,
              payload,
            );
      if (mounted) Navigator.pop(context, result);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is ApiException
            ? error.message
            : 'Could not save the customer.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _optional(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class CustomerPickerSheet extends StatefulWidget {
  const CustomerPickerSheet({
    required this.controller,
    required this.allowCreate,
    super.key,
  });

  final AppController controller;
  final bool allowCreate;

  @override
  State<CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<CustomerPickerSheet> {
  final _search = TextEditingController();
  List<CustomerSummary> _items = const [];
  bool _loading = true;
  String? _error;

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
      final business = widget.controller.selectedBusiness!;
      final page = await widget.controller.customerGateway.list(
        business.id,
        business.currency,
        search: _search.text,
        active: true,
      );
      if (mounted) setState(() => _items = page.items);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is ApiException
            ? error.message
            : 'Could not load customers.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .7,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Select customer',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (widget.allowCreate)
                  TextButton.icon(
                    key: const Key('credit-add-customer'),
                    onPressed: _add,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Add customer'),
                  ),
              ],
            ),
            TextField(
              key: const Key('customer-picker-search'),
              controller: _search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                labelText: 'Search name, phone or email',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.arrow_forward),
                ),
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) Text(_error!),
            Expanded(
              child: _items.isEmpty && !_loading
                  ? const Center(child: Text('No active customers found'))
                  : ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final customer = _items[index];
                        return ListTile(
                          title: Text(customer.name),
                          subtitle: Text(
                            customer.phoneNumber ??
                                customer.email ??
                                'No contact details',
                          ),
                          trailing: Text(
                            'Owes K${customer.totalOutstanding.decimal}',
                          ),
                          onTap: () => Navigator.pop(context, customer),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _add() async {
    final created = await showDialog<CustomerDetail>(
      context: context,
      builder: (_) => AddCustomerDialog(controller: widget.controller),
    );
    if (created == null || !mounted) return;
    Navigator.pop<CustomerSummary>(context, created);
  }
}

class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({
    required this.controller,
    required this.customerId,
    required this.writable,
    super.key,
  });

  final AppController controller;
  final String customerId;
  final bool writable;

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  CustomerDetail? _customer;
  String? _error;
  bool _busy = false;

  bool get _canManage =>
      widget.writable &&
      widget.controller.selectedBusiness!.role != BusinessRole.cashier;

  DebtSummary? get _firstOpen {
    for (final debt in _customer?.recentDebts ?? const <DebtSummary>[]) {
      if (debt.acceptsPayment) return debt;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final business = widget.controller.selectedBusiness!;
      final value = await widget.controller.customerGateway.detail(
        business.id,
        widget.customerId,
        business.currency,
      );
      if (mounted) setState(() => _customer = value);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is ApiException
            ? error.message
            : 'Could not load this customer.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final customer = _customer;
    return Scaffold(
      appBar: AppBar(
        title: Text(customer?.name ?? 'Customer'),
        actions: [
          if (_canManage && customer != null)
            IconButton(
              key: const Key('edit-customer'),
              onPressed: _edit,
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit customer',
            ),
        ],
      ),
      body: customer == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Text(_error!),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (!customer.isActive)
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.person_off_outlined),
                        title: Text('Inactive customer'),
                        subtitle: Text(
                          'This customer cannot be used for a new credit sale.',
                        ),
                      ),
                    ),
                  ListTile(
                    leading: const Icon(Icons.phone_outlined),
                    title: Text(customer.phoneNumber ?? 'No phone number'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.email_outlined),
                    title: Text(customer.email ?? 'No email address'),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _metric(
                          context,
                          'TOTAL OWED',
                          'K${customer.totalOutstanding.decimal}',
                        ),
                      ),
                      Expanded(
                        child: _metric(
                          context,
                          'OVERDUE',
                          'K${customer.totalOverdue.decimal}',
                          overdue: customer.totalOverdue.minorUnits > 0,
                        ),
                      ),
                    ],
                  ),
                  if (customer.notes != null)
                    ListTile(
                      leading: const Icon(Icons.notes),
                      title: const Text('Internal notes'),
                      subtitle: Text(customer.notes!),
                    ),
                  if (!widget.writable)
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.lock_outline),
                        title: Text('Credit history is read-only'),
                      ),
                    ),
                  if (widget.writable && _firstOpen != null)
                    FilledButton.icon(
                      key: const Key('customer-record-payment'),
                      onPressed: () => _openDebt(_firstOpen!),
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('RECORD PAYMENT'),
                    ),
                  if (_firstOpen != null)
                    OutlinedButton.icon(
                      key: const Key('customer-share-reminder'),
                      onPressed: () => _openDebt(_firstOpen!),
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('SHARE REMINDER'),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    'Recent credit',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (customer.recentDebts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('No customer credit recorded.'),
                    ),
                  ...customer.recentDebts.map(
                    (debt) => Card(
                      child: ListTile(
                        onTap: () => _openDebt(debt),
                        title: Text(debt.saleNumber ?? 'Credit sale'),
                        subtitle: Text(
                          '${_dueText(debt)}\n${debtStatusLabel(debt.status)}',
                        ),
                        isThreeLine: true,
                        trailing: Text(
                          'K${debt.outstandingAmount.decimal}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                  if (_canManage)
                    OutlinedButton.icon(
                      key: const Key('toggle-customer-active'),
                      onPressed: _busy ? null : _toggleActive,
                      icon: Icon(
                        customer.isActive
                            ? Icons.person_off_outlined
                            : Icons.person_add_alt,
                      ),
                      label: Text(
                        customer.isActive ? 'DEACTIVATE' : 'REACTIVATE',
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _metric(
    BuildContext context,
    String label,
    String amount, {
    bool overdue = false,
  }) => Card(
    color: overdue ? Theme.of(context).colorScheme.errorContainer : null,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Text(amount, style: Theme.of(context).textTheme.headlineSmall),
        ],
      ),
    ),
  );

  String _dueText(DebtSummary debt) {
    if (debt.status == DebtStatus.paid) return 'Paid in full';
    if (debt.status == DebtStatus.voided) return 'Voided';
    if (debt.dueDate == null) return 'No due date';
    final value = debt.dueDate!;
    return '${debt.isOverdue ? 'Overdue' : 'Due'} ${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
  }

  Future<void> _openDebt(DebtSummary debt) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DebtDetailScreen(
          controller: widget.controller,
          debtId: debt.id,
          writable: widget.writable,
        ),
      ),
    );
    _load();
  }

  Future<void> _edit() async {
    final updated = await showDialog<CustomerDetail>(
      context: context,
      builder: (_) =>
          AddCustomerDialog(controller: widget.controller, existing: _customer),
    );
    if (updated != null) setState(() => _customer = updated);
  }

  Future<void> _toggleActive() async {
    final customer = _customer!;
    setState(() => _busy = true);
    try {
      final business = widget.controller.selectedBusiness!;
      final updated = await widget.controller.customerGateway.setActive(
        business.id,
        customer.id,
        business.currency,
        !customer.isActive,
      );
      if (mounted) setState(() => _customer = updated);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ApiException
                ? error.message
                : 'Could not update this customer.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

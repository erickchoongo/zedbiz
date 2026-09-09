import 'package:flutter/material.dart';
import 'package:zedbiz/app/app_controller.dart';
import 'package:zedbiz/core/network/api_exception.dart';
import 'package:zedbiz/features/businesses/domain/business_summary.dart';
import 'package:zedbiz/features/expenses/domain/expense.dart';
import 'package:zedbiz/features/products/data/product_repository.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({
    required this.controller,
    required this.writable,
    super.key,
  });
  final AppController controller;
  final bool writable;

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final _search = TextEditingController();
  List<ExpenseRecord> _items = const [];
  ExpenseCategory? _category;
  ExpenseStatus? _status;
  DateTimeRange? _dates;
  bool _loading = true;
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
      final result = await widget.controller.expenseGateway.list(
        business.id,
        business.currency,
        page: _page,
        search: _search.text,
        category: _category,
        status: _status,
        dateFrom: _dates?.start,
        dateTo: _dates?.end,
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
            : 'Could not load expenses.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Expenses')),
    body: RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!widget.writable)
            const Card(
              child: ListTile(
                leading: Icon(Icons.lock_outline),
                title: Text('Expenses are read-only'),
                subtitle: Text('Historical expenses remain available.'),
              ),
            ),
          TextField(
            key: const Key('expense-search'),
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _load(reset: true),
            decoration: InputDecoration(
              labelText: 'Search description or reference',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: () => _load(reset: true),
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: const Text('All categories'),
                  selected: _category == null,
                  onSelected: (_) {
                    setState(() => _category = null);
                    _load(reset: true);
                  },
                ),
                const SizedBox(width: 6),
                ...ExpenseCategory.values.map(
                  (category) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(expenseCategoryLabel(category)),
                      selected: _category == category,
                      onSelected: (_) {
                        setState(() => _category = category);
                        _load(reset: true);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: _status == null,
                onSelected: (_) {
                  setState(() => _status = null);
                  _load(reset: true);
                },
              ),
              ChoiceChip(
                label: const Text('Recorded'),
                selected: _status == ExpenseStatus.recorded,
                onSelected: (_) {
                  setState(() => _status = ExpenseStatus.recorded);
                  _load(reset: true);
                },
              ),
              ChoiceChip(
                label: const Text('Voided'),
                selected: _status == ExpenseStatus.voided,
                onSelected: (_) {
                  setState(() => _status = ExpenseStatus.voided);
                  _load(reset: true);
                },
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              avatar: const Icon(Icons.date_range_outlined, size: 18),
              label: Text(
                _dates == null
                    ? 'All dates'
                    : '${_date(_dates!.start)} – ${_date(_dates!.end)}',
              ),
              selected: _dates != null,
              onSelected: (_) async {
                if (_dates != null) {
                  setState(() => _dates = null);
                  await _load(reset: true);
                  return;
                }
                final selected = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (selected != null) {
                  setState(() => _dates = selected);
                  await _load(reset: true);
                }
              },
            ),
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
                  Icon(Icons.payments_outlined, size: 56),
                  SizedBox(height: 12),
                  Text('No expenses found'),
                  Text('Recorded business costs will appear here.'),
                ],
              ),
            ),
          ..._items.map(
            (expense) => Card(
              child: ListTile(
                key: Key('expense-${expense.id}'),
                onTap: () => _open(expense),
                leading: CircleAvatar(
                  child: Icon(
                    expense.status == ExpenseStatus.voided
                        ? Icons.block
                        : Icons.payments_outlined,
                  ),
                ),
                title: Text(
                  '${expense.description}${expense.localSyncState == null ? '' : ' • ${expense.localSyncState!.toUpperCase()}'}',
                ),
                subtitle: Text(
                  '${expenseCategoryLabel(expense.category)} • ${_date(expense.expenseDate)}'
                  '${expense.status == ExpenseStatus.voided ? ' • VOIDED' : ''}',
                ),
                trailing: Text(
                  'K${expense.amount.decimal}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
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
              child: const Text('LOAD MORE'),
            ),
        ],
      ),
    ),
    floatingActionButton: widget.writable
        ? FloatingActionButton.extended(
            key: const Key('add-expense'),
            heroTag: 'add-expense-fab',
            onPressed: _add,
            icon: const Icon(Icons.add),
            label: const Text('Add expense'),
          )
        : null,
  );

  Future<void> _add() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseFormScreen(controller: widget.controller),
      ),
    );
    if (created == true) _load(reset: true);
  }

  Future<void> _open(ExpenseRecord expense) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseDetailScreen(
          controller: widget.controller,
          expense: expense,
          writable: widget.writable,
        ),
      ),
    );
    _load(reset: true);
  }
}

class ExpenseFormScreen extends StatefulWidget {
  const ExpenseFormScreen({
    required this.controller,
    this.operationId,
    super.key,
  });
  final AppController controller;
  final String? operationId;

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  final _form = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  late final String _operationId;
  ExpenseCategory _category = ExpenseCategory.stockPurchase;
  ExpensePaymentMethod _method = ExpensePaymentMethod.cash;
  DateTime _expenseDate = DateTime.now();
  bool _busy = false;
  String? _error;

  bool get _isCashier =>
      widget.controller.selectedBusiness!.role == BusinessRole.cashier;

  @override
  void initState() {
    super.initState();
    _operationId = widget.operationId ?? newOperationId();
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Record expense')),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          DropdownButtonFormField<ExpenseCategory>(
            key: const Key('expense-category'),
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category *'),
            items: ExpenseCategory.values
                .map(
                  (item) => DropdownMenuItem(
                    value: item,
                    child: Text(expenseCategoryLabel(item)),
                  ),
                )
                .toList(),
            onChanged: _busy
                ? null
                : (value) => setState(() => _category = value!),
          ),
          TextFormField(
            key: const Key('expense-description'),
            controller: _description,
            decoration: const InputDecoration(labelText: 'Description *'),
            validator: (value) =>
                value?.trim().isEmpty == true ? 'Enter a description' : null,
          ),
          TextFormField(
            key: const Key('expense-amount'),
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount *',
              prefixText: 'K ',
            ),
            validator: (value) {
              final cleaned = value?.trim() ?? '';
              if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(cleaned)) {
                return 'Use an amount with no more than 2 decimal places';
              }
              if (cleaned == '0' || cleaned == '0.0' || cleaned == '0.00') {
                return 'Amount must be greater than zero';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          const Text('Payment method'),
          Wrap(
            spacing: 8,
            children: ExpensePaymentMethod.values
                .map(
                  (method) => ChoiceChip(
                    label: Text(expensePaymentLabel(method)),
                    selected: _method == method,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() => _method = method),
                  ),
                )
                .toList(),
          ),
          TextField(
            key: const Key('expense-reference'),
            controller: _reference,
            decoration: const InputDecoration(
              labelText: 'Payment reference (optional)',
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today_outlined),
            title: const Text('Expense date'),
            subtitle: Text(_date(_expenseDate)),
            onTap: _busy ? null : _pickDate,
          ),
          if (!_isCashier)
            TextField(
              key: const Key('expense-notes'),
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Private notes (optional)',
              ),
            ),
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!),
              ),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const Key('submit-expense'),
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text('RECORD EXPENSE'),
          ),
        ],
      ),
    ),
  );

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _expenseDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (selected != null) setState(() => _expenseDate = selected);
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final business = widget.controller.selectedBusiness!;
      final saved = await widget.controller.expenseGateway.create(
        business.id,
        business.currency,
        {
          'client_operation_id': _operationId,
          'category': expenseCategoryApi(_category),
          'description': _description.text.trim(),
          'amount': _amount.text.trim(),
          'payment_method': expensePaymentApi(_method),
          'payment_reference': _reference.text.trim().isEmpty
              ? null
              : _reference.text.trim(),
          'expense_date': _expenseDate.toIso8601String().substring(0, 10),
          if (!_isCashier)
            'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        },
      );
      if (mounted) {
        if (saved.localSyncState != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Expense saved on this device — waiting to sync.'),
            ),
          );
        }
        Navigator.pop(context, true);
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error is ApiException
            ? error.message
            : 'Could not record expense. Retry safely.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class ExpenseDetailScreen extends StatefulWidget {
  const ExpenseDetailScreen({
    required this.controller,
    required this.expense,
    required this.writable,
    super.key,
  });
  final AppController controller;
  final ExpenseRecord expense;
  final bool writable;

  @override
  State<ExpenseDetailScreen> createState() => _ExpenseDetailScreenState();
}

class _ExpenseDetailScreenState extends State<ExpenseDetailScreen> {
  late ExpenseRecord _expense = widget.expense;
  bool _busy = false;
  String? _voidOperationId;
  String? _voidReason;

  bool get _canVoid =>
      _expense.localSyncState == null &&
      widget.controller.online &&
      widget.writable &&
      widget.controller.selectedBusiness!.role != BusinessRole.cashier &&
      _expense.status == ExpenseStatus.recorded;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Expense details')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Icon(
          _expense.status == ExpenseStatus.voided
              ? Icons.block
              : Icons.payments_outlined,
          size: 56,
        ),
        Text(
          _expense.description,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text(
          'K${_expense.amount.decimal}',
          style: Theme.of(context).textTheme.displaySmall,
        ),
        Chip(
          label: Text(
            _expense.localSyncState?.toUpperCase() ??
                _expense.status.name.toUpperCase(),
          ),
        ),
        ListTile(
          title: const Text('Category'),
          trailing: Text(expenseCategoryLabel(_expense.category)),
        ),
        ListTile(
          title: const Text('Payment method'),
          trailing: Text(expensePaymentLabel(_expense.paymentMethod)),
        ),
        ListTile(
          title: const Text('Date'),
          trailing: Text(_date(_expense.expenseDate)),
        ),
        ListTile(
          title: const Text('Recorded by'),
          trailing: Text(_expense.recordedByName),
        ),
        if (_expense.paymentReference != null)
          ListTile(
            title: const Text('Reference'),
            trailing: Text(_expense.paymentReference!),
          ),
        if (_expense.notes != null)
          ListTile(title: const Text('Notes'), subtitle: Text(_expense.notes!)),
        if (_expense.voidReason != null)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              title: const Text('Void reason'),
              subtitle: Text(_expense.voidReason!),
            ),
          ),
        if (_canVoid)
          OutlinedButton.icon(
            key: const Key('void-expense'),
            onPressed: _busy ? null : _void,
            icon: const Icon(Icons.block),
            label: const Text('VOID EXPENSE'),
          ),
      ],
    ),
  );

  Future<void> _void() async {
    final reason = TextEditingController(text: _voidReason);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Void expense?'),
        content: TextField(
          controller: reason,
          decoration: const InputDecoration(labelText: 'Reason *'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, reason.text.trim().isNotEmpty),
            child: const Text('VOID'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      reason.dispose();
      return;
    }
    final value = _voidReason ??= reason.text.trim();
    reason.dispose();
    setState(() => _busy = true);
    try {
      final business = widget.controller.selectedBusiness!;
      final updated = await widget.controller.expenseGateway.voidExpense(
        business.id,
        _expense.id,
        business.currency,
        {
          'client_operation_id': _voidOperationId ??= newOperationId(),
          'reason': value,
        },
      );
      if (mounted) {
        setState(() {
          _expense = updated;
          _voidOperationId = null;
          _voidReason = null;
        });
      }
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ApiException ? error.message : 'Could not void expense.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

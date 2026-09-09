import 'package:zedbiz/core/offline/sync_status_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zedbiz/app/app_controller.dart';
import 'package:zedbiz/core/network/api_exception.dart';
import 'package:zedbiz/features/debts/application/repayment_controller.dart';
import 'package:zedbiz/features/debts/domain/debt.dart';

class DebtsScreen extends StatefulWidget {
  const DebtsScreen({
    required this.controller,
    required this.writable,
    super.key,
  });

  final AppController controller;
  final bool writable;

  @override
  State<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends State<DebtsScreen> {
  final _search = TextEditingController();
  List<DebtSummary> _items = const [];
  DebtMetrics? _metrics;
  bool _loading = true, _overdueOnly = false;
  String? _status, _error;
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
      final page = await widget.controller.debtGateway.list(
        business.id,
        business.currency,
        page: _page,
        search: _search.text,
        status: _status,
        overdueOnly: _overdueOnly,
      );
      final metrics = reset
          ? await widget.controller.debtGateway.summary(
              business.id,
              business.currency,
            )
          : _metrics;
      if (!mounted) return;
      setState(() {
        _items = reset ? page.items : [..._items, ...page.items];
        _total = page.total;
        _metrics = metrics;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is ApiException
            ? error.message
            : 'Could not load customer credit.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Money Owed To You')),
    body: RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CacheFreshness(
            client: widget.controller.offline,
            path:
                '/api/v1/businesses/${widget.controller.selectedBusiness!.id}/debts?page=1&page_size=20',
          ),
          if (!widget.writable)
            const Card(
              child: ListTile(
                leading: Icon(Icons.lock_outline),
                title: Text('Customer credit is read-only'),
                subtitle: Text('Debts and repayment history remain available.'),
              ),
            ),
          if (_metrics != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('TOTAL OWED'),
                    Text(
                      'K${_metrics!.totalOutstanding.decimal}',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Text(
                      '${_metrics!.customersOwing} customers • ${_metrics!.openDebtCount} open credit sales',
                    ),
                    if (_metrics!.totalOverdue.minorUnits > 0)
                      Text(
                        'K${_metrics!.totalOverdue.decimal} overdue',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          TextField(
            key: const Key('debt-search'),
            controller: _search,
            onSubmitted: (_) => _load(reset: true),
            decoration: InputDecoration(
              labelText: 'Search customer name or phone',
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
              _filter('All', _status == null && !_overdueOnly, null, false),
              _filter('Open', _status == 'OPEN', 'OPEN', false),
              _filter('Overdue', _overdueOnly, null, true),
              _filter('Paid', _status == 'PAID', 'PAID', false),
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
                  Icon(Icons.account_balance_wallet_outlined, size: 56),
                  SizedBox(height: 12),
                  Text('No customer credit found'),
                  Text('Credit sales will appear here.'),
                ],
              ),
            ),
          ..._items.map(
            (debt) => Card(
              child: ListTile(
                key: Key('debt-${debt.id}'),
                onTap: () => _open(debt.id),
                leading: CircleAvatar(
                  backgroundColor: debt.isOverdue
                      ? Theme.of(context).colorScheme.errorContainer
                      : null,
                  child: Icon(
                    debt.status == DebtStatus.paid
                        ? Icons.check
                        : debt.isOverdue
                        ? Icons.schedule
                        : Icons.credit_score,
                  ),
                ),
                title: Text(debt.customerName),
                subtitle: Text(
                  '${debt.saleNumber ?? 'Credit sale'}\n${_due(debt)} • ${debtStatusLabel(debt.status)}',
                ),
                isThreeLine: true,
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'K${debt.outstandingAmount.decimal}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (debt.isOverdue)
                      Text(
                        'OVERDUE',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
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
              child: const Text('Load more'),
            ),
        ],
      ),
    ),
  );

  Widget _filter(String label, bool selected, String? status, bool overdue) =>
      ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() {
            _status = status;
            _overdueOnly = overdue;
          });
          _load(reset: true);
        },
      );

  Future<void> _open(String id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DebtDetailScreen(
          controller: widget.controller,
          debtId: id,
          writable: widget.writable,
        ),
      ),
    );
    _load(reset: true);
  }

  String _due(DebtSummary debt) {
    if (debt.status == DebtStatus.paid) return 'Paid';
    if (debt.status == DebtStatus.voided) return 'Voided';
    final value = debt.dueDate;
    if (value == null) return 'No due date';
    return '${debt.isOverdue ? 'Overdue' : 'Due'} ${_dateOnly(value)}';
  }
}

class DebtDetailScreen extends StatefulWidget {
  const DebtDetailScreen({
    required this.controller,
    required this.debtId,
    required this.writable,
    super.key,
  });

  final AppController controller;
  final String debtId;
  final bool writable;

  @override
  State<DebtDetailScreen> createState() => _DebtDetailScreenState();
}

class _DebtDetailScreenState extends State<DebtDetailScreen> {
  DebtDetail? _debt;
  List<DebtPayment> _payments = const [];
  String? _error;
  bool _reminderBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final business = widget.controller.selectedBusiness!;
      final debt = await widget.controller.debtGateway.detail(
        business.id,
        widget.debtId,
        business.currency,
      );
      final payments = await widget.controller.debtGateway.payments(
        business.id,
        widget.debtId,
        business.currency,
      );
      if (!mounted) return;
      setState(() {
        _debt = debt;
        _payments = payments.items;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is ApiException
            ? error.message
            : 'Could not load this credit record.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final debt = _debt;
    return Scaffold(
      appBar: AppBar(title: const Text('Customer Credit')),
      body: debt == null
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
                  Text(
                    debt.customerName,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(debt.customerPhoneNumber ?? 'No phone number'),
                  const SizedBox(height: 12),
                  Card(
                    color: debt.isOverdue
                        ? Theme.of(context).colorScheme.errorContainer
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _amount('Original', debt.originalAmount.decimal),
                          _amount('Paid', debt.amountPaid.decimal),
                          const Divider(),
                          _amount(
                            'REMAINING',
                            debt.outstandingAmount.decimal,
                            bold: true,
                          ),
                          const SizedBox(height: 8),
                          Chip(label: Text(debtStatusLabel(debt.status))),
                          if (debt.isOverdue)
                            const Chip(
                              avatar: Icon(Icons.schedule, size: 16),
                              label: Text('OVERDUE'),
                            ),
                          Text(_due(debt)),
                        ],
                      ),
                    ),
                  ),
                  if (!widget.writable)
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.lock_outline),
                        title: Text('Repayments are read-only'),
                        subtitle: Text(
                          'Historical balances and payments remain available.',
                        ),
                      ),
                    ),
                  if (!widget.controller.online)
                    const Text('Repayments require an internet connection.'),
                  if (widget.writable && debt.acceptsPayment)
                    FilledButton.icon(
                      key: const Key('record-payment'),
                      onPressed: widget.controller.online
                          ? _recordPayment
                          : null,
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('RECORD PAYMENT'),
                    ),
                  if (debt.acceptsPayment)
                    OutlinedButton.icon(
                      key: const Key('share-reminder'),
                      onPressed: _reminderBusy ? null : _showReminder,
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('SHARE REMINDER'),
                    ),
                  if (debt.saleNumber != null)
                    ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text('Sale ${debt.saleNumber}'),
                      subtitle: const Text(
                        'This credit originated from a sale.',
                      ),
                    ),
                  const Divider(),
                  Text(
                    'Payment history',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (_payments.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('No payments recorded yet.'),
                    ),
                  ..._payments.map(
                    (payment) => ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.payments_outlined),
                      ),
                      title: Text('K${payment.amount.decimal} received'),
                      subtitle: Text(
                        '${debtPaymentLabel(payment.paymentMethod)} • ${_dateTime(payment.paidAt)}\nReceived by ${payment.receivedByName}${payment.paymentReference == null ? '' : ' • ${payment.paymentReference}'}',
                      ),
                      isThreeLine: true,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

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
          style: bold ? Theme.of(context).textTheme.headlineSmall : null,
        ),
      ],
    ),
  );

  String _due(DebtSummary debt) {
    if (debt.status == DebtStatus.paid) {
      return debt is DebtDetail && debt.settledAt != null
          ? 'Paid ${_dateOnly(debt.settledAt!)}'
          : 'Paid in full';
    }
    if (debt.status == DebtStatus.voided) return 'Voided credit sale';
    if (debt.dueDate == null) return 'No due date';
    return 'Due ${_dateOnly(debt.dueDate!)}';
  }

  Future<void> _recordPayment() async {
    final debt = _debt!;
    final result = await Navigator.push<RepaymentResult>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            RepaymentScreen(controller: widget.controller, debt: debt),
      ),
    );
    if (result != null) {
      setState(() => _debt = result.debt);
      await _load();
    }
  }

  Future<void> _showReminder() async {
    setState(() => _reminderBusy = true);
    try {
      final business = widget.controller.selectedBusiness!;
      final reminder = await widget.controller.debtGateway.reminder(
        business.id,
        widget.debtId,
        business.currency,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Payment reminder'),
          content: SelectableText(reminder.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              key: const Key('copy-reminder'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: reminder.message));
                if (context.mounted) Navigator.pop(context);
                if (!mounted) return;
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Reminder copied. Paste it into WhatsApp or another app.',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.copy),
              label: const Text('COPY REMINDER'),
            ),
          ],
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ApiException
                ? error.message
                : 'Could not prepare the reminder.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _reminderBusy = false);
    }
  }
}

class RepaymentScreen extends StatefulWidget {
  const RepaymentScreen({
    required this.controller,
    required this.debt,
    this.operationId,
    super.key,
  });

  final AppController controller;
  final DebtDetail debt;
  final String? operationId;

  @override
  State<RepaymentScreen> createState() => _RepaymentScreenState();
}

class _RepaymentScreenState extends State<RepaymentScreen> {
  late final RepaymentController _repayment;
  final _amount = TextEditingController();
  final _reference = TextEditingController();

  @override
  void initState() {
    super.initState();
    final business = widget.controller.selectedBusiness!;
    _repayment = RepaymentController(
      gateway: widget.controller.debtGateway,
      businessId: business.id,
      debtId: widget.debt.id,
      currency: business.currency,
      outstanding: widget.debt.outstandingAmount,
      operationId: widget.operationId,
    )..addListener(_changed);
  }

  @override
  void dispose() {
    _repayment.removeListener(_changed);
    _repayment.dispose();
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Record payment')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          widget.debt.customerName,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text('Outstanding'),
        Text(
          'K${_repayment.outstanding.decimal}',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        TextField(
          key: const Key('repayment-amount'),
          controller: _amount,
          enabled: !_repayment.busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: _repayment.setAmount,
          decoration: const InputDecoration(labelText: 'Amount received *'),
        ),
        if (_repayment.amountInput.isNotEmpty &&
            _repayment.validationMessage != null)
          Text(
            _repayment.validationMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (_repayment.previewRemaining != null)
          Card(
            child: ListTile(
              title: const Text('Remaining after payment'),
              trailing: Text(
                'K${_repayment.previewRemaining!.decimal}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        const SizedBox(height: 12),
        const Text('Payment method'),
        Wrap(
          spacing: 8,
          children: DebtPaymentMethod.values
              .map(
                (method) => ChoiceChip(
                  label: Text(debtPaymentLabel(method)),
                  selected: _repayment.paymentMethod == method,
                  onSelected: _repayment.busy
                      ? null
                      : (_) => _repayment.setPaymentMethod(method),
                ),
              )
              .toList(),
        ),
        TextField(
          key: const Key('repayment-reference'),
          controller: _reference,
          enabled: !_repayment.busy,
          onChanged: (value) => _repayment.paymentReference = value,
          decoration: const InputDecoration(
            labelText: 'Payment reference (optional)',
          ),
        ),
        if (_repayment.errorMessage != null)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_repayment.errorMessage!),
            ),
          ),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const Key('submit-repayment'),
          onPressed: _repayment.busy ? null : _submit,
          icon: _repayment.busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: const Text('RECORD PAYMENT'),
        ),
      ],
    ),
  );

  Future<void> _submit() async {
    _repayment.paymentReference = _reference.text;
    final result = await _repayment.record();
    if (result == null || !mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => RepaymentConfirmationScreen(
          businessName: widget.controller.selectedBusiness!.name,
          result: result,
        ),
      ),
    );
    if (mounted) Navigator.pop(context, result);
  }
}

class RepaymentConfirmationScreen extends StatelessWidget {
  const RepaymentConfirmationScreen({
    required this.businessName,
    required this.result,
    super.key,
  });

  final String businessName;
  final RepaymentResult result;

  String get confirmationText => [
    businessName,
    'PAYMENT CONFIRMATION',
    'Customer: ${result.payment.customerName}',
    'Amount received: K${result.payment.amount.decimal}',
    'Payment method: ${debtPaymentLabel(result.payment.paymentMethod)}',
    if (result.payment.paymentReference != null)
      'Reference: ${result.payment.paymentReference}',
    'Remaining balance: K${result.debt.outstandingAmount.decimal}',
    'Date: ${_dateTime(result.payment.paidAt)}',
    'Received by: ${result.payment.receivedByName}',
  ].join('\n');

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Payment recorded'),
      automaticallyImplyLeading: false,
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 72),
            const Text(
              'Payment recorded',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(
              'K${result.payment.amount.decimal}',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            Text('Paid by ${result.payment.customerName}'),
            Text('Remaining: K${result.debt.outstandingAmount.decimal}'),
            if (result.debt.status == DebtStatus.paid)
              const Chip(label: Text('PAID IN FULL')),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('copy-payment-confirmation'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: confirmationText));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Payment confirmation copied.')),
                );
              },
              icon: const Icon(Icons.copy),
              label: const Text('COPY CONFIRMATION'),
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

String _dateOnly(DateTime value) {
  final zambia = value.isUtc
      ? value.toUtc().add(const Duration(hours: 2))
      : value;
  return '${zambia.day.toString().padLeft(2, '0')}/${zambia.month.toString().padLeft(2, '0')}/${zambia.year}';
}

String _dateTime(DateTime value) {
  final zambia = value.toUtc().add(const Duration(hours: 2));
  return '${_dateOnly(zambia)} ${zambia.hour.toString().padLeft(2, '0')}:${zambia.minute.toString().padLeft(2, '0')}';
}

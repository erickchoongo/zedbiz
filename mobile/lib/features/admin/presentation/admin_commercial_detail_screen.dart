import 'package:flutter/material.dart';
import 'package:zedbiz/app/app_controller.dart';
import 'package:zedbiz/core/network/api_exception.dart';
import 'package:zedbiz/features/admin/domain/admin_business.dart';

class AdminCommercialDetailScreen extends StatefulWidget {
  const AdminCommercialDetailScreen({
    required this.controller,
    required this.business,
    super.key,
  });
  final AppController controller;
  final AdminBusiness business;

  @override
  State<AdminCommercialDetailScreen> createState() =>
      _AdminCommercialDetailScreenState();
}

class _AdminCommercialDetailScreenState
    extends State<AdminCommercialDetailScreen> {
  Map<String, dynamic>? _detail;
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
      final detail = await widget.controller.adminGateway.commercialDetail(
        widget.business.id,
      );
      if (mounted) setState(() => _detail = detail);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) {
        setState(() => _error = 'Could not load commercial details.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _onboarding(
    Map<String, dynamic> update,
    String title,
    String message,
  ) async {
    if (!await _confirm(title, message)) return;
    await _run(
      () => widget.controller.adminGateway.updateOnboarding(
        widget.business.id,
        update,
      ),
    );
  }

  Future<void> _paymentAction({required bool renewal}) async {
    final reference = TextEditingController();
    var method = 'MTN_MONEY';
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            renewal
                ? 'Record Founder renewal'
                : 'Activate Founder subscription',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'This records an externally completed ZMW 79.00 payment.',
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: method,
                items:
                    const [
                          'MTN_MONEY',
                          'AIRTEL_MONEY',
                          'ZAMTEL_MONEY',
                          'BANK_TRANSFER',
                          'CASH',
                          'OTHER',
                        ]
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.replaceAll('_', ' ')),
                          ),
                        )
                        .toList(),
                onChanged: (value) => setDialogState(() => method = value!),
                decoration: const InputDecoration(labelText: 'Payment method'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reference,
                decoration: const InputDecoration(
                  labelText: 'External payment reference',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (reference.text.trim().isEmpty) return;
                Navigator.pop(context, {
                  'method': method,
                  'reference': reference.text.trim(),
                });
              },
              child: const Text('Confirm payment'),
            ),
          ],
        ),
      ),
    );
    reference.dispose();
    if (result == null) return;
    await _run(
      () => renewal
          ? widget.controller.adminGateway.renew(
              widget.business.id,
              method: result['method']!,
              reference: result['reference']!,
            )
          : widget.controller.adminGateway.activate(
              widget.business.id,
              method: result['method']!,
              reference: result['reference']!,
            ),
    );
  }

  Future<void> _markPaid() async {
    final reference = TextEditingController();
    var method = 'MTN_MONEY';
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Mark onboarding fee paid'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Confirm that the external ZMW 200.00 payment has already been received.',
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: method,
                items:
                    const [
                          'MTN_MONEY',
                          'AIRTEL_MONEY',
                          'ZAMTEL_MONEY',
                          'BANK_TRANSFER',
                          'CASH',
                          'OTHER',
                        ]
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.replaceAll('_', ' ')),
                          ),
                        )
                        .toList(),
                onChanged: (value) => setDialogState(() => method = value!),
                decoration: const InputDecoration(labelText: 'Payment method'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reference,
                decoration: const InputDecoration(
                  labelText: 'External payment reference',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (reference.text.trim().isNotEmpty) {
                  Navigator.pop(context, {
                    'method': method,
                    'reference': reference.text.trim(),
                  });
                }
              },
              child: const Text('Confirm payment'),
            ),
          ],
        ),
      ),
    );
    reference.dispose();
    if (result == null) return;
    await _run(
      () =>
          widget.controller.adminGateway.updateOnboarding(widget.business.id, {
            'payment_status': 'PAID',
            'payment_method': result['method'],
            'payment_reference': result['reference'],
            'assign_to_me': true,
          }),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
      await _load();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) {
        setState(() => _error = 'The admin action could not be completed.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onboarding = _detail?['onboarding'] as Map<String, dynamic>?;
    final subscription = _detail?['subscription'] as Map<String, dynamic>?;
    final payments = (_detail?['payments'] as List<dynamic>? ?? const []);
    final history = (_detail?['audit_history'] as List<dynamic>? ?? const []);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.business.name),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_loading) const LinearProgressIndicator(),
                if (_error != null)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_error!),
                    ),
                  ),
                _Section(
                  title: 'Business',
                  lines: [
                    'ID: ${widget.business.id}',
                    'Owner: ${widget.business.ownerName ?? 'Not recorded'}',
                    'Email: ${widget.business.ownerEmail ?? 'Not recorded'}',
                    'Phone: ${(_detail?['business'] as Map<String, dynamic>?)?['phone_number'] ?? 'Not recorded'}',
                  ],
                ),
                if (onboarding != null) ...[
                  _Section(
                    title: 'Onboarding',
                    lines: [
                      'Fee: ${onboarding['currency']} ${onboarding['fee_amount']}',
                      'Payment: ${onboarding['payment_status']}',
                      'Status: ${onboarding['onboarding_status']}',
                      'Method: ${onboarding['payment_method'] ?? 'Not recorded'}',
                      'Paid at: ${_date(onboarding['paid_at'])}',
                      'Completed: ${_date(onboarding['completed_at'])}',
                      'Updated: ${_date(onboarding['updated_at'])}',
                      if (onboarding['payment_reference'] != null)
                        'Reference: ${onboarding['payment_reference']}',
                      if (onboarding['notes'] != null)
                        'Internal notes: ${onboarding['notes']}',
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: _loading ? null : _markPaid,
                        child: const Text('Mark fee paid'),
                      ),
                      OutlinedButton(
                        onPressed: _loading
                            ? null
                            : () => _onboarding(
                                {'payment_status': 'WAIVED'},
                                'Waive onboarding fee?',
                                'This financial exception will be audited.',
                              ),
                        child: const Text('Waive fee'),
                      ),
                      OutlinedButton(
                        onPressed: _loading
                            ? null
                            : () => _onboarding(
                                {
                                  'onboarding_status': 'IN_PROGRESS',
                                  'assign_to_me': true,
                                },
                                'Start onboarding?',
                                'Assign this onboarding and mark it in progress.',
                              ),
                        child: const Text('Start onboarding'),
                      ),
                      OutlinedButton(
                        onPressed: _loading
                            ? null
                            : () => _onboarding(
                                {'onboarding_status': 'COMPLETED'},
                                'Complete onboarding?',
                                'Confirm that setup is complete.',
                              ),
                        child: const Text('Complete onboarding'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                _Section(
                  title: 'Founder subscription',
                  lines: subscription == null
                      ? const ['No subscription has been activated.']
                      : [
                          'Plan: ${subscription['plan_name']} (${subscription['currency']} ${subscription['plan_price']}/month)',
                          'Status: ${subscription['status']}',
                          'Started: ${_date(subscription['starts_at'])}',
                          'Period: ${_date(subscription['current_period_start'])} – ${_date(subscription['current_period_end'])}',
                          'Grace deadline: ${_date(subscription['grace_ends_at'])}',
                        ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _loading
                      ? null
                      : () => _paymentAction(renewal: subscription != null),
                  icon: const Icon(Icons.payments_outlined),
                  label: Text(
                    subscription == null
                        ? 'Activate Founder plan'
                        : 'Record renewal',
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Subscription payments (${payments.length})',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (payments.isEmpty)
                  const Text('No subscription payments recorded.'),
                for (final payment in payments.cast<Map<String, dynamic>>())
                  ListTile(
                    leading: const Icon(Icons.receipt_long),
                    title: Text(
                      '${payment['currency']} ${payment['amount']} • ${payment['payment_method']}',
                    ),
                    subtitle: Text(
                      'Reference: ${payment['payment_reference']}\nPaid: ${_date(payment['paid_at'])} | Recorded: ${_date(payment['created_at'])}\nPeriod: ${_date(payment['period_start'])} - ${_date(payment['period_end'])}',
                    ),
                  ),
                const SizedBox(height: 24),
                Text(
                  'Commercial audit history (latest 100)',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (history.isEmpty)
                  const Text('No commercial audit events available.'),
                for (final event in history.cast<Map<String, dynamic>>())
                  ListTile(
                    title: Text(
                      (event['action'] as String).replaceAll('_', ' '),
                    ),
                    subtitle: Text(
                      '${_date(event['created_at'])} | Actor: ${event['actor_user_id'] ?? 'Unavailable'}',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _date(Object? value) {
    if (value == null) return '—';
    final date = DateTime.parse(value as String)
        .toUtc()
        .add(const Duration(hours: 2));
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.lines});
  final String title;
  final List<String> lines;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(line),
            ),
        ],
      ),
    ),
  );
}

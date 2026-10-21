import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zedbiz/app/app_controller.dart';
import 'package:zedbiz/core/network/api_exception.dart';
import 'package:zedbiz/features/admin/domain/admin_business.dart';

/// Super Admin controls. The backend is authoritative for all access decisions.
class AdminAccessScreen extends StatefulWidget {
  const AdminAccessScreen({
    required this.controller,
    this.initialBusinessId,
    this.initialBusinessName,
    super.key,
  });

  final AppController controller;
  final String? initialBusinessId;
  final String? initialBusinessName;

  @override
  State<AdminAccessScreen> createState() => _AdminAccessScreenState();
}

class _AdminAccessScreenState extends State<AdminAccessScreen> {
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;
  List<AdminBusiness> _businesses = const [];
  List<Map<String, dynamic>> _users = const [];
  List<Map<String, dynamic>> _memberships = const [];
  Map<String, dynamic>? _businessState;
  String? _businessId;
  String? _businessName;
  int _tab = 0;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _businessId = widget.initialBusinessId;
    _businessName = widget.initialBusinessName;
    _refresh();
  }

  @override
  void dispose() {
    _generation++;
    _email.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_tab == 0) {
        final businesses = await widget.controller.adminGateway
            .listBusinesses();
        Map<String, dynamic>? state;
        List<Map<String, dynamic>> memberships = const [];
        if (_businessId != null) {
          state = await widget.controller.adminGateway.businessAccess(
            _businessId!,
          );
          memberships = await widget.controller.adminGateway
              .listAccessMemberships(_businessId!);
        }
        if (mounted && generation == _generation) {
          setState(() {
            _businesses = businesses;
            _businessState = state;
            _memberships = memberships;
          });
        }
      } else {
        final users = await widget.controller.adminGateway.listAccessUsers(
          email: _email.text,
        );
        if (mounted && generation == _generation) {
          setState(() => _users = users);
        }
      }
    } on ApiException catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.message);
      }
    } on Object {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Could not load account access information.');
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _selectBusiness(AdminBusiness business) async {
    setState(() {
      _businessId = business.id;
      _businessName = business.name;
    });
    await _refresh();
  }

  Future<String?> _confirmReason({
    required bool suspend,
    required String label,
  }) async {
    final reason = TextEditingController();
    String? validation;
    late DialogRoute<String> route;
    try {
      route = DialogRoute<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text('${suspend ? 'Suspend' : 'Reactivate'} $label?'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    suspend
                        ? 'This immediately restricts access. Subscription and business data are preserved.'
                        : 'This restores the selected access level, unless another suspension still applies.',
                  ),
                  if (suspend) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: reason,
                      maxLength: 2000,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Required suspension reason',
                        hintText: 'At least 5 characters',
                        errorText: validation,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final value = reason.text.trim();
                  if (suspend && (value.length < 5 || value.length > 2000)) {
                    update(() => validation = 'Enter 5–2,000 characters.');
                    return;
                  }
                  Navigator.pop(dialogContext, suspend ? value : 'confirmed');
                },
                child: Text(
                  suspend ? 'Confirm suspension' : 'Confirm reactivation',
                ),
              ),
            ],
          ),
        ),
      );
      return await Navigator.of(context).push(route);
    } finally {
      // Dispose only after the dialog exit transition removes its TextField.
      unawaited(route.completed.then((_) => reason.dispose()));
    }
  }

  Future<void> _change({
    required String label,
    required bool suspend,
    required Future<Map<String, dynamic>> Function(String? reason) action,
  }) async {
    final result = await _confirmReason(suspend: suspend, label: label);
    if (!mounted || result == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(suspend ? result : null);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label ${suspend ? 'suspended' : 'reactivated'}.'),
        ),
      );
      await _refresh();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'The access change failed. Please refresh and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _status(Map<String, dynamic> state) {
    final suspended = state['suspended_at'] != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          suspended ? 'Suspended' : 'Not suspended',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: suspended ? Theme.of(context).colorScheme.error : null,
          ),
        ),
        if (state['is_active'] == false)
          const Text('Inactive (separate from suspension)'),
        if (suspended) ...[
          Text('Since: ${state['suspended_at']}'),
          Text('Reason: ${state['suspension_reason'] ?? 'Not available'}'),
          Text(
            'Suspended by: ${state['suspended_by_user_id'] ?? 'Not available'}',
          ),
        ],
      ],
    );
  }

  Widget _actionButton({
    required bool suspended,
    required String label,
    Key? actionKey,
    required Future<Map<String, dynamic>> Function(String? reason) action,
  }) => suspended
      ? OutlinedButton.icon(
          key: actionKey,
          onPressed: _busy
              ? null
              : () => _change(label: label, suspend: false, action: action),
          icon: const Icon(Icons.lock_open_outlined),
          label: const Text('Reactivate'),
        )
      : OutlinedButton.icon(
          key: actionKey,
          onPressed: _busy
              ? null
              : () => _change(label: label, suspend: true, action: action),
          icon: const Icon(Icons.block_outlined),
          label: const Text('Suspend'),
        );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Access Management'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 950),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Super Admin access controls',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Suspensions are independent of trials and subscriptions. Reactivation does not override other access restrictions.',
              ),
              const SizedBox(height: 12),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Businesses & staff')),
                  ButtonSegment(value: 1, label: Text('Global users')),
                ],
                selected: {_tab},
                onSelectionChanged: _busy
                    ? null
                    : (value) {
                        setState(() {
                          _tab = value.first;
                          _error = null;
                        });
                        _refresh();
                      },
              ),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              if (_tab == 0) ..._businessView() else ..._userView(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _businessView() => [
    const Text(
      'Choose a business to manage its access and employee memberships.',
    ),
    const SizedBox(height: 8),
    DropdownButtonFormField<String>(
      key: ValueKey('business-$_businessId'),
      initialValue: _businessId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Business',
        border: OutlineInputBorder(),
      ),
      items: [
        if (_businessId != null && !_businesses.any((b) => b.id == _businessId))
          DropdownMenuItem(
            value: _businessId,
            child: Text(_businessName ?? _businessId!),
          ),
        for (final business in _businesses)
          DropdownMenuItem(
            value: business.id,
            child: Text(business.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: _busy
          ? null
          : (id) {
              for (final business in _businesses) {
                if (business.id == id) {
                  _selectBusiness(business);
                  return;
                }
              }
            },
    ),
    if (_businessId != null && _businessState != null) ...[
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _businessName ?? 'Business',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              SelectableText('Business ID: $_businessId'),
              const SizedBox(height: 8),
              _status(_businessState!),
              const SizedBox(height: 8),
              _actionButton(
                suspended: _businessState!['suspended_at'] != null,
                actionKey: const ValueKey('business-access-action'),
                label: 'business ${_businessName ?? _businessId}',
                action: (reason) =>
                    widget.controller.adminGateway.changeBusinessAccess(
                      _businessId!,
                      suspend: _businessState!['suspended_at'] == null,
                      reason: reason,
                    ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Text(
        'Business memberships (${_memberships.length})',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const Text(
        'Memberships are identified by user ID because the current API does not return names or emails.',
      ),
      for (final member in _memberships)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText('User: ${member['user_id']}'),
                _status(member),
                _actionButton(
                  suspended: member['suspended_at'] != null,
                  actionKey: ValueKey('membership-access-${member['user_id']}'),
                  label: 'membership for user ${member['user_id']}',
                  action: (reason) =>
                      widget.controller.adminGateway.changeMembershipAccess(
                        _businessId!,
                        member['user_id'] as String,
                        suspend: member['suspended_at'] == null,
                        reason: reason,
                      ),
                ),
              ],
            ),
          ),
        ),
    ],
  ];

  List<Widget> _userView() => [
    const Text(
      'Search by email. The API returns up to 100 users, showing IDs rather than emails.',
    ),
    const SizedBox(height: 8),
    TextField(
      controller: _email,
      decoration: InputDecoration(
        labelText: 'Email search (optional)',
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: const Icon(Icons.search),
          onPressed: _busy ? null : _refresh,
          tooltip: 'Search users',
        ),
      ),
      onSubmitted: (_) => _refresh(),
    ),
    const SizedBox(height: 12),
    for (final user in _users)
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText('User ID: ${user['id']}'),
              _status(user),
              _actionButton(
                suspended: user['suspended_at'] != null,
                actionKey: ValueKey('user-access-${user['id']}'),
                label: 'user ${user['id']}',
                action: (reason) =>
                    widget.controller.adminGateway.changeUserAccess(
                      user['id'] as String,
                      suspend: user['suspended_at'] == null,
                      reason: reason,
                    ),
              ),
            ],
          ),
        ),
      ),
    if (!_busy && _users.isEmpty) const Text('No users found.'),
  ];
}

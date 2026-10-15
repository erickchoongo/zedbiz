import 'package:flutter/material.dart';
import 'package:zedbiz/app/app_controller.dart';
import 'package:zedbiz/core/network/api_exception.dart';
import 'package:zedbiz/features/admin/domain/admin_business.dart';
import 'package:zedbiz/features/admin/presentation/admin_commercial_detail_screen.dart';

class AdminBusinessListScreen extends StatefulWidget {
  const AdminBusinessListScreen({required this.controller, super.key});
  final AppController controller;

  @override
  State<AdminBusinessListScreen> createState() =>
      _AdminBusinessListScreenState();
}

class _AdminBusinessListScreenState extends State<AdminBusinessListScreen> {
  final _search = TextEditingController();
  List<AdminBusiness> _businesses = const [];
  bool _loading = true;
  String? _error;
  String? _onboardingFilter;
  String? _subscriptionFilter;
  String? _paymentFilter;
  int _section = 0;
  int _request = 0;

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
    if (!mounted) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final businesses = await widget.controller.adminGateway.listBusinesses();
      if (mounted && request == _request) {
        setState(() => _businesses = businesses);
      }
    } on ApiException catch (error) {
      if (mounted && request == _request) {
        setState(() => _error = error.message);
      }
    } on Object {
      if (mounted && request == _request) {
        setState(() => _error = 'Could not load admin businesses.');
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final visible = _businesses
        .where(
          (b) =>
              ('${b.name} ${b.id} ${b.ownerName ?? ''} ${b.ownerEmail ?? ''}')
                  .toLowerCase()
                  .contains(query) &&
              (_onboardingFilter == null ||
                  b.onboardingStatus == _onboardingFilter) &&
              (_subscriptionFilter == null ||
                  b.subscriptionStatus == _subscriptionFilter) &&
              (_paymentFilter == null ||
                  b.onboardingPaymentStatus == _paymentFilter),
        )
        .toList();
    final metrics = <String, int>{
      'Registered businesses': _businesses.length,
      'Unpaid onboarding': _businesses
          .where((b) => b.onboardingPaymentStatus == 'UNPAID')
          .length,
      'Paid onboarding': _businesses
          .where((b) => b.onboardingPaymentStatus == 'PAID')
          .length,
      'Waived onboarding': _businesses
          .where((b) => b.onboardingPaymentStatus == 'WAIVED')
          .length,
      'Active subscriptions': _businesses
          .where((b) => b.subscriptionStatus == 'ACTIVE')
          .length,
      'Grace subscriptions': _businesses
          .where((b) => b.subscriptionStatus == 'GRACE_PERIOD')
          .length,
      'Expired subscriptions': _businesses
          .where((b) => b.subscriptionStatus == 'EXPIRED')
          .length,
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('ZedBiz Admin'),
        leading: IconButton(
          onPressed: widget.controller.closeAdmin,
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: CustomScrollView(
              key: const Key('admin-scroll'),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Overview', style: TextStyle(fontSize: 24)),
                        if (_loading) ...[
                          const LinearProgressIndicator(),
                          const Text('Loading admin data?'),
                        ],
                        if (_error != null)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Unable to load admin data',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(_error!),
                                  FilledButton.icon(
                                    onPressed: _loading ? null : _load,
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (!_loading && _error == null) ...[
                          const Text(
                            'All registered businesses. Select a business for commercial details and actions.',
                          ),
                          LayoutBuilder(
                            builder: (context, constraints) => Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final metric in metrics.entries)
                                  SizedBox(
                                    width: constraints.maxWidth >= 600
                                        ? (constraints.maxWidth - 16) / 3
                                        : constraints.maxWidth,
                                    child: Card(
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(metric.key),
                                            Text(
                                              '${metric.value}',
                                              style: const TextStyle(
                                                fontSize: 24,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (var i = 0; i < 4; i++)
                              ChoiceChip(
                                label: Text(
                                  const [
                                    'Overview',
                                    'Businesses',
                                    'Payments',
                                    'Subscriptions',
                                  ][i],
                                ),
                                selected: _section == i,
                                onSelected: (_) => setState(() => _section = i),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (_section != 0) ...[
                          SearchBar(
                            controller: _search,
                            hintText: 'Search business, ID or owner',
                            leading: const Icon(Icons.search),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 12),
                          const Text('Filters'),
                          _filter(
                            'All onboarding payments',
                            _paymentFilter,
                            const ['UNPAID', 'PAID', 'WAIVED'],
                            (v) => setState(() => _paymentFilter = v),
                          ),
                          _filter(
                            'All onboarding states',
                            _onboardingFilter,
                            const [
                              'NOT_STARTED',
                              'IN_PROGRESS',
                              'COMPLETED',
                              'CANCELLED',
                            ],
                            (v) => setState(() => _onboardingFilter = v),
                          ),
                          _filter(
                            'All subscription states',
                            _subscriptionFilter,
                            const [
                              'PENDING',
                              'ACTIVE',
                              'GRACE_PERIOD',
                              'EXPIRED',
                              'CANCELLED',
                            ],
                            (v) => setState(() => _subscriptionFilter = v),
                          ),
                          if (_section == 2)
                            const Text(
                              'Onboarding payment states are shown below. Open a business for recorded subscription payments, amounts, methods and references.',
                            ),
                          if (_section == 3)
                            const Text(
                              'Current effective subscription status is shown below. Open a business for plan, period and grace dates.',
                            ),
                        ],
                        if (!_loading && _error == null && _businesses.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Text(
                              'No businesses registered yet. Overview totals are zero.',
                            ),
                          ),
                        if (!_loading &&
                            _error == null &&
                            _businesses.isNotEmpty &&
                            visible.isEmpty)
                          const Text('No businesses match these filters.'),
                        if (!_loading &&
                            _error == null &&
                            _businesses.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text('Businesses shown: ${visible.length}'),
                          ),
                      ],
                    ),
                  ),
                ),
                if (!_loading && _error == null)
                  SliverList.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final business = visible[index];
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Card(
                          child: ListTile(
                            title: Text(business.name),
                            subtitle: Text(
                              '${business.ownerName ?? 'Owner unavailable'}\n${business.ownerEmail ?? ''}\nID: ${business.id}\nPayment: ${business.onboardingPaymentStatus}\nOnboarding: ${business.onboardingStatus} ? Subscription: ${business.subscriptionStatus}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => AdminCommercialDetailScreen(
                                    controller: widget.controller,
                                    business: business,
                                  ),
                                ),
                              );
                              await _load();
                            },
                          ),
                        ),
                      );
                    },
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filter(
    String label,
    String? value,
    List<String> values,
    ValueChanged<String?> changed,
  ) => DropdownButton<String>(
    isExpanded: true,
    value: value ?? 'ALL',
    items: ['ALL', ...values]
        .map(
          (v) => DropdownMenuItem(
            value: v,
            child: Text(v == 'ALL' ? label : v.replaceAll('_', ' ')),
          ),
        )
        .toList(),
    onChanged: (v) => changed(v == 'ALL' ? null : v),
  );
}

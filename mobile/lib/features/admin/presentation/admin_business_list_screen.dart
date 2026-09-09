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
      final businesses = await widget.controller.adminGateway.listBusinesses(
        search: _search.text,
        onboardingStatus: _onboardingFilter,
        subscriptionStatus: _subscriptionFilter,
      );
      if (mounted) setState(() => _businesses = businesses);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) setState(() => _error = 'Could not load admin businesses.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        onPressed: widget.controller.closeAdmin,
        icon: const Icon(Icons.arrow_back),
      ),
      title: const Text('ZedBiz Admin'),
      actions: [
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh',
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: SearchBar(
                  controller: _search,
                  hintText: 'Search business or owner email',
                  leading: const Icon(Icons.search),
                  trailing: [
                    IconButton(
                      onPressed: _load,
                      icon: const Icon(Icons.arrow_forward),
                    ),
                  ],
                  onSubmitted: (_) => _load(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    DropdownButton<String?>(
                      value: _onboardingFilter,
                      hint: const Text('All onboarding states'),
                      items:
                          const [
                                null,
                                'NOT_STARTED',
                                'IN_PROGRESS',
                                'COMPLETED',
                                'CANCELLED',
                              ]
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(
                                    value?.replaceAll('_', ' ') ??
                                        'All onboarding states',
                                  ),
                                ),
                              )
                              .toList(),
                      onChanged: (value) {
                        setState(() => _onboardingFilter = value);
                        _load();
                      },
                    ),
                    DropdownButton<String?>(
                      value: _subscriptionFilter,
                      hint: const Text('All subscription states'),
                      items:
                          const [
                                null,
                                'PENDING',
                                'ACTIVE',
                                'GRACE_PERIOD',
                                'EXPIRED',
                                'CANCELLED',
                              ]
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(
                                    value?.replaceAll('_', ' ') ??
                                        'All subscription states',
                                  ),
                                ),
                              )
                              .toList(),
                      onChanged: (value) {
                        setState(() => _subscriptionFilter = value);
                        _load();
                      },
                    ),
                  ],
                ),
              ),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!),
                ),
              Expanded(
                child: _businesses.isEmpty && !_loading
                    ? const Center(
                        child: Text('No businesses match this view.'),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        itemCount: _businesses.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final business = _businesses[index];
                          return Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(16),
                              leading: const CircleAvatar(
                                child: Icon(Icons.storefront),
                              ),
                              title: Text(business.name),
                              subtitle: Text(
                                '${business.ownerName ?? business.ownerEmail ?? 'Owner unavailable'}\n'
                                'Onboarding: ${business.onboardingStatus} • Subscription: ${business.subscriptionStatus}',
                              ),
                              isThreeLine: true,
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
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

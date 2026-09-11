import 'package:flutter/material.dart';
import 'package:zedbiz/app/app_controller.dart';

/// Operator-visible release identity and aggregate queue state; no payloads/tokens.
class PilotDiagnosticsScreen extends StatefulWidget {
  const PilotDiagnosticsScreen({required this.controller, super.key});
  final AppController controller;

  @override
  State<PilotDiagnosticsScreen> createState() => _PilotDiagnosticsScreenState();
}

class _PilotDiagnosticsScreenState extends State<PilotDiagnosticsScreen> {
  Map<String, dynamic>? backend;
  Map<String, int> queue = {};
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    final client = widget.controller.offline;
    final business = widget.controller.selectedBusiness;
    if (client != null && business != null) {
      try {
        final rows = await client.db.operations(
          await client.account(),
          business.id,
        );
        final counts = <String, int>{};
        for (final row in rows) {
          counts.update(row.state.name, (n) => n + 1, ifAbsent: () => 1);
        }
        if (mounted) setState(() => queue = counts);
        final metadata = await client.getJson('/api/v1/health/version');
        if (mounted) setState(() => backend = metadata);
      } on Object {
        if (mounted) {
          setState(
            () => error = 'Backend details unavailable. Reconnect and refresh.',
          );
        }
      }
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pilot diagnostics')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Include these release details when reporting an issue.'),
        const ListTile(
          title: Text('App version'),
          subtitle: Text(
            String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0'),
          ),
        ),
        const ListTile(
          title: Text('Build number'),
          subtitle: Text(
            String.fromEnvironment('APP_BUILD_NUMBER', defaultValue: '1'),
          ),
        ),
        const ListTile(
          title: Text('App Git commit'),
          subtitle: SelectableText(
            String.fromEnvironment('GIT_COMMIT', defaultValue: 'unknown'),
          ),
        ),
        const ListTile(
          title: Text('App environment'),
          subtitle: Text(
            String.fromEnvironment('APP_ENV', defaultValue: 'development'),
          ),
        ),
        if (loading) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        if (backend != null) ...[
          ListTile(
            title: const Text('Backend version'),
            subtitle: Text('${backend!['version']}'),
          ),
          ListTile(
            title: const Text('Backend Git commit'),
            subtitle: SelectableText('${backend!['git_commit']}'),
          ),
          ListTile(
            title: const Text('Backend environment'),
            subtitle: Text('${backend!['environment']}'),
          ),
        ],
        const Divider(),
        const Text(
          'Stored operations on this device for the selected account and business',
        ),
        for (final entry in queue.entries)
          ListTile(title: Text(entry.key), trailing: Text('${entry.value}')),
        const Text(
          'Counts describe the retained queue, not lifetime totals across all devices. Use Sync Status to review individual operations.',
        ),
        OutlinedButton(
          onPressed: loading ? null : load,
          child: const Text('Refresh diagnostics'),
        ),
      ],
    ),
  );
}

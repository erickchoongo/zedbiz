import 'package:flutter/material.dart';

import 'local_database.dart';
import 'offline_client.dart';

class CacheFreshness extends StatelessWidget {
  const CacheFreshness({required this.client, required this.path, super.key});
  final OfflineClient? client;
  final String path;
  @override
  Widget build(BuildContext context) {
    final api = client;
    if (api == null) return const SizedBox.shrink();
    return ValueListenableBuilder(
      valueListenable: api.changes,
      builder: (_, value, child) => FutureBuilder<CachedRead?>(
        future: api.account().then(
          (u) => api.db.readCache(u, api.businessOf(path), path),
        ),
        builder: (_, snapshot) {
          final cache = snapshot.data;
          if (cache == null) return const SizedBox.shrink();
          return Text(
            'Last updated ${cache.updatedAt.toLocal()}${cache.stale || !api.online ? ' • Cached figures may be out of date' : ''}\nPending transactions are separate from these server totals.',
            style: Theme.of(context).textTheme.bodySmall,
          );
        },
      ),
    );
  }
}

class SyncBanner extends StatelessWidget {
  const SyncBanner({required this.client, required this.business, super.key});
  final OfflineClient client;
  final String business;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: client.changes,
    builder: (_, value, child) => FutureBuilder<List<QueuedOperation>>(
      future: client.account().then((u) => client.db.operations(u, business)),
      builder: (_, snapshot) {
        final operations = snapshot.data ?? [];
        final pending = operations.where((o) => o.reservesStock).length;
        final issues = operations.where((o) => o.needsReview).length;
        final state = client.syncing
            ? 'Syncing...'
            : client.sessionRequired
            ? 'Sign in to sync'
            : issues > 0
            ? 'Sync issue'
            : client.online
            ? 'Online'
            : 'Offline — changes will sync later';
        return Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: ListTile(
            dense: true,
            leading: Icon(client.online ? Icons.sync : Icons.cloud_off),
            title: Text(state),
            subtitle: Text(
              '$pending items waiting to sync • $issues need attention${!client.online && client.lastCacheRead != null ? '\nLast updated ${client.lastCacheRead!.toLocal()}' : ''}',
            ),
            trailing: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      SyncStatusScreen(client: client, business: business),
                ),
              ),
              child: const Text('Sync Status'),
            ),
          ),
        );
      },
    ),
  );
}

class SyncStatusScreen extends StatefulWidget {
  const SyncStatusScreen({
    required this.client,
    required this.business,
    super.key,
  });
  final OfflineClient client;
  final String business;
  @override
  State<SyncStatusScreen> createState() => _SyncStatusScreenState();
}

class _SyncStatusScreenState extends State<SyncStatusScreen> {
  List<QueuedOperation> operations = [];
  String? message;
  @override
  void initState() {
    super.initState();
    widget.client.changes.addListener(load);
    load();
  }

  @override
  void dispose() {
    widget.client.changes.removeListener(load);
    super.dispose();
  }

  Future<void> load() async {
    try {
      final user = await widget.client.account();
      final rows = await widget.client.db.operations(user, widget.business);
      final saved = await widget.client.db.readCache(
        user,
        widget.business,
        'last_sync',
      );
      if (saved?.data is String) {
        widget.client.lastSync = DateTime.tryParse(saved!.data as String);
      }
      if (mounted) setState(() => operations = rows);
    } on Object {
      if (mounted) setState(() => operations = []);
    }
  }

  Future<void> sync() async {
    await widget.client.syncPendingOperations(widget.business, manual: true);
    await load();
    final unresolved = operations
        .where((o) => o.reservesStock || o.needsReview)
        .length;
    if (mounted) {
      setState(
        () => message = unresolved == 0 && widget.client.online
            ? 'Sync complete. No transactions waiting.'
            : '$unresolved transactions unresolved. ${widget.client.sessionRequired
                  ? 'Sign in to continue.'
                  : widget.client.online
                  ? 'Review the issues below.'
                  : 'Connect and try again.'}',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sync Status')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          widget.client.syncing
              ? 'Syncing...'
              : widget.client.online
              ? 'Online'
              : 'Offline',
        ),
        Text(
          'Last successful sync: ${widget.client.lastSync?.toLocal() ?? 'Not yet verified'}',
        ),
        Text(
          '${operations.where((o) => o.reservesStock).length} waiting • ${operations.where((o) => o.needsReview).length} need attention',
        ),
        FilledButton(
          onPressed: widget.client.syncing ? null : sync,
          child: const Text('Sync Now'),
        ),
        if (message != null) Text(message!),
        const Text(
          'An offline transaction is not server-confirmed until synchronization succeeds.',
        ),
        for (final op in operations.reversed)
          ListTile(
            leading: Icon(
              op.needsReview
                  ? Icons.error_outline
                  : op.state == SyncState.synced
                  ? Icons.cloud_done
                  : Icons.schedule,
            ),
            title: Text(
              '${op.type == OperationType.createSale ? 'Sale' : 'Expense'} • K${op.preview['total_amount'] ?? op.preview['amount']}',
            ),
            subtitle: Text(
              '${op.state.name.toUpperCase()} • Saved ${op.createdAt.toLocal()}${op.error == null ? '' : '\n${op.error}'}',
            ),
            onTap: () => issue(op),
          ),
      ],
    ),
  );
  Future<void> issue(QueuedOperation op) async {
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(
          op.needsReview ? 'Transaction needs review' : 'Saved transaction',
        ),
        content: Text(
          '${op.error ?? op.state.name.toUpperCase()}\nK${op.preview['total_amount'] ?? op.preview['amount']}\nSaved ${op.createdAt.toLocal()}\n${op.type == OperationType.createSale ? 'Quantities and prices will never be changed automatically.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Close'),
          ),
          if (op.type == OperationType.createSale)
            TextButton(
              onPressed: () async {
                try {
                  await widget.client.refreshProducts(widget.business);
                  if (dialog.mounted) Navigator.pop(dialog);
                } on Object {
                  if (mounted) {
                    setState(
                      () => message =
                          'Could not refresh products. Connect and retry.',
                    );
                  }
                }
              },
              child: const Text('Refresh products'),
            ),
          if (op.state != SyncState.synced &&
              op.state != SyncState.cancelled &&
              op.state != SyncState.syncing)
            TextButton(
              onPressed: () async {
                Navigator.pop(dialog);
                await cancel(op);
              },
              child: const Text('Cancel local transaction'),
            ),
        ],
      ),
    );
  }

  Future<void> cancel(QueuedOperation op) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Cancel local transaction?'),
        content: const Text(
          'This stops synchronization. If money or goods changed hands, reconcile them with the customer. This does not void a server transaction.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Keep transaction'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Confirm cancellation'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.client.cancel(op);
      await load();
    } on Object catch (e) {
      if (mounted) setState(() => message = e.toString());
    }
  }
}

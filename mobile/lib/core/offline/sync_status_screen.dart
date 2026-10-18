
import 'package:flutter/material.dart';

import 'local_database.dart';
import 'offline_client.dart';

class CacheFreshness extends StatelessWidget {
  const CacheFreshness({
    required this.client,
    required this.path,
    super.key,
  });

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
            'Last updated ${cache.updatedAt.toLocal()}'
            '${cache.stale || !api.online ? ' • Cached figures may be out of date' : ''}'
            '\nPending transactions are separate from these server totals.',
            style: Theme.of(context).textTheme.bodySmall,
          );
        },
      ),
    );
  }
}

/// Compact synchronization indicator for the business workspace.
class SyncBanner extends StatelessWidget {
  const SyncBanner({
    required this.client,
    required this.business,
    super.key,
  });

  final OfflineClient client;
  final String business;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: client.changes,
      builder: (_, value, child) => FutureBuilder<List<QueuedOperation>>(
        future: client.account().then(
          (u) => client.db.operations(u, business),
        ),
        builder: (_, snapshot) {
          final operations = snapshot.data ?? [];
          final pending =
              operations.where((o) => o.reservesStock).length;
          final issues =
              operations.where((o) => o.needsReview).length;

          final colorScheme = Theme.of(context).colorScheme;

          final hasIssues = issues > 0 || client.sessionRequired;
          final needsAttention =
              hasIssues || pending > 0 || !client.online;

          final foreground = hasIssues
              ? colorScheme.error
              : colorScheme.primary;

          final background = hasIssues
              ? colorScheme.errorContainer.withValues(alpha: 0.55)
              : needsAttention
                  ? colorScheme.surfaceContainerHighest
                  : colorScheme.primaryContainer.withValues(alpha: 0.50);

          final label = client.sessionRequired
              ? 'Sign in to sync'
              : issues > 0
                  ? '$issues need attention'
                  : pending > 0
                      ? '$pending pending'
                      : client.syncing
                          ? 'Syncing'
                          : 'Sync Status';

          final status = client.syncing
              ? 'Syncing transactions'
              : client.sessionRequired
                  ? 'Sign in to synchronize'
                  : issues > 0
                      ? '$issues transactions need review'
                      : !client.online
                          ? 'Offline — changes will sync later'
                          : 'Open synchronization details';

          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 6,
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: Material(
                color: background,
                borderRadius: BorderRadius.circular(24),
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SyncStatusScreen(
                        client: client,
                        business: business,
                      ),
                    ),
                  ),
                  child: Tooltip(
                    message: status,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasIssues
                                ? Icons.error_outline_rounded
                                : client.syncing
                                    ? Icons.sync_rounded
                                    : !client.online
                                        ? Icons.cloud_off_outlined
                                        : pending > 0
                                            ? Icons.cloud_upload_outlined
                                            : Icons.cloud_done_outlined,
                            size: 18,
                            color: foreground,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            label,
                            style: TextStyle(
                              color: foreground,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 17,
                            color: foreground,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
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

      final rows = await widget.client.db.operations(
        user,
        widget.business,
      );

      final saved = await widget.client.db.readCache(
        user,
        widget.business,
        'last_sync',
      );

      if (saved?.data is String) {
        widget.client.lastSync = DateTime.tryParse(
          saved!.data as String,
        );
      }

      if (mounted) {
        setState(() => operations = rows);
      }
    } on Object {
      if (mounted) {
        setState(() => operations = []);
      }
    }
  }

  Future<void> sync() async {
    await widget.client.syncPendingOperations(
      widget.business,
      manual: true,
    );

    await load();

    final unresolved = operations
        .where((o) => o.reservesStock || o.needsReview)
        .length;

    if (mounted) {
      setState(
        () => message = unresolved == 0 && widget.client.online
            ? 'Sync complete. No transactions waiting.'
            : '$unresolved transactions unresolved. '
                '${widget.client.sessionRequired
                    ? 'Sign in to continue.'
                    : widget.client.online
                        ? 'Review the issues below.'
                        : 'Connect and try again.'}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final pending =
        operations.where((o) => o.reservesStock).length;
    final issues =
        operations.where((o) => o.needsReview).length;

    final isOnline = widget.client.online;
    final isSyncing = widget.client.syncing;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: const Text('Sync Status'),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Main synchronization overview
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.primaryContainer.withValues(alpha: 0.40),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        isSyncing
                            ? Icons.sync_rounded
                            : isOnline
                                ? Icons.cloud_done_outlined
                                : Icons.cloud_off_outlined,
                        color: colors.primary,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            isSyncing
                                ? 'Synchronizing'
                                : isOnline
                                    ? 'Connected'
                                    : 'Working offline',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isSyncing
                                ? 'Updating your saved transactions.'
                                : isOnline
                                    ? 'Your business can communicate with the server.'
                                    : 'Saved transactions will synchronize when possible.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Divider(),
                const SizedBox(height: 10),
                Text(
                  'Last successful sync',
                  style: theme.textTheme.labelMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  widget.client.lastSync?.toLocal().toString() ??
                      'Not yet verified',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Transaction counters
          Row(
            children: [
              Expanded(
                child: _SyncMetric(
                  icon: Icons.schedule_rounded,
                  title: 'Waiting',
                  count: pending,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SyncMetric(
                  icon: Icons.error_outline_rounded,
                  title: 'Needs review',
                  count: issues,
                  color: colors.error,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isSyncing ? null : sync,
              icon: const Icon(Icons.sync_rounded),
              label: Text(
                isSyncing ? 'Syncing...' : 'Sync Now',
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  vertical: 15,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),

          if (message != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                message!,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],

          const SizedBox(height: 20),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: colors.onSurfaceVariant,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'An offline transaction is not server-confirmed until synchronization succeeds.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 28),

          Text(
            'Transaction activity',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Review your saved sales and expenses.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 14),

          if (operations.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(
                vertical: 34,
                horizontal: 18,
              ),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.task_alt_rounded,
                    size: 36,
                    color: colors.primary,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'No saved transactions to display',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

          for (final op in operations.reversed) ...[
            Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 10),
              color: colors.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                leading: CircleAvatar(
                  backgroundColor: op.needsReview
                      ? colors.errorContainer
                      : colors.primaryContainer,
                  child: Icon(
                    op.needsReview
                        ? Icons.error_outline_rounded
                        : op.state == SyncState.synced
                            ? Icons.cloud_done_outlined
                            : Icons.schedule_rounded,
                    color: op.needsReview
                        ? colors.error
                        : colors.primary,
                  ),
                ),
                title: Text(
                  '${op.type == OperationType.createSale ? 'Sale' : 'Expense'}'
                  ' • K${op.preview['total_amount'] ?? op.preview['amount']}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  '${op.state.name.toUpperCase()}'
                  ' • Saved ${op.createdAt.toLocal()}'
                  '${op.error == null ? '' : '\n${op.error}'}',
                ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                ),
                onTap: () => issue(op),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> issue(QueuedOperation op) async {
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(
          op.needsReview
              ? 'Transaction needs review'
              : 'Saved transaction',
        ),
        content: Text(
          '${op.error ?? op.state.name.toUpperCase()}'
          '\nK${op.preview['total_amount'] ?? op.preview['amount']}'
          '\nSaved ${op.createdAt.toLocal()}'
          '\n${op.type == OperationType.createSale
              ? 'Quantities and prices will never be changed automatically.'
              : ''}',
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
                  await widget.client.refreshProducts(
                    widget.business,
                  );
                  if (dialog.mounted) {
                    Navigator.pop(dialog);
                  }
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
      if (mounted) {
        setState(() => message = e.toString());
      }
    }
  }
}

class _SyncMetric extends StatelessWidget {
  const _SyncMetric({
    required this.icon,
    required this.title,
    required this.count,
    required this.color,
  });

  final IconData icon;
  final String title;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 12),
          Text(
            count.toString(),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

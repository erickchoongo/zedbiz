import 'package:flutter/material.dart';
import 'package:zedbiz/app/app_controller.dart';
import 'package:zedbiz/features/businesses/presentation/create_business_screen.dart';

class BusinessListScreen extends StatelessWidget {
  const BusinessListScreen({required this.controller, super.key});

  final AppController controller;

  Future<void> _openCreate(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => CreateBusinessScreen(controller: controller),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Your businesses'),
      actions: [
        if (controller.currentUser?.isPlatformAdmin == true)
          IconButton(
            key: const Key('open-admin'),
            onPressed: controller.openAdmin,
            icon: const Icon(Icons.admin_panel_settings),
            tooltip: 'ZedBiz admin',
          ),
        IconButton(
          onPressed: controller.busy ? null : controller.logout,
          icon: const Icon(Icons.logout),
          tooltip: 'Sign out',
        ),
      ],
    ),
    floatingActionButton: controller.businesses.isEmpty
        ? null
        : FloatingActionButton.extended(
            onPressed: () => _openCreate(context),
            icon: const Icon(Icons.add_business),
            label: const Text('New business'),
          ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: controller.businesses.isEmpty
              ? _EmptyBusinesses(onCreate: () => _openCreate(context))
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: controller.businesses.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final business = controller.businesses[index];
                    return Card(
                      child: ListTile(
                        key: Key('business-${business.id}'),
                        contentPadding: const EdgeInsets.all(16),
                        leading: CircleAvatar(
                          child: Text(
                            business.name.substring(0, 1).toUpperCase(),
                          ),
                        ),
                        title: Text(business.name),
                        subtitle: Text(
                          '${business.role.name.toUpperCase()} • ${business.currency}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async => controller.selectBusiness(business),
                      ),
                    );
                  },
                ),
        ),
      ),
    ),
  );
}

class _EmptyBusinesses extends StatelessWidget {
  const _EmptyBusinesses({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.add_business,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 20),
        Text(
          'Create your first business',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        const Text(
          'Set up a business to begin using ZedBiz.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          key: const Key('create-first-business'),
          onPressed: onCreate,
          icon: const Icon(Icons.add),
          label: const Text('Create business'),
        ),
      ],
    ),
  );
}

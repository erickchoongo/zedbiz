import 'package:flutter/material.dart';
import 'package:zedbiz/app/app_controller.dart';
import 'package:zedbiz/features/businesses/domain/business_summary.dart';
import 'package:zedbiz/features/commercial/domain/commercial_status.dart';
import 'package:zedbiz/features/businesses/presentation/business_shell.dart';

class BusinessReadyScreen extends StatelessWidget {
  const BusinessReadyScreen({required this.controller, super.key});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final business = controller.selectedBusiness!;
    final commercial = controller.commercialStatus;
    if (commercial != null &&
        commercial.onboardingState == OnboardingState.completed &&
        commercial.subscriptionState != SubscriptionState.pending) {
      return BusinessShell(
        controller: controller,
        writable: commercial.writesAllowed,
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(business.name),
        actions: [
          if (controller.currentUser?.isPlatformAdmin == true)
            IconButton(
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
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: RefreshIndicator(
              onRefresh: controller.refreshCommercialStatus,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (controller.busy) const LinearProgressIndicator(),
                  if (controller.errorMessage != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(controller.errorMessage!),
                      ),
                    ),
                  _CommercialGate(
                    business: business,
                    status: controller.commercialStatus,
                    userName: controller.currentUser!.fullName,
                    onRefresh: controller.refreshCommercialStatus,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: controller.showBusinessList,
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Switch business'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CommercialGate extends StatelessWidget {
  const _CommercialGate({
    required this.business,
    required this.status,
    required this.userName,
    required this.onRefresh,
  });
  final BusinessSummary business;
  final CommercialStatus? status;
  final String userName;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final value = status;
    if (value == null) {
      return _StatusCard(
        icon: Icons.cloud_off,
        title: 'Commercial status is unavailable',
        message: 'Refresh to check your onboarding and subscription.',
        action: FilledButton(
          onPressed: onRefresh,
          child: const Text('Try again'),
        ),
        footer: _identity(),
      );
    }
    if (!value.canManageCommercial && !value.writesAllowed) {
      return _StatusCard(
        icon: Icons.lock_clock,
        title: 'Business is read-only',
        message:
            'Ask the business owner to contact ZedBiz about the subscription.',
        footer: _identity(),
      );
    }
    if (value.onboardingPaymentState == OnboardingPaymentState.unpaid) {
      return _StatusCard(
        icon: Icons.handshake_outlined,
        title: 'Complete your ZedBiz setup',
        message:
            'Onboarding fee: ${value.onboardingFee?.display ?? 'ZMW 200.00'}\nThis covers business setup and initial configuration. Payment is confirmed manually by ZedBiz.',
        action: FilledButton.icon(
          key: const Key('refresh-commercial'),
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Check payment status'),
        ),
        footer: _identity(),
      );
    }
    if (value.onboardingState == OnboardingState.inProgress) {
      return _StatusCard(
        icon: Icons.engineering_outlined,
        title: 'Your business setup is in progress',
        message: 'ZedBiz is completing the initial configuration.',
        action: OutlinedButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
        ),
        footer: _identity(),
      );
    }
    if (value.subscriptionState == SubscriptionState.pending) {
      return _StatusCard(
        icon: Icons.workspace_premium_outlined,
        title: 'Activate your Founder Plan',
        message:
            '${value.planPrice?.display ?? 'ZMW 79.00'}/month\nSubscription payment is confirmed manually by ZedBiz.',
        action: FilledButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Check activation status'),
        ),
        footer: _identity(),
      );
    }
    if (value.subscriptionState == SubscriptionState.gracePeriod) {
      return _StatusCard(
        icon: Icons.warning_amber_rounded,
        title: 'Your subscription has expired',
        message:
            'You are in the 7-day grace period until ${_zambiaDate(value.graceEndsAt)}. Business changes remain available during grace.',
        color: Theme.of(context).colorScheme.tertiaryContainer,
        footer: _readyIdentity(readOnly: false),
      );
    }
    if (value.subscriptionState == SubscriptionState.expired ||
        value.subscriptionState == SubscriptionState.cancelled) {
      return _StatusCard(
        icon: Icons.lock_outline,
        title: 'Subscription renewal required',
        message: 'Historical information remains available, but the business is now read-only.',
        color: Theme.of(context).colorScheme.errorContainer,
        action: OutlinedButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Check renewal status'),
        ),
        footer: _readyIdentity(readOnly: true),
      );
    }
    return _StatusCard(
      icon: Icons.check_circle,
      title: 'Founder Plan Active',
      message: 'Paid through ${_zambiaDate(value.currentPeriodEnd)}',
      footer: _readyIdentity(readOnly: false),
    );
  }

  Widget _identity() => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Text('${business.name} • ${business.role.name.toUpperCase()}'),
  );

  Widget _readyIdentity({required bool readOnly}) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Column(
      children: [
        Text(
          '${business.name} is ready${readOnly ? ' in read-only mode' : ''}',
        ),
        const SizedBox(height: 6),
        Text('Signed in as $userName'),
        const SizedBox(height: 6),
        Chip(label: Text(business.role.name.toUpperCase())),
      ],
    ),
  );

  static String _zambiaDate(DateTime? date) {
    if (date == null) return '—';
    final zambia = date.toUtc().add(const Duration(hours: 2));
    return '${zambia.day.toString().padLeft(2, '0')}/${zambia.month.toString().padLeft(2, '0')}/${zambia.year}';
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.footer,
    this.action,
    this.color,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget footer;
  final Widget? action;
  final Color? color;

  @override
  Widget build(BuildContext context) => Card(
    color: color,
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(icon, size: 58, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 18),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 20), action!],
          footer,
        ],
      ),
    ),
  );
}

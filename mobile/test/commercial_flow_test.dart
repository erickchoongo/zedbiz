import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zedbiz/app/app.dart';
import 'package:zedbiz/app/app_controller.dart';
import 'package:zedbiz/features/admin/domain/admin_business.dart';
import 'package:zedbiz/features/auth/domain/user_profile.dart';
import 'package:zedbiz/features/commercial/domain/commercial_status.dart';
import 'package:zedbiz/features/commercial/domain/money.dart';

import 'helpers/fakes.dart';

AppController controllerFor(
  CommercialStatus status, {
  UserProfile user = testUser,
  FakeAdminGateway? admin,
}) => AppController(
  authGateway: FakeAuthGateway(sessionAvailable: true, user: user),
  businessGateway: FakeBusinessGateway(businesses: [testBusinessA]),
  commercialGateway: FakeCommercialGateway(status: status),
  adminGateway: admin ?? FakeAdminGateway(),
);

CommercialStatus status({
  SubscriptionState subscription = SubscriptionState.pending,
  OnboardingState onboarding = OnboardingState.completed,
  OnboardingPaymentState payment = OnboardingPaymentState.paid,
  bool writesAllowed = false,
}) => CommercialStatus(
  planName: 'Founder',
  planCode: 'FOUNDER',
  planPrice: Money.parse('79.00', 'ZMW'),
  currency: 'ZMW',
  subscriptionState: subscription,
  currentPeriodEnd: DateTime.utc(2026, 9, 30),
  graceEndsAt: DateTime.utc(2026, 10, 7),
  onboardingState: onboarding,
  onboardingPaymentState: payment,
  onboardingFee: Money.parse('200.00', 'ZMW'),
  writesAllowed: writesAllowed,
  canManageCommercial: true,
);

void main() {
  testWidgets(
    'business selection exposes named admin entry only to platform admins',
    (tester) async {
      for (final isAdmin in [false, true]) {
        final controller = AppController(
          authGateway: FakeAuthGateway(
            sessionAvailable: true,
            user: UserProfile(
              id: 'u',
              email: 'u@example.com',
              fullName: 'User',
              phoneNumber: null,
              isPlatformAdmin: isAdmin,
            ),
          ),
          businessGateway: FakeBusinessGateway(),
          commercialGateway: FakeCommercialGateway(),
          adminGateway: FakeAdminGateway(),
        );
        await tester.pumpWidget(
          ZedBizApp(key: UniqueKey(), controller: controller),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('open-admin')),
          isAdmin ? findsOneWidget : findsNothing,
        );
        controller.openAdmin();
        expect(controller.adminMode, isAdmin);
      }
    },
  );

  testWidgets('More exposes admin workspace only for platform admins', (
    tester,
  ) async {
    for (final isAdmin in [false, true]) {
      final controller = controllerFor(
        activeCommercialStatus,
        user: UserProfile(
          id: 'u',
          email: 'u@example.com',
          fullName: 'User',
          phoneNumber: null,
          isPlatformAdmin: isAdmin,
        ),
      );
      await tester.pumpWidget(
        ZedBizApp(key: UniqueKey(), controller: controller),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(
        find.text('ZedBiz admin'),
        isAdmin ? findsOneWidget : findsNothing,
      );
    }
  });

  test('money parsing uses exact integer minor units', () {
    expect(Money.parse('79.00', 'ZMW').minorUnits, 7900);
    expect(Money.parse('200.00', 'ZMW').minorUnits, 20000);
    expect(Money.parse('0.01', 'ZMW').minorUnits, 1);
    expect(Money.parse('999999.99', 'ZMW').minorUnits, 99999999);
  });

  testWidgets('owner sees backend-provided onboarding fee and refresh action', (
    tester,
  ) async {
    await tester.pumpWidget(
      ZedBizApp(
        controller: controllerFor(
          status(
            onboarding: OnboardingState.notStarted,
            payment: OnboardingPaymentState.unpaid,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Complete your ZedBiz setup'), findsOneWidget);
    expect(find.textContaining('ZMW 200.00'), findsOneWidget);
    expect(find.byKey(const Key('refresh-commercial')), findsOneWidget);
  });

  testWidgets('grace period remains writable and shows deadline warning', (
    tester,
  ) async {
    await tester.pumpWidget(
      ZedBizApp(
        controller: controllerFor(
          status(
            subscription: SubscriptionState.gracePeriod,
            writesAllowed: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your subscription has expired'), findsOneWidget);
    expect(find.textContaining('7-day grace period'), findsOneWidget);
    expect(find.text('Brown Tech is ready'), findsOneWidget);
  });

  testWidgets('expired subscription presents read-only mode', (tester) async {
    await tester.pumpWidget(
      ZedBizApp(
        controller: controllerFor(
          status(subscription: SubscriptionState.expired),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Subscription renewal required'), findsOneWidget);
    expect(find.textContaining('read-only mode'), findsOneWidget);
  });

  testWidgets('platform admin can open the protected business list', (
    tester,
  ) async {
    const adminUser = UserProfile(
      id: 'admin-1',
      email: 'admin@example.com',
      fullName: 'Platform Admin',
      phoneNumber: null,
      isPlatformAdmin: true,
    );
    final admin = FakeAdminGateway()
      ..businesses = const [
        AdminBusiness(
          id: 'business-a',
          name: 'Brown Tech',
          ownerName: 'Test Owner',
          onboardingStatus: 'COMPLETED',
          subscriptionStatus: 'ACTIVE',
        ),
      ];
    await tester.pumpWidget(
      ZedBizApp(
        controller: controllerFor(
          activeCommercialStatus,
          user: adminUser,
          admin: admin,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ZedBiz admin'));
    await tester.pumpAndSettle();

    expect(find.text('ZedBiz Admin'), findsOneWidget);
    expect(find.text('Registered businesses'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Businesses'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Businesses'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Brown Tech'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Brown Tech'), findsOneWidget);
    expect(find.textContaining('Subscription: ACTIVE'), findsOneWidget);
  });
}

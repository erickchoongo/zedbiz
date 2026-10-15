import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zedbiz/app/app_controller.dart';
import 'package:zedbiz/features/admin/presentation/admin_business_list_screen.dart';
import 'package:zedbiz/features/admin/domain/admin_business.dart';

import 'helpers/fakes.dart';

class FailingAdmin extends FakeAdminGateway {
  Object? failure;
  @override
  Future<List<AdminBusiness>> listBusinesses({
    String? search,
    String? onboardingStatus,
    String? subscriptionStatus,
  }) async {
    if (failure != null) throw failure!;
    return businesses;
  }
}

void main() {
  Future<void> show(WidgetTester tester, FakeAdminGateway admin) async {
    final controller = AppController(
      authGateway: FakeAuthGateway(),
      businessGateway: FakeBusinessGateway(),
      commercialGateway: FakeCommercialGateway(),
      adminGateway: admin,
    );
    await tester.pumpWidget(
      MaterialApp(home: AdminBusinessListScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [360.0, 600.0, 1200.0]) {
    testWidgets('zero overview at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await show(tester, FakeAdminGateway());
      expect(find.text('Registered businesses'), findsOneWidget);
      expect(find.text('0'), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('No businesses registered yet. Overview totals are zero.'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
    });
    testWidgets('filters plus content at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final admin = FakeAdminGateway()
        ..businesses = const [
          AdminBusiness(
            id: 'b',
            name: 'Visible Business',
            onboardingStatus: 'COMPLETED',
            subscriptionStatus: 'ACTIVE',
            onboardingPaymentStatus: 'PAID',
          ),
        ];
      await show(tester, admin);
      await tester.scrollUntilVisible(
        find.text('Businesses'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Businesses'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('All subscription states'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('All onboarding states'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Visible Business'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Subscription: ACTIVE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  for (final failure in [
    testApiError('Service unavailable'),
    const FormatException('bad JSON'),
  ]) {
    testWidgets('visible failure and retry ${failure.runtimeType}', (
      tester,
    ) async {
      final admin = FailingAdmin()..failure = failure;
      await show(tester, admin);
      expect(find.text('Unable to load admin data'), findsOneWidget);
      expect(find.text('Registered businesses'), findsNothing);
      admin.failure = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Registered businesses'), findsOneWidget);
      expect(find.text('Unable to load admin data'), findsNothing);
    });
  }
}

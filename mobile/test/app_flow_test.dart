import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zedbiz/app/app.dart';
import 'package:zedbiz/app/app_controller.dart';

import 'helpers/fakes.dart';

void main() {
  testWidgets('login shows loading and a safe API error', (tester) async {
    final auth = FakeAuthGateway()..loginGate = Completer<void>();
    final controller = AppController(
      authGateway: auth,
      businessGateway: FakeBusinessGateway(),
      commercialGateway: FakeCommercialGateway(),
      adminGateway: FakeAdminGateway(),
    );
    await tester.pumpWidget(ZedBizApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('login-email')),
      'owner@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'wrong-password',
    );
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    auth.loginError = testApiError('Invalid email or password');
    auth.loginGate!.complete();
    await tester.pumpAndSettle();

    expect(find.text('Invalid email or password'), findsOneWidget);
  });

  testWidgets('registration validates required fields before calling the API', (
    tester,
  ) async {
    final auth = FakeAuthGateway();
    final controller = AppController(
      authGateway: auth,
      businessGateway: FakeBusinessGateway(),
      commercialGateway: FakeCommercialGateway(),
      adminGateway: FakeAdminGateway(),
    );
    await tester.pumpWidget(ZedBizApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New to ZedBiz? Create an account'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('register-submit')));
    await tester.tap(find.byKey(const Key('register-submit')));
    await tester.pump();

    expect(find.text('Enter your full name'), findsOneWidget);
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(
      find.text('Password must have at least 8 characters'),
      findsOneWidget,
    );
    expect(auth.registerCalls, 0);
  });

  testWidgets('logout clears authenticated state', (tester) async {
    final auth = FakeAuthGateway(sessionAvailable: true);
    final controller = AppController(
      authGateway: auth,
      businessGateway: FakeBusinessGateway(businesses: [testBusinessA]),
      commercialGateway: FakeCommercialGateway(),
      adminGateway: FakeAdminGateway(),
    );
    await tester.pumpWidget(ZedBizApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('Brown Tech'), findsWidgets);

    // The redesigned UI keeps sign-out in the More tab, not the app bar.
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    // The More menu builds off-screen entries lazily; scroll until Sign out exists.
    await tester.scrollUntilVisible(
      find.text('Sign out'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(auth.loggedOut, isTrue);
    expect(controller.currentUser, isNull);
    expect(find.text('Sign in'), findsWidgets);
  });

  testWidgets('new users see the zero-business creation state', (tester) async {
    final controller = AppController(
      authGateway: FakeAuthGateway(sessionAvailable: true),
      businessGateway: FakeBusinessGateway(),
      commercialGateway: FakeCommercialGateway(),
      adminGateway: FakeAdminGateway(),
    );
    await tester.pumpWidget(ZedBizApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('Create your first business'), findsOneWidget);
    expect(find.byKey(const Key('create-first-business')), findsOneWidget);
  });

  testWidgets('a user can select one of multiple businesses', (tester) async {
    final controller = AppController(
      authGateway: FakeAuthGateway(sessionAvailable: true),
      businessGateway: FakeBusinessGateway(
        businesses: [testBusinessA, testBusinessB],
      ),
      commercialGateway: FakeCommercialGateway(),
      adminGateway: FakeAdminGateway(),
    );
    await tester.pumpWidget(ZedBizApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('Your businesses'), findsOneWidget);
    await tester.tap(find.text('Green Market'));
    await tester.pumpAndSettle();

    expect(controller.selectedBusiness?.name, 'Green Market');
    expect(find.text('Green Market'), findsWidgets);
    expect(find.text('MANAGER'), findsOneWidget);
  });

  testWidgets(
    'business creation errors remain visible without changing context',
    (tester) async {
      final businesses = FakeBusinessGateway()
        ..createError = testApiError('Business could not be created');
      final controller = AppController(
        authGateway: FakeAuthGateway(sessionAvailable: true),
        businessGateway: businesses,
        commercialGateway: FakeCommercialGateway(),
        adminGateway: FakeAdminGateway(),
      );
      await tester.pumpWidget(ZedBizApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('create-first-business')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('business-name')),
        'Brown Tech',
      );
      await tester.tap(find.byKey(const Key('business-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Business could not be created'), findsOneWidget);
      expect(controller.selectedBusiness, isNull);
    },
  );
}

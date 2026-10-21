import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zedbiz/app/app_controller.dart';
import 'package:zedbiz/core/network/api_client.dart';
import 'package:zedbiz/core/network/api_exception.dart';
import 'package:zedbiz/core/storage/token_storage.dart';
import 'package:zedbiz/features/admin/data/admin_repository.dart';
import 'package:zedbiz/features/admin/presentation/admin_access_screen.dart';

import 'helpers/fakes.dart';
import 'helpers/widget_http.dart';
import 'live_offline_integration_test.dart' show LiveBinding, LiveTokens;

void main() {
  LiveBinding();
  final fixture = Platform.environment['ZEDBIZ_SUSPENSION_FIXTURE'];

  testWidgets('local Admin Access UI and real membership/global restrictions', (
    tester,
  ) async {
    final fixtureFile = File(fixture!);
    expect(
      fixtureFile.existsSync(),
      isTrue,
      reason: 'Fixture missing or already consumed. Generate a fresh fixture for each run.',
    );
    final data = jsonDecode(fixtureFile.readAsStringSync()) as Map;
    final created = DateTime.tryParse(data['created_at'] as String? ?? '');
    expect(created, isNotNull, reason: 'Legacy fixture: regenerate it.');
    final age = DateTime.now().toUtc().difference(created!);
    expect(
      age >= Duration.zero && age < const Duration(minutes: 10),
      isTrue,
      reason: 'Fixture expired: regenerate it.',
    );
    final base = Uri.parse(data['base_url'] as String);

    // This test must NEVER send access-changing requests to production.
    expect(base.scheme, 'http');
    expect(base.host, '127.0.0.1');
    expect(base.port, 18001);

    final transport = WidgetHttp();
    addTearDown(transport.close);
    ApiClient client(String role, {bool widget = false}) => ApiClient(
      client: widget ? transport : null,
      baseUrl: base,
      tokenStorage: LiveTokens(
        StoredTokens(
          accessToken: data[role]['access_token'],
          refreshToken: data[role]['refresh_token'],
        ),
      ),
    );

    final repository = AdminRepository(client('admin'));
    final uiRepository = AdminRepository(client('admin', widget: true));
    final owner = client('owner');
    final bid = data['business']['id'] as String;
    final uid = data['owner_id'] as String;
    final controller = AppController(
      authGateway: FakeAuthGateway(),
      businessGateway: FakeBusinessGateway(),
      commercialGateway: FakeCommercialGateway(),
      adminGateway: uiRepository,
    );
    addTearDown(controller.dispose);

    const businessKey = ValueKey('business-access-action');
    final businessAction = find.byKey(businessKey);

    Future<void> waitForBusinessAction(String label) => transport.until(
      tester,
      () =>
          businessAction.evaluate().length == 1 &&
          find
                  .descendant(of: businessAction, matching: find.text(label))
                  .evaluate()
                  .length ==
              1 &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty &&
          find.byType(AlertDialog).evaluate().isEmpty &&
          tester.widget<OutlinedButton>(businessAction).onPressed != null,
      description: 'enabled business $label action',
    );

    // Catch a reused/expired fixture before performing any mutations.
    await tester.runAsync(() async {
      final state = await repository.businessAccess(bid);
      expect(
        state['suspended_at'],
        isNull,
        reason:
            'This fixture has already been used. Generate a fresh '
            'local fixture and update ZEDBIZ_SUSPENSION_FIXTURE.',
      );
    });

    fixtureFile.renameSync('$fixture.used');
    await tester.pumpWidget(
      MaterialApp(
        home: AdminAccessScreen(
          controller: controller,
          initialBusinessId: bid,
          initialBusinessName: data['business']['name'] as String,
        ),
      ),
    );
    await waitForBusinessAction('Suspend');

    await tester.ensureVisible(businessAction);
    await tester.pump();
    await tester.tap(businessAction);
    await tester.pumpAndSettle();

    // An empty suspension reason must not dismiss the confirmation dialog.
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Confirm suspension'), findsOneWidget);
    await tester.tap(find.text('Confirm suspension'));
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).last,
      'Local UI suspension review',
    );
    await tester.tap(find.text('Confirm suspension'));
    await tester.pump(); // Start the HTTP operation before entering runAsync.
    await waitForBusinessAction('Reactivate');

    await tester.runAsync(() async {
      expect((await repository.businessAccess(bid))['suspended_at'], isNotNull);
      await expectLater(
        owner.getJson('/api/v1/businesses/$bid'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
      );
    });

    await tester.ensureVisible(businessAction);
    await tester.pump();
    await tester.tap(businessAction);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Confirm reactivation'), findsOneWidget);
    await tester.tap(find.text('Confirm reactivation'));
    await tester.pump();
    await waitForBusinessAction('Suspend');

    await tester.runAsync(() async {
      expect((await repository.businessAccess(bid))['suspended_at'], isNull);
      await owner.getJson('/api/v1/businesses/$bid');

      await repository.changeMembershipAccess(
        bid,
        uid,
        suspend: true,
        reason: 'Local staff suspension',
      );
      await expectLater(
        owner.getJson('/api/v1/businesses/$bid'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
      );
      await repository.changeMembershipAccess(bid, uid, suspend: false);
      await owner.getJson('/api/v1/businesses/$bid');

      await repository.changeUserAccess(
        uid,
        suspend: true,
        reason: 'Local global suspension',
      );
      await expectLater(
        owner.getJson('/api/v1/auth/me'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
      );
      await repository.changeUserAccess(uid, suspend: false);
      // Reactivation must not revive a revoked refresh session.
      await expectLater(
        client('owner').postJson('/api/v1/auth/refresh', {
          'refresh_token': data['owner']['refresh_token'],
        }, authenticated: false),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
      );
      final restored = await owner.postJson(
        '/api/v1/auth/login',
        Map<String, dynamic>.from(data['owner_login'] as Map),
        authenticated: false,
      );
      await owner.tokenStorage.write(
        StoredTokens(
          accessToken: restored['access_token'],
          refreshToken: restored['refresh_token'],
        ),
      );
      expect((await owner.getJson('/api/v1/auth/me'))['id'], uid);
      await owner.getJson('/api/v1/businesses/$bid');
    });

    expect(tester.takeException(), isNull);
  }, skip: fixture == null);
}

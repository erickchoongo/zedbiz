
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zedbiz/app/app.dart';
import 'package:zedbiz/core/diagnostics/pilot_diagnostics_screen.dart';

import 'commercial_flow_test.dart' show controllerFor;
import 'helpers/fakes.dart';

void main() {
  testWidgets('owner can reach safe release diagnostics through More', (
    tester,
  ) async {
    final controller = controllerFor(activeCommercialStatus);

    await tester.pumpWidget(ZedBizApp(controller: controller));
    await tester.pumpAndSettle();

    // Open the redesigned More menu.
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();

    // Scroll until the lazily built diagnostics menu item appears.
    final destination = find.byKey(
      const Key('more-pilot-diagnostics'),
    );

    await tester.scrollUntilVisible(
      destination,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(destination, findsOneWidget);

    await tester.tap(destination);
    await tester.pumpAndSettle();

    // Verify that the diagnostics screen opens correctly.
    expect(find.byType(PilotDiagnosticsScreen), findsOneWidget);

    // Preserve all existing diagnostics information checks.
    expect(find.text('App version'), findsOneWidget);
    expect(find.text('Build number'), findsOneWidget);
    expect(find.text('App Git commit'), findsOneWidget);
    expect(find.text('App environment'), findsOneWidget);

    // Sensitive account details must not appear.
    expect(find.text(testUser.email), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

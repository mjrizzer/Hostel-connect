import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hostel_connect/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('anonymous startup and five live feature destinations', (
    tester,
  ) async {
    await app.main();
    // Requires configured Android Firebase staging services and valid debug App Check.
    for (
      var i = 0;
      i < 60 && find.byType(NavigationBar).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.byType(NavigationBar), findsOneWidget);
    for (final label in ['Laundry', 'Mess', 'Community', 'Games', 'Home']) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    }
    expect(find.text('myHostel'), findsOneWidget);
  });
}

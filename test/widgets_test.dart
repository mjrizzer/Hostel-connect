import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_connect/core/widgets.dart';
import 'package:hostel_connect/app/app.dart';

void main() {
  testWidgets('action disabled until server operation completes', (
    tester,
  ) async {
    int calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActionButton(
            label: 'Start Washing',
            onPressed: () async {
              calls++;
              await Future<void>.delayed(const Duration(seconds: 1));
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Start Washing'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
    expect(find.text('Start Washing'), findsOneWidget);
  });
  for (final brightness in Brightness.values) {
    testWidgets('large fonts in ${brightness.name}', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(brightness),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 800),
              textScaler: TextScaler.linear(2),
            ),
            child: const Scaffold(
              body: PageBody(
                children: [
                  Panel(child: Text('Your anonymous account stays private.')),
                ],
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }
}

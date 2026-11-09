import 'package:family_utility_app/app/app.dart';
import 'package:family_utility_app/app/bootstrap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder navLabel(String label) => find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(label),
    );

void main() {
  testWidgets('shell shows four tabs and switches between them',
      (WidgetTester tester) async {
    bootstrap();
    await tester.pumpWidget(const FamilyUtilityApp());

    expect(find.byType(NavigationBar), findsOneWidget);
    for (final String label in <String>['Tools', 'Family', 'Records', 'Files']) {
      expect(navLabel(label), findsOneWidget);
    }

    await tester.tap(navLabel('Family'));
    await tester.pumpAndSettle();
    expect(
      find.text('Start a family space'),
      findsOneWidget,
    );

    await tester.tap(navLabel('Records'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Money, health'), findsOneWidget);

    await tester.tap(navLabel('Files'));
    await tester.pumpAndSettle();
    expect(find.text('Recents, favourites and folders.'), findsOneWidget);
  });

  testWidgets('no sign-in screen anywhere on launch',
      (WidgetTester tester) async {
    await tester.pumpWidget(const FamilyUtilityApp());
    expect(find.textContaining('Sign in'), findsNothing);
    expect(find.textContaining('Log in'), findsNothing);
  });
}

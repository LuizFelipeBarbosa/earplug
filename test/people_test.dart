import 'package:earplug/screens/people.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  testWidgets('signed out shows sign in and no search field', (tester) async {
    await pumpApp(tester, home: const PeopleScreen());
    expect(find.byKey(const Key('people-sign-in')), findsOneWidget);
    expect(find.byKey(const Key('people-search-field')), findsNothing);
  });

  testWidgets('signed in shows friends section', (tester) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    await pumpApp(tester, auth: auth, home: const PeopleScreen());
    expect(find.textContaining('YOUR FRIENDS · 1'), findsOneWidget);
    expect(find.byKey(const Key('people-result-u-maya')), findsOneWidget);
  });

  testWidgets('search is debounced and offers follow controls', (tester) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    await pumpApp(tester, auth: auth, home: const PeopleScreen());
    await tester.enterText(
      find.byKey(const Key('people-search-field')),
      'Lina',
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('people-follow-u-lina')), findsNothing);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('people-result-u-lina')), findsOneWidget);
    expect(find.byKey(const Key('people-follow-u-lina')), findsOneWidget);
    await tester.tap(find.byKey(const Key('people-follow-u-lina')));
    await tester.pump();
    expect(find.text('FOLLOWING'), findsOneWidget);
  });
}

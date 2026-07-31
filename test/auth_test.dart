import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/screens/auth.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('backing out during the through splash keeps the pending RSVP', (
    tester,
  ) async {
    final app = await _pumpAuth(
      tester,
      openGate: (app) {
        app.openGig('g1');
        app.requestRsvp('g1');
      },
    );

    // Signed in, so the taste step is up with its committing button.
    expect(find.text('INTO THE ROOM'), findsOne);
    await tester.tap(find.text('INTO THE ROOM'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text("YOU'RE THROUGH"), findsOne);

    // The action committed the moment the button was tapped.
    expect(app.rsvps, contains('g1'));
    expect(app.pending, isNull);

    // System back mid-splash unmounts the auth screen and cancels its timer —
    // the RSVP must survive.
    app.back();
    await tester.pump(); // the pop's frame unmounts the auth screen
    await tester.pump(const Duration(seconds: 3));
    expect(app.rsvps, contains('g1'));
    expect(app.current.screen, Screen.gig);
  });

  testWidgets('the splash walks through to the pending action on its own', (
    tester,
  ) async {
    final app = await _pumpAuth(
      tester,
      openGate: (app) {
        app.openGig('g1');
        app.requestRsvp('g1');
      },
    );

    await tester.tap(find.text('INTO THE ROOM'));
    await tester.pump(const Duration(seconds: 3));

    expect(app.rsvps, contains('g1'));
    expect(app.current.screen, Screen.gig);
  });

  testWidgets('the splash lands on My Gigs for a myGigs intent', (
    tester,
  ) async {
    final app = await _pumpAuth(tester, openGate: (app) => app.openMyGigsTab());

    await tester.tap(find.text('INTO THE ROOM'));
    await tester.pump(const Duration(seconds: 3));

    expect(app.current.screen, Screen.myGigs);
  });

  testWidgets('a double tap commits once and still lands back on the gig', (
    tester,
  ) async {
    final app = await _pumpAuth(
      tester,
      openGate: (app) {
        app.openGig('g1');
        app.requestRsvp('g1');
      },
    );

    await tester.tap(find.text('INTO THE ROOM'));
    await tester.tap(find.text('INTO THE ROOM'));
    await tester.pump(const Duration(seconds: 3));

    expect(app.rsvps, contains('g1'));
    expect(app.current.screen, Screen.gig);
  });
}

/// Opens an authenticated route through [openGate], signs in, and pumps the
/// auth screen the way main.dart hosts it: unmounted the moment the navigation
/// stack pops it.
Future<AppState> _pumpAuth(
  WidgetTester tester, {
  required void Function(AppState app) openGate,
}) async {
  tester.view.physicalSize = const Size(402, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final auth = FakeAuthService();
  final app = AppState(
    repository: DemoRepository(auth: auth),
    auth: auth,
  );
  addTearDown(app.dispose);

  openGate(app);
  expect(app.current.screen, Screen.auth);
  await auth.signInDemo();

  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(
        theme: buildEpTheme(),
        home: Scaffold(
          body: Consumer<AppState>(
            builder: (_, a, _) => a.current.screen == Screen.auth
                ? const AuthScreen()
                : const SizedBox.shrink(),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400)); // taste-step rise-in
  return app;
}

import 'package:earplug/app_state.dart';
import 'package:earplug/navigation.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/tab_bars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

Future<AppHarness> _pumpBandTabs(WidgetTester tester) async {
  final auth = FakeAuthService();
  await auth.signInDemo();
  return pumpApp(
    tester,
    auth: auth,
    home: const Scaffold(
      body: SizedBox.expand(),
      bottomNavigationBar: BandTabBar(),
    ),
    beforePump: (app) => app.switchToBand('b1'),
  );
}

void main() {
  testWidgets('band nav shows GIGS, INSIGHTS, PROFILE, SWITCH in order', (
    tester,
  ) async {
    final harness = await _pumpBandTabs(tester);
    expect(harness.app.current.screen, Screen.gigMgr);

    final labels = ['GIGS', 'INSIGHTS', 'PROFILE', 'SWITCH'];
    final lefts = [
      for (final label in labels) tester.getTopLeft(find.text(label)).dx,
    ];
    expect(lefts, orderedEquals(List.of(lefts)..sort()));
    expect(find.text('DASH'), findsNothing);
    expect(find.byKey(const Key('band-tab-switch')), findsOne);
  });

  testWidgets('switchToBand lands on GIGS', (tester) async {
    final harness = await _pumpBandTabs(tester);
    harness.app.resetTo(Screen.analytics);
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.analytics);

    harness.app.switchToBand('b1');
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.gigMgr);
    expect(harness.app.canGoBack, isFalse);
  });

  testWidgets('PROFILE tab resets to the own band preview', (tester) async {
    final harness = await _pumpBandTabs(tester);
    await tester.tap(find.byKey(const Key('band-tab-profile')));
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.bandPreview);
    expect(harness.app.current.param, 'b1');
    expect(harness.app.canGoBack, isFalse);
  });

  testWidgets('SWITCH opens the identity switcher', (tester) async {
    await _pumpBandTabs(tester);
    await tester.tap(find.byKey(const Key('band-tab-switch')));
    await tester.pumpAndSettle();
    expect(find.text('SWITCH IDENTITY'), findsOne);
    expect(find.text('Personal account'), findsOne);
  });

  testWidgets('requestMembersSheet lands on the own profile once', (
    tester,
  ) async {
    final harness = await _pumpBandTabs(tester);
    expect(harness.app.takeMembersSheetRequest(), isFalse);

    harness.app.requestMembersSheet();
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.bandPreview);
    expect(harness.app.current.param, 'b1');
    expect(harness.app.canGoBack, isFalse);
    expect(harness.app.takeMembersSheetRequest(), isTrue);
    expect(harness.app.takeMembersSheetRequest(), isFalse);
  });
}

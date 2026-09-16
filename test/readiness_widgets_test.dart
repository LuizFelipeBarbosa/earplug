import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/date_names.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/services/readiness_memory.dart';
import 'package:earplug/widgets/readiness_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';
import 'support/stub_repository.dart';

const _profile = 'band-discovery-profile';
const _image = 'band-discovery-image';
const _clip = 'band-discovery-clip';
const _social = 'band-setup-social';
const _missingInDemo = [_profile, _image, _clip, _social];
const _doneInDemo = [
  'band-discovery-show',
  'band-discovery-listing',
  'band-discovery-revision',
  'band-setup-preview',
  'band-setup-members',
];

const _module = Key('band-readiness');
const _sheet = Key('band-readiness-sheet');
const _toggle = Key('band-readiness-toggle');

/// The 5-of-9 demo state: profile, image, clip and social links still to do.
BandDiscoveryReadiness _readiness({
  bool profileComplete = false,
  bool profileImageReady = false,
  bool clipReady = false,
}) => BandDiscoveryReadiness(
  profileComplete: profileComplete,
  profileImageReady: profileImageReady,
  clipReady: clipReady,
  publishedShowReady: true,
  venuePosterReady: true,
  publishedRevisionCurrent: true,
);

BandSetupStatus _setup({bool socialLinksAdded = false}) => BandSetupStatus(
  profileComplete: true,
  profileImageAdded: true,
  musicAdded: true,
  socialLinksAdded: socialLinksAdded,
  firstGigCreated: true,
  membersInvited: true,
  publicProfilePreviewed: true,
);

/// The module for `b1`, which the demo user administers, above the stubbed
/// readiness sources.
Future<AppHarness> _pump(
  WidgetTester tester, {
  BandDiscoveryReadiness? readiness,
  BandSetupStatus? setup,
  bool readinessPending = false,
  MemoryReadinessMemoryStore? store,
  DateTime Function()? now,
  Size size = const Size(402, 900),
}) async {
  final auth = FakeAuthService();
  await auth.signInDemo();
  final stub = StubRepository(auth: auth)
    ..returns('bandDiscoveryReadiness', readiness ?? _readiness())
    ..returns('bandSetupStatus', setup ?? _setup());
  // A load that never resolves keeps the snapshot null without the retry
  // loop a failed load would start from every rebuild.
  if (readinessPending) {
    stub.returns(
      'bandDiscoveryReadiness',
      Completer<BandDiscoveryReadiness>().future,
    );
  }
  final harness = await pumpApp(
    tester,
    auth: auth,
    repository: stub,
    readinessMemoryStore: store,
    now: now,
    size: size,
    home: Scaffold(
      body: ListView(children: const [ReadinessModule(bandId: 'b1')]),
    ),
  );
  harness.app.switchToBand('b1');
  await tester.pumpAndSettle();
  return harness;
}

/// A store that remembers [_image] as done, so a load where it is not done
/// is a regression stamped with the app clock.
MemoryReadinessMemoryStore _storeRememberingImage() =>
    MemoryReadinessMemoryStore({
      'b1': ReadinessMemory(
        doneIds: {..._doneInDemo, _image},
        seenAt: DateTime(2026, 9, 1),
      ),
    });

Finder _inSheet(Finder finder) =>
    find.descendant(of: find.byKey(_sheet), matching: finder);

/// Closes the sheet with its close pill, which may have scrolled away.
Future<void> _closeSheet(WidgetTester tester) async {
  final close = find.byKey(const Key('band-readiness-close'));
  await tester.ensureVisible(close);
  await tester.pumpAndSettle();
  await tester.tap(close);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the module lists only the missing steps and can reveal the '
      'completed ones', (tester) async {
    await _pump(tester);

    expect(find.byKey(_module), findsOne);
    expect(find.text('READINESS'), findsOne);
    expect(find.byKey(const Key('band-readiness-count')), findsOne);
    expect(find.text('5 OF 9'), findsOne);
    for (var index = 0; index < 9; index++) {
      expect(find.byKey(ValueKey('readiness-segment-$index')), findsOne);
    }
    for (final id in _missingInDemo) {
      expect(find.byKey(ValueKey(id)), findsOne, reason: id);
      expect(
        tester.getSize(find.byKey(ValueKey(id))).height,
        greaterThanOrEqualTo(44),
      );
    }
    for (final id in _doneInDemo) {
      expect(find.byKey(ValueKey(id)), findsNothing, reason: id);
    }
    expect(find.text('Complete profile'), findsOne);
    expect(find.text('Published lineup'), findsNothing);
    expect(find.byKey(const Key('band-readiness-regression')), findsNothing);

    final toggle = find.byKey(_toggle);
    expect(find.text('VIEW 5 COMPLETED'), findsOne);
    expect(tester.getSize(toggle).height, greaterThanOrEqualTo(44));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('HIDE COMPLETED'), findsOne);
    for (final id in [..._missingInDemo, ..._doneInDemo]) {
      expect(find.byKey(ValueKey(id)), findsOne, reason: id);
    }
    expect(find.text('Published lineup'), findsOne);
    expect(find.byKey(_sheet), findsNothing);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('VIEW 5 COMPLETED'), findsOne);
    for (final id in _doneInDemo) {
      expect(find.byKey(ValueKey(id)), findsNothing, reason: id);
    }
  });

  testWidgets('a step action navigates without opening the sheet', (
    tester,
  ) async {
    final harness = await _pump(tester);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey(_social)),
        matching: find.byType(TextButton),
      ),
    );
    await tester.pumpAndSettle();

    expect(harness.app.current.screen, Screen.bandEdit);
    expect(harness.app.current.param, 'links');
    expect(find.byKey(_sheet), findsNothing);
  });

  testWidgets('a complete snapshot renders nothing', (tester) async {
    final harness = await _pump(
      tester,
      readiness: _readiness(
        profileComplete: true,
        profileImageReady: true,
        clipReady: true,
      ),
      setup: _setup(socialLinksAdded: true),
    );

    expect(harness.app.readinessSnapshotFor('b1')!.complete, isTrue);
    expect(find.byKey(_module), findsNothing);
    expect(find.text('READINESS'), findsNothing);
  });

  testWidgets('a missing snapshot renders nothing', (tester) async {
    final harness = await _pump(tester, readinessPending: true);

    expect(harness.app.readinessSnapshotFor('b1'), isNull);
    expect(find.byKey(_module), findsNothing);
    // The module is mounted but takes no space, so the list keeps it offstage.
    expect(find.byType(ReadinessModule, skipOffstage: false), findsOne);
  });

  testWidgets('tapping the card opens the sheet with to do and done groups', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('band-readiness-count')));
    await tester.pumpAndSettle();

    final sheet = find.byKey(_sheet);
    expect(sheet, findsOne);
    expect(find.byKey(const Key('band-readiness-close')), findsOne);
    expect(_inSheet(find.text('READINESS')), findsOne);
    expect(_inSheet(find.text('5 OF 9')), findsOne);
    expect(find.text('TO DO · 4'), findsOne);
    expect(find.text('DONE · 5'), findsOne);
    for (final id in _missingInDemo) {
      expect(find.byKey(ValueKey('readiness-todo-$id')), findsOne, reason: id);
      expect(
        find.byKey(ValueKey('readiness-action-$id')),
        findsOne,
        reason: id,
      );
      expect(find.byKey(ValueKey('readiness-done-$id')), findsNothing);
    }
    for (final id in _doneInDemo) {
      expect(find.byKey(ValueKey('readiness-done-$id')), findsOne, reason: id);
      expect(find.byKey(ValueKey('readiness-todo-$id')), findsNothing);
    }
    expect(find.text('HOSTS READ THIS FIRST.'), findsOne);
    expect(find.text('CARDS AND LINEUPS SHOW IT.'), findsOne);
    expect(find.text('HOSTS LISTEN BEFORE BOOKING.'), findsOne);
    expect(find.text('HOSTS CHECK THESE BEFORE BOOKING.'), findsOne);
    expect(find.byKey(const Key('band-readiness-regression')), findsNothing);

    final rules = find.byKey(const Key('band-readiness-rules'));
    await tester.scrollUntilVisible(
      rules,
      120,
      scrollable: _inSheet(find.byType(Scrollable)).first,
    );
    expect(
      find.text('COMPLETES → LEAVES THE DASH. A STEP FAILING → RETURNS.'),
      findsOne,
    );

    await _closeSheet(tester);
    expect(sheet, findsNothing);
  });

  testWidgets('an action pill closes the sheet and navigates', (tester) async {
    final harness = await _pump(tester);

    await tester.tap(find.byKey(_module));
    await tester.pumpAndSettle();
    expect(find.byKey(_sheet), findsOne);

    await tester.tap(find.byKey(const ValueKey('readiness-action-$_profile')));
    await tester.pumpAndSettle();

    expect(find.byKey(_sheet), findsNothing);
    expect(harness.app.current.screen, Screen.bandEdit);
    expect(harness.app.current.param, 'required');
  });

  testWidgets('a regression shows the banner, auto-opens once, and '
      'dismissing acknowledges it', (tester) async {
    final harness = await _pump(
      tester,
      store: _storeRememberingImage(),
      now: DateTime.now,
    );
    final app = harness.app;
    expect(app.readinessRegressionFor('b1')!.stepIds, [_image]);

    // The sheet opened itself on the first build with the regression.
    final sheet = find.byKey(_sheet);
    expect(sheet, findsOne);
    final banner = find.byKey(const Key('band-readiness-regression'));
    expect(banner, findsOne);
    expect(
      find.descendant(
        of: banner,
        matching: find.text('BACK BECAUSE SOMETHING CHANGED'),
      ),
      findsOne,
    );
    expect(find.text('PROFILE IMAGE CAME UNDONE TODAY.'), findsOne);
    expect(find.byKey(const ValueKey('readiness-todo-$_image')), findsOne);

    await _closeSheet(tester);
    expect(sheet, findsNothing);
    expect(app.readinessRegressionFor('b1'), isNotNull);
    expect(app.readinessSheetShouldAutoOpen('b1'), isFalse);

    // The module still flags the regression but a later build stays quiet.
    expect(find.byKey(_module), findsOne);
    expect(find.text('BACK BECAUSE SOMETHING CHANGED'), findsOne);
    app.switchToBand('b1');
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(_module), const Offset(0, -20));
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
  });

  testWidgets('the regression banner names the weekday for older changes', (
    tester,
  ) async {
    final since = DateTime.now().subtract(const Duration(days: 4));
    await _pump(tester, store: _storeRememberingImage(), now: () => since);

    expect(find.byKey(_sheet), findsOne);
    final weekday = weekdayNames[since.weekday - 1].toUpperCase();
    expect(find.text('PROFILE IMAGE CAME UNDONE ON $weekday.'), findsOne);
  });

  testWidgets('a barrier dismissal also acknowledges the regression', (
    tester,
  ) async {
    final store = _storeRememberingImage();
    final harness = await _pump(tester, store: store, now: DateTime.now);
    expect(find.byKey(_sheet), findsOne);

    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();

    expect(find.byKey(_sheet), findsNothing);
    expect(harness.app.readinessSheetShouldAutoOpen('b1'), isFalse);
    expect((await store.read('b1'))!.regressionAcknowledged, isTrue);
  });

  testWidgets('module and sheet fit a 390 wide phone at text scale 1.3', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(
      tester,
      store: _storeRememberingImage(),
      now: DateTime.now,
      size: const Size(390, 844),
    );

    // The regression auto-opened the sheet; every group is laid out.
    expect(find.byKey(_sheet), findsOne);
    expect(find.text('TO DO · 4'), findsOne);
    await tester.scrollUntilVisible(
      find.byKey(const Key('band-readiness-rules')),
      120,
      scrollable: _inSheet(find.byType(Scrollable)).first,
    );

    await _closeSheet(tester);
    expect(find.byKey(_module), findsOne);
    await tester.tap(find.byKey(_toggle));
    await tester.pumpAndSettle();
    expect(find.text('HIDE COMPLETED'), findsOne);
    expect(tester.takeException(), isNull);
  });
}

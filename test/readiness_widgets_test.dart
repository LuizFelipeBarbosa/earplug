import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/date_names.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/services/readiness_memory.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/readiness_module.dart';
import 'package:earplug/widgets/readiness_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/fakes.dart';
import 'support/harness.dart';
import 'support/stub_repository.dart';

const _b1 = 'band:b1';
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
      body: ListView(children: const [ReadinessModule(scopeKey: _b1)]),
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
      _b1: ReadinessMemory(
        doneIds: {..._doneInDemo, _image},
        seenAt: DateTime(2026, 9, 1),
      ),
    });

/// An app whose host hook is wired, standing in for the organizer lane that
/// will fill it from live organization data.
class _HostReadyAppState extends AppState {
  _HostReadyAppState({
    required super.repository,
    required super.auth,
    required this.snapshot,
  }) : super(readinessMemoryStore: MemoryReadinessMemoryStore());

  final ReadinessSnapshot snapshot;
  final List<String> askedFor = [];

  @override
  ReadinessSnapshot? hostReadinessSnapshotFor(String orgId) {
    askedFor.add(orgId);
    return snapshot;
  }
}

/// [home] under a host-ready app for `org1`, with the same theme and
/// provider the app harness uses.
Future<_HostReadyAppState> _pumpHost(
  WidgetTester tester, {
  required ReadinessSnapshot snapshot,
  required Widget home,
}) async {
  final auth = FakeAuthService();
  await auth.signInDemo();
  final app = _HostReadyAppState(
    repository: StubRepository(auth: auth),
    auth: auth,
    snapshot: snapshot,
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>(
      create: (_) => app,
      child: MaterialApp(theme: buildEpTheme(), home: home),
    ),
  );
  await tester.pumpAndSettle();
  return app;
}

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

    expect(harness.app.readinessSnapshotFor(_b1)!.complete, isTrue);
    expect(find.byKey(_module), findsNothing);
    expect(find.text('READINESS'), findsNothing);
  });

  testWidgets('a missing snapshot renders nothing', (tester) async {
    final harness = await _pump(tester, readinessPending: true);

    expect(harness.app.readinessSnapshotFor(_b1), isNull);
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
    expect(app.readinessRegressionFor(_b1)!.stepIds, [_image]);

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
    expect(app.readinessRegressionFor(_b1), isNotNull);
    expect(app.readinessSheetShouldAutoOpen(_b1), isFalse);

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
    expect(harness.app.readinessSheetShouldAutoOpen(_b1), isFalse);
    expect((await store.read(_b1))!.regressionAcknowledged, isTrue);
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

  testWidgets('a host scope renders its two steps out of the same module', (
    tester,
  ) async {
    final app = await _pumpHost(
      tester,
      snapshot: ReadinessSnapshot.host(
        profileComplete: true,
        financeReady: false,
      ),
      home: Scaffold(
        body: ListView(children: const [ReadinessModule(scopeKey: 'org:org1')]),
      ),
    );

    expect(app.askedFor, contains('org1'));
    expect(find.byKey(_module), findsOne);
    expect(find.text('1 OF 2'), findsOne);
    expect(find.byKey(const ValueKey('readiness-segment-0')), findsOne);
    expect(find.byKey(const ValueKey('readiness-segment-1')), findsOne);
    expect(find.byKey(const ValueKey('readiness-segment-2')), findsNothing);
    expect(find.byKey(const ValueKey('org-setup-finance')), findsOne);
    expect(find.byKey(const ValueKey('org-setup-profile')), findsNothing);
    expect(find.text('Set up finance'), findsOne);
    expect(find.text('VIEW 1 COMPLETED'), findsOne);

    await tester.tap(find.byKey(_module));
    await tester.pumpAndSettle();
    expect(_inSheet(find.text('1 OF 2')), findsOne);
    expect(find.text('TO DO · 1'), findsOne);
    expect(find.text('DONE · 1'), findsOne);
    expect(find.text('DEPOSITS AND PAYOUTS NEED IT.'), findsOne);

    await tester.tap(
      find.byKey(const ValueKey('readiness-action-org-setup-finance')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(_sheet), findsNothing);
    expect(app.organizationId, 'org1');
    expect(app.current.screen, Screen.orgFinance);
  });

  testWidgets('a complete host scope reads 2 OF 2 in the sheet and hides the '
      'module', (tester) async {
    await _pumpHost(
      tester,
      snapshot: ReadinessSnapshot.host(
        profileComplete: true,
        financeReady: true,
      ),
      home: const Scaffold(
        body: Column(
          children: [
            ReadinessModule(scopeKey: 'org:org1'),
            Expanded(child: ReadinessSheet(scopeKey: 'org:org1')),
          ],
        ),
      ),
    );

    expect(find.byKey(_module), findsNothing);
    expect(find.byKey(_sheet), findsOne);
    expect(find.text('2 OF 2'), findsOne);
    expect(find.text('TO DO · 0'), findsOne);
    expect(find.text('DONE · 2'), findsOne);
    expect(
      find.byKey(const ValueKey('readiness-done-org-setup-profile')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('readiness-done-org-setup-finance')),
      findsOne,
    );
  });
}

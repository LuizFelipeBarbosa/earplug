import 'package:earplug/app_state.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/services/readiness_memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';
import 'support/stub_repository.dart';

const _image = 'band-discovery-image';
const _clip = 'band-discovery-clip';
const _social = 'band-setup-social';

BandDiscoveryReadiness _readiness({
  bool profileImageReady = true,
  bool clipReady = true,
}) => BandDiscoveryReadiness(
  profileComplete: true,
  profileImageReady: profileImageReady,
  clipReady: clipReady,
  publishedShowReady: true,
  venuePosterReady: true,
  publishedRevisionCurrent: true,
);

BandSetupStatus _setup({bool socialLinksAdded = true}) => BandSetupStatus(
  profileComplete: true,
  profileImageAdded: true,
  musicAdded: true,
  socialLinksAdded: socialLinksAdded,
  firstGigCreated: true,
  membersInvited: true,
  publicProfilePreviewed: true,
);

/// The band console with the stubbed readiness sources loaded for `b1`,
/// which the demo user administers (and `b2` when [adminOfB2]).
Future<({AppHarness harness, StubRepository stub})> _pump(
  WidgetTester tester, {
  required MemoryReadinessMemoryStore store,
  required DateTime Function() now,
  BandDiscoveryReadiness? readiness,
  BandSetupStatus? setup,
  bool adminOfB2 = false,
}) async {
  final auth = FakeAuthService();
  await auth.signInDemo();
  final stub = StubRepository(auth: auth)
    ..returns('bandDiscoveryReadiness', readiness ?? _readiness())
    ..returns('bandSetupStatus', setup ?? _setup());
  if (adminOfB2) {
    stub.returnsStream(
      'myBands',
      () => Stream.value([
        BandMembership(band: DemoData.bands['b1']!, role: 'admin'),
        BandMembership(band: DemoData.bands['b2']!, role: 'admin'),
      ]),
    );
  }
  final harness = await pumpApp(
    tester,
    auth: auth,
    repository: stub,
    readinessMemoryStore: store,
    now: now,
    home: const Scaffold(body: SizedBox()),
  );
  harness.app.switchToBand('b1');
  await tester.pumpAndSettle();
  return (harness: harness, stub: stub);
}

Future<void> _reload(
  WidgetTester tester,
  AppState app,
  String bandId, {
  BandDiscoveryReadiness? readiness,
  BandSetupStatus? setup,
  required StubRepository stub,
}) async {
  if (readiness != null) stub.returns('bandDiscoveryReadiness', readiness);
  if (setup != null) stub.returns('bandSetupStatus', setup);
  if (readiness != null) await app.refreshBandDiscoveryReadiness(bandId);
  if (setup != null) await app.refreshBandSetupStatus(bandId);
  await tester.pumpAndSettle();
}

void main() {
  final start = DateTime(2026, 9, 15, 12);

  testWidgets('the first look records the done steps without a regression', (
    tester,
  ) async {
    final store = MemoryReadinessMemoryStore();
    final harness = (await _pump(
      tester,
      store: store,
      now: () => start,
      readiness: _readiness(clipReady: false),
    )).harness;
    final app = harness.app;

    final snapshot = app.readinessSnapshotFor('b1')!;
    expect(snapshot.done, 8);
    expect(app.readinessRegressionFor('b1'), isNull);
    expect(app.readinessSheetShouldAutoOpen('b1'), isFalse);

    final memory = (await store.read('b1'))!;
    expect(memory.doneIds, snapshot.doneIds);
    expect(memory.doneIds, isNot(contains(_clip)));
    expect(memory.seenAt, start);
    expect(memory.hasRegression, isFalse);
    app.dispose();
  });

  testWidgets('a step that was done and later fails is a regression', (
    tester,
  ) async {
    final store = MemoryReadinessMemoryStore();
    var now = start;
    final pumped = await _pump(tester, store: store, now: () => now);
    final app = pumped.harness.app;
    var notifications = 0;
    app.addListener(() => notifications++);

    now = start.add(const Duration(days: 1));
    await _reload(
      tester,
      app,
      'b1',
      stub: pumped.stub,
      readiness: _readiness(profileImageReady: false),
    );

    final regression = app.readinessRegressionFor('b1')!;
    expect(regression.stepIds, [_image]);
    expect(regression.since, now);
    expect(notifications, greaterThan(0));

    final memory = (await store.read('b1'))!;
    expect(memory.regressedIds, {_image});
    expect(memory.regressedAt, now);
    expect(memory.regressionAcknowledged, isFalse);
    expect(memory.doneIds, isNot(contains(_image)));
    expect(memory.seenAt, now);

    // A later look that changes nothing keeps the original stamp and, on
    // its own, is silent: the refresh notifies, the reconcile does not.
    final later = now.add(const Duration(hours: 2));
    now = later;
    await _reload(
      tester,
      app,
      'b1',
      stub: pumped.stub,
      readiness: _readiness(profileImageReady: false),
    );
    expect(
      app.readinessRegressionFor('b1')!.since,
      start.add(const Duration(days: 1)),
    );
    expect((await store.read('b1'))!.seenAt, later);

    notifications = 0;
    await app.reconcileReadiness('b1');
    expect(notifications, 0);
    app.dispose();
  });

  testWidgets(
    'the sheet auto-opens once per regression and not after acknowledgement',
    (tester) async {
      final store = MemoryReadinessMemoryStore();
      final pumped = await _pump(tester, store: store, now: () => start);
      final app = pumped.harness.app;

      await _reload(
        tester,
        app,
        'b1',
        stub: pumped.stub,
        setup: _setup(socialLinksAdded: false),
      );
      expect(app.readinessRegressionFor('b1')!.stepIds, [_social]);
      expect(app.readinessSheetShouldAutoOpen('b1'), isTrue);
      expect(app.readinessSheetShouldAutoOpen('b1'), isFalse);

      app.acknowledgeReadinessRegression('b1');
      await tester.pump();
      expect(app.readinessSheetShouldAutoOpen('b1'), isFalse);
      expect((await store.read('b1'))!.regressionAcknowledged, isTrue);
      // Acknowledging hides the prompt, not the regression itself.
      expect(app.readinessRegressionFor('b1')!.stepIds, [_social]);
      app.dispose();
    },
  );

  testWidgets(
    'a persisted unacknowledged regression auto-opens on the next session',
    (tester) async {
      final store = MemoryReadinessMemoryStore({
        'b1': ReadinessMemory(
          doneIds: {_image},
          seenAt: start.subtract(const Duration(days: 2)),
          regressedAt: start.subtract(const Duration(days: 1)),
          regressedIds: {_image},
        ),
      });
      final app = (await _pump(
        tester,
        store: store,
        now: () => start,
        readiness: _readiness(profileImageReady: false),
      )).harness.app;

      expect(
        app.readinessRegressionFor('b1')!.since,
        start.subtract(const Duration(days: 1)),
      );
      expect(app.readinessSheetShouldAutoOpen('b1'), isTrue);
      expect(app.readinessSheetShouldAutoOpen('b1'), isFalse);
      app.dispose();
    },
  );

  testWidgets(
    'a persisted done step that is missing now regresses on first load',
    (tester) async {
      final store = MemoryReadinessMemoryStore({
        'b1': ReadinessMemory(
          doneIds: {_image, _clip},
          seenAt: start.subtract(const Duration(days: 2)),
        ),
      });
      final app = (await _pump(
        tester,
        store: store,
        now: () => start,
        readiness: _readiness(clipReady: false),
      )).harness.app;

      final regression = app.readinessRegressionFor('b1')!;
      expect(regression.stepIds, [_clip]);
      expect(regression.since, start);
      app.dispose();
    },
  );

  testWidgets('completing every step clears the regression', (tester) async {
    final store = MemoryReadinessMemoryStore();
    final pumped = await _pump(tester, store: store, now: () => start);
    final app = pumped.harness.app;

    await _reload(
      tester,
      app,
      'b1',
      stub: pumped.stub,
      readiness: _readiness(profileImageReady: false),
    );
    expect(app.readinessRegressionFor('b1'), isNotNull);

    await _reload(
      tester,
      app,
      'b1',
      stub: pumped.stub,
      readiness: _readiness(),
    );
    expect(app.readinessSnapshotFor('b1')!.complete, isTrue);
    expect(app.readinessRegressionFor('b1'), isNull);
    expect(app.readinessSheetShouldAutoOpen('b1'), isFalse);

    final memory = (await store.read('b1'))!;
    expect(memory.regressedIds, isEmpty);
    expect(memory.regressedAt, isNull);
    expect(memory.doneIds, hasLength(9));
    app.dispose();
  });

  testWidgets('a step never seen done is not a regression', (tester) async {
    final store = MemoryReadinessMemoryStore();
    final pumped = await _pump(
      tester,
      store: store,
      now: () => start,
      readiness: _readiness(clipReady: false),
    );
    final app = pumped.harness.app;

    await _reload(
      tester,
      app,
      'b1',
      stub: pumped.stub,
      readiness: _readiness(clipReady: false),
      setup: _setup(),
    );
    expect(app.readinessRegressionFor('b1'), isNull);
    expect(app.readinessSheetShouldAutoOpen('b1'), isFalse);

    // Done once and then failing counts, but only for that step.
    await _reload(
      tester,
      app,
      'b1',
      stub: pumped.stub,
      readiness: _readiness(),
    );
    await _reload(
      tester,
      app,
      'b1',
      stub: pumped.stub,
      readiness: _readiness(clipReady: false, profileImageReady: false),
    );
    expect(app.readinessRegressionFor('b1')!.stepIds, [_image, _clip]);
    app.dispose();
  });

  testWidgets('memory is kept per band', (tester) async {
    final store = MemoryReadinessMemoryStore();
    final pumped = await _pump(
      tester,
      store: store,
      now: () => start,
      adminOfB2: true,
    );
    final app = pumped.harness.app;
    app.switchToBand('b2');
    await tester.pumpAndSettle();
    expect(app.readinessSnapshotFor('b2')!.complete, isTrue);

    await _reload(
      tester,
      app,
      'b2',
      stub: pumped.stub,
      readiness: _readiness(profileImageReady: false),
    );

    expect(app.readinessRegressionFor('b2')!.stepIds, [_image]);
    expect(app.readinessRegressionFor('b1'), isNull);
    expect(app.readinessSheetShouldAutoOpen('b1'), isFalse);
    expect((await store.read('b1'))!.doneIds, hasLength(9));
    expect((await store.read('b2'))!.regressedIds, {_image});
    app.dispose();
  });

  testWidgets('readiness actions route to the intended task', (tester) async {
    final store = MemoryReadinessMemoryStore();
    final app = (await _pump(
      tester,
      store: store,
      now: () => start,
    )).harness.app;

    final expectations = <ReadinessAction, (Screen, String?)>{
      ReadinessAction.editProfile: (Screen.bandEdit, 'required'),
      ReadinessAction.addMedia: (Screen.bandMedia, 'b1'),
      ReadinessAction.manageShow: (Screen.gigMgr, null),
      ReadinessAction.republish: (Screen.gigMgr, null),
      ReadinessAction.preview: (Screen.bandPreview, 'b1'),
      ReadinessAction.editLinks: (Screen.bandEdit, 'links'),
      ReadinessAction.inviteMembers: (Screen.bandPreview, 'b1'),
    };
    for (final entry in expectations.entries) {
      app.performReadinessAction('b1', entry.key);
      await tester.pumpAndSettle();
      expect(app.current.screen, entry.value.$1, reason: '${entry.key}');
      expect(app.current.param, entry.value.$2, reason: '${entry.key}');
      app.returnToBandDashboard();
      await tester.pumpAndSettle();
    }

    app.performReadinessAction('b1', ReadinessAction.createShow);
    await tester.pumpAndSettle();
    expect(app.current.screen, Screen.gigCreate);
    app.dispose();
  });
}

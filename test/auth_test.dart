import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/screens/auth.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/harness.dart';

void main() {
  testWidgets('backing out during confirmation keeps the pending RSVP', (
    tester,
  ) async {
    final app = await _pumpAuth(
      tester,
      openGate: (app) {
        app.openGig('g1');
        app.requestRsvp('g1');
      },
    );

    expect(find.text('RSVP CONFIRMED'), findsOne);
    expect(app.rsvps, contains('g1'));
    expect(app.pending, isNull);

    // System back mid-confirmation unmounts auth and cancels its timer. The
    // replayed RSVP must survive.
    app.back();
    await tester.pump(); // the pop's frame unmounts the auth screen
    await tester.pump(const Duration(seconds: 3));
    expect(app.rsvps, contains('g1'));
    expect(app.current.screen, Screen.gig);
  });

  testWidgets('successful auth replays and returns without a taste step', (
    tester,
  ) async {
    final app = await _pumpAuth(
      tester,
      openGate: (app) {
        app.openGig('g1');
        app.requestRsvp('g1');
      },
    );

    expect(find.text('PLUG IN'), findsNothing);
    await tester.pump(const Duration(seconds: 2));

    expect(app.rsvps, contains('g1'));
    expect(app.current.screen, Screen.gig);
  });

  testWidgets('the splash lands on My Gigs for a myGigs intent', (
    tester,
  ) async {
    final app = await _pumpAuth(tester, openGate: (app) => app.openMyGigsTab());

    await tester.pump(const Duration(seconds: 2));

    expect(app.current.screen, Screen.myGigs);
  });

  testWidgets('repeated commit calls replay the pending action only once', (
    tester,
  ) async {
    final app = await _pumpAuth(
      tester,
      openGate: (app) {
        app.openGig('g1');
        app.requestRsvp('g1');
      },
    );

    await Future.wait([app.commitAuth(), app.commitAuth()]);
    await tester.pump(const Duration(seconds: 2));

    expect(app.rsvps, contains('g1'));
    expect(app.current.screen, Screen.gig);
  });

  testWidgets('the door explains public browsing and action-time accounts', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpApp(
      tester,
      beforePump: (app) => app.requestSave('g1'),
      home: const Scaffold(body: AuthScreen()),
      pumpFor: const Duration(milliseconds: 100),
    );
    expect(
      find.text(
        'Browse freely. Create an account when you RSVP, save a show, or start a band. It takes about ten seconds.',
      ),
      findsOne,
    );
    expect(find.text('PLUG IN'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending action waits for user setup before replaying', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _GatedEnsureRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) async {
        app.requestRsvp('g1');
        await auth.signInDemo();
      },
      home: const Scaffold(body: AuthScreen()),
      pumpFor: const Duration(milliseconds: 100),
    );

    expect(find.text('FINISHING SIGN-IN'), findsOne);
    expect(repository.rsvpCalls, 0);

    repository.ensureGate.complete();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(repository.rsvpCalls, 1);
    expect(find.text('RSVP CONFIRMED'), findsOne);

    await harness.app.commitAuth();
    expect(repository.rsvpCalls, 1);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('replayed intent keeps a returning fan relationship on', (
    tester,
  ) async {
    final app = await _pumpAuth(
      tester,
      openGate: (app) => app.requestRsvp('g5'),
    );

    // g5 is already in the returning demo fan's account. Replaying the intent
    // must ensure it is on, not toggle it back off.
    expect(app.rsvps, contains('g5'));
    await tester.pump(const Duration(seconds: 2));
    expect(app.rsvps, contains('g5'));
  });

  testWidgets('failed user setup preserves the intent and can be retried', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _RetryEnsureRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) async {
        app.requestSave('g1');
        await auth.signInDemo();
      },
      home: const Scaffold(body: AuthScreen()),
      pumpFor: const Duration(milliseconds: 400),
    );

    expect(find.text('TRY AGAIN'), findsOne);
    expect(harness.app.pending?.kind, PendingKind.save);
    expect(repository.saveCalls, 0);

    await tester.tap(find.text('TRY AGAIN'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(repository.ensureCalls, 2);
    expect(repository.saveCalls, 1);
    expect(harness.app.pending, isNull);
    expect(find.text('SHOW SAVED'), findsOne);
    await tester.pump(const Duration(seconds: 2));
  });
}

class _GatedEnsureRepository extends DemoRepository {
  _GatedEnsureRepository({required super.auth});

  final ensureGate = Completer<void>();
  int rsvpCalls = 0;

  @override
  Future<void> ensureUser({String? name}) => ensureGate.future;

  @override
  Future<void> ensureRsvp(String gigId) async {
    if (!ensureGate.isCompleted) {
      throw StateError('RSVP ran before ensureUser completed');
    }
    rsvpCalls++;
    await super.ensureRsvp(gigId);
  }
}

class _RetryEnsureRepository extends DemoRepository {
  _RetryEnsureRepository({required super.auth});

  int ensureCalls = 0;
  int saveCalls = 0;

  @override
  Future<void> ensureUser({String? name}) async {
    ensureCalls++;
    if (ensureCalls == 1) throw StateError('temporary setup failure');
    await super.ensureUser(name: name);
  }

  @override
  Future<void> ensureSave(String gigId) async {
    saveCalls++;
    await super.ensureSave(gigId);
  }
}

/// Opens an authenticated route through [openGate], signs in, and pumps the
/// auth screen the way main.dart hosts it: unmounted the moment the navigation
/// stack pops it.
Future<AppState> _pumpAuth(
  WidgetTester tester, {
  required void Function(AppState app) openGate,
}) async {
  final auth = FakeAuthService();
  final harness = await pumpApp(
    tester,
    auth: auth,
    beforePump: (app) async {
      openGate(app);
      expect(app.current.screen, Screen.auth);
      await auth.signInDemo();
    },
    home: Scaffold(
      body: Consumer<AppState>(
        builder: (_, a, _) => a.current.screen == Screen.auth
            ? const AuthScreen()
            : const SizedBox.shrink(),
      ),
    ),
    pumpFor: const Duration(milliseconds: 400),
  );
  return harness.app;
}

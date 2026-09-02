import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/gig_detail.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  testWidgets(
    'direct gig subscription keeps cancellations visible and includes text performers in the hero',
    (tester) async {
      final auth = FakeAuthService();
      final repository = _ControlledPublicGigRepository(auth: auth);
      final published = _textOnlyGig();
      final harness = await pumpApp(
        tester,
        repository: repository,
        home: const Scaffold(body: GigDetailScreen(gigId: 'shared-gig')),
        beforePump: (app) {
          repository.emit(published);
          app.openGig('shared-gig');
        },
        pumpFor: const Duration(milliseconds: 100),
      );

      expect(find.text('THIS GIG HAS BEEN CANCELLED'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(GigFlyer),
          matching: find.text('TEXT ONLY OPENER'),
        ),
        findsOne,
      );
      expect(find.text('RSVP — FREE'), findsOne);

      final heroContent = tester.widget<Stack>(
        find.byKey(const ValueKey('gig-detail-hero-content')),
      );
      expect(heroContent.clipBehavior, Clip.none);

      repository.emit(_textOnlyGig(lifecycle: GigLifecycle.cancelled));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(harness.app.gig('shared-gig')?.lifecycle, GigLifecycle.cancelled);
      expect(find.text('THIS GIG HAS BEEN CANCELLED'), findsOne);
    },
  );

  testWidgets('resolved presenter and lineup bands use real profile actions', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: GigDetailScreen(gigId: 'g2')),
    );

    expect(find.text('FOGHORN DIET PRESENTS'), findsOne);
    expect(find.textContaining('IN-STORE RACKET'), findsNothing);

    final follow = find.byKey(const ValueKey('gig-lineup-follow-b1'));
    await tester.scrollUntilVisible(
      follow,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(follow);
    await tester.pump();

    expect(harness.app.pending?.kind, PendingKind.follow);
    expect(harness.app.pending?.id, 'b1');
  });

  testWidgets('gigs without descriptions omit the empty About section', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _ControlledPublicGigRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      repository: repository,
      home: const Scaffold(body: GigDetailScreen(gigId: 'shared-gig')),
      beforePump: (app) {
        repository.emit(_textOnlyGig(desc: '   '));
        app.openGig('shared-gig');
      },
      pumpFor: const Duration(milliseconds: 100),
    );

    expect(harness.app.gig('shared-gig'), isNotNull);
    expect(find.text('ABOUT'), findsNothing);
    expect(find.text('VENUE'), findsOne);
  });

  testWidgets(
    'attendance reconciles optimistic changes with confirmed capacity totals',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final auth = FakeAuthService();
      await auth.signInDemo();
      final repository = _AttendanceRepository(
        auth: auth,
        gig: _textOnlyGig(going: 23, cap: '80'),
      );
      addTearDown(repository.close);
      final harness = await pumpApp(
        tester,
        auth: auth,
        repository: repository,
        home: const Scaffold(body: GigDetailScreen(gigId: 'shared-gig')),
        beforePump: (app) => app.openGig('shared-gig'),
      );

      expect(find.text("WHO'S GOING"), findsNothing);
      expect(find.text('23 GOING'), findsNothing);

      await tester.tap(find.text('RSVP — FREE'));
      await tester.pump();
      expect(harness.app.rsvpCount(repository.gig), 24);
      expect(find.text("WHO'S GOING"), findsNothing);

      repository.completeMutation();
      await tester.pumpAndSettle();
      expect(harness.app.rsvpCount(repository.gig), 24);
      expect(find.text("WHO'S GOING"), findsOne);
      expect(find.text('24+ GOING'), findsOne);
      expect(find.text('24 of 80 spots filled'), findsOne);
      final progress = find.descendant(
        of: find.byKey(
          const ValueKey('attendance-capacity-progress-shared-gig'),
        ),
        matching: find.byType(LinearProgressIndicator),
      );
      expect(tester.widget<LinearProgressIndicator>(progress).value, .3);
      await tester.scrollUntilVisible(
        find.text('24 of 80 spots filled'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(find.bySemanticsLabel('24 of 80 spots filled'), findsOne);
      expect(
        find.textContaining('Bands you follow on this bill'),
        findsNothing,
      );
      expect(find.textContaining('Attendance stays vague'), findsNothing);
      expect(find.text('YOU MAY KNOW'), findsNothing);

      repository.emitGoing(25);
      await tester.pumpAndSettle();
      expect(harness.app.rsvpCount(repository.gig), 25);
      expect(find.text('25 of 80 spots filled'), findsOne);
      expect(
        tester.widget<LinearProgressIndicator>(progress).value,
        closeTo(25 / 80, .001),
      );

      await tester.tap(find.text('GOING ✓'));
      await tester.pump();
      expect(harness.app.rsvpCount(repository.gig), 24);
      expect(harness.app.hasConfirmedRsvp(repository.gig.id), isFalse);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text("WHO'S GOING"), findsNothing);

      repository.completeMutation();
      await tester.pumpAndSettle();
      expect(harness.app.rsvpCount(repository.gig), 24);
      expect(find.text("WHO'S GOING"), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets('failed RSVP rolls back the count and keeps attendance gated', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _AttendanceRepository(
      auth: auth,
      gig: _textOnlyGig(going: 7, cap: 'No cap'),
    )..failNextMutation = true;
    addTearDown(repository.close);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: GigDetailScreen(gigId: 'shared-gig')),
      beforePump: (app) => app.openGig('shared-gig'),
    );

    await tester.tap(find.text('RSVP — FREE'));
    await tester.pump();
    expect(harness.app.rsvpCount(repository.gig), 8);

    repository.completeMutation();
    await tester.pumpAndSettle();
    expect(harness.app.rsvps, isNot(contains('shared-gig')));
    expect(harness.app.rsvpCount(repository.gig), 7);
    expect(find.text("WHO'S GOING"), findsNothing);
    expect(harness.app.toast, 'Something broke. Try again.');
  });

  testWidgets('confirmed no-cap RSVP shows a count without a percentage', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _AttendanceRepository(
      auth: auth,
      gig: _textOnlyGig(going: 4, cap: 'No cap'),
      initiallyRsvpd: true,
    );
    addTearDown(repository.close);
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: GigDetailScreen(gigId: 'shared-gig')),
      beforePump: (app) => app.openGig('shared-gig'),
    );

    expect(find.text("WHO'S GOING"), findsOne);
    expect(find.text('4+ GOING'), findsOne);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    repository.emitGig(
      repository.gig.copyWith(lifecycle: GigLifecycle.cancelled),
    );
    await tester.pumpAndSettle();
    expect(find.text("WHO'S GOING"), findsNothing);
  });
}

Gig _textOnlyGig({
  GigLifecycle lifecycle = GigLifecycle.published,
  String desc = 'A direct-link show.',
  int going = 0,
  String cap = 'No cap',
}) {
  final startsAt = DateTime.now().add(const Duration(days: 2));
  return Gig(
    id: 'shared-gig',
    title: 'Shared Show',
    venueId: 'v1',
    price: 0,
    startsAt: startsAt,
    doorsAt: startsAt.subtract(const Duration(hours: 1)),
    dateShort: Gig.dateShortFor(startsAt.millisecondsSinceEpoch),
    dateLine: Gig.dateLineFor(startsAt.millisecondsSinceEpoch, '8PM / 9PM'),
    time: '8PM / 9PM',
    when: Gig.whenFor(startsAt.millisecondsSinceEpoch),
    flyKey: 'xerox',
    lineup: const [],
    performers: const [
      GigPerformer(
        id: '',
        kind: GigPerformerKind.text,
        name: 'Text Only Opener',
        role: GigPerformerRole.opener,
      ),
    ],
    going: going,
    genres: const [],
    desc: desc,
    tix: Ticketing.rsvp,
    cap: cap,
    lifecycle: lifecycle,
  );
}

class _ControlledPublicGigRepository extends DemoRepository {
  _ControlledPublicGigRepository({required super.auth});

  final _controller = StreamController<Gig?>.broadcast();
  Gig? _current;

  @override
  Stream<Gig?> publicGig(String gigId) {
    Future<void>.microtask(() => _controller.add(_current));
    return _controller.stream;
  }

  void emit(Gig gig) {
    _current = gig;
    _controller.add(gig);
  }
}

class _AttendanceRepository extends DemoRepository {
  _AttendanceRepository({
    required super.auth,
    required this.gig,
    bool initiallyRsvpd = false,
  }) {
    if (initiallyRsvpd) _rsvpIds.add(gig.id);
  }

  Gig gig;
  bool failNextMutation = false;
  final Set<String> _rsvpIds = {};
  final StreamController<Interactions> _interactions =
      StreamController<Interactions>.broadcast();
  final StreamController<Gig?> _publicGig = StreamController<Gig?>.broadcast();
  Completer<void>? _mutation;

  Interactions get _snapshot => Interactions(
    rsvpGigIds: Set.unmodifiable(_rsvpIds),
    followBandIds: const {},
    savedGigIds: const {},
    gigs: _rsvpIds.contains(gig.id) ? [gig] : const [],
    attendedCount: 0,
  );

  @override
  Stream<Interactions> myInteractions() async* {
    yield _snapshot;
    yield* _interactions.stream;
  }

  @override
  Stream<Gig?> publicGig(String ref) async* {
    yield gig;
    yield* _publicGig.stream;
  }

  @override
  Future<void> toggleRsvp(String gigId, {bool? on}) async {
    final mutation = Completer<void>();
    _mutation = mutation;
    await mutation.future;
    _mutation = null;
    if (failNextMutation) {
      failNextMutation = false;
      throw StateError('RSVP update failed');
    }

    final wasGoing = _rsvpIds.contains(gigId);
    final goingNow = on ?? !wasGoing;
    if (goingNow == wasGoing) return;
    goingNow ? _rsvpIds.add(gigId) : _rsvpIds.remove(gigId);
    gig = gig.copyWith(going: gig.going + (goingNow ? 1 : -1));
    _interactions.add(_snapshot);
    _publicGig.add(gig);
  }

  void completeMutation() {
    final mutation = _mutation;
    if (mutation == null) throw StateError('No RSVP mutation is pending.');
    mutation.complete();
  }

  void emitGoing(int count) => emitGig(gig.copyWith(going: count));

  void emitGig(Gig value) {
    gig = value;
    _interactions.add(_snapshot);
    _publicGig.add(gig);
  }

  Future<void> close() async {
    await _interactions.close();
    await _publicGig.close();
  }
}

import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
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
}

Gig _textOnlyGig({GigLifecycle lifecycle = GigLifecycle.published}) {
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
    going: 0,
    genres: const [],
    desc: 'A direct-link show.',
    tix: Ticketing.rsvp,
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

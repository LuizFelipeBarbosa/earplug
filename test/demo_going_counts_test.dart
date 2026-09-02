import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  test('going counts track confirmed demo RSVPs', () async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final gig = _unseededRsvpGig(await repository.feed().first);
    final emissions = <Map<String, int>>[];
    final subscription = repository.goingCounts().listen(emissions.add);
    addTearDown(subscription.cancel);

    await pumpEventQueue();
    expect(emissions, hasLength(1));
    expect(emissions.single[gig.id], gig.going);

    await repository.toggleRsvp(gig.id);
    await pumpEventQueue();
    expect(emissions, hasLength(2));
    expect(emissions.last[gig.id], gig.going + 1);

    final interactions = await repository.myInteractions().first;
    final interactionGig = interactions.gigs.singleWhere(
      (candidate) => candidate.id == gig.id,
    );
    expect(interactionGig.going, gig.going + 1);

    await repository.toggleRsvp(gig.id);
    await pumpEventQueue();
    expect(emissions, hasLength(3));
    expect(emissions.last[gig.id], gig.going);
  });

  testWidgets('AppState keeps the confirmed demo RSVP count incremented', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final gig = _unseededRsvpGig(await repository.feed().first);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: SizedBox.shrink()),
    );

    expect(harness.app.rsvpCount(gig), gig.going);

    harness.app.toggleRsvp(gig.id);
    await tester.pump();
    await tester.pump();

    expect(harness.app.hasConfirmedRsvp(gig.id), isTrue);
    expect(harness.app.rsvpCount(gig), gig.going + 1);

    await tester.pump(const Duration(seconds: 3));
    harness.app.dispose();
  });
}

Gig _unseededRsvpGig(FeedSnapshot snapshot) {
  final interactionCutoff = DateTime.now().subtract(const Duration(hours: 6));
  return snapshot.gigs.firstWhere(
    (gig) =>
        gig.id != 'g5' &&
        gig.tix == Ticketing.rsvp &&
        !gig.startsAt.isBefore(interactionCutoff),
  );
}

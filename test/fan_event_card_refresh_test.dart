import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/my_gigs.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/fan_event_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/harness.dart';

void main() {
  testWidgets('compact is the default date-first card presentation', (
    tester,
  ) async {
    final gig = DemoData.gigs.firstWhere((item) => item.discoveryListingReady);
    final auth = FakeAuthService();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: _BoostedGigRepository(auth: auth, boostedGig: gig),
      now: () => gig.startsAt.subtract(const Duration(days: 1)),
      home: Builder(
        builder: (context) => Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: FanEventCard(gig: gig, app: context.watch<AppState>()),
          ),
        ),
      ),
    );

    expect(harness.app.isDiscoveryBoosted(gig), isTrue);
    final card = tester.widget<FanEventCard>(find.byType(FanEventCard));
    expect(card.presentation, FanEventCardPresentation.compact);
    expect(find.byType(DateBlock), findsOne);
    expect(find.byType(GigFlyer), findsNothing);
    expect(find.text('${gig.going} GOING'), findsOne);
    expect(find.byKey(ValueKey('save-${gig.id}')), findsOne);
    expect(find.byKey(ValueKey('share-${gig.id}')), findsOne);
    expect(find.byKey(ValueKey('ticket-action-${gig.id}')), findsOne);
    final boostLabel = tester.widget<Text>(
      find.byKey(ValueKey('discovery-boost-${gig.id}')),
    );
    expect(boostLabel.style!.fontSize, greaterThanOrEqualTo(11));
    final ageLabel = tester.widget<Text>(
      find.text(gig.ageRequirement.label.toUpperCase()),
    );
    expect(ageLabel.style!.fontSize, greaterThanOrEqualTo(11));
  });

  testWidgets('featured presentation uses the resolved presenter and flyer', (
    tester,
  ) async {
    final gig = DemoData.gigs.firstWhere((item) => item.createdByBand != null);
    await pumpApp(
      tester,
      home: Builder(
        builder: (context) => Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: FanEventCard(
              gig: gig,
              app: context.read<AppState>(),
              presentation: FanEventCardPresentation.featured,
            ),
          ),
        ),
      ),
    );

    final presenter = DemoData.bands[gig.createdByBand]!.name.toUpperCase();
    expect(find.byType(DateBlock), findsNothing);
    expect(find.byType(GigFlyer), findsOne);
    expect(find.text('$presenter PRESENTS'), findsOne);
    expect(find.text(gig.title.toUpperCase()), findsOne);
    expect(find.byKey(ValueKey('ticket-action-${gig.id}')), findsOne);
  });

  testWidgets('cancelled future RSVP still surfaces in the upcoming profile', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _CancelledRsvpRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: MyGigsScreen()),
    );

    final gig = repository.cancelledGig;
    await tester.pumpAndSettle();
    expect(harness.app.rsvps, contains(gig.id));
    expect(harness.app.upcomingRsvpGigs.map((g) => g.id), [gig.id]);
    expect(find.byKey(ValueKey('next-show-${gig.id}')), findsOne);
    expect(find.byKey(ValueKey('fan-event-${gig.id}')), findsOne);
    expect(find.byKey(ValueKey('ticket-action-${gig.id}')), findsNothing);
    expect(find.byKey(ValueKey('show-qr-${gig.id}')), findsNothing);
    expect(find.text('QR PASS'), findsNothing);
    expect(find.text('CANCELLED'), findsWidgets);
  });
}

class _CancelledRsvpRepository extends DemoRepository {
  _CancelledRsvpRepository({required super.auth})
    : cancelledGig = DemoData.gigs
          .firstWhere(
            (gig) =>
                gig.tix == Ticketing.rsvp &&
                gig.startsAt.isAfter(DateTime.now()),
          )
          .copyWith(lifecycle: GigLifecycle.cancelled);

  final Gig cancelledGig;

  @override
  Stream<FeedSnapshot> feed() => Stream.value(
    FeedSnapshot(
      gigs: [
        for (final gig in DemoData.gigs)
          if (gig.id == cancelledGig.id) cancelledGig else gig,
      ],
      venues: DemoData.venues,
      bands: DemoData.bands,
    ),
  );

  @override
  Stream<Interactions> myInteractions() => Stream.value(
    Interactions(
      rsvpGigIds: {cancelledGig.id},
      followBandIds: const {},
      savedGigIds: const {},
      gigs: [cancelledGig],
      attendedCount: 0,
    ),
  );
}

class _BoostedGigRepository extends DemoRepository {
  _BoostedGigRepository({required super.auth, required this.boostedGig});

  final Gig boostedGig;

  Band get _boostedBand => DemoData.bands[boostedGig.createdByBand]!.copyWith(
    discoveryProfileReady: true,
  );

  @override
  Stream<FeedSnapshot> feed() => Stream.value(
    FeedSnapshot(
      gigs: DemoData.gigs,
      venues: DemoData.venues,
      bands: {...DemoData.bands, boostedGig.createdByBand!: _boostedBand},
    ),
  );

  @override
  Stream<List<BandMembership>> myBands() =>
      Stream.value([BandMembership(band: _boostedBand, role: 'admin')]);
}

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/band_profile.dart';
import 'package:earplug/screens/org_dash.dart';
import 'package:earplug/screens/review_compose.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/design_rules.dart';
import 'support/harness.dart';

void main() {
  testWidgets('compose publishes bk4, goes back, and rejects a second review', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const _ReviewHost(bookingId: 'bk4'),
    );
    await enterOrganizer(tester, harness, 'org1');
    harness.app.openReviewCompose('bk4');
    await tester.pumpAndSettle();

    final booking = (await repository.booking('bk4'))!;
    expect(booking.viewerSide, BookingSide.organizer);
    expect(
      find.text(
        '${booking.opportunityTitle} · ${booking.bandName} · '
        '${Gig.dateShortFor(booking.startsAt.millisecondsSinceEpoch)}',
      ),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(_submitButton()).onPressed, isNull);
    expect(find.byIcon(Icons.star_border), findsNWidgets(5));
    expectNoFieldInCard(tester);

    await tester.tap(find.byKey(const ValueKey('review-rating-5')));
    await tester.pump();
    expect(find.byIcon(Icons.star), findsNWidgets(5));
    expect(tester.widget<FilledButton>(_submitButton()).onPressed, isNotNull);
    for (final category in ['professionalism', 'communication']) {
      final chip = find.byKey(ValueKey('review-cat-$category'));
      await tester.tap(chip);
      await tester.pump();
      expect(tester.widget<EpChip>(chip).active, isTrue);
    }
    // A second tap removes a category without clearing the others.
    final sound = find.byKey(const ValueKey('review-cat-sound'));
    await tester.tap(sound);
    await tester.pump();
    await tester.tap(sound);
    await tester.pump();
    expect(tester.widget<EpChip>(sound).active, isFalse);

    const text = 'Excellent set, easy planning, and a prepared band.';
    final field = find.byKey(const ValueKey('review-text'));
    await tester.ensureVisible(field);
    await tester.enterText(field, text);
    await tester.pump();
    expect(find.text('${text.length}/1000'), findsOneWidget);
    expectNoFieldInCard(tester);
    await tester.tap(_submitButton());
    await tester.pumpAndSettle();

    expect(find.byType(ReviewComposeScreen), findsNothing);
    expect(harness.app.current.screen, Screen.orgDash);
    expect(harness.app.canGoBack, isFalse);
    expect(harness.app.toast, 'Review published');
    final reviews = await repository.reviewsForBooking('bk4');
    expect(reviews.mine!.authorSide, BookingSide.organizer);
    expect(reviews.mine!.rating, 5);
    expect(reviews.mine!.categories, ['professionalism', 'communication']);
    expect(reviews.mine!.text, text);
    expect(reviews.mine!.visibleAt, isNotNull);
    expect(reviews.theirs!.visibleAt, reviews.mine!.visibleAt);

    harness.app.openReviewCompose('bk4');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('review-rating-4')));
    await tester.pump();
    expect(find.byIcon(Icons.star), findsNWidgets(4));
    expect(find.byIcon(Icons.star_border), findsOneWidget);
    await tester.tap(_submitButton());
    await tester.pumpAndSettle();

    expect(find.byType(ReviewComposeScreen), findsOneWidget);
    expect(harness.app.current.screen, Screen.reviewCompose);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('review-feedback')),
        matching: find.text('You already reviewed this booking'),
      ),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(_submitButton()).onPressed, isNotNull);
    expect((await repository.reviewsForBooking('bk4')).mine!.rating, 5);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('closed review window shows the exact inline error', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: DemoRepository(auth: auth),
      home: const _ReviewHost(bookingId: 'bk3'),
    );
    await enterOrganizer(tester, harness, 'org1');
    harness.app.openReviewCompose('bk3');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('review-rating-5')));
    await tester.pump();
    await tester.tap(_submitButton());
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('review-feedback')),
        matching: find.text('The review window has closed'),
      ),
      findsOneWidget,
    );
    expect(harness.app.current.screen, Screen.reviewCompose);
    expect(tester.widget<FilledButton>(_submitButton()).onPressed, isNotNull);
    expectNoFieldInCard(tester);
  });

  testWidgets('direct compose shows the organization for an artist', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    await repository.removeOrganizationMember(
      organizationId: 'org1',
      userId: DemoData.demoUserId,
    );
    final booking = (await repository.booking('bk3'))!;
    expect(booking.viewerSide, BookingSide.artist);
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const ReviewComposeScreen(bookingId: 'bk3'),
    );

    expect(
      find.text(
        '${booking.opportunityTitle} · ${booking.organizationName} · '
        '${Gig.dateShortFor(booking.startsAt.millisecondsSinceEpoch)}',
      ),
      findsOneWidget,
    );
    expectNoFieldInCard(tester);
  });

  testWidgets('missing booking has no review form or submit action', (
    tester,
  ) async {
    await pumpApp(
      tester,
      home: const ReviewComposeScreen(bookingId: 'missing'),
    );

    expect(find.text('BOOKING NOT FOUND'), findsOneWidget);
    expect(find.byKey(const ValueKey('review-submit')), findsNothing);
    expect(find.byKey(const ValueKey('review-text')), findsNothing);
  });

  testWidgets('band profile shows its summary and seeded public review', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final review = (await repository.reviewsForBand('b1')).single;
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );
    final section = find.byKey(const ValueKey('band-reviews'));
    await _scrollTo(tester, section);

    expect(
      find.descendant(
        of: section,
        matching: find.text('★ 5.0 · 1 reviews · 1 completed bookings'),
      ),
      findsOneWidget,
    );
    final card = find.byKey(ValueKey('band-review-${review.reviewId}'));
    expect(tester.widget(card), isA<EpCard>());
    expect(
      find.descendant(of: card, matching: find.text('The Foghorn Club')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text(review.monthLabel)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text(review.text)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.byIcon(Icons.star)),
      findsNWidgets(5),
    );
    final category = tester.widget<EpChip>(
      find.descendant(of: card, matching: find.byType(EpChip)),
    );
    expect(category.label, 'PROFESSIONALISM');
    expect(category.active, isTrue);
    expect(category.onTap, isNull);
    expect(category.readOnly, isTrue);
  });

  testWidgets('band without a review summary omits the reviews section', (
    tester,
  ) async {
    await pumpApp(
      tester,
      home: const Scaffold(body: BandProfileScreen(bandId: 'b2')),
    );
    await _scrollTo(tester, find.text('PAST GIGS · 2 PLAYED'));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('band-reviews')), findsNothing);
    expect(find.textContaining('REVIEWS'), findsNothing);
  });

  testWidgets(
    'organizer dashboard shows seeded rating and only public reviews',
    (tester) async {
      final auth = FakeAuthService();
      final repository = DemoRepository(auth: auth);
      final review = (await repository.reviewsForOrganization('org1')).single;
      final harness = await pumpApp(
        tester,
        auth: auth,
        repository: repository,
        home: const Scaffold(body: OrgDashScreen()),
      );
      await enterOrganizer(tester, harness, 'org1');
      final rating = find.byKey(const ValueKey('org-dash-stat-rating'));
      await _scrollTo(tester, rating);
      final stat = tester.widget<EpStatCard>(rating);
      expect(stat.label, 'RATING');
      expect(stat.value, '4.0');
      expect(stat.caption, '1 reviews');

      final section = find.byKey(const ValueKey('org-dash-reviews'));
      await _scrollTo(tester, section);
      final card = find.byKey(ValueKey('org-dash-review-${review.reviewId}'));
      expect(
        find.descendant(of: card, matching: find.text('Foghorn Diet')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text(review.monthLabel)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text(review.text)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.byIcon(Icons.star)),
        findsNWidgets(4),
      );
      // bk4's seeded artist review stays blind until the organizer submits.
      expect(find.text('Pigeon Court'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'organizer dashboard shows Pigeon Court after both sides submit',
    (tester) async {
      final auth = FakeAuthService();
      final repository = DemoRepository(auth: auth);
      await repository.submitReview(
        bookingId: 'bk4',
        rating: 5,
        categories: const [],
        text: 'Great show.',
      );
      final reviews = await repository.reviewsForOrganization('org1');
      expect(reviews.first.counterpartyName, 'Pigeon Court');
      final harness = await pumpApp(
        tester,
        auth: auth,
        repository: repository,
        home: const Scaffold(body: OrgDashScreen()),
      );
      await enterOrganizer(tester, harness, 'org1');
      final rating = find.byKey(const ValueKey('org-dash-stat-rating'));
      await _scrollTo(tester, rating);
      final stat = tester.widget<EpStatCard>(rating);
      expect(stat.value, '3.5');
      expect(stat.caption, '2 reviews');

      await _scrollTo(tester, find.byKey(const ValueKey('org-dash-reviews')));
      final first = find.byKey(
        ValueKey('org-dash-review-${reviews.first.reviewId}'),
      );
      final last = find.byKey(
        ValueKey('org-dash-review-${reviews.last.reviewId}'),
      );
      expect(
        find.descendant(of: first, matching: find.text('Pigeon Court')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: first, matching: find.text(reviews.first.text)),
        findsOneWidget,
      );
      expect(tester.getTopLeft(first).dy, lessThan(tester.getTopLeft(last).dy));
      expect(tester.takeException(), isNull);
    },
  );
}

class _ReviewHost extends StatelessWidget {
  const _ReviewHost({required this.bookingId});

  final String bookingId;

  @override
  Widget build(BuildContext context) {
    final screen = context.select<AppState, Screen>(
      (app) => app.current.screen,
    );
    return screen == Screen.reviewCompose
        ? ReviewComposeScreen(bookingId: bookingId)
        : const Material(child: SizedBox());
  }
}

Finder _submitButton() => find.descendant(
  of: find.byKey(const ValueKey('review-submit')),
  matching: find.byType(FilledButton),
);

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

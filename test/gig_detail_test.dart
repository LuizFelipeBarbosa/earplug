import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/gig_detail.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/ep_rows.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:earplug/widgets/venue_mini_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/fixtures.dart';
import 'support/harness.dart';

void main() {
  testWidgets('flat hero, open facts and sticky RSVP keep the artwork clear', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: GigDetailScreen(gigId: 'g1')),
    );
    final gig = harness.app.gig('g1')!;
    final flyer = find.byKey(const ValueKey('gig-detail-flyer'));
    final flyerRect = tester.getRect(flyer);
    expect(flyerRect.width, 402);
    expect(flyerRect.height, 402 * 1.25);
    expect(
      find.descendant(of: flyer, matching: find.byType(Text)),
      findsNothing,
    );
    expect(
      find.descendant(of: flyer, matching: find.byType(EpIconPill)),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('gig-detail-hero-content')), findsOne);
    for (final key in [
      'gig-detail-back-control',
      'gig-detail-save-g1',
      'gig-detail-share-g1',
    ]) {
      final control = find.byKey(ValueKey(key));
      expect(control, findsOne);
      expect(tester.getSize(control), const Size(44, 44));
      expect(tester.getBottomLeft(control).dy, lessThan(flyerRect.top));
    }
    final poster = tester.widget<GigFlyer>(find.byType(GigFlyer));
    expect(poster.child, isNull);
    expect(poster.scrim, isFalse);

    final title = find.byKey(const ValueKey('gig-detail-title-block'));
    expect(tester.getTopLeft(title).dy, flyerRect.bottom);
    final display = tester.widget<EpDisplay>(
      find.descendant(of: title, matching: find.byType(EpDisplay)),
    );
    expect(display.text, gig.title);
    expect(display.size, 32);
    expect(display.maxLines, 3);
    expect(
      find.descendant(of: title, matching: find.byType(EpEyebrow)),
      findsNothing,
    );
    final date = find.byKey(const Key('gig-fact-date'));
    expect(
      find.descendant(of: date, matching: find.text(gig.dateShort)),
      findsOne,
    );
    expect(
      find.descendant(
        of: date,
        matching: find.text(' · Doors 8PM · Start 9PM'),
      ),
      findsOne,
    );
    final meta = find.byKey(const Key('gig-fact-meta'));
    final free = find.descendant(of: meta, matching: find.text('FREE'));
    expect(
      tester.widget<Text>(free).style?.color,
      tester.element(meta).epColors.accent,
    );
    expect(find.descendant(of: meta, matching: find.text('18+')), findsOne);
    expect(
      find.descendant(of: meta, matching: find.text('43 GOING')),
      findsOne,
    );
    expect(find.byType(EpFactGrid), findsNothing);
    expect(find.byType(EpFactCell), findsNothing);
    expect(find.byType(EpPanel), findsNothing);

    final cta = find.byType(EpBottomCta);
    expect(
      find.descendant(
        of: cta,
        matching: find.text('FREE · RSVP FOR HEADCOUNT'),
      ),
      findsOne,
    );
    expect(
      find.descendant(of: cta, matching: find.byType(EpEyebrow)),
      findsOne,
    );
    final button = find.descendant(of: cta, matching: find.byType(EpPill));
    expect(tester.widget<EpPill>(button).variant, EpPillVariant.primary);
    expect(tester.widget<EpPill>(button).expand, isTrue);
    expect(tester.getSize(button).width, tester.getSize(cta).width - 40);
    expect(tester.getRect(cta).bottom, 900);
  });

  testWidgets(
    'portrait custom flyer uses blur and contain below flat preview status',
    (tester) async {
      final gig = gigFixture(id: 'draft-preview', title: 'Current draft');
      final portraitBytes = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 20, 40),
          Paint()..color = Colors.white,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(20, 40);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        return data!.buffer.asUint8List();
      });
      await _pumpPresentation(
        tester,
        gig,
        flyerBytes: portraitBytes!,
        previewLabel: 'PRIVATE DRAFT',
        size: const Size(402, 600),
      );

      final flyer = find.byKey(const ValueKey('gig-detail-flyer'));
      expect(tester.getSize(flyer), const Size(402, 360));
      expect(
        find.descendant(of: flyer, matching: find.byType(ImageFiltered)),
        findsOne,
      );
      final images = tester.widgetList<Image>(
        find.descendant(of: flyer, matching: find.byType(Image)),
      );
      expect(images.map((image) => image.fit), [BoxFit.cover, BoxFit.contain]);
      expect(images.every((image) => image.image is MemoryImage), isTrue);
      expect(
        find.descendant(of: flyer, matching: find.byType(Text)),
        findsNothing,
      );
      expect(find.byType(GigFlyer), findsNothing);
      final status = find.byKey(const ValueKey('gig-draft-preview-status'));
      expect(tester.getSize(status), const Size(402, 32));
      expect(tester.getBottomLeft(status).dy, tester.getTopLeft(flyer).dy);
      expect(find.byKey(const ValueKey('gig-detail-back-control')), findsOne);
      expect(
        find.byKey(const ValueKey('gig-detail-save-draft-preview')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('gig-detail-share-draft-preview')),
        findsNothing,
      );
      expect(find.text('CURRENT DRAFT'), findsOne);
      expect(find.text('FREE RSVP · PREVIEW ONLY'), findsOne);
    },
  );

  testWidgets(
    'remote custom flyer uses plain fallbacks and a sharp contain image',
    (tester) async {
      await _pumpPresentation(
        tester,
        gigFixture(
          id: 'custom',
          flyKey: 'custom',
          flyerUrl: 'https://example.test/flyer.png',
        ),
      );

      final flyer = find.byKey(const ValueKey('gig-detail-flyer'));
      expect(
        find.descendant(of: flyer, matching: find.byType(ImageFiltered)),
        findsOne,
      );
      final images = tester.widgetList<EpNetworkImage>(
        find.descendant(of: flyer, matching: find.byType(EpNetworkImage)),
      );
      expect(images.map((image) => image.fit), [BoxFit.cover, BoxFit.contain]);
      expect(images.every((image) => image.fallback is ColoredBox), isTrue);
      expect(
        find.descendant(of: flyer, matching: find.byType(Text)),
        findsNothing,
      );
      expect(find.byType(GigFlyer), findsNothing);
    },
  );

  testWidgets(
    'single-time drafts omit Start and keep an unset venue inactive',
    (tester) async {
      await _pumpPresentation(
        tester,
        gigFixture(
          id: 'single-time',
          time: '8PM',
          createdByBand: 'missing-band',
        ),
        venueSet: false,
        previewLabel: 'PRIVATE DRAFT',
      );
      final date = find.byKey(const Key('gig-fact-date'));
      expect(
        find.descendant(of: date, matching: find.text(' · Doors 8PM')),
        findsOne,
      );
      expect(
        find.descendant(of: date, matching: find.textContaining('Start')),
        findsNothing,
      );
      final venue = find.byKey(const Key('gig-fact-venue'));
      expect(find.text('VENUE NOT SET'), findsOne);
      expect(tester.widget<InkWell>(venue).onTap, isNull);
      expect(find.byKey(const Key('gig-location-strip')), findsNothing);
      final title = find.byKey(const ValueKey('gig-detail-title-block'));
      expect(
        find.descendant(of: title, matching: find.byType(EpEyebrow)),
        findsNothing,
      );
    },
  );

  for (final scenario in [
    (
      gigId: 'g2',
      area: 'Mission, San Francisco',
      verified: true,
      approximate: true,
    ),
    (
      gigId: 'g3',
      area: 'Temescal, Oakland',
      verified: false,
      approximate: false,
    ),
    (gigId: 'g4', area: 'Dogpatch, SF', verified: false, approximate: false),
  ]) {
    testWidgets(
      'location strip reflects venue precision for ${scenario.gigId}',
      (tester) async {
        final harness = await pumpApp(
          tester,
          home: Scaffold(body: GigDetailScreen(gigId: scenario.gigId)),
        );
        final venueId = harness.app.gig(scenario.gigId)!.venueId;
        final fact = find.byKey(const Key('gig-fact-venue'));
        expect(
          find.descendant(of: fact, matching: find.text(' · ${scenario.area}')),
          findsOne,
        );
        final strip = find.byKey(const Key('gig-location-strip'));
        final map = find.descendant(
          of: strip,
          matching: find.byType(VenueMapPreview),
        );
        expect(tester.getSize(map), const Size(72, 72));
        expect(
          tester.widget<VenueMapPreview>(map).approximate,
          scenario.approximate,
        );
        expect(tester.widget<VenueMapPreview>(map).showAttribution, isFalse);
        expect(tester.widget<VenueMapPreview>(map).overlayLabel, isNull);
        expect(
          find.descendant(
            of: strip,
            matching: find.text(scenario.area.toUpperCase()),
          ),
          findsOne,
        );
        expect(
          find.byKey(const Key('gig-venue-verified')),
          scenario.verified ? findsOne : findsNothing,
        );
        expect(
          find.text('APPROX. AREA'),
          scenario.approximate ? findsOne : findsNothing,
        );
        expect(
          find.byKey(const Key('gig-venue-directions')),
          scenario.approximate ? findsNothing : findsOne,
        );
        expect(find.byType(EpPanel), findsNothing);
        expect(find.byType(EpFactGrid), findsNothing);
        await tester.ensureVisible(strip);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: strip,
            matching: find.text(scenario.area.toUpperCase()),
          ),
        );
        await tester.pump();
        expect(harness.app.current.screen, Screen.venue);
        expect(harness.app.current.param, venueId);
      },
    );
  }

  testWidgets(
    'direct gig subscription keeps cancellations visible and text performers in the lineup',
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
          of: find.byType(EpEntityRow),
          matching: find.text('TEXT ONLY OPENER'),
        ),
        findsOne,
      );
      expect(find.text('RSVP'), findsOne);

      expect(find.byKey(const ValueKey('gig-detail-hero-content')), findsOne);
      expect(
        find.descendant(of: find.byType(GigFlyer), matching: find.byType(Text)),
        findsNothing,
      );
      expect(find.text('LINEUP · 1'), findsOne);

      repository.emit(_textOnlyGig(lifecycle: GigLifecycle.cancelled));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(harness.app.gig('shared-gig')?.lifecycle, GigLifecycle.cancelled);
      expect(find.text('THIS GIG HAS BEEN CANCELLED'), findsOne);
      expect(
        tester.getBottomLeft(find.text('THIS GIG HAS BEEN CANCELLED')).dy,
        lessThanOrEqualTo(
          tester.getTopLeft(find.byKey(const ValueKey('gig-detail-flyer'))).dy,
        ),
      );
      expect(find.text('GIG CANCELLED'), findsOne);
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
    final title = find.byKey(const ValueKey('gig-detail-title-block'));
    expect(
      find.descendant(of: title, matching: find.text('RIPTIDE RELEASE SHOW')),
      findsOne,
    );
    expect(
      find.descendant(of: title, matching: find.text('FOGHORN DIET')),
      findsNothing,
    );
    expect(find.text('PAY AT THE DOOR · RSVP HOLDS NOTHING'), findsOne);
    final meta = find.byKey(const Key('gig-fact-meta'));
    final price = find.descendant(of: meta, matching: find.text(r'$10'));
    expect(
      tester.widget<Text>(price).style?.color,
      tester.element(meta).epColors.ink,
    );
    expect(
      find.descendant(of: meta, matching: find.text('ALL AGES')),
      findsOne,
    );
    expect(find.text('LINEUP · 2'), findsOne);
    final rows = tester
        .widgetList<EpEntityRow>(find.byType(EpEntityRow))
        .toList();
    expect(rows.map((row) => row.title), ['Foghorn Diet', 'Pigeon Court']);
    expect(rows.first.leading, isA<BandAvatar>());
    expect(rows.first.sub, startsWith('Headliner · '));
    expect(rows.last.sub, startsWith('Support · '));
    final firstRow = find.byWidget(rows.first);
    final lastRow = find.byWidget(rows.last);
    final firstBottom = tester.getBottomLeft(firstRow).dy;
    final lastTop = tester.getTopLeft(lastRow).dy;
    expect(lastTop - firstBottom, 1);
    expect(
      find.byType(EpHairline).evaluate().where((element) {
        final rect = tester.getRect(
          find.byElementPredicate((candidate) => identical(candidate, element)),
        );
        return rect.top == firstBottom && rect.bottom == lastTop;
      }),
      hasLength(1),
    );

    final follow = find.byKey(const ValueKey('gig-lineup-follow-b1'));
    await tester.ensureVisible(follow);
    await tester.pumpAndSettle();
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
    expect(find.byKey(const Key('gig-fact-venue')), findsOne);
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
      expect(find.text('23 GOING'), findsOne);
      expect(
        find.byKey(const ValueKey('gig-attendance-hidden-shared-gig')),
        findsOne,
      );

      await tester.tap(find.text('RSVP'));
      await tester.pump();
      expect(harness.app.rsvpCount(repository.gig), 24);
      expect(find.text('24 GOING'), findsOne);
      expect(find.text("WHO'S GOING"), findsNothing);

      repository.completeMutation();
      await tester.pumpAndSettle();
      expect(harness.app.rsvpCount(repository.gig), 24);
      expect(find.text("WHO'S GOING"), findsOne);
      expect(find.text('24+ GOING'), findsOne);
      final attendance = find.byKey(
        const ValueKey('gig-attendance-shared-gig'),
      );
      expect(attendance, findsOne);
      expect(find.byKey(const ValueKey('who-is-going-shared-gig')), findsOne);
      expect(find.byType(EpCard), findsNothing);
      expect(
        tester.getBottomLeft(find.byKey(const Key('gig-fact-meta'))).dy,
        lessThan(tester.getTopLeft(find.text("WHO'S GOING")).dy),
      );
      expect(
        tester.getBottomLeft(attendance).dy,
        lessThan(tester.getTopLeft(find.text('LINEUP · 1')).dy),
      );
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
      expect(find.text('24 GOING'), findsOne);
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

    await tester.tap(find.text('RSVP'));
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

  testWidgets('paid gigs show the buy tickets CTA with their price', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    await pumpApp(
      tester,
      auth: auth,
      home: const Scaffold(body: GigDetailScreen(gigId: 'g8')),
    );

    expect(find.text(r'BUY TICKETS · $25.00'), findsOne);
    expect(find.byKey(const Key('gig-buy-tickets')), findsOne);
    expect(
      find.text(
        'TICKETS ARE SOLD BY THE ORGANIZER · EARPLUG FEE ADDED AT CHECKOUT',
      ),
      findsOne,
    );
    expect(find.text('RSVP'), findsNothing);
    expect(find.textContaining('AT DOOR'), findsNothing);
    final meta = find.byKey(const Key('gig-fact-meta'));
    final price = find.descendant(of: meta, matching: find.text(r'$25.00'));
    expect(
      tester.widget<Text>(price).style?.color,
      tester.element(meta).epColors.ink,
    );
    expect(
      find.descendant(of: meta, matching: find.textContaining('GOING')),
      findsNothing,
    );
  });

  testWidgets('buy tickets opens the purchase sheet for signed-in fans', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    await pumpApp(
      tester,
      auth: auth,
      home: const Scaffold(body: GigDetailScreen(gigId: 'g8')),
    );

    await tester.tap(find.byKey(const Key('gig-buy-tickets')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ticket-hold')), findsOne);
    expect(find.text('HOLD TICKETS'), findsOne);
  });

  testWidgets('buy tickets gates signed-out fans through sign-in', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: GigDetailScreen(gigId: 'g8')),
    );

    await tester.tap(find.byKey(const Key('gig-buy-tickets')));
    await tester.pumpAndSettle();

    expect(harness.app.pending?.kind, PendingKind.tickets);
    expect(harness.app.pending?.id, 'g8');
    expect(find.byKey(const Key('ticket-hold')), findsNothing);
  });

  testWidgets(
    'gig detail shows known people who are going, with relation subtitles and the summary line',
    (tester) async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final harness = await pumpApp(
        tester,
        auth: auth,
        home: const Scaffold(body: GigDetailScreen(gigId: 'g9')),
      );

      harness.app.toggleRsvp('g9');
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('known-people-g9')), findsOneWidget);
      expect(find.text('Maya and Theo are going'), findsOneWidget);
      expect(find.byKey(const ValueKey('known-person-u-maya')), findsOneWidget);
      expect(find.byKey(const ValueKey('known-person-u-theo')), findsOneWidget);
      expect(find.text('Friend'), findsOneWidget);
      expect(find.text('Seen at 2 shows'), findsOneWidget);
      expect(find.text('25+ GOING'), findsOneWidget);
    },
  );

  testWidgets('gig detail shows nothing extra when signed out', (tester) async {
    await pumpApp(
      tester,
      home: const Scaffold(body: GigDetailScreen(gigId: 'g9')),
    );

    expect(find.byKey(const ValueKey('known-people-g9')), findsNothing);
  });

  testWidgets('gig detail shows nothing extra when no known people are going', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final harness = await pumpApp(
      tester,
      auth: auth,
      home: const Scaffold(body: GigDetailScreen(gigId: 'g1')),
    );

    harness.app.toggleRsvp('g1');
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('known-people-g1')), findsNothing);
    expect(find.text("WHO'S GOING"), findsOneWidget);
    expect(find.text('44+ GOING'), findsOneWidget);
  });

  testWidgets('loadKnownAttendees is requested once per open', (tester) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _KnownAttendeesCountingRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: GigDetailScreen(gigId: 'g9')),
    );

    expect(repository.knownAttendeesCalls, 1);
    harness.app.notifyListeners();
    await tester.pump();
    harness.app.toggleRsvp('g9');
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(repository.knownAttendeesCalls, 1);
  });
}

Future<AppHarness> _pumpPresentation(
  WidgetTester tester,
  Gig gig, {
  Uint8List? flyerBytes,
  String? previewLabel,
  bool venueSet = true,
  Size size = const Size(402, 900),
}) => pumpApp(
  tester,
  size: size,
  home: Scaffold(
    body: Builder(
      builder: (context) => GigDetailPresentation(
        gig: gig,
        app: context.watch<AppState>(),
        performers: gig.performers,
        flyerBytes: flyerBytes,
        previewLabel: previewLabel,
        venueSet: venueSet,
      ),
    ),
  ),
);

Gig _textOnlyGig({
  GigLifecycle lifecycle = GigLifecycle.published,
  String desc = 'A direct-link show.',
  int going = 0,
  String cap = 'No cap',
}) {
  final startsAt = DateTime.now().add(const Duration(days: 2));
  return gigFixture(
    id: 'shared-gig',
    title: 'Shared Show',
    startsAt: startsAt,
    doorsAt: startsAt.subtract(const Duration(hours: 1)),
    flyKey: 'xerox',
    performers: const [
      GigPerformer(
        id: '',
        kind: GigPerformerKind.text,
        name: 'Text Only Opener',
        role: GigPerformerRole.opener,
      ),
    ],
    going: going,
    desc: desc,
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

class _KnownAttendeesCountingRepository extends DemoRepository {
  _KnownAttendeesCountingRepository({required super.auth});

  int knownAttendeesCalls = 0;

  @override
  Future<KnownAttendees> knownAttendees(
    String gigId, {
    required DateTime now,
  }) async {
    knownAttendeesCalls++;
    return super.knownAttendees(gigId, now: now);
  }
}

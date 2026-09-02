import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/gig_create.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/form_bits.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'support/fixtures.dart';
import 'support/harness.dart';

void main() {
  testWidgets(
    'the flyer, its presses and every sheet render and drive the form',
    (tester) async {
      final app = (await _pumpGigCreate(tester)).app;

      // The editor keeps section labels while the six checklist tiles identify
      // every picker without duplicate headings immediately above them.
      expect(find.text('GIG DRAFT'), findsOne);
      expect(find.text('DRAFT'), findsOne);
      expect(find.text('SAVE DRAFT'), findsOne);
      expect(find.text('GIG NAME'), findsNothing);
      expect(find.text('DATE'), findsOne);
      expect(find.text('DOORS AND START TIME'), findsNothing);
      expect(find.text('TIMES'), findsOne);
      expect(find.text('VENUE'), findsOne);
      expect(find.text('COVER'), findsOne);
      expect(find.text('ACCESS'), findsOne);
      expect(find.text('AUDIENCE'), findsOne);
      expect(find.text('LINEUP · 1'), findsOne);
      expect(find.text('POSTER'), findsOne);
      expect(find.text('Still needs a name + a date + a venue'), findsOne);

      // Typing in the standard name card updates the decorative poster.
      await tester.enterText(find.byType(TextField).first, 'Riptide Release');
      await tester.pump();
      expect(app.gfName, 'Riptide Release');
      expect(find.text('YOUR GIG NAME ✓'), findsOne);
      expect(find.text('Still needs a date + a venue'), findsOne);

      // When sheet — pick a day from the rolling calendar.
      await tester.tap(find.text('Choose a date'));
      await tester.pumpAndSettle();
      expect(find.text('WHEN IS IT'), findsOne);
      expect(find.text('DOORS 8PM'), findsOne);
      // Tomorrow, not "the 1st" — on the last day of a month tomorrow falls in
      // the next one, and the calendar shows four months at once, so a bare day
      // number matches a past cell first and taps nothing.
      final now = DateTime.now();
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      final tomorrowCell = find.byKey(
        ValueKey('day-${tomorrow.year}-${tomorrow.month}-${tomorrow.day}'),
      );
      await tester.scrollUntilVisible(
        tomorrowCell,
        80,
        scrollable: find.byType(Scrollable).last,
      );
      final calendar = find.byType(Scrollable).last;
      final cellCenter = tester.getCenter(tomorrowCell);
      if (cellCenter.dy > 580) {
        await tester.drag(calendar, Offset(0, 520 - cellCenter.dy));
        await tester.pumpAndSettle();
      }
      await tester.tap(tomorrowCell);
      await tester.pump();
      expect(app.gfDate, tomorrow);
      await tester.tap(find.text('DOORS 7PM'));
      await tester.pump();
      expect(app.gfDoorsLabel, '7PM');
      await tester.tap(find.text('DONE'));
      await tester.pumpAndSettle();

      // Venue sheet.
      await tester.tap(find.text('Choose a venue'));
      await tester.pumpAndSettle();
      expect(find.text('WHERE IS IT'), findsOne);
      await tester.tap(find.text('THE FOGHORN CLUB'));
      await tester.pumpAndSettle();
      expect(app.gfVenueId, 'v1');
      expect(
        find.text('Ready. Fans nearby see it as soon as you publish.'),
        findsOne,
      );

      // Price sheet — a preset closes it, the custom field stays open.
      final priceSlot = find.text('COVER');
      await _scrollTo(tester, priceSlot);
      await tester.tap(priceSlot);
      await tester.pumpAndSettle();
      expect(find.text('COVER'), findsWidgets);
      await tester.enterText(
        find.widgetWithText(TextField, 'Other amount'),
        '7',
      );
      await tester.pump();
      expect(app.gfPrice, '\$7');
      await tester.tap(find.text('\$10'));
      await tester.pumpAndSettle();
      expect(app.gfPrice, '\$10');

      // Tickets sheet — cap chips, then swap to an external link.
      final ticketSlot = find.text('ACCESS');
      await _scrollTo(tester, ticketSlot);
      await tester.tap(ticketSlot);
      await tester.pumpAndSettle();
      await tester.tap(find.text('100'));
      await tester.pump();
      expect(app.gfCap, '100');
      await tester.tap(find.text('External ticket link'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'https://…'),
        'https://dice.fm/riptide',
      );
      await tester.pump();
      expect(app.gfExt, 'https://dice.fm/riptide');
      await tester.tap(find.text('DONE'));
      await tester.pumpAndSettle();

      // Poster presets are a normal field later in the form.
      final riso = find.byKey(const ValueKey('press-riso'));
      await _scrollTo(tester, riso);
      await tester.tap(riso);
      await tester.pump();
      expect(app.gfFly, 'riso');

      // Publish, then the live-flyer confirmation.
      await tester.tap(find.text('PUBLISH GIG'));
      await tester.pumpAndSettle();
      expect(app.gfPublished, isTrue);
      expect(find.text('PUBLISHED'), findsOne);
      expect(find.text("IT'S LIVE."), findsOne);
      expect(find.text('earplug.app/g/riptide-release'), findsOne);
      expect(app.allGigs.last.title, 'Riptide Release');
      expect(app.allGigs.last.flyKey, 'riso');

      await tester.tap(find.text('MAKE ANOTHER'));
      await tester.pumpAndSettle();
      expect(find.text('YOUR GIG NAME · REQUIRED'), findsOne);
      expect(app.gfPrice, 'FREE');
    },
  );

  testWidgets('the six editing slots use the two-column checklist grammar', (
    tester,
  ) async {
    await _pumpGigCreate(tester);

    final date = tester.getTopLeft(find.byKey(const ValueKey('gig-slot-date')));
    final times = tester.getTopLeft(
      find.byKey(const ValueKey('gig-slot-times')),
    );
    final venue = tester.getTopLeft(
      find.byKey(const ValueKey('gig-slot-venue')),
    );
    final cover = tester.getTopLeft(
      find.byKey(const ValueKey('gig-slot-cover')),
    );
    final access = tester.getTopLeft(
      find.byKey(const ValueKey('gig-slot-access')),
    );
    final audience = tester.getTopLeft(
      find.byKey(const ValueKey('gig-slot-audience')),
    );

    expect(date.dy, times.dy);
    expect(venue.dy, cover.dy);
    expect(access.dy, audience.dy);
    expect(times.dx, greaterThan(date.dx));
    expect(venue.dx, date.dx);
    expect(cover.dx, times.dx);
    expect(access.dx, date.dx);
    expect(audience.dx, times.dx);
    expect(find.byType(StickyActionBar), findsOne);
  });

  testWidgets('the editing slots collapse to one column for enlarged text', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpGigCreate(tester);

    final leftEdges = [
      for (final key in const [
        'gig-slot-date',
        'gig-slot-times',
        'gig-slot-venue',
        'gig-slot-cover',
        'gig-slot-access',
        'gig-slot-audience',
      ])
        tester.getTopLeft(find.byKey(ValueKey(key))).dx,
    ];
    expect(leftEdges.toSet(), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'uploaded art swaps the press for a drop slot and an overlay toggle',
    (tester) async {
      final app = (await _pumpGigCreate(tester)).app;
      expect(find.text('Text overlay'), findsNothing);

      final custom = find.byKey(const ValueKey('press-custom'));
      await _scrollTo(tester, custom);
      await tester.tap(custom);
      await tester.pump();
      expect(app.gfCustomFlyer, isTrue);
      expect(find.text('CUSTOM FLYER PREVIEW'), findsOne);
      expect(find.text('ADD FLYER ART'), findsOne);
      expect(find.text('Text overlay'), findsOne);
      expect(
        find.text('Your flyer art previews with listing details on top.'),
        findsOne,
      );

      // Overlay off hides the printed details but keeps the slot cards.
      await tester.tap(find.text('Text overlay'));
      await tester.pump();
      expect(app.gfShowOverlay, isFalse);
      expect(app.gfDate, isNull);
      await app.saveGigDraft();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('picking custom flyer art shows its memory preview', (
    tester,
  ) async {
    final harness = await _pumpGigCreate(tester);
    harness.picker.nextPhoto = photoFixture(filename: 'flyer.png');

    final custom = find.byKey(const ValueKey('press-custom'));
    await _scrollTo(tester, custom);
    await tester.tap(custom);
    await tester.pump();
    await tester.tap(find.text('ADD FLYER ART'));
    await tester.pumpAndSettle();

    expect(harness.app.gfFlyerArt, isNotNull);
    expect(harness.app.gfFlyerStorageId, isNotNull);
    expect(find.byType(Image), findsOne);
    expect(find.text('CUSTOM FLYER PREVIEW'), findsNothing);
    await harness.app.saveGigDraft();
    await tester.pumpAndSettle();
  });

  testWidgets('custom flyer upload gates publish and threads its storage id', (
    tester,
  ) async {
    final repository = _GatedFlyerRepository(auth: FakeAuthService());
    final harness = await _pumpGigCreate(tester, repository: repository);
    final app = harness.app;
    harness.picker.nextPhoto = photoFixture(filename: 'flyer.png');
    app.setGfName('Gated Flyer Show');
    app.setGfDate(DateTime.now().add(const Duration(days: 2)));
    app.setGfVenue('v1');

    final custom = find.byKey(const ValueKey('press-custom'));
    await _scrollTo(tester, custom);
    await tester.tap(custom);
    await tester.pump();
    await tester.tap(find.text('ADD FLYER ART'));
    await tester.pump();

    expect(app.gfFlyerUploading, isTrue);
    expect(app.gigMissing, contains('your flyer art'));
    final disabledPublish = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'PUBLISH GIG'),
    );
    expect(disabledPublish.onPressed, isNull);
    expect(repository.publishCalls, 0);
    expect(app.gfPublished, isFalse);

    repository.uploadGate.complete();
    await tester.pumpAndSettle();
    expect(app.gfFlyerUploading, isFalse);
    expect(app.gfFlyerStorageId, isNotNull);
    expect(app.gigMissing, isNot(contains('your flyer art')));

    await tester.tap(find.text('PUBLISH GIG'));
    await tester.pumpAndSettle();
    expect(repository.publishCalls, 1);
    expect(repository.publishedFlyStorageId, app.gfFlyerStorageId);
    expect(repository.publishedFlyStorageId, isNotNull);
    expect(app.gfPublished, isTrue);

    // Flush app.say's 2.2s toast-clear timers so teardown sees none pending.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('new gigs default to all ages and offer every age choice', (
    tester,
  ) async {
    final app = (await _pumpGigCreate(tester)).app;
    expect(app.gfAgeRequirement, AgeRequirement.allAges);

    final ageSlot = find.text('AUDIENCE');
    await _scrollTo(tester, ageSlot);
    await tester.tap(ageSlot);
    await tester.pumpAndSettle();

    expect(find.text('All ages'), findsWidgets);
    expect(find.text('18+'), findsOne);
    expect(find.text('21+'), findsOne);
    await tester.tap(find.text('21+'));
    await tester.pumpAndSettle();
    expect(app.gfAgeRequirement, AgeRequirement.twentyOnePlus);
    expect(find.text('21+'), findsOne);
    await app.saveGigDraft();
    await tester.pumpAndSettle();
  });

  test('18+ to all ages survives save, reopen, and publish', () async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final app = AppState(repository: repository, auth: auth);
    addTearDown(app.dispose);
    await Future<void>.delayed(Duration.zero);
    app.startGigCreate();
    app.setGfName('Age Transition');
    app.setGfDate(DateTime.now().add(const Duration(days: 2)));
    app.setGfVenue('v1');
    app.setGfAgeRequirement(AgeRequirement.eighteenPlus);
    await app.saveGigDraft();
    app.setGfAgeRequirement(AgeRequirement.allAges);
    await app.saveGigDraft();
    final projectId = app.gfProject!.id;

    await app.editGigProject(projectId);
    expect(app.gfAgeRequirement, AgeRequirement.allAges);
    await app.publishGig();
    expect(app.allGigs.last.ageRequirement, AgeRequirement.allAges);
  });

  test('external tickets require an absolute HTTPS URL', () async {
    final auth = FakeAuthService();
    final app = AppState(
      repository: DemoRepository(auth: auth),
      auth: auth,
    );
    addTearDown(app.dispose);
    await Future<void>.delayed(Duration.zero);
    app.startGigCreate();
    app.setGfName('External Tickets');
    app.setGfDate(DateTime.now().add(const Duration(days: 2)));
    app.setGfVenue('v1');
    app.setGfTix(Ticketing.external);

    for (final invalid in [
      '',
      'dice.fm/show',
      'http://dice.fm/show',
      'https:///show',
    ]) {
      app.setGfExt(invalid);
      expect(app.validExternalTicketUrl, isFalse);
      expect(app.canPublishGig, isFalse);
    }
    app.setGfExt('https://dice.fm/show');
    expect(app.validExternalTicketUrl, isTrue);
    expect(app.canPublishGig, isTrue);
  });

  testWidgets('access slot reflects the external ticket URL requirement', (
    tester,
  ) async {
    final app = (await _pumpGigCreate(tester)).app;
    final accessSlot = find.byKey(const ValueKey('gig-slot-access'));
    Finder doneIndicator() =>
        find.descendant(of: accessSlot, matching: find.byIcon(Icons.check));

    app.setGfTix(Ticketing.external);
    await tester.pump();
    expect(doneIndicator(), findsNothing);

    app.setGfExt('https://dice.fm/show');
    await tester.pump();
    expect(doneIndicator(), findsOne);
  });

  test(
    'new venues are created, deduplicated, refreshed, and selected',
    () async {
      final auth = FakeAuthService();
      final app = AppState(
        repository: DemoRepository(auth: auth),
        auth: auth,
      );
      addTearDown(app.dispose);
      await Future<void>.delayed(Duration.zero);
      app.startGigCreate();
      final first = await app.createVenue(
        name: 'New Test Room',
        area: 'Oakland',
        address: '123 Test Street',
        point: const LatLng(37.8, -122.27),
      );
      expect(first.created, isTrue);
      expect(app.gfVenueId, first.venue.id);
      expect(app.venues.map((venue) => venue.id), contains(first.venue.id));

      final duplicate = await app.createVenue(
        name: ' new   test room ',
        area: ' OAKLAND ',
        address: '123   TEST STREET',
        point: const LatLng(37.81, -122.28),
      );
      expect(duplicate.created, isFalse);
      expect(duplicate.venue.id, first.venue.id);
      expect(app.gfVenueId, first.venue.id);
    },
  );

  test(
    'preview labels distinguish private, live, and unpublished changes',
    () async {
      final auth = FakeAuthService();
      final app = AppState(
        repository: DemoRepository(auth: auth),
        auth: auth,
      );
      addTearDown(app.dispose);
      await Future<void>.delayed(Duration.zero);
      app.startGigCreate();
      expect(app.gigPreviewLabel, 'PRIVATE DRAFT');
      app.setGfName('Preview Labels');
      app.setGfDate(DateTime.now().add(const Duration(days: 2)));
      app.setGfVenue('v1');
      await app.publishGig();
      expect(app.gigPreviewLabel, 'LIVE');
      app.editPublishedGig();
      app.setGfDescription('Changed after publication');
      expect(app.gigPreviewLabel, 'UNPUBLISHED CHANGES');
    },
  );

  testWidgets('draft preview uses the redesigned gig presentation and data', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 1400);
    tester.view.devicePixelRatio = 1;
    final harness = await _pumpGigCreate(tester);
    final app = harness.app;
    final date = DateTime.now().add(const Duration(days: 3));
    app.setGfName('Current Draft Noise');
    app.setGfDate(date);
    app.setGfVenue('v1');
    app.setGfPrice(r'$12');
    app.setGfDescription('Everything entered in the editor stays visible.');
    app.previewGigDraft();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('redesigned-gig-draft-preview')),
      findsOne,
    );
    expect(find.byKey(const ValueKey('gig-detail-hero-content')), findsOne);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('gig-draft-preview-status')))
          .height,
      32,
    );
    expect(find.text('CURRENT DRAFT NOISE'), findsOne);
    expect(find.text('PRIVATE DRAFT'), findsWidgets);
    expect(find.textContaining('THE FOGHORN CLUB'), findsWidgets);
    expect(find.text('LINEUP · 1'), findsOne);
    expect(find.text('ABOUT'), findsOne);
    expect(
      find.text('Everything entered in the editor stays visible.'),
      findsOne,
    );
    expect(find.text(r'RSVP — $12 AT DOOR'), findsOne);
    expect(find.text("WHO'S GOING"), findsNothing);
    expect(
      find.byKey(const ValueKey('gig-detail-save-draft-preview')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('gig-detail-share-draft-preview')),
      findsNothing,
    );

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(app.gfPreviewing, isFalse);
    expect(find.text('GIG DRAFT'), findsOne);
    expect(app.gfName, 'Current Draft Noise');
    expect(app.gfDesc, 'Everything entered in the editor stays visible.');
  });

  testWidgets('lineup role pills stay compact inside accessible menu targets', (
    tester,
  ) async {
    final harness = await _pumpGigCreate(tester);
    final performer = harness.app.gfPerformers.single;
    final target = find.byKey(
      ValueKey('gig-performer-role-target-${performer.id}'),
    );
    final pill = find.byKey(
      ValueKey('gig-performer-role-pill-${performer.id}'),
    );

    await _scrollTo(tester, target);
    expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(pill).height, lessThan(32));

    await harness.app.setGigPerformerRole(
      performer.id,
      GigPerformerRole.support,
    );
    await tester.pumpAndSettle();
    expect(find.text('SUPPORT'), findsOne);
    final updatedPerformer = harness.app.gfPerformers.single;
    expect(
      tester
          .getSize(
            find.byKey(
              ValueKey('gig-performer-role-pill-${updatedPerformer.id}'),
            ),
          )
          .height,
      lessThan(32),
    );
  });

  testWidgets('lineup mutations save pending form edits before applying', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await _pumpGigCreate(tester, repository: repository);
    final app = harness.app;
    final performer = app.gfPerformers.single;

    app.setGfName('Keep This Name');
    await app.setGigPerformerRole(performer.id, GigPerformerRole.headliner);
    await tester.pumpAndSettle();

    expect(app.gfName, 'Keep This Name');
    expect(
      (await repository.getGigProject(app.gfProject!.id)).title,
      'Keep This Name',
    );
  });

  testWidgets('reopened custom drafts retain and can remove persisted art', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await _pumpGigCreate(tester, repository: repository);
    final app = harness.app;
    app.setGfFly('custom');
    app.setGfFlyerStorageId('stored-flyer');
    await app.saveGigDraft();
    await app.editGigProject(app.gfProject!.id);
    await tester.pumpAndSettle();

    expect(app.gfFlyerUrl, 'demo://flyer/stored-flyer');
    await tester.drag(find.byType(ListView), const Offset(0, -650));
    await tester.pumpAndSettle();
    final clearArt = find.byKey(const ValueKey('clear-flyer-art'));
    expect(clearArt, findsOne);
    await tester.ensureVisible(clearArt);
    await tester.pumpAndSettle();
    await tester.tap(clearArt);
    await tester.pump();
    expect(app.gfFlyerUrl, isNull);
    expect(app.gfFlyerStorageId, isNull);
    await app.saveGigDraft();
    await tester.pumpAndSettle();
  });

  test('stale draft creation cannot replace a newer editor', () async {
    final auth = FakeAuthService();
    final repository = _GatedDraftRepository(auth: auth);
    final app = AppState(repository: repository, auth: auth);
    addTearDown(app.dispose);
    await Future<void>.delayed(Duration.zero);

    app.startGigCreate();
    app.setGfName('First editor');
    final firstSave = app.saveGigDraft();
    await Future<void>.delayed(Duration.zero);
    app.startGigCreate();
    app.setGfName('Second editor');
    final secondSave = app.saveGigDraft();
    await Future<void>.delayed(Duration.zero);
    expect(repository.createCalls, 2);

    repository.gates[1].complete();
    await secondSave;
    final currentProjectId = app.gfProject?.id;
    expect(currentProjectId, repository.createdByCall[1]?.id);

    repository.gates[0].complete();
    await firstSave;
    expect(app.gfProject?.id, currentProjectId);
  });

  test('stale draft saves cannot update or clear a newer editor', () async {
    final auth = FakeAuthService();
    final repository = _GatedSaveRepository(auth: auth);
    final app = AppState(repository: repository, auth: auth);
    addTearDown(app.dispose);
    await Future<void>.delayed(Duration.zero);

    app.startGigCreate();
    await Future<void>.delayed(Duration.zero);
    app.setGfName('Old editor');
    final oldSave = app.saveGigDraft();
    await Future<void>.delayed(Duration.zero);
    expect(repository.saveCalls, 1);
    final oldProjectId = app.gfProject?.id;

    app.startGigCreate();
    await Future<void>.delayed(Duration.zero);
    expect(app.gfProject, isNull);
    repository.saveGate.complete();
    await oldSave;

    expect(app.gfProject, isNull);
    expect(app.gfName, isEmpty);
    app.setGfName('New editor');
    await app.saveGigDraft();
    expect(app.gfProject?.id, isNot(oldProjectId));
    expect(repository.saveCalls, 2);
  });

  test('opening and closing a pristine editor creates no draft', () async {
    final auth = FakeAuthService();
    final repository = _CountingDraftRepository(auth: auth);
    final app = AppState(repository: repository, auth: auth);
    addTearDown(app.dispose);
    await Future<void>.delayed(Duration.zero);

    app.startGigCreate();
    expect(repository.createCalls, 0);
    app.closeGigCreate();
    await Future<void>.delayed(Duration.zero);

    expect(repository.createCalls, 0);
    expect(await repository.manageGigs('b1'), isEmpty);
  });

  test('managed gig refreshes stay bound to the requested band', () async {
    final auth = FakeAuthService();
    final repository = _GatedManageRepository(auth: auth);
    final app = AppState(repository: repository, auth: auth);
    addTearDown(app.dispose);
    await Future<void>.delayed(Duration.zero);
    final created = await repository.createBand(
      name: 'Second Band',
      genres: const ['punk'],
      bio: '',
      area: 'Oakland',
    );
    await Future<void>.delayed(Duration.zero);

    final refresh = app.refreshManagedGigs();
    await Future<void>.delayed(Duration.zero);
    app.bandId = created.band.id;
    unawaited(app.refreshManagedGigs());
    repository.firstGate.complete();
    await refresh;

    expect(repository.requestedBandIds, ['b1', created.band.id]);
    expect(app.managedGigsBandId, created.band.id);
  });
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<AppHarness> _pumpGigCreate(
  WidgetTester tester, {
  EarplugRepository? repository,
}) => pumpApp(
  tester,
  repository: repository,
  // Let the demo streams land before the form opens, the way they have by the
  // time a real user reaches this screen.
  beforePump: (app) async {
    await tester.pumpAndSettle();
    app.startGigCreate();
  },
  home: const Scaffold(body: GigCreateScreen()),
);

class _GatedFlyerRepository extends DemoRepository {
  _GatedFlyerRepository({required super.auth});

  final uploadGate = Completer<void>();
  int publishCalls = 0;
  String? publishedFlyStorageId;

  @override
  Future<String> generateMediaUploadUrl(String bandId) async {
    await uploadGate.future;
    return super.generateMediaUploadUrl(bandId);
  }

  @override
  Future<String> publishGig({
    required String bandId,
    required String title,
    required int startsAt,
    required String doorsTime,
    required String venueId,
    required int price,
    required String flyKey,
    String? flyStorageId,
    required Ticketing ticketing,
    required AgeRequirement ageRequirement,
    String? externalUrl,
    required String cap,
  }) async {
    publishCalls++;
    publishedFlyStorageId = flyStorageId;
    return super.publishGig(
      bandId: bandId,
      title: title,
      startsAt: startsAt,
      doorsTime: doorsTime,
      venueId: venueId,
      price: price,
      flyKey: flyKey,
      flyStorageId: flyStorageId,
      ticketing: ticketing,
      ageRequirement: ageRequirement,
      externalUrl: externalUrl,
      cap: cap,
    );
  }

  @override
  Future<String> publishGigDraft(String projectId) async {
    publishCalls++;
    publishedFlyStorageId = (await getGigProject(projectId)).flyStorageId;
    return super.publishGigDraft(projectId);
  }
}

class _GatedDraftRepository extends DemoRepository {
  _GatedDraftRepository({required super.auth});

  final gates = [Completer<void>(), Completer<void>()];
  final List<GigProject?> createdByCall = [null, null];
  int createCalls = 0;

  @override
  Future<GigProject> createGigDraft(String bandId) async {
    final call = createCalls++;
    await gates[call].future;
    final project = await super.createGigDraft(bandId);
    createdByCall[call] = project;
    return project;
  }
}

class _CountingDraftRepository extends DemoRepository {
  _CountingDraftRepository({required super.auth});

  int createCalls = 0;

  @override
  Future<GigProject> createGigDraft(String bandId) {
    createCalls++;
    return super.createGigDraft(bandId);
  }
}

class _GatedSaveRepository extends DemoRepository {
  _GatedSaveRepository({required super.auth});

  final saveGate = Completer<void>();
  int saveCalls = 0;

  @override
  Future<int> saveGigDraft({
    required String projectId,
    required int revision,
    required String? title,
    required DateTime? doorsAt,
    required DateTime? startsAt,
    required String? venueId,
    required int price,
    required String flyKey,
    required String? flyStorageId,
    required bool overlay,
    required String desc,
    required Ticketing ticketing,
    required AgeRequirement ageRequirement,
    required String? externalUrl,
    required String cap,
  }) async {
    saveCalls++;
    if (saveCalls == 1) await saveGate.future;
    return super.saveGigDraft(
      projectId: projectId,
      revision: revision,
      title: title,
      doorsAt: doorsAt,
      startsAt: startsAt,
      venueId: venueId,
      price: price,
      flyKey: flyKey,
      flyStorageId: flyStorageId,
      overlay: overlay,
      desc: desc,
      ticketing: ticketing,
      ageRequirement: ageRequirement,
      externalUrl: externalUrl,
      cap: cap,
    );
  }
}

class _GatedManageRepository extends DemoRepository {
  _GatedManageRepository({required super.auth});

  final firstGate = Completer<void>();
  final List<String> requestedBandIds = [];

  @override
  Future<List<GigProject>> manageGigs(String bandId) async {
    requestedBandIds.add(bandId);
    if (requestedBandIds.length == 1) await firstGate.future;
    return super.manageGigs(bandId);
  }
}

import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/gig_create.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:earplug/widgets/sheets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'support/fixtures.dart';
import 'support/harness.dart';
import 'support/stub_repository.dart';

void main() {
  testWidgets('floating controls overlay the list at the header inset', (
    tester,
  ) async {
    final app = (await _pumpGigCreate(tester)).app;
    final close = find.byKey(const Key('gig-close'));
    final save = find.byKey(const Key('gig-save'));
    final top = headerTopPad(tester.element(close));
    final list = find.byType(ListView);
    final padding = tester.widget<ListView>(list).padding as EdgeInsets;
    expect(padding, EdgeInsets.fromLTRB(20, top + 60, 20, tabBarClearance));
    for (final control in [close, save]) {
      expect(tester.getTopLeft(control).dy, top);
      expect(tester.getSize(control).height, greaterThanOrEqualTo(44));
      expect(find.ancestor(of: control, matching: list), findsNothing);
      final positioned = find.ancestor(
        of: control,
        matching: find.byType(Positioned),
      );
      expect(positioned, findsOne);
      expect(tester.widget<Positioned>(positioned).top, top);
    }
    expect(tester.getTopLeft(close).dx, EpLayout.gutter);
    expect(tester.getTopRight(save).dx, 390 - EpLayout.gutter);
    expect(tester.widget<EpPill>(save).variant, EpPillVariant.primary);
    expect(tester.widget<EpPill>(save).size, EpPillSize.chip);
    final saveState = find.byKey(const Key('gig-save-state'));
    expect(tester.widget<EpMonoText>(saveState).text, app.gfSaveState);
    expect(
      tester.widget<EpMonoText>(saveState).color,
      tester.element(saveState).epColors.contentSecondary,
    );
    expect(find.byType(ScreenHeader), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(EpBottomCta), findsNothing);
    for (final key in [
      'gig-required-progress',
      'gig-save-draft',
      'gig-slot-date',
      'gig-slot-times',
      'gig-poster-thumb',
      'gig-publish-hint',
    ]) {
      expect(find.byKey(ValueKey(key), skipOffstage: false), findsNothing);
    }
    expect(find.text('NEW GIG'), findsNothing);
    expect(find.text('REQUIRED'), findsNothing);
    await _toggleDetails(tester);
    await _scrollTo(tester, find.byKey(const Key('gig-slot-notes')));
    expect(tester.getTopLeft(close).dy, top);
    expect(tester.getTopLeft(save).dy, top);
  });

  testWidgets('Save waits for persistence before opening the fan preview', (
    tester,
  ) async {
    final repository = _GatedSaveRepository(auth: FakeAuthService());
    final gate = repository.saveGate;
    final app = (await _pumpGigCreate(tester, repository: repository)).app;
    await tester.enterText(find.byKey(const Key('gig-name-field')), 'Save Me');
    await tester.tap(find.byKey(const Key('gig-save')));
    await tester.pump();
    expect(repository.saveCalls, 1);
    expect(app.gfPreviewing, isFalse);
    expect(find.byKey(const Key('redesigned-gig-draft-preview')), findsNothing);
    expect(
      tester.widget<EpMonoText>(find.byKey(const Key('gig-save-state'))).text,
      app.gfSaveState,
    );

    gate.complete();
    await tester.pumpAndSettle();
    expect(app.gfProject?.title, 'Save Me');
    expect(app.gfPreviewing, isTrue);
    expect(find.byKey(const Key('redesigned-gig-draft-preview')), findsOne);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gig-save')), findsOne);
    expect(app.gfName, 'Save Me');
  });

  testWidgets('Close saves edited drafts using the existing close flow', (
    tester,
  ) async {
    final repository = _CountingDraftRepository(auth: FakeAuthService());
    final app = (await _pumpGigCreate(tester, repository: repository)).app;
    await tester.enterText(find.byKey(const Key('gig-name-field')), 'Keep Me');
    await tester.tap(find.byKey(const Key('gig-close')));
    await tester.pumpAndSettle();
    expect(repository.createCalls, 1);
    expect(
      (await repository.getGigProject(app.gfProject!.id)).title,
      'Keep Me',
    );
  });

  testWidgets('square flyer fills the content width with the name beneath it', (
    tester,
  ) async {
    final app = (await _pumpGigCreate(tester)).app;
    final flyer = find.byKey(const Key('gig-flyer'));
    final name = find.byKey(const Key('gig-name-field'));
    expect(tester.getSize(flyer), const Size(350, 350));
    expect(tester.getTopLeft(flyer).dx, EpLayout.gutter);
    expect(tester.getTopLeft(name).dy, tester.getBottomLeft(flyer).dy + 16);
    final field = tester.widget<TextField>(name);
    expect(field.decoration?.hintText, 'Name your gig');
    expect(field.decoration?.label, isNull);
    expect(field.decoration?.labelText, isNull);
    expect(field.style?.fontSize, 32);
    expect(field.textCapitalization, TextCapitalization.words);
    expect(
      field.decoration?.hintStyle?.color,
      tester.element(name).epColors.contentSecondary,
    );
    expect(tester.getSize(name).height, greaterThanOrEqualTo(44));

    await tester.enterText(name, 'Riptide Release');
    await tester.pump();
    expect(app.gfName, 'Riptide Release');
    expect(
      find.descendant(of: flyer, matching: find.text('RIPTIDE RELEASE')),
      findsOne,
    );
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pump();
    expect(tester.getSize(flyer), const Size(350, 350));
    expect(tester.takeException(), isNull);
  });

  for (final target in ['gig-flyer', 'gig-flyer-edit']) {
    testWidgets(
      '$target opens the flyer sheet and presses update both posters',
      (tester) async {
        final app = (await _pumpGigCreate(tester)).app;
        await tester.tap(find.byKey(Key(target)));
        await tester.pumpAndSettle();
        expect(find.text('FLYER'), findsOne);
        final sheetPoster = find.descendant(
          of: find.byType(EpFormSheet),
          matching: find.byType(EpPoster),
        );
        expect(tester.getSize(sheetPoster), const Size(120, 158));
        await tester.tap(find.byKey(const Key('press-accent')));
        await tester.pump();
        expect(app.gfFly, 'accent');
        final pagePoster = find.descendant(
          of: find.byKey(const Key('gig-flyer')),
          matching: find.byType(EpPoster),
        );
        expect(tester.widget<EpPoster>(pagePoster).style, app.flyer('accent'));
        expect(tester.widget<EpPoster>(sheetPoster).style, app.flyer('accent'));
        await _closeFlyerSheet(tester);
        expect(tester.widget<EpPoster>(pagePoster).style, app.flyer('accent'));
      },
    );
  }

  testWidgets('When opens the calendar and wheels and shows the chosen times', (
    tester,
  ) async {
    final app = (await _pumpGigCreate(tester)).app;
    final slot = find.byKey(const Key('gig-slot-when'));
    await _scrollTo(tester, slot);
    final placeholder = find.text('Pick a date and time');
    expect(
      tester.widget<Text>(placeholder).style?.color,
      tester.element(placeholder).epColors.accent,
    );
    await tester.tap(slot);
    await tester.pumpAndSettle();
    expect(find.text('WHEN'), findsOne);
    final wheel = find.byKey(const Key('gig-doors-wheel'));
    expect(wheel, findsOne);
    expect(find.byKey(const Key('gig-start-wheel')), findsOne);
    final now = DateTime.now();
    final date = DateTime(now.year, now.month + 1, 15);
    final day = find.byKey(
      ValueKey('day-${date.year}-${date.month}-${date.day}'),
    );
    final calendar = find.descendant(
      of: find.descendant(
        of: find.byType(EpFormSheet),
        matching: find.byType(ListView),
      ),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(day, 100, scrollable: calendar);
    await tester.pumpAndSettle();
    await tester.tap(day);
    await tester.pumpAndSettle();
    final picker = tester.widget<CupertinoDatePicker>(wheel);
    final point =
        tester.getTopLeft(wheel) +
        Offset(
          tester.getSize(wheel).width * .15,
          tester.getSize(wheel).height / 2,
        );
    await tester.dragFrom(point, Offset(0, picker.itemExtent), touchSlopY: 0);
    await tester.pumpAndSettle();
    expect(app.gfDate, date);
    expect(app.gfDoorsLabel, '7PM');
    await tester.tap(find.text('DONE'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: slot, matching: find.text('DOORS 7PM · START 9PM')),
      findsOne,
    );
    expect(
      find.descendant(of: slot, matching: find.byType(EpDisplay)),
      findsOne,
    );
    expect(placeholder, findsNothing);
  });

  testWidgets('venue shows its placeholder then the chosen name and area', (
    tester,
  ) async {
    final app = (await _pumpGigCreate(tester)).app;
    final slot = find.byKey(const Key('gig-slot-venue'));
    await _scrollTo(tester, slot);
    final placeholder = find.text('Choose a venue');
    expect(
      tester.widget<Text>(placeholder).style?.color,
      tester.element(placeholder).epColors.accent,
    );
    await tester.tap(slot);
    await tester.pumpAndSettle();
    expect(find.text('WHERE IS IT'), findsOne);
    await _scrollTo(tester, find.text('THE FOGHORN CLUB'));
    await tester.tap(find.text('THE FOGHORN CLUB'));
    await tester.pumpAndSettle();
    expect(app.gfVenueId, 'v1');
    final venue = app.venue('v1');
    final value = find.descendant(of: slot, matching: find.text(venue.name));
    expect(
      tester.widget<Text>(value).style?.color,
      tester.element(value).epColors.contentPrimary,
    );
    expect(
      find.descendant(of: slot, matching: find.text(venue.area.toUpperCase())),
      findsOne,
    );
    expect(placeholder, findsNothing);
  });

  testWidgets(
    'details toggle reveals five ordered cards and hides them again',
    (tester) async {
      await _pumpGigCreate(tester);
      final body = find.byKey(const Key('gig-details-body'));
      expect(body, findsNothing);
      await _toggleDetails(tester);
      expect(body, findsOne);
      expect(
        find.descendant(of: body, matching: find.byType(EpCard)),
        findsNWidgets(5),
      );
      var previousTop = -double.infinity;
      for (final key in [
        'gig-slot-cover',
        'gig-slot-access',
        'gig-slot-audience',
        'gig-slot-lineup',
        'gig-slot-notes',
      ]) {
        final slot = find.byKey(Key(key));
        expect(find.descendant(of: body, matching: slot), findsOne);
        final top = tester.getTopLeft(slot).dy;
        expect(top, greaterThan(previousTop));
        previousTop = top;
      }
      expect(find.byIcon(Icons.expand_less), findsOne);
      await _toggleDetails(tester);
      expect(body, findsNothing);
      expect(find.byIcon(Icons.expand_more), findsOne);
    },
  );

  testWidgets('empty lineup and notes retain their editing flows', (
    tester,
  ) async {
    final app = (await _pumpGigCreate(tester)).app;
    await app.saveGigDraft();
    await tester.pumpAndSettle();
    await app.removeGigPerformer(app.gfPerformers.single.id);
    await tester.pumpAndSettle();
    await _toggleDetails(tester);
    expect(find.text('Add performers'), findsOne);
    final notes = find.byKey(const Key('gig-slot-notes'));
    await _scrollTo(tester, notes);
    await tester.tap(notes);
    await tester.pumpAndSettle();
    final field = find.widgetWithText(
      TextField,
      'Accessibility, set times, parking, or anything fans should know',
    );
    await tester.enterText(field, 'Step-free entry');
    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();
    expect(app.gfDesc, 'Step-free entry');
    expect(
      find.descendant(of: notes, matching: find.text('Step-free entry')),
      findsOne,
    );
  });

  testWidgets('published gigs open with details expanded', (tester) async {
    final app = (await _pumpGigCreate(tester)).app;
    app.setGfName('Published Details');
    app.setGfDate(DateTime.now().add(const Duration(days: 2)));
    app.setGfVenue('v1');
    await app.publishGig();
    await tester.pumpAndSettle();
    app.editPublishedGig();
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const Key('gig-details-toggle')));
    expect(find.byKey(const Key('gig-details-body')), findsOne);
    await _toggleDetails(tester);
    expect(find.byKey(const Key('gig-details-body')), findsNothing);
  });

  testWidgets('detail cards stay in one column for enlarged text', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpGigCreate(tester);
    await _toggleDetails(tester);
    await _scrollTo(
      tester,
      find.byKey(const Key('gig-slot-when')),
      delta: -240,
    );
    final leftEdges = <double>[];
    for (final key in [
      'gig-slot-when',
      'gig-slot-venue',
      'gig-slot-cover',
      'gig-slot-access',
      'gig-slot-audience',
      'gig-slot-lineup',
      'gig-slot-notes',
    ]) {
      final slot = find.byKey(Key(key));
      await _scrollTo(tester, slot);
      leftEdges.add(tester.getTopLeft(slot).dx);
    }
    expect(leftEdges.toSet(), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cover shows paid ticket pricing and a missing price prompt', (
    tester,
  ) async {
    final app = (await _pumpGigCreate(tester)).app;
    app.setGfTix(Ticketing.paid);
    await tester.pump();
    expect(find.text('YOUR GIG NAME'), findsOne);
    await _toggleDetails(tester);
    final coverSlot = find.byKey(const ValueKey('gig-slot-cover'));
    await _scrollTo(tester, coverSlot);
    expect(
      find.descendant(
        of: coverSlot,
        matching: find.text('Set the cover charge'),
      ),
      findsOne,
    );

    app.setGfTicketPriceMinor(1000);
    await tester.pump();
    expect(
      find.descendant(of: coverSlot, matching: find.text(r'Tickets · $10.00')),
      findsOne,
    );
    expect(find.text('Set the cover charge'), findsNothing);
  });

  testWidgets(
    'custom press exposes art and overlay controls in the flyer sheet',
    (tester) async {
      final app = (await _pumpGigCreate(tester)).app;
      expect(find.textContaining('TEXT OVERLAY'), findsNothing);

      await _openFlyerSheet(tester);
      final custom = find.byKey(const ValueKey('press-custom'));
      await tester.tap(custom);
      await tester.pump();
      expect(app.gfCustomFlyer, isTrue);
      expect(_artPlaceholder, findsNWidgets(2));
      expect(find.text('ADD FLYER ART'), findsOne);
      expect(find.text('TEXT OVERLAY · ON'), findsOne);
      expect(find.text('YOUR GIG NAME'), findsNWidgets(2));

      // Overlay off hides the printed details on both posters.
      await tester.tap(find.text('TEXT OVERLAY · ON'));
      await tester.pump();
      expect(find.text('TEXT OVERLAY · OFF'), findsOne);
      expect(find.text('YOUR GIG NAME'), findsNothing);
      expect(find.byKey(const Key('gig-slot-when')), findsOne);
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

    await _openFlyerSheet(tester);
    final custom = find.byKey(const ValueKey('press-custom'));
    await tester.tap(custom);
    await tester.pump();
    await tester.tap(find.text('ADD FLYER ART'));
    await tester.pumpAndSettle();

    expect(harness.app.gfFlyerArt, isNotNull);
    expect(harness.app.gfFlyerStorageId, isNotNull);
    expect(find.byType(Image), findsNWidgets(2));
    expect(_artPlaceholder, findsNothing);
    await harness.app.saveGigDraft();
    await tester.pumpAndSettle();
  });

  testWidgets('custom flyer upload gates publish and threads its storage id', (
    tester,
  ) async {
    final repository = _GatedFlyerRepository(auth: FakeAuthService());
    final uploadGate = repository.uploadGate;
    final harness = await _pumpGigCreate(tester, repository: repository);
    final app = harness.app;
    harness.picker.nextPhoto = photoFixture(filename: 'flyer.png');
    app.setGfName('Gated Flyer Show');
    app.setGfDate(DateTime.now().add(const Duration(days: 2)));
    app.setGfVenue('v1');

    await _openFlyerSheet(tester);
    final custom = find.byKey(const ValueKey('press-custom'));
    await tester.tap(custom);
    await tester.pump();
    await tester.tap(find.text('ADD FLYER ART'));
    await tester.pump();

    expect(app.gfFlyerUploading, isTrue);
    expect(app.gigMissing, contains('your flyer art'));
    final strip = find.descendant(
      of: find.byKey(const Key('gig-flyer')),
      matching: find.byType(LinearProgressIndicator),
    );
    expect(tester.widget<LinearProgressIndicator>(strip).minHeight, 2);
    await tester.tap(find.text('CLOSE'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('gig-save')));
    await tester.pumpAndSettle();
    final disabledPublish = tester.widget<EpPill>(
      find.byKey(const Key('gig-preview-publish')),
    );
    expect(disabledPublish.onPressed, isNull);
    expect(repository.publishCalls, 0);
    expect(app.gfPublished, isFalse);

    uploadGate.complete();
    await tester.pumpAndSettle();
    expect(app.gfFlyerUploading, isFalse);
    expect(app.gfFlyerStorageId, isNotNull);
    expect(app.gigMissing, isNot(contains('your flyer art')));

    final publish = find.byKey(const Key('gig-preview-publish'));
    await tester.ensureVisible(publish);
    await tester.pumpAndSettle();
    await tester.tap(publish);
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

    await _toggleDetails(tester);
    final ageSlot = find.byKey(const Key('gig-slot-audience'));
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
    final app = AppState.demo(repository: repository, auth: auth);
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
    final app = AppState.demo(
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
    await _toggleDetails(tester);
    final accessSlot = find.byKey(const ValueKey('gig-slot-access'));
    await _scrollTo(tester, accessSlot);
    await tester.tap(accessSlot);
    await tester.pumpAndSettle();
    await tester.tap(find.text('External ticket link'));
    await tester.pump();
    await tester.tap(find.text('DONE'));
    await tester.pumpAndSettle();
    final placeholder = find.text('Tickets and age access');
    expect(
      tester.widget<Text>(placeholder).style?.color,
      tester.element(placeholder).epColors.accent,
    );

    await tester.tap(accessSlot);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'https://…'),
      'https://dice.fm/show',
    );
    await tester.tap(find.text('DONE'));
    await tester.pumpAndSettle();
    expect(app.gfExt, 'https://dice.fm/show');
    expect(placeholder, findsNothing);
    expect(
      find.descendant(of: accessSlot, matching: find.text('External link')),
      findsOne,
    );
    expect(
      find.descendant(
        of: accessSlot,
        matching: find.text('HTTPS://DICE.FM/SHOW'),
      ),
      findsOne,
    );
  });

  testWidgets('paid tickets stay disabled until Stripe can sell tickets', (
    tester,
  ) async {
    final app = (await _pumpGigCreate(tester)).app;
    await app.refreshBandPayoutStatus();
    await tester.pumpAndSettle();
    expect(app.bandPayoutStatus?.hasAccount, isFalse);
    expect(app.canSellTickets, isFalse);

    await _toggleDetails(tester);
    final accessSlot = find.byKey(const ValueKey('gig-slot-access'));
    await _scrollTo(tester, accessSlot);
    await tester.tap(accessSlot);
    await tester.pumpAndSettle();

    final paidOption = find.byKey(const Key('gig-tickets-paid'));
    expect(paidOption, findsOne);
    expect(find.text('Enable ticket sales in PAYOUTS'), findsOne);
    final card = tester.widget<EpCard>(paidOption);
    expect(card.variant, EpCardVariant.disabled);
    expect(card.onTap, isNull);
    await tester.tap(paidOption);
    await tester.pump();
    expect(app.gfTix, Ticketing.rsvp);
    expect(find.byKey(const Key('gig-ticket-price')), findsNothing);
    expect(find.byKey(const Key('gig-ticket-capacity')), findsNothing);
  });

  testWidgets('enabled paid tickets explain direct Stripe payments', (
    tester,
  ) async {
    final app = (await _pumpGigCreate(tester)).app;
    await app.repository.enableBandTicketSales(app.bandId);
    await app.refreshBandPayoutStatus();
    await tester.pumpAndSettle();
    expect(app.canSellTickets, isTrue);

    await _toggleDetails(tester);
    final accessSlot = find.byKey(const ValueKey('gig-slot-access'));
    await _scrollTo(tester, accessSlot);
    await tester.tap(accessSlot);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Fans pay you directly through Stripe; EarPlug adds its fee at checkout.',
      ),
      findsOne,
    );
    expect(
      find.text('In-app checkout, EarPlug handles the charge'),
      findsNothing,
    );
  });

  testWidgets('paid draft autosave waits for valid pricing then saves', (
    tester,
  ) async {
    final repository = _GatedSaveRepository(auth: FakeAuthService());
    repository.saveGate.complete();
    final app = (await _pumpGigCreate(tester, repository: repository)).app;
    app.setGfTix(Ticketing.paid);
    expect(app.gfTix, Ticketing.paid);
    expect(app.gfTicketPriceMinor, isNull);
    expect(app.gfTicketCapacity, isNull);

    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(repository.saveCalls, 0);
    expect(app.gfSaveState, 'UNSAVED');

    app.setGfTicketPriceMinor(1000);
    app.setGfTicketCapacity(80);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(repository.saveCalls, 1);
    expect(app.gfSaveState, 'SAVED');
    expect(app.gfProject?.ticketPriceMinor, 1000);
    expect(app.gfProject?.ticketCapacity, 80);
  });

  testWidgets(
    'paid ticket fields autosave and the cover opens ticket pricing',
    (tester) async {
      final app = (await _pumpGigCreate(tester)).app;
      await app.repository.enableBandTicketSales(app.bandId);
      await app.refreshBandPayoutStatus();
      await tester.pumpAndSettle();
      expect(app.canSellTickets, isTrue);
      app.setGfPrice(r'$7');

      await _toggleDetails(tester);
      final accessSlot = find.byKey(const ValueKey('gig-slot-access'));
      await _scrollTo(tester, accessSlot);
      await tester.tap(accessSlot);
      await tester.pumpAndSettle();
      final paidOption = find.byKey(const Key('gig-tickets-paid'));
      expect(tester.widget<EpCard>(paidOption).onTap, isNotNull);
      await tester.tap(paidOption);
      await tester.pumpAndSettle();
      expect(app.gfTix, Ticketing.paid);
      expect(tester.widget<EpCard>(paidOption).variant, EpCardVariant.selected);

      final priceField = find.byKey(const Key('gig-ticket-price'));
      final capacityField = find.byKey(const Key('gig-ticket-capacity'));
      expect(priceField, findsOne);
      expect(capacityField, findsOne);
      expect(
        find.ancestor(of: priceField, matching: find.byType(EpCard)),
        findsNothing,
      );
      expect(
        find.ancestor(of: capacityField, matching: find.byType(EpCard)),
        findsNothing,
      );
      expect(
        find.text(
          r'Fans pay the EarPlug fee (5% + $1.00) on top · '
          'you receive the ticket price minus Stripe processing',
        ),
        findsOne,
      );

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(priceField, '12');
      await tester.enterText(capacityField, '80');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(app.gfTicketPriceMinor, 1200);
      expect(app.gfTicketCapacity, 80);
      expect(app.gfSaveState, 'SAVED');
      expect(app.gfProject?.ticketPriceMinor, 1200);
      expect(app.gfProject?.ticketCapacity, 80);
      final projectId = app.gfProject!.id;
      final saved = await app.repository.getGigProject(projectId);
      expect(saved.ticketing, Ticketing.paid);
      expect(saved.ticketPriceMinor, 1200);
      expect(saved.ticketCapacity, 80);

      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      await tester.tap(find.text('DONE'));
      await tester.pumpAndSettle();
      final coverSlot = find.byKey(const ValueKey('gig-slot-cover'));
      await _scrollTo(tester, coverSlot);
      expect(
        find.descendant(
          of: coverSlot,
          matching: find.text(r'Tickets · $12.00'),
        ),
        findsOne,
      );
      final priceValue = find.descendant(
        of: coverSlot,
        matching: find.text(r'Tickets · $12.00'),
      );
      expect(
        tester.widget<Text>(priceValue).style?.color,
        tester.element(priceValue).epColors.contentPrimary,
      );
      await tester.tap(coverSlot);
      await tester.pumpAndSettle();
      expect(find.text('TICKETS'), findsOne);
      expect(tester.widget<TextField>(priceField).controller!.text, '12');
      expect(tester.widget<TextField>(capacityField).controller!.text, '80');

      await tester.tap(find.text('In-app RSVP'));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(app.gfTix, Ticketing.rsvp);
      expect(priceField, findsNothing);
      expect(capacityField, findsNothing);
      expect(app.gfProject?.ticketPriceMinor, isNull);
      expect(app.gfProject?.ticketCapacity, isNull);
      final cleared = await app.repository.getGigProject(projectId);
      expect(cleared.ticketing, Ticketing.rsvp);
      expect(cleared.ticketPriceMinor, isNull);
      expect(cleared.ticketCapacity, isNull);
      await tester.tap(find.text('DONE'));
      await tester.pumpAndSettle();
      expect(app.gfPrice, r'$7');
      expect(
        find.descendant(of: coverSlot, matching: find.text(r'$7')),
        findsOne,
      );
    },
  );

  testWidgets('paid tickets require a valid price and capacity to publish', (
    tester,
  ) async {
    final app = (await _pumpGigCreate(tester)).app;
    await app.repository.enableBandTicketSales(app.bandId);
    await app.refreshBandPayoutStatus();
    await tester.pumpAndSettle();
    app.setGfName('Paid Release Show');
    app.setGfDate(DateTime.now().add(const Duration(days: 2)));
    app.setGfVenue('v1');
    app.setGfTix(Ticketing.paid);
    await tester.pump();
    expect(app.canPublishGig, isFalse);
    expect(app.gigMissing, ['ticket price and capacity']);
    expect(find.byKey(const Key('gig-publish-hint')), findsNothing);

    await _toggleDetails(tester);
    final coverSlot = find.byKey(const ValueKey('gig-slot-cover'));
    await _scrollTo(tester, coverSlot);
    expect(
      find.descendant(
        of: coverSlot,
        matching: find.text('Set the cover charge'),
      ),
      findsOne,
    );
    final placeholder = find.text('Set the cover charge');
    expect(
      tester.widget<Text>(placeholder).style?.color,
      tester.element(placeholder).epColors.accent,
    );
    await tester.tap(coverSlot);
    await tester.pumpAndSettle();
    final priceField = find.byKey(const Key('gig-ticket-price'));
    final capacityField = find.byKey(const Key('gig-ticket-capacity'));
    expect(find.text(r'Enter a ticket price of at least $1.00.'), findsOne);
    expect(find.text('Enter a whole number from 1 to 5000.'), findsOne);

    await tester.enterText(capacityField, '80');
    for (final invalid in ['', 'abc', '0.99', 'NaN', 'Infinity']) {
      await tester.enterText(priceField, invalid);
      await tester.pump();
      expect(app.gfTicketPriceMinor, isNull);
      expect(app.canPublishGig, isFalse);
      expect(find.text(r'Enter a ticket price of at least $1.00.'), findsOne);
    }
    await tester.enterText(priceField, '1');
    await tester.pump();
    expect(app.gfTicketPriceMinor, 100);
    expect(app.canPublishGig, isTrue);

    for (final invalid in ['', 'abc', '1.5', '0', '5001']) {
      await tester.enterText(capacityField, invalid);
      await tester.pump();
      expect(app.canPublishGig, isFalse);
      expect(app.gigMissing, ['ticket price and capacity']);
      expect(find.text('Enter a whole number from 1 to 5000.'), findsOne);
    }
    for (final valid in ['1', '5000']) {
      await tester.enterText(capacityField, valid);
      await tester.pump();
      expect(app.gfTicketCapacity, int.parse(valid));
      expect(app.canPublishGig, isTrue);
      expect(app.gigMissing, isEmpty);
    }
    await tester.enterText(priceField, '12.345');
    await tester.pump();
    expect(app.gfTicketPriceMinor, 1235);
    await tester.tap(find.text('DONE'));
    await tester.pumpAndSettle();
    await app.saveGigDraft();
    final projectId = app.gfProject!.id;
    await app.editGigProject(projectId);
    await tester.pumpAndSettle();
    expect(app.gfTix, Ticketing.paid);
    expect(app.gfTicketPriceMinor, 1235);
    expect(app.gfTicketCapacity, 5000);

    await _scrollTo(tester, coverSlot);
    await tester.tap(coverSlot);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(priceField).controller!.text, '12.35');
    expect(tester.widget<TextField>(capacityField).controller!.text, '5000');
    await tester.tap(find.text('DONE'));
    await tester.pumpAndSettle();
    await _publishFromPreview(tester);
    expect(app.gfPublished, isTrue);
    expect(app.gfProject?.ticketPriceMinor, 1235);
    expect(app.gfProject?.ticketCapacity, 5000);
    expect(app.allGigs.last.ticketPriceMinor, 1235);

    await tester.tap(find.text('MAKE ANOTHER'));
    await tester.pumpAndSettle();
    expect(app.gfTix, Ticketing.rsvp);
    expect(app.gfTicketPriceMinor, isNull);
    expect(app.gfTicketCapacity, isNull);
  });

  testWidgets('venue sheet updates when the directory finishes loading', (
    tester,
  ) async {
    final repository = StubRepository(auth: FakeAuthService())
      ..wraps<List<Venue>>(
        'venues',
        (real) => [
          ...real,
          const Venue(
            id: 'late-venue',
            name: 'Late Arrival Hall',
            area: 'Oakland',
            addr: '123 Late Street',
            point: LatLng(37.8, -122.27),
          ),
        ],
      );
    final venueGate = repository.gate('venues');
    addTearDown(() {
      if (!venueGate.isCompleted) venueGate.complete();
    });
    await _pumpGigCreate(tester, repository: repository);

    await _scrollTo(tester, find.byKey(const ValueKey('gig-slot-venue')));
    await tester.tap(find.text('Choose a venue'));
    await tester.pumpAndSettle();
    expect(find.text('LATE ARRIVAL HALL'), findsNothing);

    venueGate.complete();
    await tester.pumpAndSettle();
    expect(find.text('LATE ARRIVAL HALL'), findsOne);
  });

  test(
    'new venues are created, deduplicated, refreshed, and selected',
    () async {
      final auth = FakeAuthService();
      final app = AppState.demo(
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
      final app = AppState.demo(
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
    expect(find.byKey(const ValueKey('gig-add-to-calendar')), findsNothing);
    expect(find.byKey(const ValueKey('gig-venue-directions')), findsNothing);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(app.gfPreviewing, isFalse);
    expect(find.byKey(const Key('gig-flyer')), findsOne);
    expect(app.gfName, 'Current Draft Noise');
    expect(app.gfDesc, 'Everything entered in the editor stays visible.');
  });

  testWidgets('lineup role pills stay compact inside accessible menu targets', (
    tester,
  ) async {
    final harness = await _pumpGigCreate(tester);
    await _toggleDetails(tester);
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
    await _openFlyerSheet(tester);
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
    final app = AppState.demo(repository: repository, auth: auth);
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
    final saveGate = repository.saveGate;
    final app = AppState.demo(repository: repository, auth: auth);
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
    saveGate.complete();
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
    final app = AppState.demo(repository: repository, auth: auth);
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
    final app = AppState.demo(repository: repository, auth: auth);
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

/// Custom art placeholders appear in the page flyer and sheet preview.
final _artPlaceholder = find.byIcon(Icons.add_photo_alternate_outlined);

Future<void> _openFlyerSheet(WidgetTester tester) async {
  final flyer = find.byKey(const Key('gig-flyer'));
  await _scrollTo(tester, flyer, delta: -240);
  await tester.tap(flyer);
  await tester.pumpAndSettle();
}

Future<void> _closeFlyerSheet(WidgetTester tester) async {
  await tester.tap(find.text('CLOSE'));
  await tester.pumpAndSettle();
}

Future<void> _publishFromPreview(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('gig-save')));
  await tester.pumpAndSettle();
  final publish = find.byKey(const Key('gig-preview-publish'));
  await tester.ensureVisible(publish);
  await tester.pumpAndSettle();
  await tester.tap(publish);
  await tester.pumpAndSettle();
}

Future<void> _toggleDetails(WidgetTester tester) async {
  final toggle = find.byKey(const ValueKey('gig-details-toggle'));
  await _scrollTo(tester, toggle);
  await tester.tap(toggle);
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(
  WidgetTester tester,
  Finder finder, {
  double delta = 240,
}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find.byType(Scrollable).first,
  );
  // Keep targets below the floating controls when bringing them into view.
  await Scrollable.ensureVisible(tester.element(finder), alignment: .2);
  await tester.pumpAndSettle();
}

Future<AppHarness> _pumpGigCreate(
  WidgetTester tester, {
  EarplugRepository? repository,
}) => pumpApp(
  tester,
  repository: repository,
  size: const Size(390, 844),
  // Let the demo streams land before the form opens, the way they have by the
  // time a real user reaches this screen.
  beforePump: (app) async {
    await tester.pumpAndSettle();
    app.startGigCreate();
  },
  home: const Scaffold(body: GigCreateScreen()),
);

class _GatedFlyerRepository extends StubRepository {
  _GatedFlyerRepository({required super.auth});

  late final uploadGate = gate('generateMediaUploadUrl');
  int get publishCalls => callsTo('publishGigDraft');
  String? publishedFlyStorageId;

  @override
  Future<String> publishGigDraft(String projectId) async {
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

class _CountingDraftRepository extends StubRepository {
  _CountingDraftRepository({required super.auth});

  int get createCalls => callsTo('createGigDraft');
}

class _GatedSaveRepository extends StubRepository {
  _GatedSaveRepository({required super.auth});

  late final saveGate = gate('saveGigDraft');
  int get saveCalls => callsTo('saveGigDraft');
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

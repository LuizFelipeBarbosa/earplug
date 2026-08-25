import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/gig_create.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';
import 'support/harness.dart';

void main() {
  testWidgets(
    'the flyer, its presses and every sheet render and drive the form',
    (tester) async {
      final app = (await _pumpGigCreate(tester)).app;

      // The editor exposes a conventional, labeled form and a visible draft
      // action instead of hiding inputs in the poster artwork.
      expect(find.text('GIG DRAFT'), findsOne);
      expect(find.text('DRAFT'), findsOne);
      expect(find.text('SAVE DRAFT'), findsOne);
      expect(find.text('GIG NAME'), findsOne);
      expect(find.text('DATE'), findsOne);
      expect(find.text('DOORS AND START TIME'), findsOne);
      expect(find.text('VENUE'), findsOne);
      expect(find.text('Still needs a name + a date + a venue'), findsOne);

      // Typing in the standard name card updates the decorative poster.
      await tester.enterText(find.byType(TextField).first, 'Riptide Release');
      await tester.pump();
      expect(app.gfName, 'Riptide Release');
      expect(find.text('GIG NAME ✓'), findsOne);
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
      expect(find.text('GIG NAME'), findsOne);
      expect(app.gfPrice, 'FREE');
    },
  );

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
    app.startGigCreate();
    expect(repository.createCalls, 2);

    repository.gates[1].complete();
    await Future<void>.delayed(Duration.zero);
    final currentProjectId = app.gfProject?.id;
    expect(currentProjectId, repository.createdByCall[1]?.id);

    repository.gates[0].complete();
    await Future<void>.delayed(Duration.zero);
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

    app.startGigCreate();
    await Future<void>.delayed(Duration.zero);
    final newProjectId = app.gfProject?.id;
    repository.saveGate.complete();
    await oldSave;

    expect(app.gfProject?.id, newProjectId);
    expect(app.gfName, isEmpty);
    app.setGfName('New editor');
    await app.saveGigDraft();
    expect(app.gfProject?.id, newProjectId);
    expect(repository.saveCalls, 2);
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

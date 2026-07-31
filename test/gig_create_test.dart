import 'dart:async';

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

      // Header, live flyer and the four slot cards.
      expect(find.text('NEW GIG'), findsOne);
      expect(find.text('DRAFT'), findsOne);
      expect(find.text('TYPE YOUR GIG NAME'), findsOne);
      expect(find.text('+ DATE & DOORS'), findsOne);
      expect(find.text('WHEN · REQUIRED'), findsOne);
      expect(find.text('VENUE · REQUIRED'), findsOne);
      expect(find.text('Still needs a name + a date + a venue'), findsOne);

      // Typing on the poster fills the name card below it too.
      await tester.enterText(find.byType(TextField).first, 'Riptide Release');
      await tester.pump();
      expect(app.gfName, 'Riptide Release');
      expect(find.text('GIG NAME ✓'), findsOne);
      expect(find.text('Still needs a date + a venue'), findsOne);

      await tester.tap(find.byKey(const ValueKey('press-riso')));
      await tester.pump();
      expect(app.gfFly, 'riso');

      // When sheet — pick a day from the rolling calendar.
      await tester.tap(find.text('WHEN · REQUIRED'));
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
      await tester.tap(find.text('VENUE · REQUIRED'));
      await tester.pumpAndSettle();
      expect(find.text('WHERE IS IT'), findsOne);
      await tester.tap(find.text('THE FOGHORN CLUB'));
      await tester.pumpAndSettle();
      expect(app.gfVenueId, 'v1');
      expect(find.text('READY'), findsOne);
      expect(
        find.text('Ready — fans nearby see it the second you post.'),
        findsOne,
      );

      // Price sheet — a preset closes it, the custom field stays open.
      await tester.tap(find.text('PRICE'));
      await tester.pumpAndSettle();
      expect(find.text('COVER'), findsOne);
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
      await tester.tap(find.text('TICKETS'));
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
      expect(find.text('TYPE YOUR GIG NAME'), findsOne);
      expect(app.gfPrice, 'FREE');
    },
  );

  testWidgets(
    'uploaded art swaps the press for a drop slot and an overlay toggle',
    (tester) async {
      final app = (await _pumpGigCreate(tester)).app;
      expect(find.text('Text overlay'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('press-custom')));
      await tester.pump();
      expect(app.gfCustomFlyer, isTrue);
      expect(find.text('DROP YOUR FLYER'), findsOne);
      expect(find.text('Text overlay'), findsOne);
      expect(
        find.text('Drop your flyer art — the text stays editable on top.'),
        findsOne,
      );

      // Overlay off hides the printed details but keeps the slot cards.
      await tester.tap(find.text('Text overlay'));
      await tester.pump();
      expect(app.gfShowOverlay, isFalse);
      expect(find.text('+ DATE & DOORS'), findsNothing);
      expect(find.text('WHEN · REQUIRED'), findsOne);
    },
  );

  testWidgets('picking custom flyer art shows its memory preview', (
    tester,
  ) async {
    final harness = await _pumpGigCreate(tester);
    harness.picker.nextPhoto = photoFixture(filename: 'flyer.png');

    await tester.tap(find.byKey(const ValueKey('press-custom')));
    await tester.pump();
    await tester.tap(find.text('DROP YOUR FLYER'));
    await tester.pumpAndSettle();

    expect(harness.app.gfFlyerArt, isNotNull);
    expect(harness.app.gfFlyerStorageId, isNotNull);
    expect(find.byType(Image), findsOne);
    expect(find.text('DROP YOUR FLYER'), findsNothing);
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

    await tester.tap(find.byKey(const ValueKey('press-custom')));
    await tester.pump();
    await tester.tap(find.text('DROP YOUR FLYER'));
    await tester.pump();

    expect(app.gfFlyerUploading, isTrue);
    expect(app.gigMissing, contains('your flyer art'));
    await tester.tap(find.text('PUBLISH GIG'));
    await tester.pump();
    expect(repository.publishCalls, 0);
    expect(app.gfPublished, isFalse);
    expect(app.toast, 'Still uploading your flyer — one sec.');

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
      externalUrl: externalUrl,
      cap: cap,
    );
  }
}

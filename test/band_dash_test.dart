import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/band_dash.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  test('band entry labels follow membership count', () {
    expect(bandEntryLabel(0), 'Start a band');
    expect(bandEntryLabel(1), 'Manage band');
    expect(bandEntryLabel(2), 'Switch band');
  });

  testWidgets('dashboard derives remaining tasks from current band data', (
    tester,
  ) async {
    await pumpApp(tester, home: const Scaffold(body: BandDashScreen()));

    expect(find.text('MANAGING · ADMIN'), findsOne);
    expect(find.text('DISCOVER'), findsOne);
    expect(find.text('BAND CHECKLIST'), findsOne);
    expect(find.text('3 OF 5 DONE'), findsOne);
    expect(find.text('Add a profile image'), findsOne);
    expect(find.text('Add a band link'), findsOne);
    expect(find.text('Write a short bio'), findsNothing);
    expect(find.text('Post a music clip'), findsNothing);
    expect(find.text('Publish a gig'), findsNothing);
  });

  testWidgets('single-band switcher uses manage language', (tester) async {
    await pumpApp(tester, home: const Scaffold(body: BandDashScreen()));

    await tester.tap(find.text('FOGHORN DIET ▾'));
    await tester.pumpAndSettle();

    expect(find.text('MANAGE BAND'), findsOne);
    expect(find.text('Personal account'), findsOne);
    expect(find.text('Manage band · admin'), findsOne);
    expect(find.text('START ANOTHER BAND'), findsOne);
  });

  testWidgets('multi-band switcher changes the managed band', (tester) async {
    final auth = FakeAuthService();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: _MultiBandRepository(auth: auth),
      home: const Scaffold(body: BandDashScreen()),
    );

    await tester.tap(find.text('FOGHORN DIET ▾'));
    await tester.pumpAndSettle();

    expect(find.text('SWITCH BAND'), findsOne);
    expect(find.text('PIGEON COURT'), findsOne);
    await tester.tap(find.text('PIGEON COURT'));
    await tester.pumpAndSettle();

    expect(harness.app.bandId, 'b2');
    expect(harness.app.current.screen, Screen.bandDash);
  });

  testWidgets(
    'a past gig completes publishing when no upcoming feed row exists',
    (tester) async {
      final auth = FakeAuthService();
      await pumpApp(
        tester,
        auth: auth,
        repository: _PastGigOnlyRepository(auth: auth),
        home: const Scaffold(body: BandDashScreen()),
      );

      expect(find.text('Publish a gig'), findsNothing);
    },
  );
}

class _MultiBandRepository extends DemoRepository {
  _MultiBandRepository({required super.auth});

  @override
  Stream<List<BandMembership>> myBands() async* {
    yield [
      BandMembership(band: DemoData.bands['b1']!, role: 'admin'),
      BandMembership(band: DemoData.bands['b2']!, role: 'member'),
    ];
  }
}

class _PastGigOnlyRepository extends DemoRepository {
  _PastGigOnlyRepository({required super.auth});

  Band get _band => DemoData.bands['b1']!.copyWith(upcoming: const []);

  @override
  Stream<FeedSnapshot> feed() => Stream.value(
    FeedSnapshot(gigs: const [], venues: DemoData.venues, bands: {'b1': _band}),
  );

  @override
  Stream<List<BandMembership>> myBands() =>
      Stream.value([BandMembership(band: _band, role: 'admin')]);
}

import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/org_settings.dart';
import 'package:earplug/screens/org_venue_edit.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/form_bits.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/fixtures.dart';
import 'support/harness.dart';
import 'support/stub_repository.dart';

void main() {
  testWidgets('adding a photo after reopening settings keeps saved photos', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final picker = FakeMediaPicker()..nextPhoto = _photo;
    var settingsKey = UniqueKey();
    late StateSetter rebuildHost;
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) => app.switchToOrganization('org1'),
      home: StatefulBuilder(
        builder: (context, setState) {
          rebuildHost = setState;
          return Scaffold(
            body: OrgSettingsScreen(key: settingsKey, mediaPicker: picker),
          );
        },
      ),
    );
    await enterOrganizer(tester, harness, 'org1');
    final photosRow = find.byKey(const Key('org-hub-photos'));
    expect(
      find.descendant(of: photosRow, matching: find.text('0 OF 10')),
      findsOneWidget,
    );
    await tester.tap(photosRow);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('org-hub-sheet-photos')), findsOneWidget);
    final addPhoto = find.byKey(const Key('org-settings-add-photo'));
    await tester.tap(addPhoto);
    await tester.pumpAndSettle();
    final firstPhotos = (await repository.organization('org1'))!.photoUrls;
    expect(firstPhotos, hasLength(1));
    expect(
      find.descendant(
        of: find.byKey(const Key('org-hub-sheet-photos')),
        matching: find.text('1 OF 10'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: photosRow, matching: find.text('1 OF 10')),
      findsOneWidget,
    );

    rebuildHost(() => settingsKey = UniqueKey());
    await tester.pumpAndSettle();
    await tester.tap(photosRow);
    await tester.pumpAndSettle();
    await tester.tap(addPhoto);
    await tester.pumpAndSettle();

    final savedPhotos = (await repository.organization('org1'))!.photoUrls;
    expect(savedPhotos, hasLength(2));
    expect(savedPhotos.first, firstPhotos.single);
    expect(savedPhotos.toSet(), hasLength(2));
    expect(picker.photoCalls, 2);
  });

  testWidgets('changing disclosure preserves unsaved venue fields and pin', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) => app.switchToOrganization('org1'),
      home: const Scaffold(body: OrgVenueEditScreen(venueId: 'v1')),
    );
    await enterOrganizer(tester, harness, 'org1');
    await tester.enterText(
      find.byKey(const Key('org-venue-public-name')),
      'Foghorn Hall',
    );
    await tester.enterText(
      find.byKey(const Key('org-venue-public-description')),
      'Updated venue description.',
    );
    await tester.tap(find.byKey(const Key('org-venue-type-club')));
    await tester.enterText(
      find.byKey(const Key('org-venue-public-capacity')),
      '220',
    );

    final address = find.byKey(const Key('org-venue-private-address'));
    await _scrollTo(tester, address);
    await tester.enterText(address, '22 V');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    final suggestion = find.byKey(const Key('org-venue-private-suggestion-0'));
    await tester.ensureVisible(suggestion);
    await tester.pump();
    await tester.tap(suggestion);
    await tester.pump();
    final loadIn = find.byKey(const Key('org-venue-private-load-in'));
    await _scrollTo(tester, loadIn);
    await tester.enterText(loadIn, 'Use the loading bay.');

    final disclosure = find.byKey(const Key('org-venue-disclosure'));
    await _scrollTo(tester, disclosure);
    await tester.tap(find.text('Show exact address publicly'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchRow>(disclosure).value, isTrue);
    expect(find.text('Address disclosure saved.'), findsOneWidget);
    expect(
      (await repository.resolveVenue('v1'))?.name,
      DemoData.venues['v1']!.name,
    );
    expect(
      (await repository.venuePrivateDetails('v1'))?.addr,
      DemoData.venuePrivateDetails['v1']!.addr,
    );

    await tester.tap(find.byKey(const Key('org-venue-save')));
    await tester.pumpAndSettle();
    final venue = await repository.resolveVenue('v1');
    final details = await repository.venuePrivateDetails('v1');
    expect(venue?.name, 'Foghorn Hall');
    expect(venue?.description, 'Updated venue description.');
    expect(venue?.venueType, VenueType.club);
    expect(venue?.capacityPublic, 220);
    expect(venue?.disclosure, AddressDisclosure.public);
    expect(venue?.exactAddress, '22 Valencia St');
    expect(details?.addr, '22 Valencia St');
    expect(
      details?.point,
      (harness.geocoding as FakeGeocodingService).suggestions.first.point,
    );
    expect(details?.loadInNotes, 'Use the loading bay.');
    expect(details?.capacity, DemoData.venuePrivateDetails['v1']!.capacity);
  });

  testWidgets('creating a venue needs a name and pin, then lists it', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) => app.switchToOrganization('org1'),
      home: const Scaffold(body: OrgVenueEditScreen(venueId: 'new')),
    );
    await enterOrganizer(tester, harness, 'org1');

    expect(find.text('New venue'), findsOneWidget);
    expect(find.byKey(const Key('org-venue-disclosure')), findsNothing);
    final save = find.byKey(const Key('org-venue-save'));
    expect(tester.widget<StickyActionBar>(save).primaryLabel, 'CREATE VENUE');

    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Needs: name, address, map pin'), findsOneWidget);
    expect(
      (await repository.organizationDashboard('org1')).venues,
      hasLength(1),
    );

    // The feedback reveal scrolled to the bottom; the public fields above
    // are lazily built, so jump back to the top before filling them in.
    tester.widget<ListView>(find.byType(ListView)).controller!.jumpTo(0);
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('org-venue-public-name')),
      '  The Annex ',
    );
    await tester.enterText(
      find.byKey(const Key('org-venue-public-description')),
      'Small room behind the club.',
    );
    await tester.tap(find.byKey(const Key('org-venue-type-club')));
    await tester.enterText(
      find.byKey(const Key('org-venue-public-capacity')),
      '90',
    );
    final address = find.byKey(const Key('org-venue-private-address'));
    await _scrollTo(tester, address);
    await tester.enterText(address, '22 V');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    final suggestion = find.byKey(const Key('org-venue-private-suggestion-0'));
    await tester.ensureVisible(suggestion);
    await tester.pump();
    await tester.tap(suggestion);
    await tester.pump();
    final loadIn = find.byKey(const Key('org-venue-private-load-in'));
    await _scrollTo(tester, loadIn);
    await tester.enterText(loadIn, 'Ring the side bell.');

    await tester.tap(save);
    await tester.pumpAndSettle();

    final venues = (await repository.organizationDashboard('org1')).venues;
    expect(venues, hasLength(2));
    final created = venues.singleWhere((venue) => venue.name == 'The Annex');
    expect(created.managedByOrganizationId, 'org1');
    expect(created.description, 'Small room behind the club.');
    expect(created.venueType, VenueType.club);
    expect(created.capacityPublic, 90);
    expect(created.disclosure, AddressDisclosure.onTicket);
    expect(created.exactAddress, isNull);
    final details = await repository.venuePrivateDetails(created.id);
    expect(details?.addr, '22 Valencia St');
    expect(
      details?.point,
      (harness.geocoding as FakeGeocodingService).suggestions.first.point,
    );
    expect(details?.loadInNotes, 'Ring the side bell.');
    expect(harness.app.toast, 'Venue created');
    expect(
      harness.app.organizationDashboardFor('org1')?.venues.map((v) => v.id),
      contains(created.id),
    );
  });

  testWidgets('a rejected venue creation shows the server reason', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = StubRepository(auth: auth)
      ..fail(
        'createOrganizationVenue',
        StateError('Another venue already uses that address'),
      );
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) => app.switchToOrganization('org1'),
      home: const Scaffold(body: OrgVenueEditScreen(venueId: 'new')),
    );
    await enterOrganizer(tester, harness, 'org1');

    await tester.enterText(
      find.byKey(const Key('org-venue-public-name')),
      'Duplicate Room',
    );
    final address = find.byKey(const Key('org-venue-private-address'));
    await _scrollTo(tester, address);
    await tester.enterText(address, '22 V');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    final suggestion = find.byKey(const Key('org-venue-private-suggestion-0'));
    await tester.ensureVisible(suggestion);
    await tester.pump();
    await tester.tap(suggestion);
    await tester.pump();

    await tester.tap(find.byKey(const Key('org-venue-save')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('org-venue-save-error'))).data,
      'Another venue already uses that address',
    );
    expect(repository.callsTo('createOrganizationVenue'), 1);
    expect(
      (await repository.organizationDashboard('org1')).venues,
      hasLength(1),
    );
  });

  testWidgets('venue profile and disclosure saves cannot overlap', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = StubRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) => app.switchToOrganization('org1'),
      home: const Scaffold(body: OrgVenueEditScreen(venueId: 'v1')),
    );
    await enterOrganizer(tester, harness, 'org1');
    await tester.enterText(
      find.byKey(const Key('org-venue-public-name')),
      'Pending venue name',
    );
    final disclosure = find.byKey(const Key('org-venue-disclosure'));
    final save = find.byKey(const Key('org-venue-save'));
    await _scrollTo(tester, disclosure);
    final disclosureGate = repository.gate('setVenueAddressDisclosure');
    await tester.tap(find.text('Show exact address publicly'));
    await tester.pump();
    expect(tester.widget<StickyActionBar>(save).onPrimary, isNull);

    disclosureGate.complete();
    await tester.pumpAndSettle();
    final profileGate = repository.gate('updateVenueProfile');
    await tester.tap(save);
    await tester.pump();
    expect(tester.widget<SwitchRow>(disclosure).onChanged, isNull);

    profileGate.complete();
    await tester.pumpAndSettle();
    expect((await repository.resolveVenue('v1'))?.name, 'Pending venue name');
    expect(tester.widget<SwitchRow>(disclosure).value, isTrue);
    expect(tester.widget<SwitchRow>(disclosure).onChanged, isNotNull);
  });
}

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  final scrollable = find
      .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
      .first;
  await tester.scrollUntilVisible(target, 250, scrollable: scrollable);
  await tester.pumpAndSettle();
}

final _photo = photoFixture(filename: 'organization.png');

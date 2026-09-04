import 'dart:async';
import 'dart:convert';

import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/org_settings.dart';
import 'package:earplug/screens/org_venue_edit.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/services/media_picker.dart';
import 'package:earplug/widgets/form_bits.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

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
    final addPhoto = find.byKey(const Key('org-settings-add-photo'));
    await _scrollTo(tester, addPhoto);
    await tester.tap(addPhoto);
    await tester.pumpAndSettle();
    final firstPhotos = (await repository.organization('org1'))!.photoUrls;
    expect(firstPhotos, hasLength(1));

    rebuildHost(() => settingsKey = UniqueKey());
    await tester.pumpAndSettle();
    await _scrollTo(tester, addPhoto);
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

  testWidgets('venue profile and disclosure saves cannot overlap', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _GatedVenueRepository(auth: auth);
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
    repository.disclosureGate = Completer<void>();
    await tester.tap(find.text('Show exact address publicly'));
    await tester.pump();
    expect(tester.widget<StickyActionBar>(save).onPrimary, isNull);

    repository.disclosureGate!.complete();
    await tester.pumpAndSettle();
    repository.profileGate = Completer<void>();
    await tester.tap(save);
    await tester.pump();
    expect(tester.widget<SwitchRow>(disclosure).onChanged, isNull);

    repository.profileGate!.complete();
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

final _photo = PickedMedia(
  bytes: base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  ),
  filename: 'organization.png',
  contentType: 'image/png',
  sizeBytes: 68,
);

class _GatedVenueRepository extends DemoRepository {
  _GatedVenueRepository({required super.auth});

  Completer<void>? disclosureGate;
  Completer<void>? profileGate;

  @override
  Future<void> setVenueAddressDisclosure({
    required String venueId,
    required AddressDisclosure disclosure,
  }) async {
    await disclosureGate?.future;
    await super.setVenueAddressDisclosure(
      venueId: venueId,
      disclosure: disclosure,
    );
  }

  @override
  Future<void> updateVenueProfile({
    required String venueId,
    String? name,
    String? description,
    VenueType? venueType,
    int? capacityPublic,
    String? neighborhood,
    String? city,
  }) async {
    await profileGate?.future;
    await super.updateVenueProfile(
      venueId: venueId,
      name: name,
      description: description,
      venueType: venueType,
      capacityPublic: capacityPublic,
      neighborhood: neighborhood,
      city: city,
    );
  }
}

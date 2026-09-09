import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/navigation.dart';
import 'package:earplug/screens/org_dash.dart';
import 'package:earplug/screens/private_locations.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/services/geocoding_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/design_rules.dart';
import 'support/fakes.dart';
import 'support/harness.dart';
import 'support/stub_repository.dart';

void main() {
  testWidgets('host locations show labels and areas and open the editor', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const PrivateLocationsScreen(),
      beforePump: (app) => app.switchToOrganization('org2'),
    );

    expect(find.text("Jordan's courtyard"), findsOneWidget);
    expect(find.text('Mission District'), findsOneWidget);
    expect(find.text('120 Demo Lane, San Francisco'), findsNothing);
    await _tap(tester, 'private-location-private-location-org2');
    expect(harness.app.current.screen, Screen.privateLocationEdit);
    expect(harness.app.current.param, 'private-location-org2');
    await _tap(tester, 'private-locations-new');
    expect(harness.app.current.screen, Screen.privateLocationEdit);
    expect(harness.app.current.param, 'new');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('new location saves a flat form with an autocomplete pin', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final beforeCount = (await repository.privateLocationsFor('org2')).length;
    final geocoding = FakeGeocodingService();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      geocoding: geocoding,
      home: const PrivateLocationEditScreen(locationId: 'new'),
      beforePump: (app) {
        app.switchToOrganization('org2');
        app.go(Screen.privateLocations);
        app.go(Screen.privateLocationEdit, 'new');
      },
    );
    expectNoFieldInCard(tester);

    await _enterText(tester, 'private-location-label', 'Backyard');
    await _pickAddress(tester, 'Valencia');
    expect(find.text('Artists will see: Mission'), findsOneWidget);
    expect(find.textContaining('Fans will see:'), findsNothing);
    await _reveal(tester, find.byKey(const Key('private-location-city')));
    expect(
      _field(tester, 'private-location-city').controller!.text,
      'San Francisco',
    );
    await _enterText(tester, 'private-location-city', 'San Francisco');
    // A later pin placement must preserve the host's city correction.
    await _pickAddress(tester, '22 Valencia');
    expect(
      _field(tester, 'private-location-city').controller!.text,
      'San Francisco',
    );
    await _enterText(tester, 'private-location-notes', 'Use the side gate.');
    expectNoFieldInCard(tester);
    await _tap(tester, 'private-location-save');

    final locations = await repository.privateLocationsFor('org2');
    expect(locations, hasLength(beforeCount + 1));
    final saved = locations.singleWhere(
      (location) => location.label == 'Backyard',
    );
    final suggestion = geocoding.suggestions.first;
    expect(saved.addr, suggestion.address);
    expect(saved.area, suggestion.area);
    expect(saved.lat, suggestion.point.latitude);
    expect(saved.lng, suggestion.point.longitude);
    expect(saved.city, 'San Francisco');
    expect(saved.notes, 'Use the side gate.');
    expect(harness.app.current.screen, Screen.privateLocations);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final locality in <String?>[null, '']) {
    testWidgets(
      'address with ${locality == null ? 'missing' : 'empty'} locality leaves city empty',
      (tester) async {
        final auth = FakeAuthService();
        await auth.signInDemo();
        final repository = DemoRepository(auth: auth);
        final suggestion = FakeGeocodingService().suggestions.first;
        await pumpApp(
          tester,
          auth: auth,
          repository: repository,
          geocoding: FakeGeocodingService(
            suggestions: [
              AddressSuggestion(
                label: suggestion.label,
                address: suggestion.address,
                area: suggestion.area,
                locality: locality,
                point: suggestion.point,
              ),
            ],
          ),
          home: const PrivateLocationEditScreen(locationId: 'new'),
          beforePump: (app) => app.switchToOrganization('org2'),
        );

        await _enterText(tester, 'private-location-label', 'Backyard');
        await _pickAddress(tester, 'Valencia');
        expect(find.text('Artists will see: Mission'), findsOneWidget);
        await _reveal(tester, find.byKey(const Key('private-location-city')));
        expect(
          _field(tester, 'private-location-city').controller!.text,
          isEmpty,
        );
        expectNoFieldInCard(tester);
        await _tap(tester, 'private-location-save');
        expect(find.text('Needs: city'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('location save requires a label, address, pin, and city', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final beforeCount = (await repository.privateLocationsFor('org2')).length;
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const PrivateLocationEditScreen(locationId: 'new'),
      beforePump: (app) => app.switchToOrganization('org2'),
    );

    await _tap(tester, 'private-location-save');
    expect(find.byKey(const Key('private-location-feedback')), findsOneWidget);
    expect(find.text('Needs: label, address, map pin, city'), findsOneWidget);
    expect(
      await repository.privateLocationsFor('org2'),
      hasLength(beforeCount),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('existing location hydrates its fields and saves changes', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final original = (await repository.privateLocationsFor('org2')).single;
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: PrivateLocationEditScreen(locationId: original.id),
      beforePump: (app) => app.switchToOrganization('org2'),
    );

    expect(
      _field(tester, 'private-location-label').controller!.text,
      original.label,
    );
    expect(
      _field(tester, 'private-location-address').controller!.text,
      original.addr,
    );
    await _enterText(tester, 'private-location-label', 'The courtyard');
    await _enterText(tester, 'private-location-notes', '');
    expectNoFieldInCard(tester);
    await _tap(tester, 'private-location-save');

    final saved = (await repository.privateLocationsFor('org2')).single;
    expect(saved.id, original.id);
    expect(saved.label, 'The courtyard');
    expect(saved.notes, isEmpty);
    expect(saved.addr, original.addr);
    expect(saved.city, original.city);
    expect(saved.area, original.area);
    expect(saved.lat, original.lat);
    expect(saved.lng, original.lng);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('unused location removal requires confirmation', (tester) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final id = await repository.createPrivateLocation(
      organizationId: 'org2',
      label: 'Backyard',
      addr: '22 Valencia St',
      city: 'San Francisco',
      area: 'Mission',
      lat: 37.7676,
      lng: -122.4220,
    );
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: PrivateLocationEditScreen(locationId: id),
      beforePump: (app) {
        app.switchToOrganization('org2');
        app.go(Screen.privateLocations);
        app.go(Screen.privateLocationEdit, id);
      },
    );

    await _tap(tester, 'private-location-remove');
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'KEEP'));
    await tester.pumpAndSettle();
    expect(
      (await repository.privateLocationsFor(
        'org2',
      )).map((location) => location.id),
      contains(id),
    );
    await _tap(tester, 'private-location-remove');
    await tester.tap(find.widgetWithText(FilledButton, 'CONFIRM'));
    await tester.pumpAndSettle();
    expect(
      (await repository.privateLocationsFor(
        'org2',
      )).map((location) => location.id),
      isNot(contains(id)),
    );
    expect(harness.app.current.screen, Screen.privateLocations);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('removal errors appear inline for a location in use', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const PrivateLocationEditScreen(
        locationId: 'private-location-org2',
      ),
      beforePump: (app) => app.switchToOrganization('org2'),
    );

    await _tap(tester, 'private-location-remove');
    await tester.tap(find.widgetWithText(FilledButton, 'CONFIRM'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('private-location-feedback')), findsOneWidget);
    expect(
      find.textContaining('Private location is used by an opportunity'),
      findsOneWidget,
    );
    expect(await repository.privateLocationsFor('org2'), hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('location load errors offer retry and an empty state', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = StubRepository(auth: auth)
      ..failOnce('privateLocationsFor', StateError('Temporarily unavailable'))
      ..returns('privateLocationsFor', const <PrivateLocation>[]);
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const PrivateLocationsScreen(),
      beforePump: (app) => app.switchToOrganization('org2'),
    );

    expect(find.text('Could not load locations.'), findsOneWidget);
    await tester.tap(find.text('RETRY'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'No locations yet. Add the place where your event happens; artists see only the area until the deposit is paid.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('private-locations-new')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'host dashboard exposes requests, locations, finance, and settings',
    (tester) async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final repository = DemoRepository(auth: auth);
      final harness = await pumpApp(
        tester,
        auth: auth,
        repository: repository,
        home: const OrgDashScreen(),
        beforePump: (app) => app.switchToOrganization('org2'),
      );

      final readiness = find.byKey(const Key('org-dash-verification'));
      expect(
        tester
            .widgetList<Text>(
              find.descendant(of: readiness, matching: find.byType(Text)),
            )
            .map((text) => text.data),
        ['HOST READINESS', 'Verified', 'Profile complete'],
      );
      expect(find.text('ORGANIZATION READINESS'), findsNothing);
      expect(find.text('Stripe details'), findsNothing);
      expect(find.text('Payouts enabled'), findsNothing);
      expect(find.text('Team invited'), findsNothing);
      expect(find.text('VENUES'), findsNothing);
      expect(find.text('MEMBERS'), findsNothing);
      await _reveal(tester, find.byKey(const Key('org-dash-locations')));
      expect(find.text('NEW REQUEST'), findsOneWidget);
      expect(
        find.byKey(const Key('org-dash-command-opportunity')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('org-dash-locations')), findsOneWidget);
      expect(find.byKey(const Key('org-dash-command-finance')), findsOneWidget);
      expect(
        find.byKey(const Key('org-dash-command-settings')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('org-dash-command-venues')), findsNothing);
      expect(find.byKey(const Key('org-dash-command-team')), findsNothing);
      await _tap(tester, 'org-dash-locations');
      expect(harness.app.current.screen, Screen.privateLocations);
      await _tap(tester, 'org-dash-command-opportunity');
      expect(harness.app.current.screen, Screen.opportunityEdit);
      expect(harness.app.current.param, 'new');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('public organizer dashboard keeps its venue and team controls', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    await pumpApp(
      tester,
      auth: auth,
      home: const OrgDashScreen(),
      beforePump: (app) => app.switchToOrganization('org1'),
    );

    final readiness = find.byKey(const Key('org-dash-verification'));
    expect(
      tester
          .widgetList<Text>(
            find.descendant(of: readiness, matching: find.byType(Text)),
          )
          .map((text) => text.data),
      [
        'ORGANIZATION READINESS',
        'Verified',
        'Stripe details',
        'Payouts enabled',
        'Profile complete',
        'Team invited',
      ],
    );
    expect(find.text('HOST READINESS'), findsNothing);
    expect(find.text('MEMBERS'), findsOneWidget);
    await _reveal(tester, find.byKey(const Key('org-dash-command-venues')));
    expect(find.text('NEW OPPORTUNITY'), findsOneWidget);
    expect(find.byKey(const Key('org-dash-command-venues')), findsOneWidget);
    expect(find.byKey(const Key('org-dash-command-team')), findsOneWidget);
    expect(find.byKey(const Key('org-dash-command-settings')), findsOneWidget);
    expect(find.byKey(const Key('org-dash-command-finance')), findsOneWidget);
    expect(find.byKey(const Key('org-dash-locations')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

TextField _field(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key)));

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  final scrollable = find
      .descendant(
        of: find.byType(ListView).first,
        matching: find.byType(Scrollable),
      )
      .first;
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: scrollable,
    maxScrolls: 40,
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await _reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _enterText(WidgetTester tester, String key, String text) async {
  final finder = find.byKey(Key(key));
  await _reveal(tester, finder);
  await tester.enterText(finder, text);
  await tester.pumpAndSettle();
}

Future<void> _pickAddress(WidgetTester tester, String query) async {
  final address = find.byKey(const Key('private-location-address'));
  await _reveal(tester, address);
  await tester.enterText(address, query);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
  await _tap(tester, 'private-location-suggestion-0');
}

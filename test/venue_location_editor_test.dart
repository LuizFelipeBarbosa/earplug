import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/gig_create.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/ep_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'support/harness.dart';

void main() {
  testWidgets(
    'new venue sheet shows every field and refuses an empty submission',
    (tester) async {
      final repository = _RecordingVenueRepository(auth: FakeAuthService());
      await _openNewVenueSheet(tester, repository);

      expect(find.text('NEW VENUE'), findsOne);
      expect(find.byKey(const Key('new-venue-name')), findsOne);
      expect(find.byKey(const Key('new-venue-address')), findsOne);
      expect(find.byKey(const Key('new-venue-area')), findsOne);
      expect(find.byKey(const Key('new-venue-map')), findsOne);
      expect(find.text('TAP THE MAP TO PLACE THE REQUIRED PIN'), findsOne);
      expect(find.text('CREATE & SELECT VENUE'), findsOne);

      await tester.tap(find.text('CREATE & SELECT VENUE'));
      await tester.pump();

      expect(
        find.text('Name, street address, area, and map pin are required.'),
        findsOne,
      );
      expect(repository.createCalls, isEmpty);
      expect(find.text('NEW VENUE'), findsOne);
    },
  );

  testWidgets('a complete new venue is created, announced and selected', (
    tester,
  ) async {
    final repository = _RecordingVenueRepository(auth: FakeAuthService());
    final harness = await _openNewVenueSheet(tester, repository);
    final app = harness.app;
    expect(app.gfVenueId, isNull);

    await tester.enterText(
      find.byKey(const Key('new-venue-name')),
      'Harbor Loft',
    );
    await tester.enterText(
      find.byKey(const Key('new-venue-address')),
      '9 Pier Street',
    );
    await tester.enterText(find.byKey(const Key('new-venue-area')), 'Oakland');
    await tester.pump();

    final map = tester.widget<EpMap>(
      find.descendant(
        of: find.byKey(const Key('new-venue-map')),
        matching: find.byType(EpMap),
      ),
    );
    map.options.onTap!(
      const TapPosition(Offset.zero, Offset.zero),
      const LatLng(37.8, -122.27),
    );
    await tester.pump();
    expect(find.text('MAP PIN SET ✓'), findsOne);
    expect(find.text('TAP THE MAP TO PLACE THE REQUIRED PIN'), findsNothing);

    await tester.tap(find.text('CREATE & SELECT VENUE'));
    await tester.pumpAndSettle();

    expect(repository.createCalls, hasLength(1));
    final call = repository.createCalls.single;
    expect(call.name, 'Harbor Loft');
    expect(call.address, '9 Pier Street');
    expect(call.area, 'Oakland');
    expect(call.latitude, 37.8);
    expect(call.longitude, -122.27);

    expect(app.toast, 'Venue created and selected.');
    expect(app.gfVenueId, isNotNull);
    expect(app.venue(app.gfVenueId!).name, 'Harbor Loft');
    expect(find.text('NEW VENUE'), findsNothing);
    expect(find.text('Harbor Loft'), findsOne);
  });
}

/// Opens the gig editor, its venue sheet, then the new-venue sheet.
Future<AppHarness> _openNewVenueSheet(
  WidgetTester tester,
  DemoRepository repository,
) async {
  final harness = await pumpApp(
    tester,
    repository: repository,
    beforePump: (app) async {
      await tester.pumpAndSettle();
      app.startGigCreate();
    },
    home: const Scaffold(body: GigCreateScreen()),
  );

  await tester.tap(find.text('Choose a venue'));
  await tester.pumpAndSettle();
  expect(find.text('+ NEW VENUE'), findsOne);

  await tester.tap(find.text('+ NEW VENUE'));
  await tester.pumpAndSettle();
  return harness;
}

typedef _VenueCall = ({
  String name,
  String area,
  String address,
  double latitude,
  double longitude,
});

class _RecordingVenueRepository extends DemoRepository {
  _RecordingVenueRepository({required super.auth});

  final List<_VenueCall> createCalls = [];

  @override
  Future<VenueCreationResult> createVenue({
    required String bandId,
    required String name,
    required String area,
    required String address,
    required double latitude,
    required double longitude,
  }) {
    createCalls.add((
      name: name,
      area: area,
      address: address,
      latitude: latitude,
      longitude: longitude,
    ));
    return super.createVenue(
      bandId: bandId,
      name: name,
      area: area,
      address: address,
      latitude: latitude,
      longitude: longitude,
    );
  }
}

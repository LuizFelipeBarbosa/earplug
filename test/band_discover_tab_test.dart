import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/services/location_service.dart';
import 'package:earplug/widgets/band_discover_tab.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'support/harness.dart';

void main() {
  testWidgets(
    'mount loads browse; search matches all supported fields and clears',
    (tester) async {
      final harness = await _pumpDiscover(
        tester,
        items: [
          _item('first', title: 'Midnight Static', venue: _nearVenue),
          _item('second', title: 'Matinee', venue: _farVenue),
        ],
      );
      final repository = harness.app.repository as _BrowseRepository;
      expect(repository.publicCalls, greaterThan(0));
      expect(harness.app.bandId, 'b1');
      expect(find.text('OPEN · 2'), findsOneWidget);
      expect(
        tester
            .widget<ListView>(find.byKey(const PageStorageKey('band-discover')))
            .physics,
        isA<AlwaysScrollableScrollPhysics>(),
      );

      final calls = repository.publicCalls;
      for (final query in [
        'mIDnight',
        'fOGhorn',
        'san fran',
        'mission',
        'bay area',
      ]) {
        await tester.enterText(
          find.byKey(const Key('discover-search-field')),
          query,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('opp-card-first')), findsOneWidget);
        expect(find.byKey(const Key('opp-card-second')), findsNothing);
        expect(find.text('OPEN · 1'), findsOneWidget);
      }
      expect(repository.publicCalls, calls);
      await tester.tap(find.byKey(const Key('discover-search-clear')));
      await tester.pumpAndSettle();
      expect(find.text('OPEN · 2'), findsOneWidget);
      expect(find.byKey(const Key('discover-search-clear')), findsNothing);
    },
  );

  testWidgets(
    'unmatched search explains loaded scope and searches the next page',
    (tester) async {
      final harness = await _pumpDiscover(
        tester,
        items: [_item('first')],
        moreItems: [_item('later', title: 'Hidden gem')],
      );
      await tester.enterText(
        find.byKey(const Key('discover-search-field')),
        'hidden',
      );
      await tester.pumpAndSettle();
      expect(
        find.text('No loaded gigs match. Load more to search further.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('band-gigs-load-more')));
      await tester.pumpAndSettle();
      expect((harness.app.repository as _BrowseRepository).lastCursor, 'next');
      expect(find.byKey(const Key('opp-card-later')), findsOneWidget);
      expect(find.byKey(const Key('opp-card-first')), findsNothing);
      expect(find.byKey(const Key('band-gigs-load-more')), findsNothing);
    },
  );

  testWidgets(
    'NEAR YOU orders by distance, puts missing venues last, and toggles',
    (tester) async {
      await _pumpDiscover(
        tester,
        position: _origin,
        size: const Size(390, 1400),
        items: [
          _item('missing', days: 1),
          _item('far', days: 2, venue: _farVenue),
          _item('near', days: 3, venue: _nearVenue),
        ],
      );
      expect(_chip(tester, 'near').selected, isTrue);
      _expectOrder(tester, ['near', 'far', 'missing']);
      await tester.tap(find.byKey(const Key('discover-chip-near')));
      await tester.pumpAndSettle();
      expect(_chip(tester, 'near').selected, isFalse);
      _expectOrder(tester, ['missing', 'far', 'near']);
    },
  );

  testWidgets(
    'first NEAR YOU tap requests location without prompting on mount',
    (tester) async {
      final location = _LocationService();
      final harness = await _pumpDiscover(
        tester,
        locationService: location,
        items: [
          _item('far', days: 1, venue: _farVenue),
          _item('near', days: 2, venue: _nearVenue),
        ],
      );
      expect(location.requests, 0);
      expect(_chip(tester, 'near').selected, isTrue);
      _expectOrder(tester, ['far', 'near']);
      await tester.tap(find.byKey(const Key('discover-chip-near')));
      await tester.pumpAndSettle();
      expect(location.requests, 1);
      expect(harness.app.currentPosition, _origin);
      _expectOrder(tester, ['near', 'far']);
      await tester.tap(find.byKey(const Key('discover-chip-near')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('discover-chip-near')));
      await tester.pumpAndSettle();
      expect(location.requests, 1);
    },
  );

  testWidgets(
    'DATE filters the next 7 or 31 days and relabels without fetching',
    (tester) async {
      final harness = await _pumpDiscover(
        tester,
        items: [
          _item('past', days: -1),
          _item('soon', days: 2),
          _item('month', days: 15),
          _item('later', days: 32),
        ],
      );
      final repository = harness.app.repository as _BrowseRepository;
      final calls = repository.publicCalls;
      await _choose(tester, 'discover-chip-date', 'This week');
      expect(_chip(tester, 'date').label, 'THIS WEEK');
      expect(_chip(tester, 'date').selected, isTrue);
      expect(find.text('OPEN · 1'), findsOneWidget);
      expect(find.byKey(const Key('opp-card-soon')), findsOneWidget);
      expect(find.byKey(const Key('opp-card-past')), findsNothing);
      await _choose(tester, 'discover-chip-date', 'This month');
      expect(_chip(tester, 'date').label, 'THIS MONTH');
      expect(find.text('OPEN · 2'), findsOneWidget);
      expect(find.byKey(const Key('opp-card-month')), findsOneWidget);
      await _choose(tester, 'discover-chip-date', 'Any date');
      expect(_chip(tester, 'date').label, 'DATE');
      expect(_chip(tester, 'date').selected, isFalse);
      expect(find.text('OPEN · 4'), findsOneWidget);
      expect(repository.publicCalls, calls);
    },
  );

  testWidgets(
    'PAY and GENRE update server filters and preserve other selections',
    (tester) async {
      final harness = await _pumpDiscover(tester, items: [_item('first')]);
      harness.app.setBrowseFilters(
        const OpportunityFilters(area: 'Oakland', venueType: VenueType.bar),
      );
      await tester.pumpAndSettle();
      for (final dollars in [100, 250, 500]) {
        await _choose(tester, 'discover-chip-pay', '\$$dollars+');
        expect(harness.app.browseFilters.minGuaranteeMinor, dollars * 100);
        expect(_chip(tester, 'pay').label, '\$$dollars+');
        expect(_chip(tester, 'pay').selected, isTrue);
      }
      await _choose(tester, 'discover-chip-genre', 'punk');
      expect(harness.app.browseFilters.genre, 'punk');
      expect(_chip(tester, 'genre').label, 'punk');
      expect(_chip(tester, 'genre').selected, isTrue);
      expect(harness.app.browseFilters.minGuaranteeMinor, 50000);
      expect(harness.app.browseFilters.area, 'Oakland');
      expect(harness.app.browseFilters.venueType, VenueType.bar);
      final repository = harness.app.repository as _BrowseRepository;
      expect(repository.lastFilters?.genre, 'punk');
      await _choose(tester, 'discover-chip-pay', 'Any');
      expect(harness.app.browseFilters.minGuaranteeMinor, isNull);
      expect(harness.app.browseFilters.genre, 'punk');
      await _choose(tester, 'discover-chip-genre', 'Any');
      expect(harness.app.browseFilters.genre, isNull);
      expect(_chip(tester, 'genre').selected, isFalse);
      expect(_chip(tester, 'pay').selected, isFalse);
    },
  );

  testWidgets(
    'more filters badge counts area and venue type; Clear preserves pay and genre',
    (tester) async {
      final harness = await _pumpDiscover(tester, items: [_item('first')]);
      expect(
        find.byKey(const Key('discover-more-filters-count')),
        findsNothing,
      );
      harness.app.setBrowseFilters(
        const OpportunityFilters(genre: 'punk', minGuaranteeMinor: 25000),
      );
      await tester.pumpAndSettle();
      await _openMore(tester);
      expect(find.text('GENRE'), findsNothing);
      expect(find.byKey(const Key('band-gigs-filter-minimum')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('band-gigs-filter-area')),
        ' Oakland ',
      );
      await tester.tap(find.byKey(const Key('band-gigs-filter-apply')));
      await tester.pumpAndSettle();
      expect(harness.app.browseFilters.area, 'Oakland');
      expect(_badge(tester), '1');
      await _openMore(tester);
      await tester.tap(find.widgetWithText(EpPill, 'BAR'));
      await tester.tap(find.byKey(const Key('band-gigs-filter-apply')));
      await tester.pumpAndSettle();
      expect(harness.app.browseFilters.venueType, VenueType.bar);
      expect(_badge(tester), '2');
      await _openMore(tester);
      await tester.tap(find.widgetWithText(EpPill, 'CLEAR'));
      await tester.pumpAndSettle();
      expect(harness.app.browseFilters.area, isNull);
      expect(harness.app.browseFilters.venueType, isNull);
      expect(harness.app.browseFilters.genre, 'punk');
      expect(harness.app.browseFilters.minGuaranteeMinor, 25000);
      expect(
        find.byKey(const Key('discover-more-filters-count')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'invitations stay first and are deduplicated against the public page',
    (tester) async {
      await _pumpDiscover(
        tester,
        position: _origin,
        items: [
          _item('near', days: 1, venue: _nearVenue),
          _item('invited', days: 20, venue: _farVenue),
        ],
        invited: [_item('invited', days: 20, venue: _farVenue, invited: true)],
      );
      _expectOrder(tester, ['invited', 'near']);
      expect(find.byKey(const Key('opp-card-invited')), findsOneWidget);
      expect(find.text('INVITED'), findsOneWidget);
      expect(find.text('OPEN · 2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('discover-chip-near')));
      await tester.pumpAndSettle();
      _expectOrder(tester, ['invited', 'near']);
    },
  );

  for (final status in <ArtistApplicationStatus?>[
    null,
    ArtistApplicationStatus.withdrawn,
    ArtistApplicationStatus.declined,
    ArtistApplicationStatus.expired,
  ]) {
    testWidgets('APPLY opens opportunity detail for status ${status?.name}', (
      tester,
    ) async {
      final harness = await _pumpDiscover(
        tester,
        items: [_item('first', applicationStatus: status)],
      );
      final action = find.byKey(const Key('opp-card-first-apply'));
      expect(action, findsOneWidget);
      expect(find.byKey(const Key('opp-card-first-applied')), findsNothing);
      expect(tester.getSize(action).height, greaterThanOrEqualTo(44));
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(harness.app.current.screen, Screen.opportunityDetail);
      expect(harness.app.current.param, 'first-slug');
    });
  }

  for (final status in [
    ArtistApplicationStatus.submitted,
    ArtistApplicationStatus.underReview,
    ArtistApplicationStatus.shortlisted,
    ArtistApplicationStatus.offered,
    ArtistApplicationStatus.booked,
  ]) {
    testWidgets(
      '${status.name} shows a non-interactive check pill and 1 spot left',
      (tester) async {
        final harness = await _pumpDiscover(
          tester,
          items: [_item('first', applicationStatus: status)],
        );
        final action = find.byKey(const Key('opp-card-first-applied'));
        final pill = tester.widget<EpPill>(action);
        expect(pill.onPressed, isNull);
        expect(pill.selected, isTrue);
        expect(pill.variant, EpPillVariant.outline);
        expect(
          find.descendant(of: action, matching: find.byIcon(Icons.check)),
          findsOneWidget,
        );
        expect(find.byKey(const Key('opp-card-first-apply')), findsNothing);
        expect(find.text('1 spot left'), findsOneWidget);
        expect(find.byIcon(Icons.schedule), findsNothing);
        await tester.tap(find.text('LIVE TONIGHT'));
        await tester.pumpAndSettle();
        expect(harness.app.current.screen, Screen.opportunityDetail);
        expect(harness.app.current.param, 'first-slug');
      },
    );
  }

  testWidgets(
    'cards summarize only open roles and retain the deadline above two spots',
    (tester) async {
      await _pumpDiscover(
        tester,
        items: [
          _item(
            'first',
            applicationStatus: ArtistApplicationStatus.submitted,
            slots: [
              _slot(0, status: SlotStatus.booked),
              _slot(1, role: SlotRole.support, guarantee: 0),
              _slot(2),
              _slot(3),
            ],
          ),
        ],
      );
      expect(find.text('SUPPORT + 2 MORE · unpaid'), findsOneWidget);
      expect(find.textContaining('Apply by '), findsOneWidget);
      expect(find.byIcon(Icons.schedule), findsOneWidget);
      expect(find.textContaining('spots left'), findsNothing);
    },
  );

  testWidgets(
    'private cards retain keys, area, guest estimate and disclosure',
    (tester) async {
      final harness = await _pumpDiscover(
        tester,
        privateItems: [_item('private', private: true)],
      );
      expect(harness.app.browse.privateCount, 1);
      final card = find.byKey(const Key('opp-card-private'));
      expect(card, findsOneWidget);
      expect(find.byKey(const Key('opp-card-private-private')), findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('~45 guests')),
        findsOneWidget,
      );
      expect(find.text('Bay Area'), findsOneWidget);
      expect(find.textContaining('after the deposit is paid.'), findsOneWidget);
      expect(find.byKey(const Key('opp-card-private-apply')), findsOneWidget);
    },
  );

  testWidgets('browse errors display the message and RETRY reloads', (
    tester,
  ) async {
    final harness = await _pumpDiscover(
      tester,
      items: [_item('first')],
      error: 'Could not load opportunities.',
    );
    expect(
      find.text('Bad state: Could not load opportunities.'),
      findsOneWidget,
    );
    final repository = harness.app.repository as _BrowseRepository;
    final calls = repository.publicCalls;
    repository.error = null;
    await tester.tap(find.widgetWithText(EpPill, 'RETRY'));
    await tester.pumpAndSettle();
    expect(repository.publicCalls, calls + 1);
    expect(find.byKey(const Key('opp-card-first')), findsOneWidget);
    expect(find.text('RETRY'), findsNothing);
  });

  testWidgets('empty browse is refreshable and shows the empty copy', (
    tester,
  ) async {
    final harness = await _pumpDiscover(tester);
    expect(find.text('Nothing open right now.'), findsOneWidget);
    final repository = harness.app.repository as _BrowseRepository;
    final calls = repository.publicCalls;
    repository.items = [_item('new')];
    await tester.drag(find.byType(ListView), const Offset(0, 350));
    await tester.pumpAndSettle();
    expect(repository.publicCalls, calls + 1);
    expect(find.byKey(const Key('opp-card-new')), findsOneWidget);
  });

  testWidgets(
    'pagination shows LOADING and prevents duplicate load-more taps',
    (tester) async {
      final harness = await _pumpDiscover(
        tester,
        items: [_item('first')],
        moreItems: [_item('second')],
      );
      final repository = harness.app.repository as _BrowseRepository;
      final gate = Completer<void>();
      repository.gate = gate;
      await tester.tap(find.byKey(const Key('band-gigs-load-more')));
      await tester.pump();
      expect(find.text('LOADING…'), findsOneWidget);
      expect(
        tester
            .widget<EpPill>(find.byKey(const Key('band-gigs-load-more')))
            .onPressed,
        isNull,
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('LOADING…'), findsNothing);
      expect(find.byKey(const Key('opp-card-second')), findsOneWidget);
    },
  );

  testWidgets(
    '390px layout has no overflow and filter chips support mouse dragging',
    (tester) async {
      await _pumpDiscover(
        tester,
        size: const Size(390, 844),
        items: [
          _item(
            'first',
            title:
                'An exceptionally long opportunity title that wraps across two lines',
            venue: _nearVenue,
            slots: [
              _slot(0, role: SlotRole.support),
              _slot(1),
            ],
          ),
        ],
      );
      expect(tester.takeException(), isNull);
      expect(
        find.text(r'SUPPORT + 1 MORE · $250.00 guarantee'),
        findsOneWidget,
      );
      final scroll = find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      );
      final behavior = ScrollConfiguration.of(tester.element(scroll));
      expect(behavior.dragDevices, contains(PointerDeviceKind.mouse));
      final gesture = await tester.startGesture(
        tester.getCenter(scroll),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-280, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('discover-more-filters')).hitTestable(),
        findsOneWidget,
      );
      await _openMore(tester);
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(const Key('band-gigs-filter-apply'))).height,
        greaterThanOrEqualTo(44),
      );
    },
  );
}

EpPill _chip(WidgetTester tester, String name) =>
    tester.widget<EpPill>(find.byKey(Key('discover-chip-$name')));

String? _badge(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const Key('discover-more-filters-count')))
    .data;

Future<void> _choose(WidgetTester tester, String chipKey, String option) async {
  await tester.ensureVisible(find.byKey(Key(chipKey)));
  await tester.tap(find.byKey(Key(chipKey)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> _openMore(WidgetTester tester) async {
  final more = find.byKey(const Key('discover-more-filters'));
  await tester.ensureVisible(more);
  await tester.tap(more);
  await tester.pumpAndSettle();
}

void _expectOrder(WidgetTester tester, List<String> ids) {
  for (var index = 1; index < ids.length; index++) {
    expect(
      tester.getTopLeft(find.byKey(Key('opp-card-${ids[index - 1]}'))).dy,
      lessThan(tester.getTopLeft(find.byKey(Key('opp-card-${ids[index]}'))).dy),
    );
  }
}

Future<AppHarness> _pumpDiscover(
  WidgetTester tester, {
  List<BrowseItem> items = const [],
  List<BrowseItem> invited = const [],
  List<BrowseItem> privateItems = const [],
  List<BrowseItem>? moreItems,
  String? error,
  LatLng? position,
  LocationService? locationService,
  Size size = const Size(390, 900),
}) async {
  final auth = FakeAuthService();
  await auth.signInDemo();
  final repository = _BrowseRepository(auth: auth)
    ..items = items
    ..invited = invited
    ..privateItems = privateItems
    ..moreItems = moreItems
    ..error = error;
  return pumpApp(
    tester,
    home: const Scaffold(body: BandDiscoverTab()),
    auth: auth,
    repository: repository,
    size: size,
    locationService: locationService,
    beforePump: (app) {
      app.switchToBand('b1');
      if (position != null) app.useCurrentPosition(position);
    },
  );
}

const _origin = LatLng(37.76, -122.42);
const _nearVenue = Venue(
  id: 'near',
  name: 'The Foghorn Club',
  area: 'San Francisco',
  addr: '',
  point: LatLng(37.761, -122.421),
  city: 'San Francisco',
  neighborhood: 'Mission',
);
const _farVenue = Venue(
  id: 'far',
  name: 'Eastside Hall',
  area: 'Oakland',
  addr: '',
  point: LatLng(37.81, -122.27),
  city: 'Oakland',
  neighborhood: 'Temescal',
);

BrowseItem _item(
  String id, {
  String title = 'Live tonight',
  int days = 3,
  Venue? venue,
  bool invited = false,
  bool private = false,
  ArtistApplicationStatus? applicationStatus,
  List<OpportunitySlot>? slots,
}) {
  final now = DateTime.now();
  return BrowseItem(
    invited: invited,
    myApplicationStatus: applicationStatus,
    opportunity: Opportunity(
      id: id,
      organizationId: 'org1',
      mode: private
          ? OpportunityMode.privateBooking
          : OpportunityMode.publicEvent,
      privateEvent: private,
      venue: venue,
      title: title,
      desc: '',
      expectedAttendance: private ? 45 : null,
      genres: const ['punk'],
      startsAt: now.add(Duration(days: days)),
      ageRequirement: AgeRequirement.allAges,
      flyKey: 'xerox',
      applicationsCloseAt: now.add(const Duration(days: 1)),
      visibility: OpportunityVisibility.publicListing,
      ticketing: OpportunityTicketing.none,
      status: OpportunityStatus.open,
      slug: '$id-slug',
      revision: 1,
      applicationCount: 0,
      slots: slots ?? [_slot(0)],
      invitedBandIds: invited ? const ['b1'] : const [],
      createdAt: now,
      updatedAt: now,
      area: venue == _farVenue ? 'East Bay' : 'Bay Area',
      currency: 'usd',
    ),
  );
}

OpportunitySlot _slot(
  int order, {
  SlotRole role = SlotRole.headliner,
  int guarantee = 25000,
  SlotStatus status = SlotStatus.open,
}) => OpportunitySlot(
  id: 'slot-$order',
  order: order,
  role: role,
  guaranteeMinor: guarantee,
  required: true,
  status: status,
);

class _BrowseRepository extends DemoRepository {
  _BrowseRepository({required super.auth});

  List<BrowseItem> items = [];
  List<BrowseItem> invited = [];
  List<BrowseItem> privateItems = [];
  List<BrowseItem>? moreItems;
  String? error;
  Completer<void>? gate;
  int publicCalls = 0;
  String? lastCursor;
  OpportunityFilters? lastFilters;

  @override
  Future<OpportunityPage> browseOpportunities({
    String? cursor,
    int numItems = 25,
    String? bandId,
    OpportunityFilters? filters,
    OpportunityMode? mode,
  }) async {
    if (mode == OpportunityMode.privateBooking) {
      return OpportunityPage(
        items: privateItems,
        continueCursor: null,
        isDone: true,
      );
    }
    publicCalls++;
    lastCursor = cursor;
    lastFilters = filters;
    await gate?.future;
    if (error != null) throw StateError(error!);
    return OpportunityPage(
      items: cursor == null ? items : moreItems ?? const [],
      continueCursor: cursor == null && moreItems != null ? 'next' : null,
      isDone: cursor != null || moreItems == null,
    );
  }

  @override
  Future<List<BrowseItem>> invitedOpportunities(String bandId) async => invited;
}

class _LocationService implements LocationService {
  int requests = 0;

  @override
  Future<LocationResult> requestCurrentLocation() async {
    requests++;
    return const LocationSuccess(
      UserLocation(latitude: 37.76, longitude: -122.42, accuracyMeters: 5),
    );
  }

  @override
  Future<bool> openAppSettings() async => false;

  @override
  Future<bool> openLocationSettings() async => false;
}

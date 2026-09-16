import 'package:earplug/host_request_groups.dart';
import 'package:earplug/models.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 9, 15, 12);

void main() {
  group('isFullyBooked', () {
    test('a confirmed status is fully booked whatever its slots say', () {
      expect(
        isFullyBooked(
          _opportunity(
            'a',
            status: OpportunityStatus.confirmed,
            slots: [_slot('a1', SlotStatus.open)],
          ),
        ),
        isTrue,
      );
    });

    test('every live slot booked counts even while the status is open', () {
      expect(
        isFullyBooked(
          _opportunity(
            'a',
            slots: [
              _slot('a1', SlotStatus.booked),
              _slot('a2', SlotStatus.booked),
            ],
          ),
        ),
        isTrue,
      );
    });

    test('a cancelled slot is ignored', () {
      expect(
        isFullyBooked(
          _opportunity(
            'a',
            slots: [
              _slot('a1', SlotStatus.booked),
              _slot('a2', SlotStatus.cancelled),
            ],
          ),
        ),
        isTrue,
      );
    });

    test('one open slot leaves the request unfilled', () {
      expect(
        isFullyBooked(
          _opportunity(
            'a',
            slots: [
              _slot('a1', SlotStatus.booked),
              _slot('a2', SlotStatus.open),
            ],
          ),
        ),
        isFalse,
      );
    });

    test('no slots, or only cancelled slots, is never fully booked', () {
      expect(isFullyBooked(_opportunity('a')), isFalse);
      expect(
        isFullyBooked(
          _opportunity('a', slots: [_slot('a1', SlotStatus.cancelled)]),
        ),
        isFalse,
      );
    });
  });

  group('HostRequestGroups.from', () {
    test('fully booked live requests are confirmed, soonest first', () {
      final later = _opportunity(
        'later',
        days: 9,
        status: OpportunityStatus.confirmed,
      );
      final sooner = _opportunity(
        'sooner',
        days: 2,
        slots: [_slot('s1', SlotStatus.booked)],
      );
      final open = _opportunity('open', days: 1);

      final groups = HostRequestGroups.from([later, open, sooner], now: _now);

      expect(groups.confirmed, [sooner, later]);
      expect(groups.active, [open]);
      expect(groups.past, isEmpty);
      expect(groups.nextEvent, sooner);
    });

    test('active holds the still-looking statuses with drafts last', () {
      final draft = _opportunity(
        'draft',
        days: 1,
        status: OpportunityStatus.draft,
      );
      final booking = _opportunity(
        'booking',
        days: 6,
        status: OpportunityStatus.booking,
        slots: [_slot('b1', SlotStatus.booked), _slot('b2', SlotStatus.open)],
      );
      final closed = _opportunity(
        'closed',
        days: 3,
        status: OpportunityStatus.applicationsClosed,
      );
      final open = _opportunity('open', days: 4);

      final groups = HostRequestGroups.from([
        draft,
        booking,
        closed,
        open,
      ], now: _now);

      expect(groups.active, [closed, open, booking, draft]);
      expect(groups.confirmed, isEmpty);
    });

    test(
      'completed, cancelled and already-started requests are past, newest first',
      () {
        final completed = _opportunity(
          'completed',
          days: -10,
          status: OpportunityStatus.completed,
        );
        final cancelled = _opportunity(
          'cancelled',
          days: 5,
          status: OpportunityStatus.cancelled,
        );
        final yesterdayConfirmed = _opportunity(
          'yesterday',
          days: -1,
          status: OpportunityStatus.confirmed,
        );
        final staleOpen = _opportunity('stale', days: -3);
        final upcoming = _opportunity('upcoming', days: 2);

        final groups = HostRequestGroups.from([
          completed,
          upcoming,
          cancelled,
          staleOpen,
          yesterdayConfirmed,
        ], now: _now);

        expect(groups.past, [
          cancelled,
          yesterdayConfirmed,
          staleOpen,
          completed,
        ]);
        expect(groups.cancelledCount, 1);
        expect(groups.active, [upcoming]);
        expect(groups.confirmed, isEmpty);
        expect(groups.nextEvent, isNull);
      },
    );

    test('a request earlier today is not past yet', () {
      final thisMorning = _opportunity('morning', days: 0, hour: 8);
      final lastNight = _opportunity('last-night', days: -1, hour: 23);

      final groups = HostRequestGroups.from([
        thisMorning,
        lastNight,
      ], now: _now);

      expect(groups.active, [thisMorning]);
      expect(groups.past, [lastNight]);
    });

    test('the start of today follows a UTC now', () {
      final utcNow = DateTime.utc(2026, 9, 15, 12);
      final earlyUtc = _opportunity('early', days: 0, hour: 1, utc: true);
      final beforeUtc = _opportunity('before', days: -1, hour: 23, utc: true);

      final groups = HostRequestGroups.from([earlyUtc, beforeUtc], now: utcNow);

      expect(groups.active, [earlyUtc]);
      expect(groups.past, [beforeUtc]);
    });

    test('an empty list yields empty groups', () {
      final groups = HostRequestGroups.from(const [], now: _now);

      expect(groups.confirmed, isEmpty);
      expect(groups.active, isEmpty);
      expect(groups.past, isEmpty);
      expect(groups.cancelledCount, 0);
      expect(groups.nextEvent, isNull);
    });
  });
}

OpportunitySlot _slot(String id, SlotStatus status) => OpportunitySlot(
  id: id,
  order: 0,
  role: SlotRole.headliner,
  guaranteeMinor: 10000,
  required: true,
  status: status,
  bandId: status == SlotStatus.booked ? 'b1' : null,
);

Opportunity _opportunity(
  String id, {
  OpportunityStatus status = OpportunityStatus.open,
  int days = 1,
  int hour = 20,
  bool utc = false,
  List<OpportunitySlot> slots = const [],
}) {
  final startsAt = utc
      ? DateTime.utc(2026, 9, 15 + days, hour)
      : DateTime(2026, 9, 15 + days, hour);
  return Opportunity(
    id: id,
    organizationId: 'org1',
    mode: OpportunityMode.publicEvent,
    title: id,
    desc: '',
    genres: const [],
    startsAt: startsAt,
    ageRequirement: AgeRequirement.allAges,
    flyKey: 'xerox',
    applicationsCloseAt: startsAt.subtract(const Duration(days: 1)),
    visibility: OpportunityVisibility.publicListing,
    ticketing: OpportunityTicketing.none,
    status: status,
    slug: id,
    revision: 1,
    applicationCount: 0,
    slots: slots,
    invitedBandIds: const [],
    createdAt: _now,
    updatedAt: _now,
    area: 'Mission',
    currency: 'usd',
  );
}

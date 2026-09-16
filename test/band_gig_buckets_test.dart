import 'package:earplug/band_gig_buckets.dart';
import 'package:earplug/models.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 9, 15, 12);

void main() {
  test('nextUp is earliest live future booking; upcoming is sorted', () {
    final latest = _booking('latest', days: 5);
    final first = _booking('first', days: 1);
    final middle = _booking('middle', days: 3);
    final bookings = [latest, first, middle];

    final buckets = _buckets(bookings: bookings);

    expect(buckets.nextUp, same(first));
    expect(buckets.upcoming, [middle, latest]);
    expect(buckets.past, isEmpty);
    expect(bookings, [latest, first, middle]);
  });

  test('application and unresolved booking statuses are ignored entirely', () {
    const ignored = [
      BookingStatus.offerSent,
      BookingStatus.artistAccepted,
      BookingStatus.awaitingPayment,
      BookingStatus.declined,
      BookingStatus.expired,
      BookingStatus.withdrawn,
      BookingStatus.disputed,
      BookingStatus.unknown,
    ];
    final buckets = _buckets(
      bookings: [
        for (final status in ignored)
          for (final days in [-1, 1])
            _booking('${status.name}-$days', status: status, days: days),
      ],
    );

    expect(buckets.nextUp, isNull);
    expect(buckets.upcoming, isEmpty);
    expect(buckets.hosting, isEmpty);
    expect(buckets.drafts, isEmpty);
    expect(buckets.past, isEmpty);
    expect(buckets.cancelledCount, 0);
  });

  test('completed, paid, and live bookings before now are past', () {
    final completed = _booking(
      'completed',
      status: BookingStatus.completed,
      days: -3,
    );
    final paid = _booking('paid', status: BookingStatus.paid, days: -1);
    final live = _booking('still-confirmed', days: -2);
    final buckets = _buckets(bookings: [completed, paid, live]);
    final entries = buckets.past.cast<BandPastBooking>();

    expect(entries.map((entry) => entry.booking), [paid, live, completed]);
    expect(entries.every((entry) => !entry.cancelled), isTrue);
    expect(buckets.nextUp, isNull);
    expect(buckets.upcoming, isEmpty);
    expect(buckets.cancelledCount, 0);
  });

  test('future isLive and completed/paid past rules are independent', () {
    final paid = _booking('paid', status: BookingStatus.paid, days: 2);
    final completed = _booking(
      'completed',
      status: BookingStatus.completed,
      days: 1,
    );
    final buckets = _buckets(bookings: [paid, completed]);

    expect(buckets.nextUp, completed);
    expect(buckets.upcoming, [paid]);
    expect(buckets.past.cast<BandPastBooking>().map((entry) => entry.booking), [
      paid,
      completed,
    ]);
  });

  test('a live booking exactly at now is neither before nor after', () {
    final buckets = _buckets(bookings: [_booking('now', days: 0)]);

    expect(buckets.nextUp, isNull);
    expect(buckets.upcoming, isEmpty);
    expect(buckets.past, isEmpty);
  });

  test('every cancellation status goes into past and counts as cancelled', () {
    const statuses = [
      BookingStatus.cancelledByOrganizer,
      BookingStatus.cancelledByArtist,
      BookingStatus.forceMajeure,
      BookingStatus.refunded,
    ];
    final buckets = _buckets(
      bookings: [
        for (var index = 0; index < statuses.length; index++)
          _booking(
            statuses[index].name,
            status: statuses[index],
            days: index - 2,
          ),
      ],
    );

    expect(buckets.nextUp, isNull);
    expect(buckets.upcoming, isEmpty);
    expect(buckets.past, hasLength(4));
    expect(
      buckets.past.cast<BandPastBooking>().every((entry) => entry.cancelled),
      isTrue,
    );
    expect(buckets.cancelledCount, 4);
  });

  test('projects split by status and sort without changing the input', () {
    final later = _project(
      'later',
      startsAt: _now.add(const Duration(days: 4)),
    );
    final earlier = _project('earlier', startsAt: _now);
    final undated = _project('undated');
    final olderDraft = _project(
      'older-draft',
      status: GigProjectStatus.draft,
      updatedAt: _now.subtract(const Duration(days: 1)),
    );
    final newerDraft = _project('newer-draft', status: GigProjectStatus.draft);
    final cancelled = _project('cancelled', status: GigProjectStatus.cancelled);
    final deleted = _project('deleted', status: GigProjectStatus.deleted);
    final projects = [
      later,
      olderDraft,
      cancelled,
      undated,
      deleted,
      earlier,
      newerDraft,
    ];
    final original = List<GigProject>.of(projects);

    final buckets = _buckets(projects: projects);

    expect(buckets.hosting, [earlier, later, undated]);
    expect(buckets.drafts, [newerDraft, olderDraft]);
    expect((buckets.past.single as BandPastProject).project, cancelled);
    expect(buckets.cancelledCount, 1);
    expect(projects, original);
  });

  test('past sorts newest first with undated projects using updatedAt', () {
    final old = _booking('old', status: BookingStatus.paid, days: -5);
    final recent = _booking('recent', days: -1);
    final cancelledBooking = _booking(
      'cancelled-booking',
      status: BookingStatus.cancelledByArtist,
      days: 2,
    );
    final datedProject = _project(
      'dated-project',
      status: GigProjectStatus.cancelled,
      startsAt: _now.subtract(const Duration(days: 3)),
      updatedAt: _now.add(const Duration(days: 10)),
    );
    final undatedProject = _project(
      'undated-project',
      status: GigProjectStatus.cancelled,
      updatedAt: _now.subtract(const Duration(days: 2)),
    );
    const ledger = [
      PastGig('First ledger', '2001'),
      PastGig('Second ledger', '2099'),
    ];

    final buckets = _buckets(
      bookings: [old, recent, cancelledBooking],
      projects: [datedProject, undatedProject],
      ledger: ledger,
    );

    expect(
      buckets.past.map(
        (entry) => switch (entry) {
          BandPastBooking(:final booking) => booking.id,
          BandPastProject(:final project) => project.id,
          BandPastLedger(:final pastGig) => pastGig.title,
        },
      ),
      [
        'cancelled-booking',
        'recent',
        'undated-project',
        'dated-project',
        'old',
        'First ledger',
        'Second ledger',
      ],
    );
    expect(
      buckets.past.whereType<BandPastLedger>().map((entry) => entry.pastGig),
      ledger,
    );
    expect(buckets.cancelledCount, 3);
  });

  test('empty inputs produce empty buckets', () {
    final buckets = _buckets();

    expect(buckets.nextUp, isNull);
    expect(buckets.upcoming, isEmpty);
    expect(buckets.hosting, isEmpty);
    expect(buckets.drafts, isEmpty);
    expect(buckets.past, isEmpty);
    expect(buckets.cancelledCount, 0);
  });
}

BandGigBuckets _buckets({
  List<Booking> bookings = const [],
  List<GigProject> projects = const [],
  List<PastGig> ledger = const [],
}) => BandGigBuckets.from(
  bookings: bookings,
  projects: projects,
  ledger: ledger,
  now: _now,
);

Booking _booking(
  String id, {
  BookingStatus status = BookingStatus.confirmed,
  required int days,
}) => Booking.fromJson({
  '_id': id,
  'status': status.wireValue,
  'startsAt': _now.add(Duration(days: days)).millisecondsSinceEpoch,
});

GigProject _project(
  String id, {
  GigProjectStatus status = GigProjectStatus.published,
  DateTime? startsAt,
  DateTime? updatedAt,
}) => GigProject(
  id: id,
  bandId: 'b1',
  status: status,
  revision: 1,
  price: 0,
  flyKey: 'blue',
  overlay: true,
  desc: '',
  ticketing: Ticketing.rsvp,
  ageRequirement: AgeRequirement.allAges,
  cap: 'No cap',
  updatedAt: updatedAt ?? _now,
  startsAt: startsAt,
  performers: const [],
);

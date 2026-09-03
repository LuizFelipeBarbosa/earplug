import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/models.dart';

class ManyShowsRecapRepository extends DemoRepository {
  ManyShowsRecapRepository({required super.auth});

  @override
  Future<BandRecap> bandRecap(String bandId) async => manyShowsRecap(12);
}

class FortyShowsRecapRepository extends DemoRepository {
  FortyShowsRecapRepository({required super.auth});

  @override
  Future<BandRecap> bandRecap(String bandId) async => manyShowsRecap(40);
}

BandRecap manyShowsRecap(int showCount) =>
    _manyShowsRecap(showCount, splitCount: showCount);

BandRecap manyShowsRecapWithPartialSplit(
  int showCount, {
  required int splitCount,
}) {
  assert(splitCount >= 0 && splitCount <= showCount);
  return _manyShowsRecap(showCount, splitCount: splitCount);
}

BandRecap _manyShowsRecap(int showCount, {required int splitCount}) {
  final firstShow = DateTime.utc(2026, 1, 1).millisecondsSinceEpoch;
  final shows = [
    for (var index = 0; index < showCount; index++)
      RecapShow(
        gigId: 'show-${index + 1}',
        title: 'Show ${(index + 1).toString().padLeft(2, '0')}',
        startsAt: firstShow + index * const Duration(days: 1).inMilliseconds,
        venueName: 'Venue ${(index % 8 + 1).toString().padLeft(2, '0')}',
        price: 0,
        ticketing: Ticketing.rsvp,
        goingCount: 10 + index,
        measuredRsvps: 10 + index,
        newFans: index < splitCount ? 6 + index : null,
        returningFans: index < splitCount ? 4 : null,
      ),
  ];
  final measuredRsvps = shows.fold<int>(
    0,
    (total, show) => total + show.measuredRsvps,
  );

  return BandRecap(
    window: RecapWindow(
      showsAnalyzed: showCount,
      scanned: showCount,
      truncated: false,
      firstStartsAt: shows.first.startsAt,
      lastStartsAt: shows.last.startsAt,
    ),
    totals: RecapTotals(
      shows: showCount,
      reportedRsvps: measuredRsvps,
      measuredRsvps: measuredRsvps,
      avgPerShow: measuredRsvps / showCount,
      bestShowRsvps: shows.last.measuredRsvps,
      distinctFans: measuredRsvps,
      followerCount: measuredRsvps,
    ),
    shows: shows,
    newReturningSuppressed: false,
    leadTime: const RecapLeadTime(
      buckets: [
        RecapBucket(key: 'twoWeeksPlus', count: 12),
        RecapBucket(key: 'oneToTwoWeeks', count: 18),
        RecapBucket(key: 'underWeek', count: 24),
        RecapBucket(key: 'dayOf', count: 9),
      ],
      medianDays: 6,
      unmeasurable: 0,
      suppressed: false,
    ),
    venues: RecapVenues(
      rows: [
        for (var number = 1; number <= 8; number++)
          RecapVenue(
            venueName: 'Venue ${number.toString().padLeft(2, '0')}',
            shows: number % 3 + 1,
            totalRsvps: number * 10 * (number % 3 + 1),
            avgRsvps: number * 10,
          ),
      ],
      suppressed: false,
    ),
    weekdays: RecapWeekdays(
      rows: [
        for (var weekday = 1; weekday <= 7; weekday++)
          RecapWeekday(weekday: weekday, shows: 2, avgRsvps: weekday * 5),
      ],
      suppressed: false,
    ),
    repeatFans: const RecapRepeatFans(
      tiers: [
        RecapBucket(key: 'one', count: 30),
        RecapBucket(key: 'twoToThree', count: 18),
        RecapBucket(key: 'fourPlus', count: 7),
      ],
      suppressed: false,
    ),
    pricing: const RecapPricing(
      freeShows: 12,
      freeAvgRsvps: 15.5,
      paidShows: 0,
      paidAvgRsvps: 0,
      suppressed: false,
    ),
  );
}

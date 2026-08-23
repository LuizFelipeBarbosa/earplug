import '../models.dart';

Map<String, dynamic> _recapMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> _recapMapList(Object? value) {
  if (value is! List<Object?>) return const <Map<String, dynamic>>[];
  return <Map<String, dynamic>>[
    for (final item in value)
      if (item is Map<String, dynamic>) item,
  ];
}

String _recapString(Object? value) => value is String ? value : '';

int _recapInt(Object? value) => value is num ? value.toInt() : 0;

int? _recapNullableInt(Object? value) => value is num ? value.toInt() : null;

num _recapNum(Object? value) => value is num ? value : 0;

num? _recapNullableNum(Object? value) => value is num ? value : null;

bool _recapBool(Object? value) => value is bool ? value : false;

Ticketing _recapTicketing(Object? value) => switch (value) {
  'external' => Ticketing.external,
  _ => Ticketing.rsvp,
};

class FeedSnapshot {
  final List<Gig> gigs;
  final Map<String, Venue> venues;
  final Map<String, Band> bands;

  /// Start time of the first row beyond [gigs], or null when the feed is
  /// exhaustive. Discovery uses this to avoid offering a partially loaded day.
  final DateTime? nextStartsAt;

  const FeedSnapshot({
    required this.gigs,
    required this.venues,
    required this.bands,
    this.nextStartsAt,
  });
}

class Interactions {
  final Set<String> rsvpGigIds;
  final Set<String> followBandIds;
  final Set<String> savedGigIds;
  final List<Gig> gigs;
  final int attendedCount;

  const Interactions({
    required this.rsvpGigIds,
    required this.followBandIds,
    required this.savedGigIds,
    this.gigs = const [],
    required this.attendedCount,
  });

  static const empty = Interactions(
    rsvpGigIds: {},
    followBandIds: {},
    savedGigIds: {},
    gigs: [],
    attendedCount: 0,
  );
}

class BandMembership {
  final Band band;
  final String role;

  const BandMembership({required this.band, required this.role});
}

/// A band's past gigs, newest first, with the venues they were played at.
///
/// Separate from [FeedSnapshot] because history carries no band map: the caller
/// already knows whose profile it is looking at.
class BandHistory {
  final List<Gig> gigs;
  final Map<String, Venue> venues;

  const BandHistory({required this.gigs, required this.venues});

  static const empty = BandHistory(gigs: [], venues: {});
}

/// One page from the name-ordered band directory.
class BandPage {
  final List<Band> items;
  final String? continueCursor;
  final bool isDone;

  const BandPage({
    required this.items,
    required this.continueCursor,
    required this.isDone,
  });
}

/// A venue and the bounded set of upcoming relationships needed by its page.
class VenueDetail {
  final Venue venue;
  final List<Gig> gigs;
  final Map<String, Band> bands;
  final bool truncated;

  const VenueDetail({
    required this.venue,
    required this.gigs,
    required this.bands,
    required this.truncated,
  });
}

/// Aggregated performance data for a band's past events.
class BandRecap {
  final RecapWindow window;
  final RecapTotals totals;
  final List<RecapShow> shows;

  /// True when the per-show new/returning columns were hidden server-side.
  final bool newReturningSuppressed;
  final RecapLeadTime leadTime;
  final RecapVenues venues;
  final RecapWeekdays weekdays;
  final RecapRepeatFans repeatFans;
  final RecapPricing pricing;

  const BandRecap({
    required this.window,
    required this.totals,
    required this.shows,
    required this.newReturningSuppressed,
    required this.leadTime,
    required this.venues,
    required this.weekdays,
    required this.repeatFans,
    required this.pricing,
  });

  factory BandRecap.fromJson(Map<String, dynamic> json) => BandRecap(
    window: RecapWindow.fromJson(_recapMap(json['window'])),
    totals: RecapTotals.fromJson(_recapMap(json['totals'])),
    shows: [
      for (final show in _recapMapList(json['shows'])) RecapShow.fromJson(show),
    ],
    newReturningSuppressed: _recapBool(
      _recapMap(json['newReturning'])['suppressed'],
    ),
    leadTime: RecapLeadTime.fromJson(_recapMap(json['leadTime'])),
    venues: RecapVenues.fromJson(_recapMap(json['venues'])),
    weekdays: RecapWeekdays.fromJson(_recapMap(json['weekdays'])),
    repeatFans: RecapRepeatFans.fromJson(_recapMap(json['repeatFans'])),
    pricing: RecapPricing.fromJson(_recapMap(json['pricing'])),
  );

  static const empty = BandRecap(
    window: RecapWindow(
      showsAnalyzed: 0,
      scanned: 0,
      truncated: false,
      firstStartsAt: null,
      lastStartsAt: null,
    ),
    totals: RecapTotals(
      shows: 0,
      reportedRsvps: 0,
      measuredRsvps: 0,
      avgPerShow: 0,
      bestShowRsvps: 0,
      distinctFans: 0,
      followerCount: 0,
    ),
    shows: [],
    newReturningSuppressed: false,
    leadTime: RecapLeadTime(
      buckets: [],
      medianDays: null,
      unmeasurable: 0,
      suppressed: false,
    ),
    venues: RecapVenues(rows: [], suppressed: false),
    weekdays: RecapWeekdays(rows: [], suppressed: false),
    repeatFans: RecapRepeatFans(tiers: [], suppressed: false),
    pricing: RecapPricing(
      freeShows: 0,
      freeAvgRsvps: 0,
      paidShows: 0,
      paidAvgRsvps: 0,
      suppressed: false,
    ),
  );
}

class RecapWindow {
  final int showsAnalyzed;
  final int scanned;
  final bool truncated;
  final int? firstStartsAt;
  final int? lastStartsAt;

  const RecapWindow({
    required this.showsAnalyzed,
    required this.scanned,
    required this.truncated,
    required this.firstStartsAt,
    required this.lastStartsAt,
  });

  factory RecapWindow.fromJson(Map<String, dynamic> json) => RecapWindow(
    showsAnalyzed: _recapInt(json['showsAnalyzed']),
    scanned: _recapInt(json['scanned']),
    truncated: _recapBool(json['truncated']),
    firstStartsAt: _recapNullableInt(json['firstStartsAt']),
    lastStartsAt: _recapNullableInt(json['lastStartsAt']),
  );
}

class RecapTotals {
  final int shows;
  final int reportedRsvps;
  final int measuredRsvps;
  final num avgPerShow;
  final int bestShowRsvps;
  final int distinctFans;
  final int followerCount;

  const RecapTotals({
    required this.shows,
    required this.reportedRsvps,
    required this.measuredRsvps,
    required this.avgPerShow,
    required this.bestShowRsvps,
    required this.distinctFans,
    required this.followerCount,
  });

  factory RecapTotals.fromJson(Map<String, dynamic> json) => RecapTotals(
    shows: _recapInt(json['shows']),
    reportedRsvps: _recapInt(json['reportedRsvps']),
    measuredRsvps: _recapInt(json['measuredRsvps']),
    avgPerShow: _recapNum(json['avgPerShow']),
    bestShowRsvps: _recapInt(json['bestShowRsvps']),
    distinctFans: _recapInt(json['distinctFans']),
    followerCount: _recapInt(json['followerCount']),
  );
}

class RecapShow {
  final String gigId;
  final String title;
  final int startsAt;
  final String venueName;
  final int price;
  final Ticketing ticketing;
  final int goingCount;
  final int measuredRsvps;
  final int? newFans;
  final int? returningFans;

  const RecapShow({
    required this.gigId,
    required this.title,
    required this.startsAt,
    required this.venueName,
    required this.price,
    required this.ticketing,
    required this.goingCount,
    required this.measuredRsvps,
    required this.newFans,
    required this.returningFans,
  });

  factory RecapShow.fromJson(Map<String, dynamic> json) => RecapShow(
    gigId: _recapString(json['gigId']),
    title: _recapString(json['title']),
    startsAt: _recapInt(json['startsAt']),
    venueName: _recapString(json['venueName']),
    price: _recapInt(json['price']),
    ticketing: _recapTicketing(json['ticketing']),
    goingCount: _recapInt(json['goingCount']),
    measuredRsvps: _recapInt(json['measuredRsvps']),
    newFans: _recapNullableInt(json['newFans']),
    returningFans: _recapNullableInt(json['returningFans']),
  );
}

/// A keyed count used by lead-time buckets and repeat-fan tiers.
class RecapBucket {
  final String key;
  final int count;

  const RecapBucket({required this.key, required this.count});

  factory RecapBucket.fromJson(Map<String, dynamic> json) => RecapBucket(
    key: _recapString(json['key']),
    count: _recapInt(json['count']),
  );
}

class RecapVenue {
  final String venueName;
  final int shows;
  final int totalRsvps;
  final num avgRsvps;

  const RecapVenue({
    required this.venueName,
    required this.shows,
    required this.totalRsvps,
    required this.avgRsvps,
  });

  factory RecapVenue.fromJson(Map<String, dynamic> json) => RecapVenue(
    venueName: _recapString(json['venueName']),
    shows: _recapInt(json['shows']),
    totalRsvps: _recapInt(json['totalRsvps']),
    avgRsvps: _recapNum(json['avgRsvps']),
  );
}

class RecapWeekday {
  final int weekday;
  final int shows;
  final num avgRsvps;

  const RecapWeekday({
    required this.weekday,
    required this.shows,
    required this.avgRsvps,
  });

  factory RecapWeekday.fromJson(Map<String, dynamic> json) => RecapWeekday(
    weekday: _recapInt(json['weekday']),
    shows: _recapInt(json['shows']),
    avgRsvps: _recapNum(json['avgRsvps']),
  );
}

class RecapLeadTime {
  final List<RecapBucket> buckets;
  final num? medianDays;
  final int unmeasurable;
  final bool suppressed;

  const RecapLeadTime({
    required this.buckets,
    required this.medianDays,
    required this.unmeasurable,
    required this.suppressed,
  });

  factory RecapLeadTime.fromJson(Map<String, dynamic> json) => RecapLeadTime(
    buckets: [
      for (final bucket in _recapMapList(json['buckets']))
        RecapBucket.fromJson(bucket),
    ],
    medianDays: _recapNullableNum(json['medianDays']),
    unmeasurable: _recapInt(json['unmeasurable']),
    suppressed: _recapBool(json['suppressed']),
  );
}

class RecapVenues {
  final List<RecapVenue> rows;
  final bool suppressed;

  const RecapVenues({required this.rows, required this.suppressed});

  factory RecapVenues.fromJson(Map<String, dynamic> json) => RecapVenues(
    rows: [
      for (final row in _recapMapList(json['rows'])) RecapVenue.fromJson(row),
    ],
    suppressed: _recapBool(json['suppressed']),
  );
}

class RecapWeekdays {
  final List<RecapWeekday> rows;
  final bool suppressed;

  const RecapWeekdays({required this.rows, required this.suppressed});

  factory RecapWeekdays.fromJson(Map<String, dynamic> json) => RecapWeekdays(
    rows: [
      for (final row in _recapMapList(json['rows'])) RecapWeekday.fromJson(row),
    ],
    suppressed: _recapBool(json['suppressed']),
  );
}

class RecapRepeatFans {
  final List<RecapBucket> tiers;
  final bool suppressed;

  const RecapRepeatFans({required this.tiers, required this.suppressed});

  factory RecapRepeatFans.fromJson(Map<String, dynamic> json) =>
      RecapRepeatFans(
        tiers: [
          for (final tier in _recapMapList(json['tiers']))
            RecapBucket.fromJson(tier),
        ],
        suppressed: _recapBool(json['suppressed']),
      );
}

class RecapPricing {
  final int freeShows;
  final num freeAvgRsvps;
  final int paidShows;
  final num paidAvgRsvps;
  final bool suppressed;

  const RecapPricing({
    required this.freeShows,
    required this.freeAvgRsvps,
    required this.paidShows,
    required this.paidAvgRsvps,
    required this.suppressed,
  });

  factory RecapPricing.fromJson(Map<String, dynamic> json) => RecapPricing(
    freeShows: _recapInt(json['freeShows']),
    freeAvgRsvps: _recapNum(json['freeAvgRsvps']),
    paidShows: _recapInt(json['paidShows']),
    paidAvgRsvps: _recapNum(json['paidAvgRsvps']),
    suppressed: _recapBool(json['suppressed']),
  );
}

abstract class EarplugRepository {
  /// Pushes the current auth token to the backend; awaitable so callers can
  /// sequence mutations after an identity change.
  Future<void> refreshAuth();

  /// The signed-in user's profile, or null when the backend holds none.
  Future<UserProfile?> me();

  Stream<FeedSnapshot> feed();
  Stream<Interactions> myInteractions();
  Stream<List<BandMembership>> myBands();
  Future<List<BandMedia>> mediaFor(String bandId);
  Future<String> generateMediaUploadUrl(String bandId);
  Future<String> addBandMedia({
    required String bandId,
    required MediaKind kind,
    required String storageId,
    required String title,
    String? caption,
    int? lengthSec,
  });
  Future<void> deleteBandMedia(String mediaId);
  Future<void> pinBandMedia(String mediaId);
  Future<void> moveBandMedia(String mediaId, String direction);
  Future<void> setBandPhoto({required String bandId, required String mediaId});
  Future<void> clearBandPhoto(String bandId);
  Future<List<PastGig>> history();
  Future<BandHistory> bandHistory(String bandId);
  Future<BandRecap> bandRecap(String bandId);
  Future<List<Venue>> venues();
  Future<VenueDetail?> venueDetail(String venueId);
  Future<Band?> band(String bandId);
  Future<List<Band>> searchBands(String q);
  Future<BandPage> listBands({String? cursor, int numItems = 50});

  Future<void> toggleRsvp(String gigId);
  Future<void> toggleFollow(String bandId);
  Future<void> toggleSave(String gigId);
  Future<void> ensureRsvp(String gigId);
  Future<void> ensureFollow(String bandId);
  Future<void> ensureSave(String gigId);
  Future<void> setGenres(List<String> genres);
  Future<void> updateFanOnboarding({
    FanCity? preferredCity,
    FanGenreChoice? genreChoice,
    bool? collapsed,
    List<String>? genres,
  });
  Future<void> ensureUser({String? name});

  /// Returns the new band and its server-issued unique profile slug.
  Future<({Band band, String slug})> createBand({
    required String name,
    required List<String> genres,
    required String bio,
    required List<String> inviteHandles,
    String? area,
    String? linkIg,
    String? linkBc,
    String? linkYt,
  });
  Future<void> updateBandProfile({
    required String bandId,
    String? name,
    List<String>? genres,
    String? area,
    String? bio,
    List<String>? inviteHandles,
    String? linkIg,
    String? linkBc,
    String? linkYt,
  });
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
    required AgeRequirement ageRequirement,
    String? externalUrl,
    required String cap,
  });
}

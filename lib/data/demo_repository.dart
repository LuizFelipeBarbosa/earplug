import 'dart:async';
import 'dart:ui' show Color;

import '../demo_data.dart';
import '../models.dart';
import '../services/auth_service.dart';
import 'repository.dart';

/// The URL form of a name, as the backend derives it.
String _slugify(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

class DemoRepository implements EarplugRepository {
  DemoRepository({required this._auth}) {
    _bands = Map<String, Band>.of(DemoData.bands);
    _memberships = [BandMembership(band: _bands['b1']!, role: 'admin')];
    _mediaLists = {
      'b1': List<BandMedia>.of(DemoData.b1Media),
      '_generic': List<BandMedia>.of(DemoData.genericMedia),
    };

    if (_auth.signedIn) _seedInteractions();
    _auth.signedInChanges.listen(_handleSignedInChange);
  }

  final AuthService _auth;
  final StreamController<FeedSnapshot> _feedController =
      StreamController<FeedSnapshot>.broadcast();
  final StreamController<Interactions> _interactionsController =
      StreamController<Interactions>.broadcast();
  final StreamController<List<BandMembership>> _bandsController =
      StreamController<List<BandMembership>>.broadcast();

  late final Map<String, Band> _bands;
  late final List<BandMembership> _memberships;
  late final Map<String, List<BandMedia>> _mediaLists;
  final List<Gig> _publishedGigs = [];
  final Set<String> _rsvpGigIds = {};
  final Set<String> _followBandIds = {};
  final Set<String> _savedGigIds = {};
  final Set<String> _userGenres = {};
  final Map<String, String> _heroByBand = {};

  String? _userName;
  int _attendedCount = 0;
  int _nextBandId = 1;
  int _nextGigId = 1;
  int _nextMediaId = 1;
  bool _interactionsSeeded = false;

  /// Nothing to push: the demo data does not check identity.
  @override
  Future<void> refreshAuth() async {}

  /// The demo dataset has no user record — no email, and no honest "fan since"
  /// date to show. Callers fall back to the auth service's display name, which
  /// is what the demo has always shown.
  @override
  Future<UserProfile?> me() async => null;

  @override
  Stream<FeedSnapshot> feed() => _replay(_feedController, _currentFeed);

  @override
  Stream<Interactions> myInteractions() =>
      _replay(_interactionsController, _currentInteractions);

  @override
  Stream<List<BandMembership>> myBands() =>
      _replay(_bandsController, _currentMemberships);

  @override
  Future<List<BandMedia>> mediaFor(String bandId) async {
    // Sorted copy: moveBandMedia swaps `order` values in place, and the wire
    // contract (media:forBand) returns rows ordered by `order` asc.
    final media = List<BandMedia>.of(
      _mediaLists[bandId] ?? _mediaLists['_generic']!,
    )..sort((a, b) => a.order.compareTo(b.order));
    return [
      for (final item in media)
        BandMedia(
          id: item.id,
          bandId: item.bandId,
          kind: item.kind,
          url: item.url,
          title: item.title,
          caption: item.caption,
          sizeBytes: item.sizeBytes,
          views: item.views,
          lengthSec: item.lengthSec,
          pinned: item.pinned,
          order: item.order,
          isHero: _heroByBand[bandId] == item.id,
        ),
    ];
  }

  @override
  Future<String> generateMediaUploadUrl(String bandId) async => 'demo://upload';

  @override
  Future<String> addBandMedia({
    required String bandId,
    required MediaKind kind,
    required String storageId,
    required String title,
    String? caption,
    int? lengthSec,
  }) async {
    final media = _mediaLists.putIfAbsent(bandId, () => []);
    final id = 'demo-media-${_nextMediaId++}';
    final isFirstVideo =
        kind == MediaKind.video &&
        !media.any((item) => item.kind == MediaKind.video);
    media.add(
      BandMedia(
        id: id,
        bandId: bandId,
        kind: kind,
        url: null,
        title: title,
        caption: caption,
        sizeBytes: null,
        views: null,
        lengthSec: lengthSec,
        pinned: isFirstVideo,
        order: media.where((item) => item.kind == kind).length,
        isHero: false,
      ),
    );
    return id;
  }

  @override
  Future<void> deleteBandMedia(String mediaId) async {
    final media = _mediaListContaining(mediaId);
    if (media == null) return;

    final index = media.indexWhere((item) => item.id == mediaId);
    final removed = media.removeAt(index);
    final sameKindIndices = [
      for (var i = 0; i < media.length; i++)
        if (media[i].kind == removed.kind) i,
    ]..sort((a, b) => media[a].order.compareTo(media[b].order));
    for (var order = 0; order < sameKindIndices.length; order++) {
      final itemIndex = sameKindIndices[order];
      media[itemIndex] = media[itemIndex].copyWith(order: order);
    }

    if (_heroByBand[removed.bandId] == mediaId) {
      _heroByBand.remove(removed.bandId);
    }
  }

  @override
  Future<void> pinBandMedia(String mediaId) async {
    final media = _mediaListContaining(mediaId);
    if (media == null) return;

    final target = media.firstWhere((item) => item.id == mediaId);
    if (!target.isVideo) return;
    for (var i = 0; i < media.length; i++) {
      if (media[i].isVideo) {
        media[i] = media[i].copyWith(pinned: media[i].id == mediaId);
      }
    }
  }

  @override
  Future<void> moveBandMedia(String mediaId, String direction) async {
    final media = _mediaListContaining(mediaId);
    if (media == null) return;

    final itemIndex = media.indexWhere((item) => item.id == mediaId);
    final target = media[itemIndex];
    final sameKindIndices = [
      for (var i = 0; i < media.length; i++)
        if (media[i].kind == target.kind) i,
    ]..sort((a, b) => media[a].order.compareTo(media[b].order));
    final index = sameKindIndices.indexOf(itemIndex);
    final delta = switch (direction) {
      'up' => -1,
      'down' => 1,
      _ => 0,
    };
    final destination = index + delta;
    if (delta == 0 ||
        destination < 0 ||
        destination >= sameKindIndices.length) {
      return;
    }

    final destinationIndex = sameKindIndices[destination];
    final destinationOrder = media[destinationIndex].order;
    media[destinationIndex] = media[destinationIndex].copyWith(
      order: target.order,
    );
    media[itemIndex] = target.copyWith(order: destinationOrder);
  }

  @override
  Future<void> setBandPhoto({
    required String bandId,
    required String mediaId,
  }) async {
    final media = _mediaListContaining(mediaId);
    final targetIndex = media?.indexWhere((item) => item.id == mediaId) ?? -1;
    final target = targetIndex == -1 ? null : media![targetIndex];
    if (target == null ||
        target.kind != MediaKind.photo ||
        target.bandId != bandId) {
      throw StateError('Band photo must be a photo owned by the same band.');
    }
    _heroByBand[bandId] = mediaId;
  }

  @override
  Future<void> clearBandPhoto(String bandId) async {
    _heroByBand.remove(bandId);
  }

  @override
  Future<List<PastGig>> history() async =>
      _auth.signedIn ? DemoData.fanHistory : const [];

  /// Empty by construction: every demo gig is upcoming, so the demo dataset has
  /// no history to show. Inventing past shows here would put fabricated dates on
  /// a real-looking profile.
  @override
  Future<BandHistory> bandHistory(String bandId) async => BandHistory.empty;

  @override
  Future<BandRecap> bandRecap(String bandId) async => const BandRecap(
    window: RecapWindow(
      showsAnalyzed: 5,
      scanned: 5,
      truncated: false,
      firstStartsAt: 1774137600000,
      lastStartsAt: 1784419200000,
    ),
    totals: RecapTotals(
      shows: 5,
      reportedRsvps: 202,
      measuredRsvps: 190,
      avgPerShow: 38,
      bestShowRsvps: 56,
      distinctFans: 121,
      followerCount: 184,
    ),
    shows: [
      RecapShow(
        gigId: 'recap-gig-5',
        title: 'Summer Static',
        startsAt: 1784419200000,
        venueName: 'The Knockout',
        price: 18,
        ticketing: Ticketing.external,
        goingCount: 59,
        measuredRsvps: 56,
        newFans: 24,
        returningFans: 32,
      ),
      RecapShow(
        gigId: 'recap-gig-4',
        title: 'No Cover Noise',
        startsAt: 1782604800000,
        venueName: 'Bottom of the Hill',
        price: 0,
        ticketing: Ticketing.rsvp,
        goingCount: 49,
        measuredRsvps: 47,
        newFans: 21,
        returningFans: 26,
      ),
      RecapShow(
        gigId: 'recap-gig-3',
        title: 'Feedback Friday',
        startsAt: 1780185600000,
        venueName: 'Kilowatt',
        price: 12,
        ticketing: Ticketing.external,
        goingCount: 41,
        measuredRsvps: 38,
        newFans: 19,
        returningFans: 19,
      ),
      RecapShow(
        gigId: 'recap-gig-2',
        title: 'Mission Matinee',
        startsAt: 1777161600000,
        venueName: 'The Knockout',
        price: 0,
        ticketing: Ticketing.rsvp,
        goingCount: 30,
        measuredRsvps: 29,
        newFans: 17,
        returningFans: 12,
      ),
      RecapShow(
        gigId: 'recap-gig-1',
        title: 'First Spark',
        startsAt: 1774137600000,
        venueName: 'Bottom of the Hill',
        price: 10,
        ticketing: Ticketing.rsvp,
        goingCount: 23,
        measuredRsvps: 20,
        newFans: 13,
        returningFans: 7,
      ),
    ],
    newReturningSuppressed: false,
    leadTime: RecapLeadTime(
      buckets: [
        RecapBucket(key: 'twoWeeksPlus', count: 36),
        RecapBucket(key: 'oneToTwoWeeks', count: 52),
        RecapBucket(key: 'underWeek', count: 64),
        RecapBucket(key: 'dayOf', count: 32),
      ],
      medianDays: 6.5,
      unmeasurable: 6,
      suppressed: false,
    ),
    venues: RecapVenues(
      rows: [
        RecapVenue(
          venueName: 'The Knockout',
          shows: 2,
          totalRsvps: 85,
          avgRsvps: 42.5,
        ),
        RecapVenue(
          venueName: 'Kilowatt',
          shows: 1,
          totalRsvps: 38,
          avgRsvps: 38,
        ),
        RecapVenue(
          venueName: 'Bottom of the Hill',
          shows: 2,
          totalRsvps: 67,
          avgRsvps: 33.5,
        ),
      ],
      suppressed: false,
    ),
    weekdays: RecapWeekdays(rows: [], suppressed: true),
    repeatFans: RecapRepeatFans(
      tiers: [
        RecapBucket(key: 'one', count: 78),
        RecapBucket(key: 'twoToThree', count: 35),
        RecapBucket(key: 'fourPlus', count: 8),
      ],
      suppressed: false,
    ),
    pricing: RecapPricing(
      freeShows: 0,
      freeAvgRsvps: 0,
      paidShows: 0,
      paidAvgRsvps: 0,
      suppressed: true,
    ),
  );

  @override
  Future<List<Venue>> venues() async =>
      DemoData.venues.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  @override
  Future<VenueDetail?> venueDetail(String venueId) async {
    final venue = DemoData.venues[venueId];
    if (venue == null) return null;
    final gigs =
        [...DemoData.gigs, ..._publishedGigs]
            .where(
              (gig) =>
                  gig.venueId == venueId &&
                  gig.startsAt.isAfter(
                    DateTime.now().subtract(const Duration(hours: 6)),
                  ),
            )
            .toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final bands = <String, Band>{};
    for (final gig in gigs) {
      for (final bandId in gig.lineup) {
        final band = _bands[bandId];
        if (band != null) bands[bandId] = band;
      }
    }
    return VenueDetail(
      venue: venue,
      gigs: gigs,
      bands: bands,
      truncated: false,
    );
  }

  @override
  Future<Band?> band(String bandId) async => _bands[bandId];

  @override
  Future<List<Band>> searchBands(String q) async {
    final normalized = q.toLowerCase();
    return _bands.values
        .where((band) => band.name.toLowerCase().contains(normalized))
        .take(50)
        .toList();
  }

  @override
  Future<BandPage> listBands({String? cursor, int numItems = 50}) async {
    final ordered = _bands.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final requestedStart = int.tryParse(cursor ?? '') ?? 0;
    final start = requestedStart < 0
        ? 0
        : requestedStart > ordered.length
        ? ordered.length
        : requestedStart;
    final requestedEnd = start + numItems;
    final end = requestedEnd < start
        ? start
        : requestedEnd > ordered.length
        ? ordered.length
        : requestedEnd;
    return BandPage(
      items: ordered.sublist(start, end),
      continueCursor: end.toString(),
      isDone: end == ordered.length,
    );
  }

  @override
  Future<void> toggleRsvp(String gigId) async {
    _toggle(_rsvpGigIds, gigId);
    _emitInteractionsIfSignedIn();
  }

  @override
  Future<void> toggleFollow(String bandId) async {
    _toggle(_followBandIds, bandId);
    _emitInteractionsIfSignedIn();
  }

  @override
  Future<void> toggleSave(String gigId) async {
    _toggle(_savedGigIds, gigId);
    _emitInteractionsIfSignedIn();
  }

  @override
  Future<void> setGenres(List<String> genres) async {
    _userGenres
      ..clear()
      ..addAll(genres);
  }

  @override
  Future<void> ensureUser({String? name}) async {
    _userName = name ?? _userName;
  }

  static String _initialsFor(String name) => name
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) => word[0])
      .take(2)
      .join()
      .toUpperCase();

  /// Mirrors the backend: "static-bloom", or "static-bloom-2" when taken.
  String _uniqueSlug(String name) {
    var base = _slugify(name);
    if (base.isEmpty) base = 'band';

    final taken = {
      ..._issuedSlugs,
      for (final band in _bands.values) _slugify(band.name),
    };
    for (var n = 1; ; n++) {
      final candidate = n == 1 ? base : '$base-$n';
      if (!taken.contains(candidate)) {
        _issuedSlugs.add(candidate);
        return candidate;
      }
    }
  }

  final Set<String> _issuedSlugs = {};

  @override
  Future<({String bandId, String slug})> createBand({
    required String name,
    required List<String> genres,
    required String bio,
    required List<String> inviteHandles,
    String? area,
    String? linkIg,
    String? linkBc,
    String? linkYt,
  }) async {
    final id = 'nb${_nextBandId++}';
    final bandName = name.trim();
    final slug = _uniqueSlug(bandName);
    final created = Band(
      id: id,
      name: bandName,
      genres: genres.isEmpty ? const ['punk'] : List<String>.of(genres),
      area: area ?? 'Mission, SF',
      color: const Color(0xFF8FE6C4),
      initials: _initialsFor(bandName),
      followers: 1 + inviteHandles.length,
      bio: bio.isEmpty
          ? 'New band. No recordings yet. Come see us anyway.'
          : bio,
      linkIg: linkIg,
      linkBc: linkBc,
    );

    _bands[id] = created;
    _memberships.add(BandMembership(band: created, role: 'admin'));
    _feedController.add(_currentFeed());
    _bandsController.add(_currentMemberships());
    return (bandId: id, slug: slug);
  }

  @override
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
  }) async {
    final existing = _bands[bandId];
    if (existing == null) return;

    final trimmedName = name?.trim();
    final updated = existing.copyWith(
      name: trimmedName,
      initials: trimmedName == null ? null : _initialsFor(trimmedName),
      genres: genres,
      area: area,
      bio: bio,
      linkIg: linkIg,
      linkBc: linkBc,
    );
    _bands[bandId] = updated;
    for (var i = 0; i < _memberships.length; i++) {
      final membership = _memberships[i];
      if (membership.band.id == bandId) {
        _memberships[i] = BandMembership(band: updated, role: membership.role);
      }
    }
    _feedController.add(_currentFeed());
    _bandsController.add(_currentMemberships());
  }

  @override
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
  }) async {
    final id = 'gx${_nextGigId++}';
    final now = DateTime.now();
    final bandName = _bands[bandId]?.name ?? '';
    _publishedGigs.add(
      Gig(
        id: id,
        title: title,
        venueId: venueId,
        price: price,
        startsAt: DateTime.fromMillisecondsSinceEpoch(startsAt),
        dateShort: Gig.dateShortFor(startsAt),
        dateLine: Gig.dateLineFor(startsAt, doorsTime, now: now),
        time: doorsTime,
        when: Gig.whenFor(startsAt, now: now),
        flyKey: flyKey,
        lineup: [bandId],
        going: 0,
        genres: const ['punk'],
        desc:
            '${ticketing == Ticketing.external ? 'Tickets via external link. ' : 'RSVP in app. '}'
            'Listed by $bandName.',
        tix: ticketing,
        ageRequirement: ageRequirement,
        externalUrl: externalUrl,
        cap: cap,
      ),
    );
    _feedController.add(_currentFeed());
    return id;
  }

  FeedSnapshot _currentFeed() => FeedSnapshot(
    gigs: List<Gig>.unmodifiable([...DemoData.gigs, ..._publishedGigs]),
    venues: DemoData.venues,
    bands: Map<String, Band>.unmodifiable(_bands),
    nextStartsAt: null,
  );

  Interactions _currentInteractions() {
    if (!_auth.signedIn) return Interactions.empty;
    return Interactions(
      rsvpGigIds: Set<String>.unmodifiable(_rsvpGigIds),
      followBandIds: Set<String>.unmodifiable(_followBandIds),
      savedGigIds: Set<String>.unmodifiable(_savedGigIds),
      attendedCount: _attendedCount,
    );
  }

  List<BandMembership> _currentMemberships() =>
      List<BandMembership>.unmodifiable(_memberships);

  Stream<T> _replay<T>(
    StreamController<T> controller,
    T Function() current,
  ) async* {
    yield current();
    yield* controller.stream;
  }

  void _handleSignedInChange(bool signedIn) {
    if (signedIn) _seedInteractions();
    _interactionsController.add(_currentInteractions());
  }

  void _seedInteractions() {
    if (_interactionsSeeded) return;
    _interactionsSeeded = true;
    _rsvpGigIds.add('g5');
    _followBandIds.addAll({'b2', 'b4'});
    _savedGigIds.add('g6');
    _attendedCount = 12;
  }

  void _emitInteractionsIfSignedIn() {
    if (_auth.signedIn) {
      _interactionsController.add(_currentInteractions());
    }
  }

  void _toggle(Set<String> values, String id) {
    values.contains(id) ? values.remove(id) : values.add(id);
  }

  List<BandMedia>? _mediaListContaining(String mediaId) {
    for (final media in _mediaLists.values) {
      if (media.any((item) => item.id == mediaId)) return media;
    }
    return null;
  }
}

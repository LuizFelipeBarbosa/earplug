import 'dart:async';
import 'dart:ui' show Color;

import 'package:latlong2/latlong.dart';

import '../app_links.dart';
import '../band_identity.dart';
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
    _venues = Map<String, Venue>.of(DemoData.venues);
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
  late final Map<String, Venue> _venues;
  late final List<BandMembership> _memberships;
  late final Map<String, List<BandMedia>> _mediaLists;
  final List<Gig> _publishedGigs = [];
  final Map<String, GigProject> _gigProjects = {};
  final Set<String> _rsvpGigIds = {};
  final Set<String> _followBandIds = {};
  final Set<String> _savedGigIds = {};
  final Map<String, RsvpTicket> _ticketsByGigId = {};
  final Set<String> _checkedInGigIds = {};
  final Set<String> _userGenres = {};
  final Map<String, String> _heroByBand = {};
  final Set<String> _previewedBands = {};
  final Map<String, BandInvite> _bandInvites = {};
  final Map<String, Set<String>> _acceptedMemberNames = {};
  final Map<String, DateTime> _archivedBands = {};
  FanOnboarding _fanOnboarding = const FanOnboarding(
    preferredCity: null,
    genreChoice: FanGenreChoice.pending,
    collapsed: false,
  );
  final DateTime _userCreatedAt = DateTime.now();

  String? _userName;
  String? _avatarUrl;
  String? _bio;
  FanCity? _homeLocation;
  bool _locationPersonalizationEnabled = false;
  bool _followedBandUpdatesEnabled = true;
  bool _profileTutorialCompleted = false;
  int _attendedCount = 0;
  int _nextBandId = 1;
  int _nextGigId = 1;
  int _nextGigProjectId = 1;
  int _nextGigPerformerId = 1;
  int _nextMediaId = 1;
  int _nextInviteId = 1;
  int _nextVenueId = 1;
  bool _interactionsSeeded = false;

  /// Nothing to push: the demo data does not check identity.
  @override
  Future<void> refreshAuth() async {}

  @override
  Future<UserProfile?> me() async {
    if (!_auth.signedIn) return null;
    return UserProfile(
      name: _userName ?? _auth.displayName ?? 'Earplug Fan',
      email: '',
      genres: List<String>.unmodifiable(_userGenres),
      attendedCount: _attendedCount,
      createdAt: _userCreatedAt,
      avatarUrl: _avatarUrl,
      bio: _bio,
      homeLocation: _homeLocation,
      locationPersonalizationEnabled: _locationPersonalizationEnabled,
      followedBandUpdatesEnabled: _followedBandUpdatesEnabled,
      profileTutorialCompleted: _profileTutorialCompleted,
      fanOnboarding: _fanOnboarding,
    );
  }

  @override
  Stream<FeedSnapshot> feed() => _replay(_feedController, _currentFeed);

  @override
  Stream<Gig?> publicGig(String ref) => Stream.value(
    [
      ...DemoData.gigs,
      ..._publishedGigs,
    ].where((gig) => gig.id == ref || gig.slug == ref).firstOrNull,
  );

  @override
  Stream<List<Gig>> upcomingGigsForBand(String bandId) {
    return feed().map(
      (snapshot) => [
        for (final gig in snapshot.gigs)
          if (gig.lineup.contains(bandId)) gig,
      ]..sort((a, b) => a.startsAt.compareTo(b.startsAt)),
    );
  }

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
          thumbnailUrl: item.thumbnailUrl,
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
    String? thumbnailStorageId,
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
        thumbnailUrl: thumbnailStorageId == null
            ? null
            : 'demo://thumbnail/$thumbnailStorageId',
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
    _refreshBandReadiness(bandId);
    _feedController.add(_currentFeed());
    _bandsController.add(_currentMemberships());
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
    _refreshBandReadiness(removed.bandId);
    _feedController.add(_currentFeed());
    _bandsController.add(_currentMemberships());
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
    _refreshBandReadiness(bandId);
    _feedController.add(_currentFeed());
    _bandsController.add(_currentMemberships());
  }

  @override
  Future<void> clearBandPhoto(String bandId) async {
    _heroByBand.remove(bandId);
    _refreshBandReadiness(bandId);
    _feedController.add(_currentFeed());
    _bandsController.add(_currentMemberships());
  }

  @override
  Future<List<FanHistoryItem>> history() async {
    if (!_auth.signedIn) return const [];
    final now = DateTime.now();
    return [
      for (final (index, show) in DemoData.fanHistory.indexed)
        FanHistoryItem(
          gigId: 'demo-history-$index',
          title: show.title,
          startsAt: now.subtract(Duration(days: 30 + index * 14)),
          venueName: '',
          bandNames: const [],
          flyKey: 'paper',
          flyerUrl: null,
          status: FanHistoryStatus.rsvped,
        ),
    ];
  }

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
      _venues.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  @override
  Future<VenueCreationResult> createVenue({
    required String bandId,
    required String name,
    required String area,
    required String address,
    required double latitude,
    required double longitude,
  }) async {
    if (!_memberships.any(
      (membership) =>
          membership.band.id == bandId && membership.role == 'admin',
    )) {
      throw StateError('Band admin access required.');
    }
    String normalize(String value) =>
        value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final normalizedName = normalize(name);
    final normalizedArea = normalize(area);
    final normalizedAddress = normalize(address);
    final existing = _venues.values
        .where(
          (venue) =>
              normalize(venue.addr) == normalizedAddress ||
              (normalize(venue.name) == normalizedName &&
                  normalize(venue.area) == normalizedArea),
        )
        .firstOrNull;
    if (existing != null) {
      return VenueCreationResult(venue: existing, created: false);
    }
    final venue = Venue(
      id: 'demo-venue-${_nextVenueId++}',
      name: name.trim(),
      area: area.trim(),
      addr: address.trim(),
      distSF: '—',
      distOak: '—',
      point: LatLng(latitude, longitude),
    );
    _venues[venue.id] = venue;
    _feedController.add(_currentFeed());
    return VenueCreationResult(venue: venue, created: true);
  }

  @override
  Future<VenueDetail?> venueDetail(String venueId) async {
    final venue = _venues[venueId];
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
  Future<Band?> bandBySlug(String slug) async => _bands.values
      .where((band) => band.slug == slug || _slugify(band.name) == slug)
      .firstOrNull;

  @override
  Future<BandProfileDetails> bandProfileDetails(String bandId) async {
    final band = _bands[bandId];
    final names = <String>{
      if (_memberships.any((membership) => membership.band.id == bandId))
        _userName ?? _auth.displayName ?? 'Band admin',
      ...?_acceptedMemberNames[bandId],
    };
    return BandProfileDetails(
      credits: band?.credits,
      linkIg: band?.linkIg,
      linkBc: band?.linkBc,
      linkYt: band?.linkYt,
      memberNames: names.toList(growable: false),
    );
  }

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
    if (!_rsvpGigIds.contains(gigId)) {
      _ticketsByGigId.remove(gigId);
      _checkedInGigIds.remove(gigId);
    }
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
  Future<RsvpTicket> ticketForGig(String gigId) async {
    if (!_rsvpGigIds.contains(gigId)) {
      throw StateError('RSVP before opening your ticket.');
    }
    return _ticketsByGigId.putIfAbsent(
      gigId,
      () => RsvpTicket(payload: 'earplug:ticket:v1:demo-$gigId'),
    );
  }

  @override
  Future<void> ensureRsvp(String gigId) async {
    _rsvpGigIds.add(gigId);
    _emitInteractionsIfSignedIn();
  }

  @override
  Future<void> ensureFollow(String bandId) async {
    _followBandIds.add(bandId);
    _emitInteractionsIfSignedIn();
  }

  @override
  Future<void> ensureSave(String gigId) async {
    _savedGigIds.add(gigId);
    _emitInteractionsIfSignedIn();
  }

  @override
  Future<void> setGenres(List<String> genres) async {
    _userGenres
      ..clear()
      ..addAll(genres);
  }

  @override
  Future<void> updateFanProfile({
    required String name,
    required String? bio,
    required FanCity? homeLocation,
    required List<String> genres,
    required bool locationPersonalizationEnabled,
    required bool followedBandUpdatesEnabled,
  }) async {
    _userName = name;
    _bio = bio;
    _homeLocation = homeLocation;
    _userGenres
      ..clear()
      ..addAll(genres);
    _locationPersonalizationEnabled = locationPersonalizationEnabled;
    _followedBandUpdatesEnabled = followedBandUpdatesEnabled;
  }

  @override
  Future<String> generateAvatarUploadUrl() async => 'demo://avatar-upload';

  @override
  Future<void> setAvatar(String storageId) async {
    _avatarUrl = 'demo://avatar/$storageId';
  }

  @override
  Future<void> clearAvatar() async {
    _avatarUrl = null;
  }

  @override
  Future<void> setProfileTutorialCompleted(bool completed) async {
    _profileTutorialCompleted = completed;
  }

  @override
  Future<void> updateFanOnboarding({
    FanCity? preferredCity,
    FanGenreChoice? genreChoice,
    bool? collapsed,
    List<String>? genres,
  }) async {
    if (genres != null) {
      _userGenres
        ..clear()
        ..addAll(genres);
    }
    _fanOnboarding = FanOnboarding(
      preferredCity: preferredCity ?? _fanOnboarding.preferredCity,
      genreChoice: genreChoice ?? _fanOnboarding.genreChoice,
      collapsed: collapsed ?? _fanOnboarding.collapsed,
    );
  }

  @override
  Future<void> ensureUser({String? name}) async {
    _userName = name ?? _userName;
  }

  @override
  Future<void> deleteCurrentUser() async {}

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
  final Set<String> _issuedGigSlugs = {};

  String _uniqueGigSlug(String title) {
    var base = _slugify(title);
    if (base.isEmpty) base = 'gig';
    final taken = {
      ..._issuedGigSlugs,
      for (final gig in [...DemoData.gigs, ..._publishedGigs])
        if (gig.slug.isNotEmpty) gig.slug,
    };
    for (var suffix = 1; ; suffix++) {
      final candidate = suffix == 1 ? base : '$base-$suffix';
      if (taken.add(candidate)) {
        _issuedGigSlugs.add(candidate);
        return candidate;
      }
    }
  }

  @override
  Future<({Band band, String slug})> createBand({
    required String name,
    required List<String> genres,
    required String bio,
    required String area,
    String? linkIg,
    String? linkBc,
    String? linkYt,
    String? credits,
  }) async {
    final id = 'nb${_nextBandId++}';
    final bandName = name.trim();
    final slug = _uniqueSlug(bandName);
    final created = Band(
      id: id,
      slug: slug,
      name: bandName,
      genres: genres.isEmpty ? const ['punk'] : List<String>.of(genres),
      area: area,
      color: const Color(0xFF8FE6C4),
      initials: bandInitialsFor(bandName),
      followers: 1,
      bio: bio,
      linkIg: linkIg,
      linkBc: linkBc,
      linkYt: linkYt,
      credits: credits,
      profileComplete:
          bandName.isNotEmpty &&
          genres.isNotEmpty &&
          genres.length <= 3 &&
          area.trim().isNotEmpty &&
          bio.trim().isNotEmpty,
    );

    _bands[id] = created;
    _memberships.add(BandMembership(band: created, role: 'admin'));
    _feedController.add(_currentFeed());
    _bandsController.add(_currentMemberships());
    return (band: created, slug: slug);
  }

  @override
  Future<void> updateBandProfile(BandProfileUpdate update) async {
    final existing = _bands[update.bandId];
    if (existing == null) return;

    final trimmedName = update.name.trim();
    final updated = existing.copyWith(
      name: trimmedName,
      initials: bandInitialsFor(trimmedName),
      genres: List<String>.of(update.genres),
      area: update.area.trim(),
      bio: update.bio.trim(),
      linkIg: update.linkIg.trim(),
      linkBc: update.linkBc.trim(),
      linkYt: update.linkYt.trim(),
      credits: update.credits.trim(),
    );
    _bands[update.bandId] = updated;
    _refreshBandReadiness(update.bandId);
    _feedController.add(_currentFeed());
    _bandsController.add(_currentMemberships());
  }

  @override
  Future<BandArchiveResult> archiveBand(String bandId) async {
    final priorArchive = _archivedBands[bandId];
    if (priorArchive != null) {
      return BandArchiveResult(
        bandId: bandId,
        archivedAt: priorArchive,
        alreadyArchived: true,
      );
    }
    final membership = _memberships
        .where(
          (candidate) =>
              candidate.band.id == bandId && candidate.role == 'admin',
        )
        .firstOrNull;
    if (membership == null) throw StateError('Band admin access required.');
    final now = DateTime.now();
    _archivedBands[bandId] = now;
    for (final project in _gigProjects.values.toList()) {
      if (project.bandId == bandId &&
          project.startsAt?.isAfter(now) == true &&
          project.status == GigProjectStatus.published) {
        _gigProjects[project.id] = _copyGigProject(
          project,
          status: GigProjectStatus.cancelled,
        );
      }
    }
    _publishedGigs.removeWhere(
      (gig) => gig.createdByBand == bandId && gig.startsAt.isAfter(now),
    );
    _bandInvites.remove(bandId);
    _followBandIds.remove(bandId);
    _memberships.removeWhere((candidate) => candidate.band.id == bandId);
    _bands.remove(bandId);
    _feedController.add(_currentFeed());
    _bandsController.add(_currentMemberships());
    return BandArchiveResult(
      bandId: bandId,
      archivedAt: now,
      alreadyArchived: false,
    );
  }

  @override
  Future<BandArchiveStatus> bandArchiveStatus(String bandId) async {
    final archivedAt = _archivedBands[bandId];
    if (archivedAt == null && !_bands.containsKey(bandId)) {
      throw StateError('Band not found.');
    }
    return BandArchiveStatus(bandId: bandId, archivedAt: archivedAt);
  }

  @override
  Future<BandSetupStatus> bandSetupStatus(String bandId) async {
    final band = _bands[bandId];
    final media = _mediaLists[bandId] ?? const <BandMedia>[];
    final membershipCount = _memberships
        .where((membership) => membership.band.id == bandId)
        .length;
    return BandSetupStatus(
      profileComplete:
          band != null &&
          band.name.trim().isNotEmpty &&
          band.genres.isNotEmpty &&
          band.genres.length <= 3 &&
          band.area.trim().isNotEmpty &&
          band.bio.trim().isNotEmpty,
      profileImageAdded: _heroByBand.containsKey(bandId),
      musicAdded:
          media.any((item) => item.kind == MediaKind.video) ||
          (band?.linkBc?.trim().isNotEmpty ?? false) ||
          (band?.linkYt?.trim().isNotEmpty ?? false),
      socialLinksAdded: band?.linkIg?.trim().isNotEmpty ?? false,
      firstGigCreated: [
        ...DemoData.gigs,
        ..._publishedGigs,
      ].any((gig) => gig.lineup.contains(bandId)),
      membersInvited:
          membershipCount > 1 ||
          (_acceptedMemberNames[bandId]?.isNotEmpty ?? false),
      publicProfilePreviewed: _previewedBands.contains(bandId),
    );
  }

  @override
  Future<BandDiscoveryReadiness> bandDiscoveryReadiness(
    String bandId, {
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now();
    final band = _bands[bandId];
    final media = _mediaLists[bandId] ?? const <BandMedia>[];
    final gigs =
        [...DemoData.gigs, ..._publishedGigs]
            .where(
              (gig) =>
                  gig.createdByBand == bandId &&
                  !gig.startsAt.isBefore(
                    current.subtract(const Duration(hours: 6)),
                  ),
            )
            .toList()
          ..sort((left, right) => left.startsAt.compareTo(right.startsAt));
    GigProject? projectFor(Gig gig) => _gigProjects.values
        .where((project) => project.publicGigId == gig.id)
        .firstOrNull;
    bool publishedShowReady(Gig gig, GigProject? project) {
      final publicListingReady =
          gig.lifecycle == GigLifecycle.published &&
          gig.createdByBand == bandId &&
          gig.lineup.contains(bandId);
      if (!publicListingReady) return false;
      if (project == null) return gig.discoveryListingReady;
      return project.status == GigProjectStatus.published &&
          project.performers.any(
            (performer) => performer.bandId == project.bandId,
          ) &&
          project.performers.every(
            (performer) => performer.kind != GigPerformerKind.invited,
          );
    }

    bool venuePosterReady(Gig gig, GigProject? project) {
      if (!DemoData.venues.containsKey(gig.venueId)) return false;
      if (gig.flyKey != 'custom') return true;
      return project == null
          ? gig.discoveryListingReady
          : project.overlay && project.flyStorageId != null;
    }

    bool publishedRevisionCurrent(Gig gig, GigProject? project) =>
        project == null
        ? gig.discoveryListingReady
        : project.status == GigProjectStatus.published &&
              project.publishedRevision == project.revision;

    final candidates = [
      for (final gig in gigs) (gig: gig, project: projectFor(gig)),
    ];
    final eligible = candidates
        .where(
          (candidate) =>
              candidate.gig.discoveryListingReady &&
              publishedShowReady(candidate.gig, candidate.project) &&
              venuePosterReady(candidate.gig, candidate.project) &&
              publishedRevisionCurrent(candidate.gig, candidate.project),
        )
        .firstOrNull;
    final relevant = eligible ?? candidates.firstOrNull;
    BandDiscoveryShow? showFor(Gig? gig) {
      if (gig == null) return null;
      final project = projectFor(gig);
      return BandDiscoveryShow(
        gigId: gig.id,
        projectId: project?.id ?? 'demo-${gig.id}',
        title: gig.title,
        startsAt: gig.startsAt,
      );
    }

    final eligibleShow = showFor(eligible?.gig);
    final opensAt = eligibleShow?.startsAt.subtract(const Duration(days: 7));
    final closesAt = eligibleShow?.startsAt.add(const Duration(hours: 6));
    final profileComplete = band?.profileComplete ?? false;
    final profileImageReady = _heroByBand.containsKey(bandId);
    final clipReady = media.any((item) => item.kind == MediaKind.video);
    return BandDiscoveryReadiness(
      profileComplete: profileComplete,
      profileImageReady: profileImageReady,
      clipReady: clipReady,
      publishedShowReady: relevant != null
          ? publishedShowReady(relevant.gig, relevant.project)
          : false,
      venuePosterReady: relevant != null
          ? venuePosterReady(relevant.gig, relevant.project)
          : false,
      publishedRevisionCurrent: relevant != null
          ? publishedRevisionCurrent(relevant.gig, relevant.project)
          : false,
      relevantShow: showFor(relevant?.gig),
      nextEligibleShow: eligibleShow,
      boostWindow: opensAt == null || closesAt == null
          ? null
          : DiscoveryBoostWindow(
              opensAt: opensAt,
              closesAt: closesAt,
              active:
                  profileComplete &&
                  profileImageReady &&
                  clipReady &&
                  !current.isBefore(opensAt) &&
                  !current.isAfter(closesAt),
            ),
    );
  }

  @override
  Future<void> markBandPreviewed(String bandId) async {
    _previewedBands.add(bandId);
  }

  @override
  Future<BandInvite?> bandInvite(String bandId) async => _bandInvites[bandId];

  BandInvite _newInvite(String bandId) {
    final invite = BandInvite(
      bandId: bandId,
      token: 'demo-invite-${_nextInviteId++}',
      expiresAt: DateTime.now().add(const Duration(days: 7)),
      revoked: false,
      expired: false,
    );
    _bandInvites[bandId] = invite;
    return invite;
  }

  @override
  Future<BandInvite> createBandInvite(String bandId) async {
    final current = _bandInvites[bandId];
    if (current != null &&
        !current.revoked &&
        !current.expired &&
        current.expiresAt.isAfter(DateTime.now())) {
      return current;
    }
    return _newInvite(bandId);
  }

  @override
  Future<BandInvite> rotateBandInvite(String bandId) async =>
      _newInvite(bandId);

  @override
  Future<void> revokeBandInvite(String bandId) async {
    final invite = _bandInvites[bandId];
    if (invite == null) return;
    _bandInvites[bandId] = BandInvite(
      bandId: invite.bandId,
      token: invite.token,
      expiresAt: invite.expiresAt,
      revoked: true,
      expired: invite.expired,
    );
  }

  @override
  Future<BandInviteResolution?> resolveBandInvite(String token) async {
    final invite = _bandInvites.values
        .where((candidate) => candidate.token == token)
        .firstOrNull;
    if (invite == null ||
        invite.revoked ||
        invite.expired ||
        !invite.expiresAt.isAfter(DateTime.now())) {
      return null;
    }
    final band = _bands[invite.bandId];
    if (band == null) return null;
    return BandInviteResolution(
      bandId: band.id,
      bandName: band.name,
      initials: band.initials,
      color: band.color,
    );
  }

  @override
  Future<BandInviteAcceptance> acceptBandInvite(String token) async {
    if (!_auth.signedIn) throw StateError('Not signed in.');
    final resolved = await resolveBandInvite(token);
    if (resolved == null) throw StateError('Invitation is no longer active.');
    final existingMembership = _memberships.any(
      (membership) => membership.band.id == resolved.bandId,
    );
    if (existingMembership) {
      return BandInviteAcceptance(
        bandId: resolved.bandId,
        membershipCreated: false,
      );
    }

    final band = _bands[resolved.bandId];
    if (band == null) throw StateError('Invitation is no longer active.');
    final name = _userName ?? _auth.displayName ?? 'Band member';
    _acceptedMemberNames
        .putIfAbsent(resolved.bandId, () => <String>{})
        .add(name);
    final updatedBand = band.copyWith(followers: band.followers + 1);
    _bands[band.id] = updatedBand;
    _memberships.add(BandMembership(band: updatedBand, role: 'member'));
    _feedController.add(_currentFeed());
    _bandsController.add(_currentMemberships());
    return BandInviteAcceptance(
      bandId: resolved.bandId,
      membershipCreated: true,
    );
  }

  @override
  Future<PerformerInviteResolution?> resolvePerformerInvite(
    String token,
  ) async {
    for (final project in _gigProjects.values) {
      for (final performer in project.performers) {
        if (performer.kind == GigPerformerKind.invited &&
            performer.inviteUrl?.endsWith('/$token') == true) {
          return PerformerInviteResolution(
            performerName: performer.name,
            gigTitle: project.title ?? 'Untitled gig',
          );
        }
      }
    }
    return null;
  }

  @override
  Future<String> claimPerformerInvite({
    required String token,
    required String bandId,
  }) async {
    if (!_auth.signedIn) throw StateError('Not signed in.');
    final band = _bands[bandId];
    if (band == null) throw StateError('Band not found.');
    for (final project in _gigProjects.values) {
      final invited = project.performers.where(
        (performer) =>
            performer.kind == GigPerformerKind.invited &&
            performer.inviteUrl?.endsWith('/$token') == true,
      );
      if (invited.isEmpty) continue;
      final performerId = invited.first.id;
      _replaceGigProject(
        project,
        performers: [
          for (final performer in project.performers)
            if (performer.id == performerId)
              GigPerformer(
                id: performer.id,
                kind: GigPerformerKind.band,
                name: band.name,
                role: performer.role,
                bandId: band.id,
              )
            else
              performer,
        ],
      );
      return project.id;
    }
    throw StateError('Invitation is no longer active.');
  }

  @override
  Future<List<GigProject>> manageGigs(String bandId) async => [
    for (final project in _gigProjects.values)
      if (project.bandId == bandId &&
          project.status != GigProjectStatus.deleted)
        project,
  ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<GigProject> createGigDraft(String bandId) async {
    final now = DateTime.now();
    final project = GigProject(
      id: 'gdp${_nextGigProjectId++}',
      bandId: bandId,
      status: GigProjectStatus.draft,
      revision: 1,
      price: 0,
      flyKey: 'xerox',
      overlay: true,
      desc: '',
      ticketing: Ticketing.rsvp,
      ageRequirement: AgeRequirement.allAges,
      cap: 'No cap',
      updatedAt: now,
      performers: [
        GigPerformer(
          id: 'gpf${_nextGigPerformerId++}',
          kind: GigPerformerKind.band,
          name: _bands[bandId]?.name ?? 'Your band',
          role: GigPerformerRole.headliner,
          bandId: bandId,
        ),
      ],
    );
    _gigProjects[project.id] = project;
    return project;
  }

  @override
  Future<GigProject> getGigProject(String projectId) async =>
      _requireGigProject(projectId);

  @override
  Future<int> saveGigDraft({
    required String projectId,
    required int revision,
    required String? title,
    required DateTime? doorsAt,
    required DateTime? startsAt,
    required String? venueId,
    required int price,
    required String flyKey,
    required String? flyStorageId,
    required bool overlay,
    required String desc,
    required Ticketing ticketing,
    required AgeRequirement ageRequirement,
    required String? externalUrl,
    required String cap,
  }) async {
    final project = _requireGigProject(projectId);
    if (project.revision != revision) {
      throw Exception('Draft changed elsewhere');
    }
    final updated = GigProject(
      id: project.id,
      bandId: project.bandId,
      publicGigId: project.publicGigId,
      publicSlug: project.publicSlug,
      status: project.status,
      revision: revision + 1,
      publishedRevision: project.publishedRevision,
      title: title?.trim().isEmpty == true ? null : title?.trim(),
      doorsAt: doorsAt,
      startsAt: startsAt,
      venueId: venueId,
      price: price,
      flyKey: flyKey,
      flyStorageId: flyStorageId,
      flyerUrl: flyStorageId == null ? null : 'demo://flyer/$flyStorageId',
      overlay: overlay,
      desc: desc,
      ticketing: ticketing,
      ageRequirement: ageRequirement,
      externalUrl: externalUrl,
      cap: cap,
      updatedAt: DateTime.now(),
      performers: project.performers,
    );
    _gigProjects[projectId] = updated;
    _markDemoProjectListingStale(project);
    return updated.revision;
  }

  @override
  Future<GigProject> addGigPerformer({
    required String projectId,
    required GigPerformerKind kind,
    required GigPerformerRole role,
    String? name,
    String? bandId,
  }) async {
    final project = _requireGigProject(projectId);
    final band = bandId == null ? null : _bands[bandId];
    final performer = GigPerformer(
      id: 'gpf${_nextGigPerformerId++}',
      kind: kind,
      name: band?.name ?? name?.trim() ?? '',
      role: role,
      bandId: bandId,
      inviteUrl: kind == GigPerformerKind.invited
          ? publicWebUrl('gig-invite/demo-${_nextInviteId++}')
          : null,
    );
    return _replaceGigProject(
      project,
      performers: [...project.performers, performer],
    );
  }

  @override
  Future<GigProject> updateGigPerformer({
    required String performerId,
    String? name,
    GigPerformerRole? role,
  }) async {
    final project = _projectForPerformer(performerId);
    return _replaceGigProject(
      project,
      performers: [
        for (final performer in project.performers)
          if (performer.id == performerId)
            GigPerformer(
              id: performer.id,
              kind: performer.kind,
              name: name?.trim() ?? performer.name,
              role: role ?? performer.role,
              bandId: performer.bandId,
              inviteUrl: performer.inviteUrl,
            )
          else
            performer,
      ],
    );
  }

  @override
  Future<GigProject> removeGigPerformer(String performerId) async {
    final project = _projectForPerformer(performerId);
    return _replaceGigProject(
      project,
      performers: project.performers
          .where((performer) => performer.id != performerId)
          .toList(),
    );
  }

  @override
  Future<GigProject> reorderGigPerformers(
    String projectId,
    List<String> performerIds,
  ) async {
    final project = _requireGigProject(projectId);
    final byId = {
      for (final performer in project.performers) performer.id: performer,
    };
    return _replaceGigProject(
      project,
      performers: [for (final id in performerIds) byId[id]!],
    );
  }

  @override
  Future<String> publishGigDraft(String projectId) async {
    final project = _requireGigProject(projectId);
    final startsAt = project.startsAt;
    final doorsAt = project.doorsAt;
    if (project.title == null ||
        startsAt == null ||
        doorsAt == null ||
        project.venueId == null ||
        project.performers.isEmpty) {
      throw Exception('Gig is incomplete');
    }
    final gigId = project.publicGigId ?? 'gx${_nextGigId++}';
    final slug = project.publicSlug ?? _uniqueGigSlug(project.title!);
    final time = '${_demoTimeLabel(doorsAt)} / ${_demoTimeLabel(startsAt)}';
    final gig = Gig(
      id: gigId,
      slug: slug,
      title: project.title!,
      venueId: project.venueId!,
      price: project.price,
      startsAt: startsAt,
      doorsAt: doorsAt,
      dateShort: Gig.dateShortFor(startsAt.millisecondsSinceEpoch),
      dateLine: Gig.dateLineFor(startsAt.millisecondsSinceEpoch, time),
      time: time,
      when: Gig.whenFor(startsAt.millisecondsSinceEpoch),
      flyKey: project.flyKey,
      lineup: [
        for (final performer in project.performers)
          if (performer.bandId != null) performer.bandId!,
      ],
      performers: project.performers,
      going:
          _publishedGigs
              .where((gig) => gig.id == gigId)
              .map((gig) => gig.going)
              .firstOrNull ??
          0,
      genres: const ['punk'],
      desc: project.desc,
      tix: project.ticketing,
      externalUrl: project.externalUrl,
      flyerUrl: project.flyerUrl,
      cap: project.cap,
      ageRequirement: project.ageRequirement,
      createdByBand: project.bandId,
      discoveryListingReady:
          project.performers.any(
            (performer) => performer.bandId == project.bandId,
          ) &&
          project.performers.every(
            (performer) => performer.kind != GigPerformerKind.invited,
          ) &&
          DemoData.venues.containsKey(project.venueId) &&
          (project.flyKey != 'custom' ||
              (project.overlay && project.flyStorageId != null)),
    );
    _publishedGigs.removeWhere((gig) => gig.id == gigId);
    _publishedGigs.add(gig);
    _gigProjects[project.id] = _copyGigProject(
      project,
      status: GigProjectStatus.published,
      publicGigId: gigId,
      publicSlug: slug,
      publishedRevision: project.revision,
    );
    _feedController.add(_currentFeed());
    return gigId;
  }

  @override
  Future<GigProject> duplicateGig(String projectId) async {
    final source = _requireGigProject(projectId);
    final duplicate = GigProject(
      id: 'gdp${_nextGigProjectId++}',
      bandId: source.bandId,
      status: GigProjectStatus.draft,
      revision: 1,
      title: source.title == null ? null : 'Copy of ${source.title}',
      doorsAt: source.doorsAt,
      startsAt: source.startsAt,
      venueId: source.venueId,
      price: source.price,
      flyKey: source.flyKey,
      flyStorageId: source.flyStorageId,
      flyerUrl: source.flyerUrl,
      overlay: source.overlay,
      desc: source.desc,
      ticketing: source.ticketing,
      ageRequirement: source.ageRequirement,
      externalUrl: source.externalUrl,
      cap: source.cap,
      updatedAt: DateTime.now(),
      performers: [
        for (final performer in source.performers)
          GigPerformer(
            id: 'gpf${_nextGigPerformerId++}',
            kind: performer.kind == GigPerformerKind.invited
                ? GigPerformerKind.text
                : performer.kind,
            name: performer.name,
            role: performer.role,
            bandId: performer.bandId,
          ),
      ],
    );
    _gigProjects[duplicate.id] = duplicate;
    return duplicate;
  }

  @override
  Future<void> unpublishGig(String projectId) async {
    final project = _requireGigProject(projectId);
    _gigProjects[projectId] = _copyGigProject(
      project,
      status: GigProjectStatus.draft,
    );
    _publishedGigs.removeWhere((gig) => gig.id == project.publicGigId);
    _feedController.add(_currentFeed());
  }

  @override
  Future<void> cancelGig(String projectId) async {
    final project = _requireGigProject(projectId);
    _gigProjects[projectId] = _copyGigProject(
      project,
      status: GigProjectStatus.cancelled,
    );
    _publishedGigs.removeWhere((gig) => gig.id == project.publicGigId);
    _feedController.add(_currentFeed());
  }

  @override
  Future<void> deleteGig(String projectId) async {
    final project = _requireGigProject(projectId);
    _publishedGigs.removeWhere((gig) => gig.id == project.publicGigId);
    _gigProjects.remove(projectId);
    _feedController.add(_currentFeed());
  }

  @override
  Future<DoorRoster> doorRoster(String projectId) async {
    final project = _requireGigProject(projectId);
    final gigId = project.publicGigId;
    if (gigId == null || project.ticketing != Ticketing.rsvp) {
      throw StateError('Door Mode is available only for in-app RSVP gigs.');
    }
    return DoorRoster(
      total: _rsvpGigIds.contains(gigId) ? 1 : 0,
      checkedIn: _checkedInGigIds.contains(gigId) ? 1 : 0,
      truncated: false,
    );
  }

  @override
  Future<DoorCheckInResult> checkInTicket({
    required String projectId,
    required String payload,
  }) async {
    final project = _requireGigProject(projectId);
    final gigId = project.publicGigId;
    if (gigId == null || payload != 'earplug:ticket:v1:demo-$gigId') {
      final belongsToAnotherGig = payload.startsWith('earplug:ticket:v1:demo-');
      return DoorCheckInResult(
        status: belongsToAnotherGig
            ? DoorCheckInStatus.wrongGig
            : DoorCheckInStatus.invalid,
      );
    }
    if (!_rsvpGigIds.contains(gigId)) {
      return const DoorCheckInResult(status: DoorCheckInStatus.invalid);
    }
    if (!_checkedInGigIds.add(gigId)) {
      return DoorCheckInResult(
        status: DoorCheckInStatus.alreadyCheckedIn,
        fanName: _userName ?? 'Earplug Fan',
        checkedInAt: DateTime.now(),
      );
    }
    return DoorCheckInResult(
      status: DoorCheckInStatus.checkedIn,
      fanName: _userName ?? 'Earplug Fan',
      checkedInAt: DateTime.now(),
    );
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
    final slug = _uniqueGigSlug(title);
    final now = DateTime.now();
    final bandName = _bands[bandId]?.name ?? '';
    _publishedGigs.add(
      Gig(
        id: id,
        slug: slug,
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
        createdByBand: bandId,
        discoveryListingReady:
            DemoData.venues.containsKey(venueId) &&
            (flyKey != 'custom' || flyStorageId != null),
      ),
    );
    _feedController.add(_currentFeed());
    return id;
  }

  GigProject _requireGigProject(String projectId) {
    final project = _gigProjects[projectId];
    if (project == null) throw Exception('Gig draft not found');
    return project;
  }

  GigProject _projectForPerformer(String performerId) {
    for (final project in _gigProjects.values) {
      if (project.performers.any((performer) => performer.id == performerId)) {
        return project;
      }
    }
    throw Exception('Performer not found');
  }

  GigProject _replaceGigProject(
    GigProject project, {
    required List<GigPerformer> performers,
  }) {
    final updated = _copyGigProject(
      project,
      revision: project.revision + 1,
      performers: performers,
    );
    _gigProjects[project.id] = updated;
    _markDemoProjectListingStale(project);
    return updated;
  }

  void _markDemoProjectListingStale(GigProject project) {
    if (project.status != GigProjectStatus.published ||
        project.publicGigId == null) {
      return;
    }
    final index = _publishedGigs.indexWhere(
      (gig) => gig.id == project.publicGigId,
    );
    if (index == -1) return;
    _publishedGigs[index] = _publishedGigs[index].copyWith(
      discoveryListingReady: false,
    );
    _feedController.add(_currentFeed());
  }

  GigProject _copyGigProject(
    GigProject project, {
    GigProjectStatus? status,
    int? revision,
    int? publishedRevision,
    String? publicGigId,
    String? publicSlug,
    List<GigPerformer>? performers,
  }) => GigProject(
    id: project.id,
    bandId: project.bandId,
    publicGigId: publicGigId ?? project.publicGigId,
    publicSlug: publicSlug ?? project.publicSlug,
    status: status ?? project.status,
    revision: revision ?? project.revision,
    publishedRevision: publishedRevision ?? project.publishedRevision,
    title: project.title,
    doorsAt: project.doorsAt,
    startsAt: project.startsAt,
    venueId: project.venueId,
    price: project.price,
    flyKey: project.flyKey,
    flyStorageId: project.flyStorageId,
    flyerUrl: project.flyerUrl,
    overlay: project.overlay,
    desc: project.desc,
    ticketing: project.ticketing,
    ageRequirement: project.ageRequirement,
    externalUrl: project.externalUrl,
    cap: project.cap,
    updatedAt: DateTime.now(),
    performers: performers ?? project.performers,
  );

  FeedSnapshot _currentFeed() => FeedSnapshot(
    gigs: List<Gig>.unmodifiable([...DemoData.gigs, ..._publishedGigs]),
    venues: Map<String, Venue>.unmodifiable(_venues),
    bands: Map<String, Band>.unmodifiable(_bands),
    nextStartsAt: null,
  );

  void _refreshBandReadiness(String bandId) {
    final band = _bands[bandId];
    if (band == null) return;
    final profileComplete =
        band.name.trim().isNotEmpty &&
        band.genres.isNotEmpty &&
        band.genres.length <= 3 &&
        band.genres.every((genre) => genre.trim().isNotEmpty) &&
        band.area.trim().isNotEmpty &&
        band.bio.trim().isNotEmpty;
    final updated = band.copyWith(
      profileComplete: profileComplete,
      discoveryProfileReady:
          profileComplete &&
          _heroByBand.containsKey(bandId) &&
          (_mediaLists[bandId] ?? const <BandMedia>[]).any(
            (item) => item.kind == MediaKind.video,
          ),
    );
    _bands[bandId] = updated;
    for (var index = 0; index < _memberships.length; index++) {
      final membership = _memberships[index];
      if (membership.band.id == bandId) {
        _memberships[index] = BandMembership(
          band: updated,
          role: membership.role,
        );
      }
    }
  }

  Interactions _currentInteractions() {
    if (!_auth.signedIn) return Interactions.empty;
    final cutoff = DateTime.now().subtract(const Duration(hours: 6));
    final gigsById = {
      for (final gig in [...DemoData.gigs, ..._publishedGigs])
        if (!gig.startsAt.isBefore(cutoff)) gig.id: gig,
    };
    return Interactions(
      rsvpGigIds: Set<String>.unmodifiable(_rsvpGigIds),
      followBandIds: Set<String>.unmodifiable(_followBandIds),
      savedGigIds: Set<String>.unmodifiable(_savedGigIds),
      gigs: List<Gig>.unmodifiable([
        for (final id in {..._rsvpGigIds, ..._savedGigIds}) ?gigsById[id],
      ]),
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

String _demoTimeLabel(DateTime time) {
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minutes = time.minute == 0
      ? ''
      : ':${time.minute.toString().padLeft(2, '0')}';
  return '$hour$minutes${time.hour < 12 ? 'AM' : 'PM'}';
}

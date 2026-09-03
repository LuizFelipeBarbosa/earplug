import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:latlong2/latlong.dart';

import '../app_links.dart';
import '../band_identity.dart';
import '../date_names.dart';
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
    _venuePrivateDetails = Map<String, VenuePrivateDetails>.of(
      DemoData.venuePrivateDetails,
    );
    _organizations = Map<String, Organization>.of(DemoData.organizations);
    _organizationMemberships = [
      OrganizationMembership(
        organization: _organizations['org1']!,
        role: OrganizationRole.owner,
      ),
    ];
    _organizationMembers = {
      'org1': Map<String, OrganizationMember>.of(DemoData.organizationMembers),
    };
    _organizationPrivateDetails = {
      'org1': const OrganizationPrivateDetails(
        legalName: 'The Foghorn Club LLC',
        businessEmail: 'hello@foghorn.example',
        contactName: 'Earplug Fan',
        phone: '415-555-0142',
      ),
    };
    _organizationApplications = {
      DemoData.submittedOrganizationApplication.id:
          DemoData.submittedOrganizationApplication,
    };
    _applicationApplicants = {
      DemoData.submittedOrganizationApplication.id: (
        userId: 'applicant-sam',
        name: 'Sam Reyes',
        email: 'sam@example.com',
      ),
    };
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
  final StreamController<Map<String, int>> _goingCountsController =
      StreamController<Map<String, int>>.broadcast();
  final StreamController<List<BandMembership>> _bandsController =
      StreamController<List<BandMembership>>.broadcast();
  final StreamController<List<OrganizationMembership>>
  _organizationsController =
      StreamController<List<OrganizationMembership>>.broadcast();

  late final Map<String, Band> _bands;
  late final Map<String, Venue> _venues;
  late final Map<String, VenuePrivateDetails> _venuePrivateDetails;
  late final Map<String, Organization> _organizations;
  late final List<OrganizationMembership> _organizationMemberships;
  late final Map<String, Map<String, OrganizationMember>> _organizationMembers;
  late final Map<String, OrganizationPrivateDetails>
  _organizationPrivateDetails;
  late final Map<String, OrganizationApplication> _organizationApplications;
  late final Map<String, ({String userId, String name, String email})>
  _applicationApplicants;
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
  final Map<String, String> _avatarByBand = {};
  final Set<String> _previewedBands = {};
  final Map<String, BandInvite> _bandInvites = {};
  final Map<String, OrganizationInvite> _organizationInvites = {};
  final Map<String, String> _venueDescriptions = {};
  final Map<String, VenueType> _venueTypes = {};
  final Map<String, int> _venuePublicCapacities = {};
  final Map<String, List<String>> _venuePhotoStorageIds = {};
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
  int _nextOrganizationId = 1;
  int _nextOrganizationApplicationId = 1;
  int _nextOrganizationInviteId = 1;
  bool _interactionsSeeded = false;
  Map<String, int> _lastGoingCounts = const {};
  String? _myOrganizationApplicationId;

  bool platformAdmin = false;

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
  Stream<Map<String, int>> goingCounts() =>
      _replay(_goingCountsController, _currentGoingCounts);

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
          isAvatar: _avatarByBand[bandId] == item.id,
          isBanner: _heroByBand[bandId] == item.id,
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
    _emitFeed();
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
    if (_avatarByBand[removed.bandId] == mediaId) {
      _avatarByBand.remove(removed.bandId);
    }
    _refreshBandReadiness(removed.bandId);
    _emitFeed();
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
  Future<void> moveMediaWithinKind(String mediaId, String direction) =>
      moveBandMedia(mediaId, direction == 'earlier' ? 'up' : 'down');

  void _requireOwnedPhoto(String bandId, String mediaId) {
    final media = _mediaListContaining(mediaId);
    final targetIndex = media?.indexWhere((item) => item.id == mediaId) ?? -1;
    final target = targetIndex == -1 ? null : media![targetIndex];
    if (target == null ||
        target.kind != MediaKind.photo ||
        target.bandId != bandId) {
      throw StateError('Band photo must be a photo owned by the same band.');
    }
  }

  @override
  Future<void> setBandAvatar({
    required String bandId,
    required String mediaId,
  }) async {
    _requireOwnedPhoto(bandId, mediaId);
    _avatarByBand[bandId] = mediaId;
    _refreshBandReadiness(bandId);
    _emitFeed();
    _bandsController.add(_currentMemberships());
  }

  @override
  Future<void> clearBandAvatar(String bandId) async {
    _avatarByBand.remove(bandId);
    _refreshBandReadiness(bandId);
    _emitFeed();
    _bandsController.add(_currentMemberships());
  }

  @override
  Future<void> setBandBanner({
    required String bandId,
    required String mediaId,
  }) async {
    _requireOwnedPhoto(bandId, mediaId);
    _heroByBand[bandId] = mediaId;
    _emitFeed();
    _bandsController.add(_currentMemberships());
  }

  @override
  Future<void> clearBandBanner(String bandId) async {
    _heroByBand.remove(bandId);
    _emitFeed();
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
      point: LatLng(latitude, longitude),
    );
    _venues[venue.id] = venue;
    _emitFeed();
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
  Future<OrganizationApplication?> myOrganizationApplication() async {
    final applicationId = _myOrganizationApplicationId;
    return applicationId == null
        ? null
        : _organizationApplications[applicationId];
  }

  @override
  Future<({String applicationId, int revision})>
  saveOrganizationApplicationDraft({
    String? applicationId,
    int? expectedRevision,
    required String orgName,
    required OrganizationType orgType,
    String? website,
    required String contactName,
    required String businessEmail,
    String? phone,
    ApplicationVenueDraft? venue,
  }) async {
    final existing = applicationId == null
        ? null
        : _organizationApplications[applicationId];
    if (existing != null && existing.revision != expectedRevision) {
      throw StateError('Application changed elsewhere');
    }
    if (existing == null && applicationId != null) {
      throw StateError('Application changed elsewhere');
    }

    final now = DateTime.now();
    final id =
        applicationId ?? 'demo-application-${_nextOrganizationApplicationId++}';
    final application = OrganizationApplication(
      id: id,
      status: existing?.status == OrganizationApplicationStatus.needsInfo
          ? OrganizationApplicationStatus.needsInfo
          : OrganizationApplicationStatus.draft,
      orgName: orgName,
      orgType: orgType,
      website: website,
      contactName: contactName,
      businessEmail: businessEmail,
      phone: phone,
      venue: venue,
      documents: existing?.documents ?? const [],
      reviewNote: existing?.reviewNote,
      decidedAt: existing?.decidedAt,
      resultingOrganizationId: existing?.resultingOrganizationId,
      resultingVenueId: existing?.resultingVenueId,
      revision: (existing?.revision ?? 0) + 1,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    _organizationApplications[id] = application;
    _myOrganizationApplicationId = id;
    _applicationApplicants.putIfAbsent(
      id,
      () => (
        userId: DemoData.demoUserId,
        name: _userName ?? _auth.displayName ?? 'Earplug Fan',
        email: '',
      ),
    );
    return (applicationId: id, revision: application.revision);
  }

  @override
  Future<int> submitOrganizationApplication({
    required String applicationId,
    required int expectedRevision,
  }) async {
    final application = _requireOrganizationApplication(applicationId);
    _checkApplicationRevision(application, expectedRevision);
    final updated = _copyOrganizationApplication(
      application,
      status: OrganizationApplicationStatus.submitted,
      revision: application.revision + 1,
      updatedAt: DateTime.now(),
    );
    _organizationApplications[applicationId] = updated;
    return updated.revision;
  }

  @override
  Future<void> withdrawOrganizationApplication(String applicationId) async {
    final application = _requireOrganizationApplication(applicationId);
    _organizationApplications[applicationId] = _copyOrganizationApplication(
      application,
      status: OrganizationApplicationStatus.withdrawn,
      revision: application.revision + 1,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<String> generateApplicationDocumentUploadUrl() async =>
      'demo://organization-application-upload';

  @override
  Future<int> attachApplicationDocument({
    required String applicationId,
    required String storageId,
  }) async {
    final application = _requireOrganizationApplication(applicationId);
    final documents = [
      ...application.documents.where(
        (document) => document.storageId != storageId,
      ),
      ApplicationDocument(
        storageId: storageId,
        url: 'demo://organization-application-document/$storageId',
      ),
    ];
    final updated = _copyOrganizationApplication(
      application,
      documents: documents,
      revision: application.revision + 1,
      updatedAt: DateTime.now(),
    );
    _organizationApplications[applicationId] = updated;
    return updated.revision;
  }

  @override
  Future<int> removeApplicationDocument({
    required String applicationId,
    required String storageId,
  }) async {
    final application = _requireOrganizationApplication(applicationId);
    final updated = _copyOrganizationApplication(
      application,
      documents: application.documents
          .where((document) => document.storageId != storageId)
          .toList(),
      revision: application.revision + 1,
      updatedAt: DateTime.now(),
    );
    _organizationApplications[applicationId] = updated;
    return updated.revision;
  }

  @override
  Future<OrganizationApplication?> organizationApplication(
    String applicationId,
  ) async => _organizationApplications[applicationId];

  @override
  Future<AdminApplicationPage> applicationsForReview({
    OrganizationApplicationStatus? status,
    String? cursor,
    int numItems = 25,
  }) async {
    final rows = <AdminApplicationRow>[];
    for (final application in _organizationApplications.values) {
      if (status != null && application.status != status) continue;
      if (application.status == OrganizationApplicationStatus.draft) continue;
      final applicant = _applicationApplicants[application.id];
      rows.add(
        AdminApplicationRow(
          application: application,
          applicantUserId: applicant?.userId ?? '',
          applicantName: applicant?.name ?? '',
          applicantEmail: applicant?.email ?? '',
        ),
      );
    }
    rows.sort(
      (left, right) =>
          right.application.createdAt.compareTo(left.application.createdAt),
    );
    final start = (int.tryParse(cursor ?? '') ?? 0).clamp(0, rows.length);
    final end = (start + numItems).clamp(start, rows.length);
    return AdminApplicationPage(
      items: rows.sublist(start, end),
      continueCursor: end.toString(),
      isDone: end == rows.length,
    );
  }

  @override
  Future<
    ({
      OrganizationApplicationStatus status,
      String? organizationId,
      String? venueId,
    })
  >
  decideOrganizationApplication({
    required String applicationId,
    required ApplicationDecision decision,
    String? note,
  }) async {
    if (!platformAdmin) throw StateError('Platform admin access required.');
    final application = _requireOrganizationApplication(applicationId);
    final status = switch (decision) {
      ApplicationDecision.underReview =>
        OrganizationApplicationStatus.underReview,
      ApplicationDecision.needsInfo => OrganizationApplicationStatus.needsInfo,
      ApplicationDecision.approved => OrganizationApplicationStatus.approved,
      ApplicationDecision.rejected => OrganizationApplicationStatus.rejected,
    };

    String? organizationId = application.resultingOrganizationId;
    String? venueId = application.resultingVenueId;
    if (decision == ApplicationDecision.approved && organizationId == null) {
      organizationId = 'demo-organization-${_nextOrganizationId++}';
      final organization = Organization(
        id: organizationId,
        slug: _uniqueOrganizationSlug(application.orgName),
        name: application.orgName,
        orgType: application.orgType,
        status: OrganizationStatus.verified,
        verified: true,
        website: application.website,
        photoUrls: const [],
        createdAt: DateTime.now(),
      );
      _organizations[organizationId] = organization;
      _organizationPrivateDetails[organizationId] = OrganizationPrivateDetails(
        businessEmail: application.businessEmail,
        contactName: application.contactName,
        phone: application.phone,
      );

      final venueDraft = application.venue;
      if (venueDraft != null) {
        venueId = 'demo-venue-${_nextVenueId++}';
        final approx = ApproxLocation(
          centroid: venueDraft.point,
          label: venueDraft.area,
        );
        _venues[venueId] = Venue(
          id: venueId,
          name: venueDraft.name,
          area: approx.label,
          addr: approx.label,
          point: approx.centroid,
          slug: _uniqueVenueSlug(venueDraft.name),
          approx: approx,
          neighborhood: venueDraft.neighborhood,
          city: venueDraft.city,
          disclosure: AddressDisclosure.onTicket,
          verified: true,
          managedByOrganizationId: organizationId,
          supportsApproxLocation: true,
        );
        _venuePrivateDetails[venueId] = VenuePrivateDetails(
          venueId: venueId,
          addr: venueDraft.addr,
          point: venueDraft.point,
          capacity: venueDraft.capacity,
        );
        if (venueDraft.venueType case final type?) {
          _venueTypes[venueId] = type;
        }
      }

      if (_myOrganizationApplicationId == applicationId) {
        _organizationMemberships.add(
          OrganizationMembership(
            organization: organization,
            role: OrganizationRole.owner,
          ),
        );
        _organizationMembers[organizationId] = {
          DemoData.demoUserId: OrganizationMember(
            userId: DemoData.demoUserId,
            name: _userName ?? _auth.displayName ?? 'Earplug Fan',
            email: '',
            role: OrganizationRole.owner,
            createdAt: DateTime.now(),
          ),
        };
      }
      _emitOrganizations();
      _emitFeed();
    }

    final decidedAt = switch (decision) {
      ApplicationDecision.approved ||
      ApplicationDecision.rejected => DateTime.now(),
      _ => null,
    };
    final updated = _copyOrganizationApplication(
      application,
      status: status,
      reviewNote: note,
      decidedAt: decidedAt,
      resultingOrganizationId: organizationId,
      resultingVenueId: venueId,
      revision: application.revision + 1,
      updatedAt: DateTime.now(),
    );
    _organizationApplications[applicationId] = updated;
    return (status: status, organizationId: organizationId, venueId: venueId);
  }

  @override
  Stream<List<OrganizationMembership>> myOrganizations() =>
      _replay(_organizationsController, _currentOrganizationMemberships);

  @override
  Future<Organization?> organizationBySlug(String slug) async => _organizations
      .values
      .where((organization) => organization.slug == slug)
      .firstOrNull;

  @override
  Future<Organization?> organization(String organizationId) async =>
      _organizations[organizationId];

  @override
  Future<OrganizationDashboard> organizationDashboard(
    String organizationId,
  ) async {
    final organization = _requireOrganization(organizationId);
    final membership = _organizationMemberships
        .where((item) => item.organization.id == organizationId)
        .firstOrNull;
    return OrganizationDashboard(
      organization: organization,
      role: membership?.role,
      viaPlatformAdmin: platformAdmin,
      verification: OrganizationVerification(
        verified: organization.verified,
        stripeDetailsSubmitted: organization.verified,
        stripeChargesEnabled: organization.verified,
        stripePayoutsEnabled: organization.verified,
        profileComplete: organization.name.isNotEmpty,
        teamInvited: (_organizationMembers[organizationId]?.length ?? 0) > 1,
      ),
      venues: [
        for (final venue in _venues.values)
          if (venue.managedByOrganizationId == organizationId) venue,
      ],
      memberCount: _organizationMembers[organizationId]?.length ?? 0,
      privateDetails: _organizationPrivateDetails[organizationId],
    );
  }

  @override
  Future<void> updateOrganizationProfile({
    required String organizationId,
    String? name,
    String? description,
    String? website,
  }) async {
    final organization = _requireOrganization(organizationId);
    final updated = _copyOrganization(
      organization,
      name: name,
      description: description,
      website: website,
    );
    _organizations[organizationId] = updated;
    _replaceOrganizationInMemberships(updated);
    _emitOrganizations();
  }

  @override
  Future<void> updateOrganizationPrivateDetails({
    required String organizationId,
    String? legalName,
    String? businessEmail,
    String? contactName,
    String? phone,
  }) async {
    _requireOrganization(organizationId);
    final current = _organizationPrivateDetails[organizationId];
    _organizationPrivateDetails[organizationId] = OrganizationPrivateDetails(
      legalName: legalName ?? current?.legalName,
      businessEmail: businessEmail ?? current?.businessEmail ?? '',
      contactName: contactName ?? current?.contactName ?? '',
      phone: phone ?? current?.phone,
    );
  }

  @override
  Future<String> generateOrganizationPhotoUploadUrl(
    String organizationId,
  ) async {
    _requireOrganization(organizationId);
    return 'demo://organization-photo-upload/$organizationId';
  }

  @override
  Future<void> setOrganizationPhotos({
    required String organizationId,
    required List<String> storageIds,
  }) async {
    final organization = _requireOrganization(organizationId);
    final updated = _copyOrganization(
      organization,
      photoUrls: [
        for (final storageId in storageIds)
          'demo://organization-photo/$storageId',
      ],
    );
    _organizations[organizationId] = updated;
    _replaceOrganizationInMemberships(updated);
    _emitOrganizations();
  }

  @override
  Future<void> deactivateOrganization(String organizationId) async {
    final organization = _requireOrganization(organizationId);
    final updated = _copyOrganization(
      organization,
      status: OrganizationStatus.suspended,
      verified: false,
    );
    _organizations[organizationId] = updated;
    _replaceOrganizationInMemberships(updated);
    _emitOrganizations();
  }

  @override
  Future<List<OrganizationMember>> organizationMembers(
    String organizationId,
  ) async {
    _requireOrganization(organizationId);
    return _organizationMembers[organizationId]?.values.toList() ?? const [];
  }

  @override
  Future<void> setOrganizationMemberRole({
    required String organizationId,
    required String userId,
    required OrganizationRole role,
  }) async {
    final members = _organizationMembers[organizationId];
    final member = members?[userId];
    if (member == null) throw StateError('Organization member not found.');
    members![userId] = OrganizationMember(
      userId: member.userId,
      name: member.name,
      email: member.email,
      role: role,
      createdAt: member.createdAt,
    );
    if (userId == DemoData.demoUserId) {
      final index = _organizationMemberships.indexWhere(
        (membership) => membership.organization.id == organizationId,
      );
      if (index != -1) {
        _organizationMemberships[index] = OrganizationMembership(
          organization: _organizationMemberships[index].organization,
          role: role,
        );
      }
    }
    _emitOrganizations();
  }

  @override
  Future<void> removeOrganizationMember({
    required String organizationId,
    required String userId,
  }) async {
    _organizationMembers[organizationId]?.remove(userId);
    if (userId == DemoData.demoUserId) {
      _organizationMemberships.removeWhere(
        (membership) => membership.organization.id == organizationId,
      );
    }
    _emitOrganizations();
  }

  @override
  Future<OrganizationInvite?> organizationInvite(String organizationId) async =>
      _organizationInvites[organizationId];

  OrganizationInvite _newOrganizationInvite(
    String organizationId,
    OrganizationRole role,
  ) {
    _requireOrganization(organizationId);
    final invite = OrganizationInvite(
      organizationId: organizationId,
      token: 'demo-organization-invite-${_nextOrganizationInviteId++}',
      role: role,
      expiresAt: DateTime.now().add(const Duration(days: 7)),
      revoked: false,
      expired: false,
    );
    _organizationInvites[organizationId] = invite;
    return invite;
  }

  @override
  Future<OrganizationInvite> createOrganizationInvite({
    required String organizationId,
    required OrganizationRole role,
  }) async {
    final current = _organizationInvites[organizationId];
    if (current != null &&
        current.role == role &&
        !current.revoked &&
        !current.expired &&
        current.expiresAt.isAfter(DateTime.now())) {
      return current;
    }
    return _newOrganizationInvite(organizationId, role);
  }

  @override
  Future<OrganizationInvite> rotateOrganizationInvite(
    String organizationId,
  ) async => _newOrganizationInvite(
    organizationId,
    _organizationInvites[organizationId]?.role ?? OrganizationRole.manager,
  );

  @override
  Future<void> revokeOrganizationInvite(String organizationId) async {
    final invite = _organizationInvites[organizationId];
    if (invite == null) return;
    _organizationInvites[organizationId] = OrganizationInvite(
      organizationId: invite.organizationId,
      token: invite.token,
      role: invite.role,
      expiresAt: invite.expiresAt,
      revoked: true,
      expired: invite.expired,
    );
  }

  @override
  Future<OrganizationInviteResolution?> resolveOrganizationInvite(
    String token,
  ) async {
    final invite = _organizationInvites.values
        .where((candidate) => candidate.token == token)
        .firstOrNull;
    if (invite == null ||
        invite.revoked ||
        invite.expired ||
        !invite.expiresAt.isAfter(DateTime.now())) {
      return null;
    }
    final organization = _organizations[invite.organizationId];
    if (organization == null) return null;
    return OrganizationInviteResolution(
      organizationId: organization.id,
      organizationName: organization.name,
      role: invite.role,
    );
  }

  @override
  Future<OrganizationInviteAcceptance> acceptOrganizationInvite(
    String token,
  ) async {
    if (!_auth.signedIn) throw StateError('Not signed in.');
    final resolution = await resolveOrganizationInvite(token);
    if (resolution == null) {
      throw StateError('Invitation is no longer active.');
    }
    final alreadyMember = _organizationMemberships.any(
      (membership) => membership.organization.id == resolution.organizationId,
    );
    if (alreadyMember) {
      _emitOrganizations();
      return OrganizationInviteAcceptance(
        organizationId: resolution.organizationId,
        membershipCreated: false,
      );
    }

    final organization = _requireOrganization(resolution.organizationId);
    _organizationMemberships.add(
      OrganizationMembership(organization: organization, role: resolution.role),
    );
    _organizationMembers.putIfAbsent(
      organization.id,
      () => {},
    )[DemoData.demoUserId] = OrganizationMember(
      userId: DemoData.demoUserId,
      name: _userName ?? _auth.displayName ?? 'Earplug Fan',
      email: '',
      role: resolution.role,
      createdAt: DateTime.now(),
    );
    _emitOrganizations();
    return OrganizationInviteAcceptance(
      organizationId: organization.id,
      membershipCreated: true,
    );
  }

  @override
  Future<Venue?> resolveVenue(String ref) async => _venues.values
      .where((venue) => venue.id == ref || venue.slug == ref)
      .firstOrNull;

  @override
  Future<VenuePrivateDetails?> venuePrivateDetails(String venueId) async =>
      _venuePrivateDetails[venueId];

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
    final venue = _requireVenue(venueId);
    _venues[venueId] = Venue(
      id: venue.id,
      name: name ?? venue.name,
      area: venue.area,
      addr: venue.addr,
      point: venue.point,
      slug: venue.slug,
      approx: venue.approx,
      neighborhood: neighborhood ?? venue.neighborhood,
      city: city ?? venue.city,
      disclosure: venue.disclosure,
      verified: venue.verified,
      managedByOrganizationId: venue.managedByOrganizationId,
      exactAddress: venue.exactAddress,
      supportsApproxLocation: venue.supportsApproxLocation,
    );
    if (description != null) _venueDescriptions[venueId] = description;
    if (venueType != null) _venueTypes[venueId] = venueType;
    if (capacityPublic != null) {
      _venuePublicCapacities[venueId] = capacityPublic;
    }
    _emitFeed();
  }

  @override
  Future<void> updateVenuePrivateDetails({
    required String venueId,
    required String addr,
    required LatLng point,
    String? loadInNotes,
    int? capacity,
  }) async {
    final venue = _requireVenue(venueId);
    _venuePrivateDetails[venueId] = VenuePrivateDetails(
      venueId: venueId,
      addr: addr,
      point: point,
      loadInNotes: loadInNotes,
      capacity: capacity,
    );
    if (venue.disclosure == AddressDisclosure.public) {
      _venues[venueId] = Venue(
        id: venue.id,
        name: venue.name,
        area: venue.area,
        addr: addr,
        point: point,
        slug: venue.slug,
        approx: venue.approx,
        neighborhood: venue.neighborhood,
        city: venue.city,
        disclosure: venue.disclosure,
        verified: venue.verified,
        managedByOrganizationId: venue.managedByOrganizationId,
        exactAddress: addr,
        supportsApproxLocation: venue.supportsApproxLocation,
      );
      _emitFeed();
    }
  }

  @override
  Future<void> setVenueAddressDisclosure({
    required String venueId,
    required AddressDisclosure disclosure,
  }) async {
    final venue = _requireVenue(venueId);
    final privateDetails = _venuePrivateDetails[venueId];
    final discloseExact =
        disclosure == AddressDisclosure.public && privateDetails != null;
    _venues[venueId] = Venue(
      id: venue.id,
      name: venue.name,
      area: discloseExact ? venue.area : venue.approx.label,
      addr: discloseExact ? privateDetails.addr : venue.approx.label,
      point: discloseExact ? privateDetails.point : venue.approx.centroid,
      slug: venue.slug,
      approx: venue.approx,
      neighborhood: venue.neighborhood,
      city: venue.city,
      disclosure: disclosure,
      verified: venue.verified,
      managedByOrganizationId: venue.managedByOrganizationId,
      exactAddress: discloseExact ? privateDetails.addr : null,
      supportsApproxLocation: true,
    );
    _emitFeed();
  }

  @override
  Future<String> generateVenuePhotoUploadUrl(String venueId) async {
    _requireVenue(venueId);
    return 'demo://venue-photo-upload/$venueId';
  }

  @override
  Future<void> setVenuePhotos({
    required String venueId,
    required List<String> storageIds,
  }) async {
    _requireVenue(venueId);
    _venuePhotoStorageIds[venueId] = List<String>.of(storageIds);
  }

  @override
  Future<bool> isPlatformAdmin() async => platformAdmin;

  @override
  Future<AdminOverview> adminOverview() async => AdminOverview(
    submitted: _organizationApplications.values
        .where(
          (application) =>
              application.status == OrganizationApplicationStatus.submitted,
        )
        .length,
    underReview: _organizationApplications.values
        .where(
          (application) =>
              application.status == OrganizationApplicationStatus.underReview,
        )
        .length,
    needsInfo: _organizationApplications.values
        .where(
          (application) =>
              application.status == OrganizationApplicationStatus.needsInfo,
        )
        .length,
    verifiedOrganizations: _organizations.values
        .where(
          (organization) => organization.status == OrganizationStatus.verified,
        )
        .length,
    suspendedOrganizations: _organizations.values
        .where(
          (organization) => organization.status == OrganizationStatus.suspended,
        )
        .length,
    capped: false,
  );

  @override
  Future<void> setOrganizationSuspended({
    required String organizationId,
    required bool suspended,
    String? note,
  }) async {
    final organization = _requireOrganization(organizationId);
    final updated = _copyOrganization(
      organization,
      status: suspended
          ? OrganizationStatus.suspended
          : OrganizationStatus.verified,
      verified: !suspended,
    );
    _organizations[organizationId] = updated;
    _replaceOrganizationInMemberships(updated);
    _emitOrganizations();
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
  Future<void> toggleRsvp(String gigId, {bool? on}) async {
    final wasOn = _rsvpGigIds.contains(gigId);
    final goingNow = on ?? !wasOn;
    if (goingNow == wasOn) return;
    goingNow ? _rsvpGigIds.add(gigId) : _rsvpGigIds.remove(gigId);
    if (!_rsvpGigIds.contains(gigId)) {
      _ticketsByGigId.remove(gigId);
      _checkedInGigIds.remove(gigId);
    }
    _emitInteractionsIfSignedIn();
    _emitGoingCounts();
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
    _emitGoingCounts();
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
    _emitFeed();
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
    _emitFeed();
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
    _emitFeed();
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
      profileImageAdded: _avatarByBand.containsKey(bandId),
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
    final profileImageReady = _avatarByBand.containsKey(bandId);
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
    _emitFeed();
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
    final time =
        '${timeLabel(TimeOfDay.fromDateTime(doorsAt))} / '
        '${timeLabel(TimeOfDay.fromDateTime(startsAt))}';
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
    _emitFeed();
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
    _emitFeed();
  }

  @override
  Future<void> cancelGig(String projectId) async {
    final project = _requireGigProject(projectId);
    _gigProjects[projectId] = _copyGigProject(
      project,
      status: GigProjectStatus.cancelled,
    );
    _publishedGigs.removeWhere((gig) => gig.id == project.publicGigId);
    _emitFeed();
  }

  @override
  Future<void> deleteGig(String projectId) async {
    final project = _requireGigProject(projectId);
    _publishedGigs.removeWhere((gig) => gig.id == project.publicGigId);
    _gigProjects.remove(projectId);
    _emitFeed();
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
    _emitFeed();
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

  Map<String, int> _currentGoingCounts() => {
    for (final gig in _currentFeed().gigs) gig.id: _goingFor(gig),
  };

  int _goingFor(Gig gig) =>
      gig.going + (_auth.signedIn && _rsvpGigIds.contains(gig.id) ? 1 : 0);

  void _emitFeed() {
    _feedController.add(_currentFeed());
    _emitGoingCounts();
  }

  void _emitGoingCounts() {
    final counts = _currentGoingCounts();
    if (mapEquals(_lastGoingCounts, counts)) return;
    _lastGoingCounts = counts;
    _goingCountsController.add(counts);
  }

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
          _avatarByBand.containsKey(bandId) &&
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
        for (final id in {..._rsvpGigIds, ..._savedGigIds})
          if (gigsById[id] case final gig?)
            gig.copyWith(
              // Production stores the complete confirmed total on the gig.
              // Keep the demo subscription faithful to that contract.
              going: _goingFor(gig),
            ),
      ]),
      attendedCount: _attendedCount,
    );
  }

  List<BandMembership> _currentMemberships() =>
      List<BandMembership>.unmodifiable(_memberships);

  List<OrganizationMembership> _currentOrganizationMemberships() =>
      List<OrganizationMembership>.unmodifiable(_organizationMemberships);

  void _emitOrganizations() {
    _organizationsController.add(_currentOrganizationMemberships());
  }

  OrganizationApplication _requireOrganizationApplication(
    String applicationId,
  ) {
    final application = _organizationApplications[applicationId];
    if (application == null) throw StateError('Application not found.');
    return application;
  }

  void _checkApplicationRevision(
    OrganizationApplication application,
    int expectedRevision,
  ) {
    if (application.revision != expectedRevision) {
      throw StateError('Application changed elsewhere');
    }
  }

  OrganizationApplication _copyOrganizationApplication(
    OrganizationApplication application, {
    OrganizationApplicationStatus? status,
    List<ApplicationDocument>? documents,
    String? reviewNote,
    DateTime? decidedAt,
    String? resultingOrganizationId,
    String? resultingVenueId,
    int? revision,
    DateTime? updatedAt,
  }) => OrganizationApplication(
    id: application.id,
    status: status ?? application.status,
    orgName: application.orgName,
    orgType: application.orgType,
    website: application.website,
    contactName: application.contactName,
    businessEmail: application.businessEmail,
    phone: application.phone,
    venue: application.venue,
    documents: documents ?? application.documents,
    reviewNote: reviewNote ?? application.reviewNote,
    decidedAt: decidedAt ?? application.decidedAt,
    resultingOrganizationId:
        resultingOrganizationId ?? application.resultingOrganizationId,
    resultingVenueId: resultingVenueId ?? application.resultingVenueId,
    revision: revision ?? application.revision,
    createdAt: application.createdAt,
    updatedAt: updatedAt ?? application.updatedAt,
  );

  Organization _requireOrganization(String organizationId) {
    final organization = _organizations[organizationId];
    if (organization == null) throw StateError('Organization not found.');
    return organization;
  }

  Venue _requireVenue(String venueId) {
    final venue = _venues[venueId];
    if (venue == null) throw StateError('Venue not found.');
    return venue;
  }

  Organization _copyOrganization(
    Organization organization, {
    String? name,
    String? description,
    String? website,
    List<String>? photoUrls,
    OrganizationStatus? status,
    bool? verified,
  }) => Organization(
    id: organization.id,
    slug: organization.slug,
    name: name ?? organization.name,
    orgType: organization.orgType,
    status: status ?? organization.status,
    verified: verified ?? organization.verified,
    description: description ?? organization.description,
    website: website ?? organization.website,
    photoUrls: photoUrls ?? organization.photoUrls,
    createdAt: organization.createdAt,
  );

  void _replaceOrganizationInMemberships(Organization organization) {
    for (var index = 0; index < _organizationMemberships.length; index++) {
      final membership = _organizationMemberships[index];
      if (membership.organization.id == organization.id) {
        _organizationMemberships[index] = OrganizationMembership(
          organization: organization,
          role: membership.role,
        );
      }
    }
  }

  String _uniqueOrganizationSlug(String name) {
    var base = _slugify(name);
    if (base.isEmpty) base = 'organization';
    final taken = {
      for (final organization in _organizations.values) organization.slug,
    };
    for (var suffix = 1; ; suffix++) {
      final candidate = suffix == 1 ? base : '$base-$suffix';
      if (!taken.contains(candidate)) return candidate;
    }
  }

  String _uniqueVenueSlug(String name) {
    var base = _slugify(name);
    if (base.isEmpty) base = 'venue';
    final taken = {
      for (final venue in _venues.values)
        if (venue.slug != null) venue.slug,
    };
    for (var suffix = 1; ; suffix++) {
      final candidate = suffix == 1 ? base : '$base-$suffix';
      if (!taken.contains(candidate)) return candidate;
    }
  }

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
    _emitGoingCounts();
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

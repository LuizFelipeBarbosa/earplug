import 'package:latlong2/latlong.dart';

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
  Stream<Map<String, int>> goingCounts();
  Stream<Gig?> publicGig(String ref);
  Stream<List<Gig>> upcomingGigsForBand(String bandId);
  Stream<Interactions> myInteractions();
  Stream<List<BandMembership>> myBands();
  Future<List<BandMedia>> mediaFor(String bandId);
  Future<String> generateMediaUploadUrl(String bandId);
  Future<String> addBandMedia({
    required String bandId,
    required MediaKind kind,
    required String storageId,
    String? thumbnailStorageId,
    required String title,
    String? caption,
    int? lengthSec,
  });
  Future<void> deleteBandMedia(String mediaId);
  Future<void> pinBandMedia(String mediaId);
  Future<void> moveBandMedia(String mediaId, String direction);
  Future<void> moveMediaWithinKind(String mediaId, String direction);
  Future<void> setBandAvatar({required String bandId, required String mediaId});
  Future<void> clearBandAvatar(String bandId);
  Future<void> setBandBanner({required String bandId, required String mediaId});
  Future<void> clearBandBanner(String bandId);
  Future<List<FanHistoryItem>> history();
  Future<BandHistory> bandHistory(String bandId);
  Future<BandRecap> bandRecap(String bandId);
  Future<List<Venue>> venues();
  Stream<List<Venue>> watchVenues();
  Future<VenueCreationResult> createVenue({
    required String bandId,
    required String name,
    required String area,
    required String address,
    required double latitude,
    required double longitude,
  });
  Future<VenueDetail?> venueDetail(String venueId);
  Future<OrganizationApplication?> myOrganizationApplication();
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
  });
  Future<int> submitOrganizationApplication({
    required String applicationId,
    required int expectedRevision,
  });
  Future<void> withdrawOrganizationApplication(String applicationId);
  Future<String> generateApplicationDocumentUploadUrl();
  Future<int> attachApplicationDocument({
    required String applicationId,
    required String storageId,
  });
  Future<int> removeApplicationDocument({
    required String applicationId,
    required String storageId,
  });
  Future<OrganizationApplication?> organizationApplication(
    String applicationId,
  );
  Future<AdminApplicationPage> applicationsForReview({
    OrganizationApplicationStatus? status,
    String? cursor,
    int numItems = 25,
  });
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
  });
  Stream<List<OrganizationMembership>> myOrganizations();
  Future<Organization?> organizationBySlug(String slug);
  Future<Organization?> organization(String organizationId);
  Future<OrganizationDashboard> organizationDashboard(String organizationId);
  Future<void> updateOrganizationProfile({
    required String organizationId,
    String? name,
    String? description,
    String? website,
  });
  Future<void> updateOrganizationPrivateDetails({
    required String organizationId,
    String? legalName,
    String? businessEmail,
    String? contactName,
    String? phone,
  });
  Future<String> generateOrganizationPhotoUploadUrl(String organizationId);
  Future<void> addOrganizationPhoto({
    required String organizationId,
    required String storageId,
  });
  Future<void> setOrganizationPhotos({
    required String organizationId,
    required List<String> storageIds,
  });
  Future<void> deactivateOrganization(String organizationId);
  Future<List<OrganizationMember>> organizationMembers(String organizationId);
  Future<void> setOrganizationMemberRole({
    required String organizationId,
    required String userId,
    required OrganizationRole role,
  });
  Future<void> removeOrganizationMember({
    required String organizationId,
    required String userId,
  });
  Future<OrganizationInvite?> organizationInvite(String organizationId);
  Future<OrganizationInvite> createOrganizationInvite({
    required String organizationId,
    required OrganizationRole role,
  });
  Future<OrganizationInvite> rotateOrganizationInvite(String organizationId);
  Future<void> revokeOrganizationInvite(String organizationId);
  Future<OrganizationInviteResolution?> resolveOrganizationInvite(String token);
  Future<OrganizationInviteAcceptance> acceptOrganizationInvite(String token);
  Future<Venue?> resolveVenue(String ref);
  Future<VenuePrivateDetails?> venuePrivateDetails(String venueId);
  Future<void> updateVenueProfile({
    required String venueId,
    String? name,
    String? description,
    VenueType? venueType,
    int? capacityPublic,
    String? neighborhood,
    String? city,
  });
  Future<void> updateVenuePrivateDetails({
    required String venueId,
    required String addr,
    required LatLng point,
    String? loadInNotes,
    int? capacity,
  });
  Future<void> setVenueAddressDisclosure({
    required String venueId,
    required AddressDisclosure disclosure,
  });
  Future<String> generateVenuePhotoUploadUrl(String venueId);
  Future<void> setVenuePhotos({
    required String venueId,
    required List<String> storageIds,
  });
  Future<bool> isPlatformAdmin();
  Future<AdminOverview> adminOverview();
  Future<void> setOrganizationSuspended({
    required String organizationId,
    required bool suspended,
    String? note,
  });
  Future<Band?> band(String bandId);
  Future<Band?> bandBySlug(String slug);
  Future<BandProfileDetails> bandProfileDetails(String bandId);
  Future<List<Band>> searchBands(String q);
  Future<BandPage> listBands({String? cursor, int numItems = 50});

  Future<void> toggleRsvp(String gigId, {bool? on});
  Future<void> toggleFollow(String bandId);
  Future<void> toggleSave(String gigId);
  Future<RsvpTicket> ticketForGig(String gigId);
  Future<void> ensureRsvp(String gigId);
  Future<void> ensureFollow(String bandId);
  Future<void> ensureSave(String gigId);
  Future<void> updateFanProfile({
    required String name,
    required String? bio,
    required FanCity? homeLocation,
    required List<String> genres,
    required bool locationPersonalizationEnabled,
    required bool followedBandUpdatesEnabled,
  });
  Future<String> generateAvatarUploadUrl();
  Future<void> setAvatar(String storageId);
  Future<void> clearAvatar();
  Future<void> setProfileTutorialCompleted(bool completed);
  Future<void> updateFanOnboarding({
    FanCity? preferredCity,
    FanGenreChoice? genreChoice,
    bool? collapsed,
    List<String>? genres,
  });
  Future<void> ensureUser({String? name});
  Future<void> deleteCurrentUser();

  /// Returns the new band and its server-issued unique profile slug.
  Future<({Band band, String slug})> createBand({
    required String name,
    required List<String> genres,
    required String bio,
    required String area,
    String? linkIg,
    String? linkBc,
    String? linkYt,
    String? credits,
  });
  Future<void> updateBandProfile(BandProfileUpdate update);
  Future<BandArchiveResult> archiveBand(String bandId);
  Future<BandArchiveStatus> bandArchiveStatus(String bandId);
  Future<BandSetupStatus> bandSetupStatus(String bandId);
  Future<BandDiscoveryReadiness> bandDiscoveryReadiness(
    String bandId, {
    DateTime? now,
  });
  Future<void> markBandPreviewed(String bandId);
  Future<BandInvite?> bandInvite(String bandId);
  Future<BandInvite> createBandInvite(String bandId);
  Future<BandInvite> rotateBandInvite(String bandId);
  Future<void> revokeBandInvite(String bandId);
  Future<BandInviteResolution?> resolveBandInvite(String token);
  Future<BandInviteAcceptance> acceptBandInvite(String token);
  Future<PerformerInviteResolution?> resolvePerformerInvite(String token);
  Future<String> claimPerformerInvite({
    required String token,
    required String bandId,
  });
  // Organizer opportunities and applicant review.
  Future<({String opportunityId, String slug})> createOpportunity({
    required String organizationId,
    required String title,
    String? desc,
    required String venueId,
    String? eventType,
    int? expectedAttendance,
    List<String>? genres,
    required DateTime startsAt,
    DateTime? doorsAt,
    DateTime? endsAt,
    AgeRequirement? ageRequirement,
    String? equipment,
    String? requirements,
    String? flyKey,
    String? flyStorageId,
    DateTime? applicationsCloseAt,
    OpportunityVisibility? visibility,
    OpportunityTicketing? ticketing,
    String? externalUrl,
    List<SlotInput>? slots,
  }) {
    // TODO(marketplace-phase2): demo lane implements this.
    throw UnimplementedError('createOpportunity');
  }

  Future<int> updateOpportunity({
    required String opportunityId,
    required int expectedRevision,
    String? title,
    String? desc,
    String? venueId,
    String? eventType,
    int? expectedAttendance,
    List<String>? genres,
    DateTime? startsAt,
    DateTime? doorsAt,
    DateTime? endsAt,
    AgeRequirement? ageRequirement,
    String? equipment,
    String? requirements,
    String? flyKey,
    String? flyStorageId,
    DateTime? applicationsCloseAt,
    OpportunityVisibility? visibility,
    OpportunityTicketing? ticketing,
    String? externalUrl,
    List<SlotInput>? slots,
  }) {
    // TODO(marketplace-phase2): demo lane implements this.
    throw UnimplementedError('updateOpportunity');
  }

  Future<({int revision, DateTime applicationsCloseAt})> openOpportunity({
    required String opportunityId,
    required int expectedRevision,
  }) {
    // TODO(marketplace-phase2): demo lane implements this.
    throw UnimplementedError('openOpportunity');
  }

  Future<void> closeOpportunityApplications(String opportunityId) {
    // TODO(marketplace-phase2): demo lane implements this.
    throw UnimplementedError('closeOpportunityApplications');
  }

  Future<void> reopenOpportunity({
    required String opportunityId,
    required DateTime applicationsCloseAt,
  }) {
    // TODO(marketplace-phase2): demo lane implements this.
    throw UnimplementedError('reopenOpportunity');
  }

  Future<void> cancelOpportunity(String opportunityId, {String? reason}) {
    // TODO(marketplace-phase2): demo lane implements this.
    throw UnimplementedError('cancelOpportunity');
  }

  Future<void> deleteOpportunityDraft(String opportunityId) {
    // TODO(marketplace-phase2): demo lane implements this.
    throw UnimplementedError('deleteOpportunityDraft');
  }

  Future<({String opportunityId, String slug})> duplicateOpportunity(
    String opportunityId,
  ) {
    // TODO(marketplace-phase2): demo lane implements this.
    throw UnimplementedError('duplicateOpportunity');
  }

  Future<bool> inviteBandToOpportunity({
    required String opportunityId,
    required String bandId,
  }) {
    // TODO(marketplace-phase2): demo lane implements this.
    throw UnimplementedError('inviteBandToOpportunity');
  }

  Future<void> uninviteBandFromOpportunity({
    required String opportunityId,
    required String bandId,
  }) {
    // TODO(marketplace-phase2): demo lane implements this.
    throw UnimplementedError('uninviteBandFromOpportunity');
  }

  Future<List<Opportunity>> manageOpportunities(String organizationId) {
    // TODO(marketplace-phase2): demo lane implements this.
    throw UnimplementedError('manageOpportunities');
  }

  Future<Opportunity?> opportunity(String opportunityId) {
    // TODO(marketplace-phase2): demo lane implements this.
    throw UnimplementedError('opportunity');
  }

  Future<List<ApplicantRow>> applicantsFor(String opportunityId) {
    // TODO(marketplace-phase2): demo lane implements this.
    throw UnimplementedError('applicantsFor');
  }

  Future<void> reviewApplication({
    required String applicationId,
    required ArtistApplicationReviewAction action,
  }) {
    // TODO(marketplace-phase2): demo lane implements this.
    throw UnimplementedError('reviewApplication');
  }

  // Band opportunity discovery and applications.
  Future<OpportunityPage> browseOpportunities({
    String? cursor,
    int numItems = 25,
    String? bandId,
    OpportunityFilters? filters,
  }) {
    // TODO(marketplace-phase2): demo lane implements this.
    throw UnimplementedError('browseOpportunities');
  }

  Future<List<BrowseItem>> invitedOpportunities(String bandId) {
    // TODO(marketplace-phase2): demo lane implements this.
    throw UnimplementedError('invitedOpportunities');
  }

  Future<BrowseItem?> resolveOpportunity(String ref, {String? bandId}) {
    // TODO(marketplace-phase2): demo lane implements this.
    throw UnimplementedError('resolveOpportunity');
  }

  Future<String> applyToOpportunity({
    required String opportunityId,
    required String slotId,
    required String bandId,
    required String message,
    int? askMinor,
    String? availabilityNote,
    String? lineupNote,
  }) {
    // TODO(marketplace-phase2): demo lane implements this.
    throw UnimplementedError('applyToOpportunity');
  }

  Future<void> withdrawApplication(String applicationId) {
    // TODO(marketplace-phase2): demo lane implements this.
    throw UnimplementedError('withdrawApplication');
  }

  Future<List<BandApplication>> myApplications(String bandId) {
    // TODO(marketplace-phase2): demo lane implements this.
    throw UnimplementedError('myApplications');
  }

  Future<ArtistApplication?> myApplicationFor({
    required String opportunityId,
    required String bandId,
  }) {
    // TODO(marketplace-phase2): demo lane implements this.
    throw UnimplementedError('myApplicationFor');
  }

  Future<GigWritePolicy> gigWritePolicy() {
    // TODO(marketplace-phase2): demo lane implements this.
    throw UnimplementedError('gigWritePolicy');
  }

  Future<({String bookingId, String offerId, int revision})> sendOffer({
    required String applicationId,
    required int grossMinor,
    required CancellationTemplate cancellationTemplate,
    String? termsNotes,
    String? message,
  }) {
    // TODO(marketplace-phase3): demo lane implements this.
    throw UnimplementedError('sendOffer');
  }

  Future<int> withdrawOffer({
    required String bookingId,
    required int expectedRevision,
  }) {
    // TODO(marketplace-phase3): demo lane implements this.
    throw UnimplementedError('withdrawOffer');
  }

  Future<({BookingStatus status, int revision})> respondToOffer({
    required String bookingId,
    required bool accept,
    required int expectedRevision,
    String? message,
  }) {
    // TODO(marketplace-phase3): demo lane implements this.
    throw UnimplementedError('respondToOffer');
  }

  Future<({BookingStatus status, int revision})> cancelBooking({
    required String bookingId,
    required String reason,
    required int expectedRevision,
  }) {
    // TODO(marketplace-phase3): demo lane implements this.
    throw UnimplementedError('cancelBooking');
  }

  Future<Booking?> booking(String bookingId, {BookingSide? viewAs}) {
    // TODO(marketplace-phase3): demo lane implements this.
    throw UnimplementedError('booking');
  }

  Future<List<Booking>> organizationBookings(
    String organizationId, {
    List<BookingStatus>? statuses,
  }) {
    // TODO(marketplace-phase3): demo lane implements this.
    throw UnimplementedError('organizationBookings');
  }

  Future<List<Booking>> bandBookings(String bandId) {
    // TODO(marketplace-phase3): demo lane implements this.
    throw UnimplementedError('bandBookings');
  }

  Future<({String reviewId, bool visible})> submitReview({
    required String bookingId,
    required int rating,
    required List<String> categories,
    required String text,
  }) {
    // TODO(marketplace-phase3): demo lane implements this.
    throw UnimplementedError('submitReview');
  }

  Future<BookingReviews> reviewsForBooking(String bookingId) {
    // TODO(marketplace-phase3): demo lane implements this.
    throw UnimplementedError('reviewsForBooking');
  }

  Future<List<PublicReview>> reviewsForBand(String bandId, {int? limit}) {
    // TODO(marketplace-phase3): demo lane implements this.
    throw UnimplementedError('reviewsForBand');
  }

  Future<List<PublicReview>> reviewsForOrganization(
    String organizationId, {
    int? limit,
  }) {
    // TODO(marketplace-phase3): demo lane implements this.
    throw UnimplementedError('reviewsForOrganization');
  }

  Future<List<GigProject>> manageGigs(String bandId);
  Future<GigProject> createGigDraft(String bandId);
  Future<GigProject> getGigProject(String projectId);
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
  });
  Future<GigProject> addGigPerformer({
    required String projectId,
    required GigPerformerKind kind,
    required GigPerformerRole role,
    String? name,
    String? bandId,
  });
  Future<GigProject> updateGigPerformer({
    required String performerId,
    String? name,
    GigPerformerRole? role,
  });
  Future<GigProject> removeGigPerformer(String performerId);
  Future<GigProject> reorderGigPerformers(
    String projectId,
    List<String> performerIds,
  );
  Future<String> publishGigDraft(String projectId);
  Future<GigProject> duplicateGig(String projectId);
  Future<void> unpublishGig(String projectId);
  Future<void> cancelGig(String projectId);
  Future<void> deleteGig(String projectId);
  Future<DoorRoster> doorRoster(String projectId);
  Future<DoorCheckInResult> checkInTicket({
    required String projectId,
    required String payload,
  });
}

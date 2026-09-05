import 'package:latlong2/latlong.dart';

import '../models.dart';
import '../services/convex_service.dart';
import 'repository.dart';

class ConvexRepository implements EarplugRepository {
  const ConvexRepository(this._convexService);

  final ConvexService _convexService;

  @override
  Future<void> refreshAuth() => _convexService.refreshAuth();

  @override
  Future<UserProfile?> me() async {
    final result = await _convexService.query('users:me');
    final json = _asMap(result);
    return json.isEmpty ? null : UserProfile.fromJson(json);
  }

  @override
  Stream<FeedSnapshot> feed() {
    return _convexService.subscribe('gigs:feedV2', const {}, parseFeedSnapshot);
  }

  @override
  Stream<Map<String, int>> goingCounts() =>
      _convexService.subscribe('gigs:goingCounts', const {}, parseGoingCounts);

  @override
  Stream<Gig?> publicGig(String ref) =>
      _convexService.subscribe('gigs:resolvePublic', {'ref': ref}, (decoded) {
        final json = _asMap(decoded);
        return json.isEmpty ? null : Gig.fromJson(json);
      });

  @override
  Stream<List<Gig>> upcomingGigsForBand(String bandId) {
    return _convexService.subscribe('gigs:forBand', {'bandId': bandId}, (
      decoded,
    ) {
      return [for (final json in _mapList(decoded)) Gig.fromJson(json)];
    });
  }

  @override
  Stream<Interactions> myInteractions() {
    return _convexService.subscribe(
      'interactions:myInteractions',
      const {},
      parseInteractions,
    );
  }

  @override
  Stream<List<BandMembership>> myBands() {
    return _convexService.subscribe(
      'bands:myBands',
      const {},
      (decoded) => [
        for (final membershipJson in _mapList(decoded))
          BandMembership(
            band: Band.fromJson(
              Map<String, dynamic>.from(membershipJson['band'] as Map),
            ),
            role: membershipJson['role'] as String,
          ),
      ],
    );
  }

  @override
  Future<List<BandMedia>> mediaFor(String bandId) async {
    final result = await _convexService.query('media:forBand', {
      'bandId': bandId,
    });
    return [for (final json in _mapList(result)) BandMedia.fromJson(json)];
  }

  @override
  Future<String> generateMediaUploadUrl(String bandId) async {
    final result = await _convexService.mutation('media:generateUploadUrl', {
      'bandId': bandId,
    });
    return result as String;
  }

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
    final result = await _convexService.mutation('media:addMedia', {
      'bandId': bandId,
      'kind': kind.name,
      'storageId': storageId,
      'thumbnailStorageId': ?thumbnailStorageId,
      'title': title,
      'caption': ?caption,
      'lengthSec': ?lengthSec,
    });
    return _asMap(result)['mediaId'] as String;
  }

  @override
  Future<void> deleteBandMedia(String mediaId) async {
    await _convexService.mutation('media:deleteMedia', {'mediaId': mediaId});
  }

  @override
  Future<void> pinBandMedia(String mediaId) async {
    await _convexService.mutation('media:pinMedia', {'mediaId': mediaId});
  }

  @override
  Future<void> moveBandMedia(String mediaId, String direction) async {
    await _convexService.mutation('media:moveMedia', {
      'mediaId': mediaId,
      'direction': direction,
    });
  }

  @override
  Future<void> moveMediaWithinKind(String mediaId, String direction) async {
    await _convexService.mutation('media:moveWithinKind', {
      'mediaId': mediaId,
      'direction': direction,
    });
  }

  @override
  Future<void> setBandAvatar({
    required String bandId,
    required String mediaId,
  }) async {
    await _convexService.mutation('bands:setBandAvatar', {
      'bandId': bandId,
      'mediaId': mediaId,
    });
  }

  @override
  Future<void> clearBandAvatar(String bandId) async {
    await _convexService.mutation('bands:clearBandAvatar', {'bandId': bandId});
  }

  @override
  Future<void> setBandBanner({
    required String bandId,
    required String mediaId,
  }) async {
    await _convexService.mutation('bands:setBandBanner', {
      'bandId': bandId,
      'mediaId': mediaId,
    });
  }

  @override
  Future<void> clearBandBanner(String bandId) async {
    await _convexService.mutation('bands:clearBandBanner', {'bandId': bandId});
  }

  @override
  Future<List<FanHistoryItem>> history() async {
    final result = await _convexService.query('interactions:history', {
      'now': DateTime.now().millisecondsSinceEpoch,
    });
    return [for (final json in _mapList(result)) FanHistoryItem.fromJson(json)];
  }

  @override
  Future<BandHistory> bandHistory(String bandId) async {
    final json = _asMap(
      await _convexService.query('gigs:pastForBand', {'bandId': bandId}),
    );
    if (json.isEmpty) return BandHistory.empty;
    return BandHistory(
      gigs: _mapList(json['gigs']).map(Gig.fromJson).toList(),
      venues: {
        for (final venueJson in _mapList(json['venues']))
          venueJson['_id'] as String: Venue.fromJson(venueJson),
      },
    );
  }

  @override
  Future<BandRecap> bandRecap(String bandId) async {
    final json = _asMap(
      await _convexService.query('analytics:bandRecap', {'bandId': bandId}),
    );
    if (json.isEmpty) return BandRecap.empty;
    return BandRecap.fromJson(json);
  }

  @override
  Future<List<Venue>> venues() async {
    final result = await _convexService.query('venues:list');
    return [for (final json in _mapList(result)) Venue.fromJson(json)];
  }

  @override
  Stream<List<Venue>> watchVenues() => _convexService.subscribe(
    'venues:list',
    const {},
    (result) => [for (final json in _mapList(result)) Venue.fromJson(json)],
  );

  @override
  Future<VenueCreationResult> createVenue({
    required String bandId,
    required String name,
    required String area,
    required String address,
    required double latitude,
    required double longitude,
  }) async {
    final result = _asMap(
      await _convexService.mutation('venues:create', {
        'bandId': bandId,
        'name': name,
        'area': area,
        'addr': address,
        'lat': latitude,
        'lng': longitude,
      }),
    );
    return VenueCreationResult(
      venue: Venue.fromJson(Map<String, dynamic>.from(result['venue'] as Map)),
      created: result['created'] as bool,
    );
  }

  @override
  Future<VenueDetail?> venueDetail(String venueId) async {
    final result = await _convexService.query('venues:detail', {
      'venueId': venueId,
    });
    return parseVenueDetail(result);
  }

  @override
  Future<OrganizationApplication?> myOrganizationApplication() async {
    final json = _asMap(
      await _convexService.query('organizationApplications:mine'),
    );
    return json.isEmpty ? null : OrganizationApplication.fromJson(json);
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
    final result = _asMap(
      await _convexService.mutation('organizationApplications:saveDraft', {
        'applicationId': ?applicationId,
        'expectedRevision': ?expectedRevision,
        'orgName': orgName,
        'orgType': orgType.wireValue,
        'website': ?website,
        'contactName': contactName,
        'businessEmail': businessEmail,
        'phone': ?phone,
        'venue': ?venue?.toJson(),
      }),
    );
    return (
      applicationId: result['applicationId'] as String,
      revision: (result['revision'] as num).toInt(),
    );
  }

  @override
  Future<int> submitOrganizationApplication({
    required String applicationId,
    required int expectedRevision,
  }) async => _revisionFrom(
    await _convexService.mutation('organizationApplications:submit', {
      'applicationId': applicationId,
      'expectedRevision': expectedRevision,
    }),
  );

  @override
  Future<void> withdrawOrganizationApplication(String applicationId) async {
    await _convexService.mutation('organizationApplications:withdraw', {
      'applicationId': applicationId,
    });
  }

  @override
  Future<String> generateApplicationDocumentUploadUrl() async {
    final result = await _convexService.mutation(
      'organizationApplications:generateDocumentUploadUrl',
    );
    return result as String;
  }

  @override
  Future<int> attachApplicationDocument({
    required String applicationId,
    required String storageId,
  }) async => _revisionFrom(
    await _convexService.mutation('organizationApplications:attachDocument', {
      'applicationId': applicationId,
      'storageId': storageId,
    }),
  );

  @override
  Future<int> removeApplicationDocument({
    required String applicationId,
    required String storageId,
  }) async => _revisionFrom(
    await _convexService.mutation('organizationApplications:removeDocument', {
      'applicationId': applicationId,
      'storageId': storageId,
    }),
  );

  @override
  Future<OrganizationApplication?> organizationApplication(
    String applicationId,
  ) async {
    final json = _asMap(
      await _convexService.query('organizationApplications:get', {
        'applicationId': applicationId,
      }),
    );
    return json.isEmpty ? null : OrganizationApplication.fromJson(json);
  }

  @override
  Future<AdminApplicationPage> applicationsForReview({
    OrganizationApplicationStatus? status,
    String? cursor,
    int numItems = 25,
  }) async {
    final result = await _convexService.query(
      'organizationApplications:listForReview',
      {
        'status': ?status?.wireValue,
        'paginationOpts': {'numItems': numItems, 'cursor': cursor},
      },
    );
    return AdminApplicationPage.fromJson(_asMap(result));
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
    final result = _asMap(
      await _convexService.mutation('organizationApplications:decide', {
        'applicationId': applicationId,
        'decision': decision.wireValue,
        'note': ?note,
      }),
    );
    return (
      status: OrganizationApplicationStatus.fromWire(result['status']),
      organizationId: result['organizationId'] as String?,
      venueId: result['venueId'] as String?,
    );
  }

  @override
  Stream<List<OrganizationMembership>> myOrganizations() =>
      _convexService.subscribe(
        'organizations:mine',
        const {},
        (decoded) => [
          for (final membershipJson in _mapList(decoded))
            OrganizationMembership.fromJson(membershipJson),
        ],
      );

  @override
  Future<Organization?> organizationBySlug(String slug) async {
    final json = _asMap(
      await _convexService.query('organizations:bySlug', {'slug': slug}),
    );
    return json.isEmpty ? null : Organization.fromJson(json);
  }

  @override
  Future<Organization?> organization(String organizationId) async {
    final json = _asMap(
      await _convexService.query('organizations:get', {
        'organizationId': organizationId,
      }),
    );
    return json.isEmpty ? null : Organization.fromJson(json);
  }

  @override
  Future<OrganizationDashboard> organizationDashboard(
    String organizationId,
  ) async => OrganizationDashboard.fromJson(
    _asMap(
      await _convexService.query('organizations:dashboard', {
        'organizationId': organizationId,
      }),
    ),
  );

  @override
  Future<void> updateOrganizationProfile({
    required String organizationId,
    String? name,
    String? description,
    String? website,
  }) async {
    await _convexService.mutation('organizations:updateProfile', {
      'organizationId': organizationId,
      'name': ?name,
      'description': ?description,
      'website': ?website,
    });
  }

  @override
  Future<void> updateOrganizationPrivateDetails({
    required String organizationId,
    String? legalName,
    String? businessEmail,
    String? contactName,
    String? phone,
  }) async {
    await _convexService.mutation('organizations:updatePrivateDetails', {
      'organizationId': organizationId,
      'legalName': ?legalName,
      'businessEmail': ?businessEmail,
      'contactName': ?contactName,
      'phone': ?phone,
    });
  }

  @override
  Future<String> generateOrganizationPhotoUploadUrl(
    String organizationId,
  ) async {
    final result = await _convexService.mutation(
      'organizations:generatePhotoUploadUrl',
      {'organizationId': organizationId},
    );
    return result as String;
  }

  @override
  Future<void> addOrganizationPhoto({
    required String organizationId,
    required String storageId,
  }) async {
    await _convexService.mutation('organizations:addPhoto', {
      'organizationId': organizationId,
      'storageId': storageId,
    });
  }

  @override
  Future<void> setOrganizationPhotos({
    required String organizationId,
    required List<String> storageIds,
  }) async {
    await _convexService.mutation('organizations:setPhotos', {
      'organizationId': organizationId,
      'storageIds': storageIds,
    });
  }

  @override
  Future<void> deactivateOrganization(String organizationId) async {
    await _convexService.mutation('organizations:deactivate', {
      'organizationId': organizationId,
    });
  }

  @override
  Future<List<OrganizationMember>> organizationMembers(
    String organizationId,
  ) async {
    final result = await _convexService.query('organizationMembers:list', {
      'organizationId': organizationId,
    });
    return [
      for (final json in _mapList(result)) OrganizationMember.fromJson(json),
    ];
  }

  @override
  Future<void> setOrganizationMemberRole({
    required String organizationId,
    required String userId,
    required OrganizationRole role,
  }) async {
    await _convexService.mutation('organizationMembers:setRole', {
      'organizationId': organizationId,
      'userId': userId,
      'role': role.wireValue,
    });
  }

  @override
  Future<void> removeOrganizationMember({
    required String organizationId,
    required String userId,
  }) async {
    await _convexService.mutation('organizationMembers:remove', {
      'organizationId': organizationId,
      'userId': userId,
    });
  }

  @override
  Future<OrganizationInvite?> organizationInvite(String organizationId) async {
    final json = _asMap(
      await _convexService.query('organizationMembers:manageInvite', {
        'organizationId': organizationId,
      }),
    );
    return json.isEmpty ? null : OrganizationInvite.fromJson(json);
  }

  @override
  Future<OrganizationInvite> createOrganizationInvite({
    required String organizationId,
    required OrganizationRole role,
  }) async => OrganizationInvite.fromJson(
    _asMap(
      await _convexService.mutation('organizationMembers:createInvite', {
        'organizationId': organizationId,
        'role': role.wireValue,
      }),
    ),
  );

  @override
  Future<OrganizationInvite> rotateOrganizationInvite(
    String organizationId,
  ) async => OrganizationInvite.fromJson(
    _asMap(
      await _convexService.mutation('organizationMembers:rotateInvite', {
        'organizationId': organizationId,
      }),
    ),
  );

  @override
  Future<void> revokeOrganizationInvite(String organizationId) async {
    await _convexService.mutation('organizationMembers:revokeInvite', {
      'organizationId': organizationId,
    });
  }

  @override
  Future<OrganizationInviteResolution?> resolveOrganizationInvite(
    String token,
  ) async {
    final json = _asMap(
      await _convexService.query('organizationMembers:resolveInvite', {
        'token': token,
      }),
    );
    return json.isEmpty ? null : OrganizationInviteResolution.fromJson(json);
  }

  @override
  Future<OrganizationInviteAcceptance> acceptOrganizationInvite(
    String token,
  ) async => OrganizationInviteAcceptance.fromJson(
    _asMap(
      await _convexService.mutation('organizationMembers:acceptInvite', {
        'token': token,
      }),
    ),
  );

  @override
  Future<Venue?> resolveVenue(String ref) async {
    final json = _asMap(
      await _convexService.query('venues:resolvePublic', {'ref': ref}),
    );
    return json.isEmpty ? null : Venue.fromJson(json);
  }

  @override
  Future<VenuePrivateDetails?> venuePrivateDetails(String venueId) async {
    final json = _asMap(
      await _convexService.query('venues:privateDetail', {'venueId': venueId}),
    );
    return json.isEmpty ? null : VenuePrivateDetails.fromJson(json);
  }

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
    await _convexService.mutation('venues:updateProfile', {
      'venueId': venueId,
      'name': ?name,
      'description': ?description,
      'venueType': ?venueType?.wireValue,
      'capacityPublic': ?capacityPublic,
      'neighborhood': ?neighborhood,
      'city': ?city,
    });
  }

  @override
  Future<void> updateVenuePrivateDetails({
    required String venueId,
    required String addr,
    required LatLng point,
    String? loadInNotes,
    int? capacity,
  }) async {
    await _convexService.mutation('venues:updatePrivateDetails', {
      'venueId': venueId,
      'addr': addr,
      'lat': point.latitude,
      'lng': point.longitude,
      'loadInNotes': ?loadInNotes,
      'capacity': ?capacity,
    });
  }

  @override
  Future<void> setVenueAddressDisclosure({
    required String venueId,
    required AddressDisclosure disclosure,
  }) async {
    await _convexService.mutation('venues:setAddressDisclosure', {
      'venueId': venueId,
      'addressDisclosure': disclosure.wireValue,
    });
  }

  @override
  Future<String> generateVenuePhotoUploadUrl(String venueId) async {
    final result = await _convexService.mutation(
      'venues:generatePhotoUploadUrl',
      {'venueId': venueId},
    );
    return result as String;
  }

  @override
  Future<void> setVenuePhotos({
    required String venueId,
    required List<String> storageIds,
  }) async {
    await _convexService.mutation('venues:setPhotos', {
      'venueId': venueId,
      'storageIds': storageIds,
    });
  }

  @override
  Future<bool> isPlatformAdmin() async {
    final result = _asMap(await _convexService.query('admin:me'));
    return result['isPlatformAdmin'] == true;
  }

  @override
  Future<AdminOverview> adminOverview() async => AdminOverview.fromJson(
    _asMap(await _convexService.query('admin:overview')),
  );

  @override
  Future<void> setOrganizationSuspended({
    required String organizationId,
    required bool suspended,
    String? note,
  }) async {
    await _convexService.mutation('admin:suspendOrganization', {
      'organizationId': organizationId,
      'suspended': suspended,
      'note': ?note,
    });
  }

  @override
  Future<Band?> band(String bandId) async {
    final result = await _convexService.query('bands:get', {'bandId': bandId});
    final json = _asMap(result);
    return json.isEmpty ? null : Band.fromJson(json);
  }

  @override
  Future<Band?> bandBySlug(String slug) async {
    final result = await _convexService.query('bands:bySlug', {'slug': slug});
    final json = _asMap(result);
    return json.isEmpty ? null : Band.fromJson(json);
  }

  @override
  Future<BandProfileDetails> bandProfileDetails(String bandId) async {
    final result = await _convexService.query('bands:profileDetails', {
      'bandId': bandId,
    });
    return BandProfileDetails.fromJson(_asMap(result));
  }

  @override
  Future<List<Band>> searchBands(String q) async {
    final result = await _convexService.query('bands:search', {'q': q});
    return [for (final json in _mapList(result)) Band.fromJson(json)];
  }

  @override
  Future<BandPage> listBands({String? cursor, int numItems = 50}) async {
    final result = await _convexService.query('bands:list', {
      'paginationOpts': {'numItems': numItems, 'cursor': cursor},
    });
    return parseBandPage(result);
  }

  @override
  Future<void> toggleRsvp(String gigId, {bool? on}) async {
    await _convexService.mutation('interactions:toggleRsvp', {
      'gigId': gigId,
      'on': ?on,
    });
  }

  @override
  Future<void> toggleFollow(String bandId) async {
    await _convexService.mutation('interactions:toggleFollow', {
      'bandId': bandId,
    });
  }

  @override
  Future<void> toggleSave(String gigId) async {
    await _convexService.mutation('interactions:toggleSave', {'gigId': gigId});
  }

  @override
  Future<RsvpTicket> ticketForGig(String gigId) async => RsvpTicket.fromJson(
    _asMap(
      await _convexService.mutation('interactions:ticketForGig', {
        'gigId': gigId,
      }),
    ),
  );

  @override
  Future<void> ensureRsvp(String gigId) async {
    await _convexService.mutation('interactions:toggleRsvp', {
      'gigId': gigId,
      'on': true,
    });
  }

  @override
  Future<void> ensureFollow(String bandId) async {
    await _convexService.mutation('interactions:toggleFollow', {
      'bandId': bandId,
      'on': true,
    });
  }

  @override
  Future<void> ensureSave(String gigId) async {
    await _convexService.mutation('interactions:toggleSave', {
      'gigId': gigId,
      'on': true,
    });
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
    await _convexService.mutation('users:updateProfile', {
      'name': name,
      'bio': bio,
      'homeLocation': homeLocation?.name,
      'genres': genres,
      'locationPersonalizationEnabled': locationPersonalizationEnabled,
      'followedBandUpdatesEnabled': followedBandUpdatesEnabled,
    });
  }

  @override
  Future<String> generateAvatarUploadUrl() async {
    final result = await _convexService.mutation(
      'users:generateAvatarUploadUrl',
    );
    return result as String;
  }

  @override
  Future<void> setAvatar(String storageId) async {
    await _convexService.mutation('users:setAvatar', {'storageId': storageId});
  }

  @override
  Future<void> clearAvatar() async {
    await _convexService.mutation('users:clearAvatar');
  }

  @override
  Future<void> setProfileTutorialCompleted(bool completed) async {
    await _convexService.mutation('users:setProfileTutorialCompleted', {
      'completed': completed,
    });
  }

  @override
  Future<void> updateFanOnboarding({
    FanCity? preferredCity,
    FanGenreChoice? genreChoice,
    bool? collapsed,
    List<String>? genres,
  }) async {
    final preferredCityValue = preferredCity?.name;
    final genreChoiceValue = genreChoice?.name;
    await _convexService.mutation('users:updateFanOnboarding', {
      'preferredCity': ?preferredCityValue,
      'genreChoice': ?genreChoiceValue,
      'collapsed': ?collapsed,
      'genres': ?genres,
    });
  }

  @override
  Future<void> ensureUser({String? name}) async {
    await _convexService.mutation('users:ensureUser', {'name': ?name});
  }

  @override
  Future<void> deleteCurrentUser() async {
    await _convexService.mutation('users:deleteMe');
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
    final result = await _convexService.mutation('bands:createBand', {
      'name': name,
      'genres': genres,
      'bio': bio,
      'area': area,
      'linkIg': ?linkIg,
      'linkBc': ?linkBc,
      'linkYt': ?linkYt,
      'credits': ?credits,
    });
    final payload = _asMap(result);
    return (
      band: Band.fromJson(_asMap(payload['band'])),
      slug: payload['slug'] as String,
    );
  }

  @override
  Future<void> updateBandProfile(BandProfileUpdate update) async {
    await _convexService.mutation('bands:updateProfile', {
      'bandId': update.bandId,
      'name': update.name,
      'genres': update.genres,
      'area': update.area,
      'bio': update.bio,
      'linkIg': update.linkIg,
      'linkBc': update.linkBc,
      'linkYt': update.linkYt,
      'credits': update.credits,
    });
  }

  @override
  Future<BandArchiveResult> archiveBand(String bandId) async {
    final result = await _convexService.mutation('bands:archive', {
      'bandId': bandId,
    });
    return BandArchiveResult.fromJson(_asMap(result));
  }

  @override
  Future<BandArchiveStatus> bandArchiveStatus(String bandId) async {
    final result = await _convexService.query('bands:archiveStatus', {
      'bandId': bandId,
    });
    return BandArchiveStatus.fromJson(_asMap(result));
  }

  @override
  Future<BandSetupStatus> bandSetupStatus(String bandId) async {
    final result = await _convexService.query('bands:setupStatus', {
      'bandId': bandId,
    });
    return BandSetupStatus.fromJson(_asMap(result));
  }

  @override
  Future<BandDiscoveryReadiness> bandDiscoveryReadiness(
    String bandId, {
    DateTime? now,
  }) async {
    final result = await _convexService.query('bands:discoveryReadiness', {
      'bandId': bandId,
      'now': (now ?? DateTime.now()).millisecondsSinceEpoch,
    });
    return BandDiscoveryReadiness.fromJson(_asMap(result));
  }

  @override
  Future<void> markBandPreviewed(String bandId) async {
    await _convexService.mutation('bands:markPreviewed', {'bandId': bandId});
  }

  @override
  Future<BandInvite?> bandInvite(String bandId) async {
    final result = await _convexService.query('bandInvites:manage', {
      'bandId': bandId,
    });
    final json = _asMap(result);
    return json.isEmpty ? null : BandInvite.fromJson(json);
  }

  @override
  Future<BandInvite> createBandInvite(String bandId) async {
    final result = await _convexService.mutation('bandInvites:create', {
      'bandId': bandId,
    });
    return BandInvite.fromJson(_asMap(result));
  }

  @override
  Future<BandInvite> rotateBandInvite(String bandId) async {
    final result = await _convexService.mutation('bandInvites:rotate', {
      'bandId': bandId,
    });
    return BandInvite.fromJson(_asMap(result));
  }

  @override
  Future<void> revokeBandInvite(String bandId) async {
    await _convexService.mutation('bandInvites:revoke', {'bandId': bandId});
  }

  @override
  Future<BandInviteResolution?> resolveBandInvite(String token) async {
    final result = await _convexService.query('bandInvites:resolve', {
      'token': token,
    });
    final json = _asMap(result);
    return json.isEmpty ? null : BandInviteResolution.fromJson(json);
  }

  @override
  Future<BandInviteAcceptance> acceptBandInvite(String token) async {
    final result = await _convexService.mutation('bandInvites:accept', {
      'token': token,
    });
    return BandInviteAcceptance.fromJson(_asMap(result));
  }

  @override
  Future<PerformerInviteResolution?> resolvePerformerInvite(
    String token,
  ) async {
    final result = await _convexService.query('gigs:resolvePerformerInvite', {
      'token': token,
    });
    final json = _asMap(result);
    return json.isEmpty ? null : PerformerInviteResolution.fromJson(json);
  }

  @override
  Future<String> claimPerformerInvite({
    required String token,
    required String bandId,
  }) async {
    final result = await _convexService.mutation('gigs:claimPerformerInvite', {
      'token': token,
      'bandId': bandId,
    });
    return _asMap(result)['projectId'] as String;
  }

  @override
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
  }) async {
    final result = _asMap(
      await _convexService.mutation('talentOpportunities:create', {
        'organizationId': organizationId,
        'title': title,
        'desc': ?desc,
        'venueId': venueId,
        'eventType': ?eventType,
        'expectedAttendance': ?expectedAttendance,
        'genres': ?genres,
        'startsAt': startsAt.millisecondsSinceEpoch,
        'doorsAt': ?doorsAt?.millisecondsSinceEpoch,
        'endsAt': ?endsAt?.millisecondsSinceEpoch,
        'ageRequirement': ?ageRequirement?.wireValue,
        'equipment': ?equipment,
        'requirements': ?requirements,
        'flyKey': ?flyKey,
        'flyStorageId': ?flyStorageId,
        'applicationsCloseAt': ?applicationsCloseAt?.millisecondsSinceEpoch,
        'visibility': ?visibility?.wireValue,
        'ticketing': ?ticketing?.wireValue,
        'externalUrl': ?externalUrl,
        if (slots != null) 'slots': [for (final slot in slots) slot.toJson()],
      }),
    );
    return (
      opportunityId: result['opportunityId'] as String,
      slug: result['slug'] as String,
    );
  }

  @override
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
  }) async => _revisionFrom(
    await _convexService.mutation('talentOpportunities:update', {
      'opportunityId': opportunityId,
      'expectedRevision': expectedRevision,
      'title': ?title,
      'desc': ?desc,
      'venueId': ?venueId,
      'eventType': ?eventType,
      'expectedAttendance': ?expectedAttendance,
      'genres': ?genres,
      'startsAt': ?startsAt?.millisecondsSinceEpoch,
      'doorsAt': ?doorsAt?.millisecondsSinceEpoch,
      'endsAt': ?endsAt?.millisecondsSinceEpoch,
      'ageRequirement': ?ageRequirement?.wireValue,
      'equipment': ?equipment,
      'requirements': ?requirements,
      'flyKey': ?flyKey,
      'flyStorageId': ?flyStorageId,
      'applicationsCloseAt': ?applicationsCloseAt?.millisecondsSinceEpoch,
      'visibility': ?visibility?.wireValue,
      'ticketing': ?ticketing?.wireValue,
      'externalUrl': ?externalUrl,
      if (slots != null) 'slots': [for (final slot in slots) slot.toJson()],
    }),
  );

  @override
  Future<({int revision, DateTime applicationsCloseAt})> openOpportunity({
    required String opportunityId,
    required int expectedRevision,
  }) async {
    final result = _asMap(
      await _convexService.mutation('talentOpportunities:open', {
        'opportunityId': opportunityId,
        'expectedRevision': expectedRevision,
      }),
    );
    return (
      revision: (result['revision'] as num).toInt(),
      applicationsCloseAt: DateTime.fromMillisecondsSinceEpoch(
        (result['applicationsCloseAt'] as num).toInt(),
      ),
    );
  }

  @override
  Future<void> closeOpportunityApplications(String opportunityId) async {
    await _convexService.mutation('talentOpportunities:closeApplications', {
      'opportunityId': opportunityId,
    });
  }

  @override
  Future<void> reopenOpportunity({
    required String opportunityId,
    required DateTime applicationsCloseAt,
  }) async {
    await _convexService.mutation('talentOpportunities:reopen', {
      'opportunityId': opportunityId,
      'applicationsCloseAt': applicationsCloseAt.millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> cancelOpportunity(String opportunityId, {String? reason}) async {
    await _convexService.mutation('talentOpportunities:cancel', {
      'opportunityId': opportunityId,
      'reason': ?reason,
    });
  }

  @override
  Future<void> deleteOpportunityDraft(String opportunityId) async {
    await _convexService.mutation('talentOpportunities:deleteDraft', {
      'opportunityId': opportunityId,
    });
  }

  @override
  Future<({String opportunityId, String slug})> duplicateOpportunity(
    String opportunityId,
  ) async {
    final result = _asMap(
      await _convexService.mutation('talentOpportunities:duplicate', {
        'opportunityId': opportunityId,
      }),
    );
    return (
      opportunityId: result['opportunityId'] as String,
      slug: result['slug'] as String,
    );
  }

  @override
  Future<bool> inviteBandToOpportunity({
    required String opportunityId,
    required String bandId,
  }) async {
    final result = _asMap(
      await _convexService.mutation('talentOpportunities:inviteBand', {
        'opportunityId': opportunityId,
        'bandId': bandId,
      }),
    );
    return result['invited'] == true;
  }

  @override
  Future<void> uninviteBandFromOpportunity({
    required String opportunityId,
    required String bandId,
  }) async {
    await _convexService.mutation('talentOpportunities:uninviteBand', {
      'opportunityId': opportunityId,
      'bandId': bandId,
    });
  }

  @override
  Future<List<Opportunity>> manageOpportunities(String organizationId) async {
    final result = await _convexService.query(
      'talentOpportunitiesRead:manageForOrganization',
      {'organizationId': organizationId},
    );
    return [for (final json in _mapList(result)) Opportunity.fromJson(json)];
  }

  @override
  Future<Opportunity?> opportunity(String opportunityId) async {
    final json = _asMap(
      await _convexService.query('talentOpportunitiesRead:get', {
        'opportunityId': opportunityId,
      }),
    );
    return json.isEmpty ? null : Opportunity.fromJson(json);
  }

  @override
  Future<List<ApplicantRow>> applicantsFor(String opportunityId) async {
    final result = await _convexService.query(
      'artistApplications:forOpportunity',
      {'opportunityId': opportunityId},
    );
    return [for (final json in _mapList(result)) ApplicantRow.fromJson(json)];
  }

  @override
  Future<void> reviewApplication({
    required String applicationId,
    required ArtistApplicationReviewAction action,
  }) async {
    await _convexService.mutation('artistApplications:review', {
      'applicationId': applicationId,
      'action': action.wireValue,
    });
  }

  @override
  Future<OpportunityPage> browseOpportunities({
    String? cursor,
    int numItems = 25,
    String? bandId,
    OpportunityFilters? filters,
  }) async {
    final result = await _convexService.query(
      'talentOpportunitiesRead:browse',
      {
        'paginationOpts': {'numItems': numItems, 'cursor': cursor},
        'bandId': ?bandId,
        'filters': ?filters?.toJson(),
      },
    );
    return OpportunityPage.fromJson(_asMap(result));
  }

  @override
  Future<List<BrowseItem>> invitedOpportunities(String bandId) async {
    final result = await _convexService.query(
      'talentOpportunitiesRead:invitedFor',
      {'bandId': bandId},
    );
    return [for (final json in _mapList(result)) BrowseItem.fromJson(json)];
  }

  @override
  Future<BrowseItem?> resolveOpportunity(String ref, {String? bandId}) async {
    final json = _asMap(
      await _convexService.query('talentOpportunitiesRead:resolvePublic', {
        'ref': ref,
        'bandId': ?bandId,
      }),
    );
    return json.isEmpty ? null : BrowseItem.fromJson(json);
  }

  @override
  Future<String> applyToOpportunity({
    required String opportunityId,
    required String slotId,
    required String bandId,
    required String message,
    int? askMinor,
    String? availabilityNote,
    String? lineupNote,
  }) async {
    final result = await _convexService.mutation('artistApplications:apply', {
      'opportunityId': opportunityId,
      'slotId': slotId,
      'bandId': bandId,
      'message': message,
      'askMinor': ?askMinor,
      'availabilityNote': ?availabilityNote,
      'lineupNote': ?lineupNote,
    });
    return _asMap(result)['applicationId'] as String;
  }

  @override
  Future<void> withdrawApplication(String applicationId) async {
    await _convexService.mutation('artistApplications:withdraw', {
      'applicationId': applicationId,
    });
  }

  @override
  Future<List<BandApplication>> myApplications(String bandId) async {
    final result = await _convexService.query('artistApplications:forBand', {
      'bandId': bandId,
    });
    return [
      for (final json in _mapList(result)) BandApplication.fromJson(json),
    ];
  }

  @override
  Future<ArtistApplication?> myApplicationFor({
    required String opportunityId,
    required String bandId,
  }) async {
    final json = _asMap(
      await _convexService.query('artistApplications:mine', {
        'opportunityId': opportunityId,
        'bandId': bandId,
      }),
    );
    return json.isEmpty ? null : ArtistApplication.fromJson(json);
  }

  @override
  Future<GigWritePolicy> gigWritePolicy() async => GigWritePolicy.fromJson(
    _asMap(await _convexService.query('gigs:writePolicy')),
  );

  @override
  Future<List<GigProject>> manageGigs(String bandId) async {
    final result = await _convexService.query('gigs:manageForBand', {
      'bandId': bandId,
    });
    return [for (final json in _mapList(result)) GigProject.fromJson(json)];
  }

  @override
  Future<GigProject> createGigDraft(String bandId) async => GigProject.fromJson(
    _asMap(
      await _convexService.mutation('gigs:createDraft', {'bandId': bandId}),
    ),
  );

  @override
  Future<GigProject> getGigProject(String projectId) async =>
      GigProject.fromJson(
        _asMap(
          await _convexService.query('gigs:getProject', {
            'projectId': projectId,
          }),
        ),
      );

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
    final result = _asMap(
      await _convexService.mutation('gigs:saveDraft', {
        'projectId': projectId,
        'revision': revision,
        'title': title,
        'doorsAt': doorsAt?.millisecondsSinceEpoch,
        'startsAt': startsAt?.millisecondsSinceEpoch,
        'venueId': venueId,
        'price': price,
        'flyKey': flyKey,
        'flyStorageId': flyStorageId,
        'overlay': overlay,
        'desc': desc,
        'ticketing': ticketing.name,
        'ageRequirement': ageRequirement.wireValue,
        'externalUrl': externalUrl,
        'cap': cap,
      }),
    );
    return (result['revision'] as num).toInt();
  }

  @override
  Future<GigProject> addGigPerformer({
    required String projectId,
    required GigPerformerKind kind,
    required GigPerformerRole role,
    String? name,
    String? bandId,
  }) async => GigProject.fromJson(
    _asMap(
      await _convexService.mutation('gigs:addPerformer', {
        'projectId': projectId,
        'kind': kind.name,
        'role': role.name,
        'name': ?name,
        'bandId': ?bandId,
      }),
    ),
  );

  @override
  Future<GigProject> updateGigPerformer({
    required String performerId,
    String? name,
    GigPerformerRole? role,
  }) async => GigProject.fromJson(
    _asMap(
      await _convexService.mutation('gigs:updatePerformer', {
        'performerId': performerId,
        'name': ?name,
        'role': ?role?.name,
      }),
    ),
  );

  @override
  Future<GigProject> removeGigPerformer(String performerId) async =>
      GigProject.fromJson(
        _asMap(
          await _convexService.mutation('gigs:removePerformer', {
            'performerId': performerId,
          }),
        ),
      );

  @override
  Future<GigProject> reorderGigPerformers(
    String projectId,
    List<String> performerIds,
  ) async => GigProject.fromJson(
    _asMap(
      await _convexService.mutation('gigs:reorderPerformers', {
        'projectId': projectId,
        'performerIds': performerIds,
      }),
    ),
  );

  @override
  Future<String> publishGigDraft(String projectId) async {
    final result = _asMap(
      await _convexService.mutation('gigs:publishDraft', {
        'projectId': projectId,
      }),
    );
    return result['gigId'] as String;
  }

  @override
  Future<GigProject> duplicateGig(String projectId) async =>
      GigProject.fromJson(
        _asMap(
          await _convexService.mutation('gigs:duplicate', {
            'projectId': projectId,
          }),
        ),
      );

  @override
  Future<void> unpublishGig(String projectId) =>
      _convexService.mutation('gigs:unpublish', {'projectId': projectId});

  @override
  Future<void> cancelGig(String projectId) =>
      _convexService.mutation('gigs:cancel', {'projectId': projectId});

  @override
  Future<void> deleteGig(String projectId) =>
      _convexService.mutation('gigs:deleteGig', {'projectId': projectId});

  @override
  Future<DoorRoster> doorRoster(String projectId) async => DoorRoster.fromJson(
    _asMap(
      await _convexService.query('gigs:doorRoster', {'projectId': projectId}),
    ),
  );

  @override
  Future<DoorCheckInResult> checkInTicket({
    required String projectId,
    required String payload,
  }) async => DoorCheckInResult.fromJson(
    _asMap(
      await _convexService.mutation('gigs:checkInTicket', {
        'projectId': projectId,
        'payload': payload,
      }),
    ),
  );

  @override
  Future<({String bookingId, String offerId, int revision})> sendOffer({
    required String applicationId,
    required int grossMinor,
    required CancellationTemplate cancellationTemplate,
    String? termsNotes,
    String? message,
    List<OfferInstallmentInput>? installments,
  }) async {
    final dynamic decoded = await _convexService
        .mutation('bookings:sendOffer', {
          'applicationId': applicationId,
          'grossMinor': grossMinor,
          'cancellationTemplate': cancellationTemplate.wireValue,
          'termsNotes': ?termsNotes,
          'message': ?message,
          if (installments != null && installments.isNotEmpty)
            'installments': [
              for (final i in installments)
                {
                  'label': i.label,
                  'amountMinor': i.amountMinor,
                  'dueAfterAcceptanceDays': i.dueAfterAcceptanceDays,
                },
            ],
        });
    if (decoded is String) throw Exception(decoded);
    if (decoded is! Map) {
      throw Exception('Unexpected sendOffer response: $decoded');
    }
    final result = _asMap(decoded);
    return (
      bookingId: result['bookingId'] as String,
      offerId: result['offerId'] as String,
      revision: (result['revision'] as num).toInt(),
    );
  }

  @override
  Future<int> withdrawOffer({
    required String bookingId,
    required int expectedRevision,
  }) async {
    final result = _asMap(
      await _convexService.mutation('bookings:withdrawOffer', {
        'bookingId': bookingId,
        'expectedRevision': expectedRevision,
      }),
    );
    return (result['revision'] as num).toInt();
  }

  @override
  Future<({BookingStatus status, int revision})> respondToOffer({
    required String bookingId,
    required bool accept,
    required int expectedRevision,
    String? message,
  }) async {
    final result = _asMap(
      await _convexService.mutation('bookings:respond', {
        'bookingId': bookingId,
        'action': accept ? 'accept' : 'decline',
        'expectedRevision': expectedRevision,
        'message': ?message,
      }),
    );
    return (
      status: BookingStatus.fromWire(result['status']),
      revision: (result['revision'] as num).toInt(),
    );
  }

  @override
  Future<({BookingStatus status, int revision})> cancelBooking({
    required String bookingId,
    required String reason,
    required int expectedRevision,
    BookingSide? side,
  }) async {
    final result = _asMap(
      await _convexService.mutation('bookings:cancel', {
        'bookingId': bookingId,
        'reason': reason,
        'expectedRevision': expectedRevision,
        'as': ?side?.wireValue,
      }),
    );
    return (
      status: BookingStatus.fromWire(result['status']),
      revision: (result['revision'] as num).toInt(),
    );
  }

  @override
  Future<StripeAccountStatus> bandPayoutStatus(String bandId) async =>
      StripeAccountStatus.fromJson(
        _asMap(
          await _convexService.query('payoutAccounts:bandPayoutStatus', {
            'bandId': bandId,
          }),
        ),
      );

  @override
  Future<StripeAccountStatus> organizationStripeStatus(
    String organizationId,
  ) async => StripeAccountStatus.fromJson(
    _asMap(
      await _convexService.query('payoutAccounts:organizationStripeStatus', {
        'organizationId': organizationId,
      }),
    ),
  );

  @override
  Future<String> startBandOnboarding(String bandId) async {
    final result = _asMap(
      await _convexService.action('stripeActions:startBandOnboarding', {
        'bandId': bandId,
      }),
    );
    return result['url'] as String;
  }

  @override
  Future<String> startOrganizationOnboarding(String organizationId) async {
    final result = _asMap(
      await _convexService.action('stripeActions:startOrganizationOnboarding', {
        'organizationId': organizationId,
      }),
    );
    return result['url'] as String;
  }

  @override
  Future<StripeAccountStatus> refreshBandAccountStatus(String bandId) async =>
      StripeAccountStatus.fromJson(
        _asMap(
          await _convexService.action(
            'stripeActions:refreshBandAccountStatus',
            {'bandId': bandId},
          ),
        ),
      );

  @override
  Future<StripeAccountStatus> refreshOrganizationAccountStatus(
    String organizationId,
  ) async => StripeAccountStatus.fromJson(
    _asMap(
      await _convexService.action(
        'stripeActions:refreshOrganizationAccountStatus',
        {'organizationId': organizationId},
      ),
    ),
  );

  @override
  Future<String> bandExpressDashboardLink(String bandId) async {
    final result = _asMap(
      await _convexService.action('stripeActions:bandExpressDashboardLink', {
        'bandId': bandId,
      }),
    );
    return result['url'] as String;
  }

  @override
  Future<String> organizationExpressDashboardLink(String organizationId) async {
    final result = _asMap(
      await _convexService.action(
        'stripeActions:organizationExpressDashboardLink',
        {'organizationId': organizationId},
      ),
    );
    return result['url'] as String;
  }

  @override
  Future<({String url, String sessionId})> startInstallmentCheckout(
    String paymentRecordId,
  ) async {
    final result = _asMap(
      await _convexService.action('payments:startInstallmentCheckout', {
        'paymentRecordId': paymentRecordId,
      }),
    );
    return (
      url: result['url'] as String,
      sessionId: result['sessionId'] as String,
    );
  }

  @override
  Future<List<PaymentRecord>> paymentsForBooking(String bookingId) async {
    final result = await _convexService.query('payments:paymentsForBooking', {
      'bookingId': bookingId,
    });
    return [for (final json in _mapList(result)) PaymentRecord.fromJson(json)];
  }

  @override
  Future<CheckoutStatus?> checkoutStatus(String sessionId) async {
    final decoded = await _convexService.query('payments:checkoutStatus', {
      'sessionId': sessionId,
    });
    return decoded == null ? null : CheckoutStatus.fromJson(_asMap(decoded));
  }

  @override
  Future<List<Payout>> payoutsForBooking(String bookingId) async {
    final result = await _convexService.query('payouts:payoutsForBooking', {
      'bookingId': bookingId,
    });
    return [for (final json in _mapList(result)) Payout.fromJson(json)];
  }

  @override
  Future<List<Payout>> payoutsForBand(String bandId) async {
    final result = await _convexService.query('payouts:payoutsForBand', {
      'bandId': bandId,
    });
    return [for (final json in _mapList(result)) Payout.fromJson(json)];
  }

  @override
  Future<RefundPreview> previewCancellation(
    String bookingId, {
    BookingSide? side,
    required DateTime now,
  }) async => RefundPreview.fromJson(
    _asMap(
      await _convexService.query('refunds:previewCancellation', {
        'bookingId': bookingId,
        'as': ?side?.wireValue,
        'now': now.millisecondsSinceEpoch,
      }),
    ),
  );

  @override
  Future<List<RefundRecord>> refundsForBooking(String bookingId) async {
    final result = await _convexService.query('refunds:refundsForBooking', {
      'bookingId': bookingId,
    });
    return [for (final json in _mapList(result)) RefundRecord.fromJson(json)];
  }

  @override
  Future<Booking?> booking(String bookingId, {BookingSide? viewAs}) async {
    final json = _asMap(
      await _convexService.query('bookingsRead:get', {
        'bookingId': bookingId,
        'viewAs': ?viewAs?.wireValue,
      }),
    );
    return json.isEmpty ? null : Booking.fromJson(json);
  }

  @override
  Future<List<Booking>> organizationBookings(
    String organizationId, {
    List<BookingStatus>? statuses,
  }) async {
    final result = await _convexService.query('bookingsRead:forOrganization', {
      'organizationId': organizationId,
      'statuses': ?statuses?.map((s) => s.wireValue).toList(),
    });
    return [for (final json in _mapList(result)) Booking.fromJson(json)];
  }

  @override
  Future<List<Booking>> bandBookings(String bandId) async {
    final result = await _convexService.query('bookingsRead:forBand', {
      'bandId': bandId,
    });
    return [for (final json in _mapList(result)) Booking.fromJson(json)];
  }

  @override
  Future<({String reviewId, bool visible})> submitReview({
    required String bookingId,
    required int rating,
    required List<String> categories,
    required String text,
  }) async {
    final result = _asMap(
      await _convexService.mutation('reviews:submit', {
        'bookingId': bookingId,
        'rating': rating,
        'categories': categories,
        'text': text,
      }),
    );
    return (
      reviewId: result['reviewId'] as String,
      visible: result['visible'] == true,
    );
  }

  @override
  Future<BookingReviews> reviewsForBooking(String bookingId) async =>
      BookingReviews.fromJson(
        _asMap(
          await _convexService.query('reviews:forBooking', {
            'bookingId': bookingId,
          }),
        ),
      );

  @override
  Future<List<PublicReview>> reviewsForBand(String bandId, {int? limit}) async {
    final result = await _convexService.query('reviews:forBand', {
      'bandId': bandId,
      'limit': ?limit,
    });
    return [for (final json in _mapList(result)) PublicReview.fromJson(json)];
  }

  @override
  Future<List<PublicReview>> reviewsForOrganization(
    String organizationId, {
    int? limit,
  }) async {
    final result = await _convexService.query('reviews:forOrganization', {
      'organizationId': organizationId,
      'limit': ?limit,
    });
    return [for (final json in _mapList(result)) PublicReview.fromJson(json)];
  }
}

BandPage parseBandPage(dynamic decoded) {
  final json = _asMap(decoded);
  final cursor = json['continueCursor'];
  return BandPage(
    items: [
      for (final bandJson in _mapList(json['page'])) Band.fromJson(bandJson),
    ],
    continueCursor: cursor is String ? cursor : null,
    isDone: json['isDone'] == true,
  );
}

VenueDetail? parseVenueDetail(dynamic decoded) {
  final json = _asMap(decoded);
  if (json.isEmpty) return null;
  return VenueDetail(
    venue: Venue.fromJson(_asMap(json['venue'])),
    gigs: [for (final gigJson in _mapList(json['gigs'])) Gig.fromJson(gigJson)],
    bands: {
      for (final bandJson in _mapList(json['bands']))
        bandJson['_id'] as String: Band.fromJson(bandJson),
    },
    truncated: json['truncated'] == true,
  );
}

FeedSnapshot parseFeedSnapshot(dynamic decoded) {
  final now = DateTime.now();
  final json = _asMap(decoded);
  final gigs = [
    for (final gigJson in _mapList(json['gigs']))
      Gig.fromJson(gigJson, now: now),
  ];
  final nextStartsAt = json['nextStartsAt'];
  final venues = <String, Venue>{
    for (final venueJson in _mapList(json['venues']))
      venueJson['_id'] as String: Venue.fromJson(venueJson),
  };
  final bands = <String, Band>{
    for (final bandJson in _mapList(json['bands']))
      bandJson['_id'] as String: Band.fromJson(bandJson),
  };
  return FeedSnapshot(
    gigs: gigs,
    venues: venues,
    bands: bands,
    nextStartsAt: nextStartsAt is num
        ? DateTime.fromMillisecondsSinceEpoch(nextStartsAt.toInt())
        : null,
  );
}

Map<String, int> parseGoingCounts(dynamic decoded) => Map.unmodifiable({
  for (final json in _mapList(decoded))
    json['gigId'] as String: (json['goingCount'] as num).toInt(),
});

Interactions parseInteractions(dynamic decoded) {
  final json = _asMap(decoded);
  if (json.isEmpty) return Interactions.empty;
  return Interactions(
    rsvpGigIds: Set<String>.from(json['rsvpGigIds'] as List? ?? const []),
    followBandIds: Set<String>.from(json['followBandIds'] as List? ?? const []),
    savedGigIds: Set<String>.from(json['savedGigIds'] as List? ?? const []),
    gigs: [for (final gigJson in _mapList(json['gigs'])) Gig.fromJson(gigJson)],
    attendedCount: (json['attendedCount'] as num?)?.toInt() ?? 0,
  );
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value == null) return const {};
  return Map<String, dynamic>.from(value as Map);
}

List<Map<String, dynamic>> _mapList(dynamic value) {
  if (value == null) return const [];
  return [
    for (final item in value as List) Map<String, dynamic>.from(item as Map),
  ];
}

int _revisionFrom(dynamic value) {
  if (value is num) return value.toInt();
  final revision = _asMap(value)['revision'];
  return revision is num ? revision.toInt() : 0;
}

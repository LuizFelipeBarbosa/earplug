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
    return _convexService.subscribe('gigs:feed', const {}, parseFeedSnapshot);
  }

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
  Future<void> setBandPhoto({
    required String bandId,
    required String mediaId,
  }) async {
    await _convexService.mutation('bands:setBandPhoto', {
      'bandId': bandId,
      'mediaId': mediaId,
    });
  }

  @override
  Future<void> clearBandPhoto(String bandId) async {
    await _convexService.mutation('bands:clearBandPhoto', {'bandId': bandId});
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
  Future<void> setGenres(List<String> genres) async {
    await _convexService.mutation('users:setGenres', {'genres': genres});
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
    final result = await _convexService.mutation('gigs:publishGig', {
      'bandId': bandId,
      'title': title,
      'startsAt': startsAt,
      'doorsTime': doorsTime,
      'venueId': venueId,
      'price': price,
      'flyKey': flyKey,
      'flyStorageId': ?flyStorageId,
      'ticketing': ticketing.name,
      'ageRequirement': ageRequirement.wireValue,
      'externalUrl': ?externalUrl,
      'cap': cap,
    });
    return _asMap(result)['gigId'] as String;
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
  final json = _asMap(decoded);
  final gigs = _mapList(json['gigs']).map(Gig.fromJson).toList();
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

import '../models.dart';
import '../services/convex_service.dart';
import 'repository.dart';

class ConvexRepository implements EarplugRepository {
  const ConvexRepository(this._convexService);

  final ConvexService _convexService;

  /// Pushes the current auth token to the websocket; awaitable so callers can
  /// sequence mutations after the identity change.
  Future<void> refreshAuth() => _convexService.refreshAuth();

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
  Stream<Interactions> myInteractions() {
    return _convexService.subscribe(
      'interactions:myInteractions',
      const {},
      _interactionsFromJson,
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
  Future<List<VideoClip>> videosFor(String bandId) async {
    final result = await _convexService.query('videos:forBand', {
      'bandId': bandId,
    });
    return [for (final json in _mapList(result)) VideoClip.fromJson(json)];
  }

  @override
  Future<List<PastGig>> history() async {
    final result = await _convexService.query('interactions:history');
    return [
      for (final json in _mapList(result))
        PastGig(
          (json['venueName'] as String).isEmpty
              ? json['title'] as String
              : '${json['title']} — ${json['venueName']}',
          Gig.dateShortFor((json['startsAt'] as num).toInt()),
        ),
    ];
  }

  @override
  Future<Band?> band(String bandId) async {
    final result = await _convexService.query('bands:get', {'bandId': bandId});
    final json = _asMap(result);
    return json.isEmpty ? null : Band.fromJson(json);
  }

  @override
  Future<List<Band>> searchBands(String q) async {
    final result = await _convexService.query('bands:search', {'q': q});
    return [for (final json in _mapList(result)) Band.fromJson(json)];
  }

  @override
  Future<void> toggleRsvp(String gigId) async {
    await _convexService.mutation('interactions:toggleRsvp', {'gigId': gigId});
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
  Future<void> setGenres(List<String> genres) async {
    await _convexService.mutation('users:setGenres', {'genres': genres});
  }

  @override
  Future<void> ensureUser({String? name}) async {
    await _convexService.mutation('users:ensureUser', {'name': ?name});
  }

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
    final result = await _convexService.mutation('bands:createBand', {
      'name': name,
      'genres': genres,
      'bio': bio,
      'inviteHandles': inviteHandles,
      'area': ?area,
      'linkIg': ?linkIg,
      'linkBc': ?linkBc,
      'linkYt': ?linkYt,
    });
    final payload = _asMap(result);
    return (
      bandId: payload['bandId'] as String,
      slug: payload['slug'] as String,
    );
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
    await _convexService.mutation('bands:updateProfile', {
      'bandId': bandId,
      'name': ?name,
      'genres': ?genres,
      'area': ?area,
      'bio': ?bio,
      'inviteHandles': ?inviteHandles,
      'linkIg': ?linkIg,
      'linkBc': ?linkBc,
      'linkYt': ?linkYt,
    });
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
    required Ticketing ticketing,
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
      'ticketing': ticketing.name,
      'externalUrl': ?externalUrl,
      'cap': cap,
    });
    return _asMap(result)['gigId'] as String;
  }

  @override
  Future<void> pinVideo(String videoId) async {
    await _convexService.mutation('videos:pinVideo', {'videoId': videoId});
  }

  @override
  Future<void> moveVideo(String videoId, String direction) async {
    await _convexService.mutation('videos:moveVideo', {
      'videoId': videoId,
      'direction': direction,
    });
  }
}

FeedSnapshot parseFeedSnapshot(dynamic decoded) {
  final json = _asMap(decoded);
  final gigs = _mapList(json['gigs']).map(Gig.fromJson).toList();
  final venues = <String, Venue>{
    for (final venueJson in _mapList(json['venues']))
      venueJson['_id'] as String: Venue.fromJson(venueJson),
  };
  final bands = <String, Band>{
    for (final bandJson in _mapList(json['bands']))
      bandJson['_id'] as String: Band.fromJson(bandJson),
  };
  return FeedSnapshot(gigs: gigs, venues: venues, bands: bands);
}

Interactions _interactionsFromJson(dynamic decoded) {
  final json = _asMap(decoded);
  if (json.isEmpty) return Interactions.empty;
  return Interactions(
    rsvpGigIds: Set<String>.from(json['rsvpGigIds'] as List? ?? const []),
    followBandIds: Set<String>.from(json['followBandIds'] as List? ?? const []),
    savedGigIds: Set<String>.from(json['savedGigIds'] as List? ?? const []),
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

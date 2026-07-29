import 'dart:async';
import 'dart:ui' show Color;

import '../demo_data.dart';
import '../models.dart';
import '../services/auth_service.dart';
import 'repository.dart';

class DemoRepository implements EarplugRepository {
  DemoRepository({required this._auth}) {
    _bands = Map<String, Band>.of(DemoData.bands);
    _memberships = [BandMembership(band: _bands['b1']!, role: 'admin')];
    _videoLists = {
      'b1': List<VideoClip>.of(DemoData.b1Videos),
      '_generic': List<VideoClip>.of(DemoData.genericVideos),
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
  late final Map<String, List<VideoClip>> _videoLists;
  final List<Gig> _publishedGigs = [];
  final Set<String> _rsvpGigIds = {};
  final Set<String> _followBandIds = {};
  final Set<String> _savedGigIds = {};
  final Set<String> _userGenres = {};

  String? _userName;
  int _attendedCount = 0;
  int _nextBandId = 1;
  int _nextGigId = 1;
  bool _interactionsSeeded = false;

  @override
  Stream<FeedSnapshot> feed() => _replay(_feedController, _currentFeed);

  @override
  Stream<Interactions> myInteractions() =>
      _replay(_interactionsController, _currentInteractions);

  @override
  Stream<List<BandMembership>> myBands() =>
      _replay(_bandsController, _currentMemberships);

  @override
  Future<List<VideoClip>> videosFor(String bandId) async {
    final videos = bandId == 'b1'
        ? _videoLists['b1']!
        : _videoLists['_generic']!;
    return List<VideoClip>.of(videos);
  }

  @override
  Future<List<PastGig>> history() async =>
      _auth.signedIn ? DemoData.fanHistory : const [];

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

  @override
  Future<String> createBand({
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
    final created = Band(
      id: id,
      name: bandName,
      genres: genres.isEmpty ? const ['punk'] : List<String>.of(genres),
      area: area ?? 'Mission, SF',
      color: const Color(0xFF8FE6C4),
      initials: bandName
          .split(' ')
          .where((word) => word.isNotEmpty)
          .map((word) => word[0])
          .take(2)
          .join()
          .toUpperCase(),
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
    return id;
  }

  @override
  Future<void> updateBandProfile({
    required String bandId,
    String? bio,
    String? linkIg,
    String? linkBc,
  }) async {
    final existing = _bands[bandId];
    if (existing == null) return;

    final updated = existing.copyWith(bio: bio, linkIg: linkIg, linkBc: linkBc);
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
    required Ticketing ticketing,
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
        externalUrl: externalUrl,
        cap: cap,
      ),
    );
    _feedController.add(_currentFeed());
    return id;
  }

  @override
  Future<void> pinVideo(String videoId) async {
    final videos = _videoListContaining(videoId);
    if (videos == null) return;

    for (var i = 0; i < videos.length; i++) {
      videos[i] = videos[i].copyWith(pinned: videos[i].id == videoId);
    }
  }

  @override
  Future<void> moveVideo(String videoId, String direction) async {
    final videos = _videoListContaining(videoId);
    if (videos == null) return;

    final index = videos.indexWhere((video) => video.id == videoId);
    final delta = switch (direction) {
      'up' => -1,
      'down' => 1,
      _ => 0,
    };
    final destination = index + delta;
    if (delta == 0 || destination < 0 || destination >= videos.length) return;

    final moved = videos[index];
    videos[index] = videos[destination];
    videos[destination] = moved;
  }

  FeedSnapshot _currentFeed() => FeedSnapshot(
    gigs: List<Gig>.unmodifiable([...DemoData.gigs, ..._publishedGigs]),
    venues: DemoData.venues,
    bands: Map<String, Band>.unmodifiable(_bands),
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

  List<VideoClip>? _videoListContaining(String videoId) {
    for (final videos in _videoLists.values) {
      if (videos.any((video) => video.id == videoId)) return videos;
    }
    return null;
  }
}

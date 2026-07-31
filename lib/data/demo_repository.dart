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
  Future<List<Venue>> venues() async =>
      DemoData.venues.values.toList()..sort((a, b) => a.name.compareTo(b.name));

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

  static String _initialsFor(String name) => name
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) => word[0])
      .take(2)
      .join()
      .toUpperCase();

  /// Mirrors the backend: "static-bloom", or "static-bloom-2" when taken.
  String _uniqueSlug(String name) {
    var base = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (base.isEmpty) base = 'band';

    final taken = {
      ..._issuedSlugs,
      for (final band in _bands.values)
        band.name
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
            .replaceAll(RegExp(r'^-+|-+$'), ''),
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

  List<BandMedia>? _mediaListContaining(String mediaId) {
    for (final media in _mediaLists.values) {
      if (media.any((item) => item.id == mediaId)) return media;
    }
    return null;
  }
}

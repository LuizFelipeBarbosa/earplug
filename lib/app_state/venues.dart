part of '../app_state.dart';

/// The curated venue directory, per-venue relationship details, and the
/// merged venue list every screen reads. The marketplace's venue identity
/// will land here later.
mixin _VenueState on _AppStateCore {
  // ---- requires (declared by sibling mixins or AppState)
  String get bandId;
  Map<String, Band> get _bands;
  Map<String, Gig> get _relationshipGigs;
  void setGfVenue(String v);

  /// The full curated venue table (`venues:list`), including venues no upcoming
  /// gig references. The feed only carries venues its gigs point at.
  Map<String, Venue> _venueDirectory = const {};
  DataStatus _venueStatus = DataStatus.connecting;
  bool _venueDirectoryRequested = false;
  DataStatus get venueStatus => _venueStatus;
  String? venueError;

  /// Venue relationship payloads are separate from the discovery feed. They
  /// stay cached across rebuilds; feed changes and venue revisits invalidate
  /// the affected key so its next read refetches authoritative relationships.
  final Map<String, VenueDetail> _venueDetails = {};
  final Set<String> _missingVenueDetails = {};
  final Map<String, Object> _venueDetailTokens = {};
  final Map<String, String> _venueDetailErrors = {};

  /// One-shot directory refresh, following the `_refreshExploreBands` pattern.
  void ensureVenueDirectory() {
    if (_venueDirectoryRequested || _disposed) return;
    _venueDirectoryRequested = true;
    unawaited(_refreshVenueDirectory());
  }

  Future<void> _refreshVenueDirectory() async {
    try {
      final loaded = await repository.venues();
      if (_disposed) return;
      _venueDirectory = {for (final venue in loaded) venue.id: venue};
      _venueStatus = DataStatus.ready;
      venueError = null;
      notifyListeners();
    } catch (error) {
      logError('venues', error);
      if (_disposed) return;
      _venueStatus = DataStatus.error;
      venueError = '$error';
      notifyListeners();
    }
  }

  void retryVenues() {
    if (_venueStatus == DataStatus.connecting) return;
    _venueStatus = DataStatus.connecting;
    venueError = null;
    notifyListeners();
    unawaited(_refreshVenueDirectory());
  }

  Future<VenueCreationResult> createVenue({
    required String name,
    required String area,
    required String address,
    required LatLng point,
  }) async {
    final result = await repository.createVenue(
      bandId: bandId,
      name: name,
      area: area,
      address: address,
      latitude: point.latitude,
      longitude: point.longitude,
    );
    _venueDirectory = {..._venueDirectory, result.venue.id: result.venue};
    setGfVenue(result.venue.id);
    notifyListeners();
    return result;
  }

  VenueDetail? venueDetail(String id) {
    final cached = _venueDetails[id];
    if (cached != null) return cached;
    if (!_missingVenueDetails.contains(id) &&
        !_venueDetailTokens.containsKey(id) &&
        !_venueDetailErrors.containsKey(id)) {
      unawaited(_loadVenueDetail(id));
    }
    return null;
  }

  @override
  void _invalidateVenueDetails(Set<String> ids) {
    for (final id in ids) {
      _venueDetails.remove(id);
      _missingVenueDetails.remove(id);
      _venueDetailErrors.remove(id);
      // Removing the token makes any older response fail the identity check in
      // `_loadVenueDetail`, so a pre-change payload cannot overwrite a reload.
      _venueDetailTokens.remove(id);
    }
  }

  bool venueDetailLoading(String id) => _venueDetailTokens.containsKey(id);

  bool venueDetailMissing(String id) => _missingVenueDetails.contains(id);

  String? venueDetailError(String id) => _venueDetailErrors[id];

  void retryVenueDetail(String id) {
    if (_venueDetailTokens.containsKey(id)) return;
    _venueDetailErrors.remove(id);
    _missingVenueDetails.remove(id);
    notifyListeners();
    unawaited(_loadVenueDetail(id));
  }

  Future<void> _loadVenueDetail(String id) async {
    final token = Object();
    _venueDetailTokens[id] = token;
    try {
      final detail = await repository.venueDetail(id);
      if (_disposed || !identical(_venueDetailTokens[id], token)) return;
      _venueDetailErrors.remove(id);
      if (detail == null) {
        _missingVenueDetails.add(id);
        return;
      }
      _missingVenueDetails.remove(id);
      _venueDetails[id] = detail;
      _venueDirectory = {..._venueDirectory, detail.venue.id: detail.venue};
      for (final gig in detail.gigs) {
        _relationshipGigs[gig.id] = gig;
      }
      for (final entry in detail.bands.entries) {
        final relatedGigIds = [
          for (final gig in detail.gigs)
            if (gig.lineup.contains(entry.key)) gig.id,
        ];
        final existingUpcoming = _bands[entry.key]?.upcoming ?? const [];
        _bands[entry.key] = entry.value.copyWith(
          upcoming: {...existingUpcoming, ...relatedGigIds}.toList(),
        );
      }
    } catch (error) {
      logError('venueDetail', error);
      if (_disposed || !identical(_venueDetailTokens[id], token)) return;
      _venueDetailErrors[id] = '$error';
    } finally {
      if (!_disposed && identical(_venueDetailTokens[id], token)) {
        _venueDetailTokens.remove(id);
        notifyListeners();
      }
    }
  }

  /// Returns only a real feed or directory venue, never the display fallback.
  Venue? knownVenue(String id) {
    final venue = _venues[id] ?? _venueDirectory[id];
    if (venue == null) ensureVenueDirectory();
    return venue;
  }

  Venue venue(String id) => knownVenue(id) ?? _unknownVenue;

  int _venuesVersion = -1;
  List<Venue> _cachedVenues = const [];

  /// Every venue the app knows: the curated table plus whatever the live feed
  /// carries. Feed rows win on id — they are realtime. Name-ordered, one entry
  /// per id; this is the only venue list any screen reads.
  List<Venue> get venues {
    ensureVenueDirectory();
    if (_venuesVersion == _stateVersion) return _cachedVenues;
    final merged = <String, Venue>{..._venueDirectory, ..._venues};
    final venues = merged.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    _cachedVenues = List<Venue>.unmodifiable(venues);
    _venuesVersion = _stateVersion;
    return _cachedVenues;
  }

  static const _unknownVenue = Venue(
    id: '',
    name: 'Venue unavailable',
    area: '',
    addr: '',
    point: LatLng(0, 0),
  );
}

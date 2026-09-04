part of '../app_state.dart';

/// The curated venue directory, per-venue relationship details, and the
/// merged venue list every screen reads. The marketplace's venue identity
/// will land here later.
mixin _VenueState on _AppStateCore {
  // ---- requires (declared by sibling mixins or AppState)
  String get bandId;
  Map<String, Band> get _bands;
  set _bands(Map<String, Band> value);
  Map<String, Gig> get _relationshipGigs;
  set _relationshipGigs(Map<String, Gig> value);
  void setGfVenue(String v);

  /// The full curated venue table (`venues:list`), including venues no upcoming
  /// gig references. The feed only carries venues its gigs point at.
  Map<String, Venue> _venueDirectory = const {};
  DataStatus _venueStatus = DataStatus.connecting;
  bool _venueDirectoryRequested = false;
  Object? _venueDirectoryLoadToken;
  StreamSubscription<List<Venue>>? _venueDirectorySubscription;
  DataStatus get venueStatus => _venueStatus;
  String? venueError;

  /// Venue relationship payloads are separate from the discovery feed. They
  /// stay cached across rebuilds; feed changes and venue revisits invalidate
  /// the affected key so its next read refetches authoritative relationships.
  final Map<String, VenueDetail> _venueDetails = {};
  final Set<String> _missingVenueDetails = {};
  final Map<String, Object> _venueDetailTokens = {};
  final Map<String, String> _venueDetailErrors = {};

  /// Keep the directory live even when none of its venues have upcoming gigs.
  void ensureVenueDirectory() {
    if (_venueDirectoryRequested || _disposed) return;
    _venueDirectoryRequested = true;
    _subscribeToVenueDirectory();
  }

  void _subscribeToVenueDirectory() {
    final token = Object();
    _venueDirectoryLoadToken = token;
    unawaited(_venueDirectorySubscription?.cancel());
    _venueDirectorySubscription = repository.watchVenues().listen(
      (loaded) {
        if (_disposed || !identical(_venueDirectoryLoadToken, token)) return;
        final directory = {for (final venue in loaded) venue.id: venue};
        final changedVisibility = <String>{
          for (final id in _venueDirectory.keys)
            if (!directory.containsKey(id)) id,
          for (final id in directory.keys)
            if (!_venueDirectory.containsKey(id)) id,
        };
        _invalidateVenueDetails(changedVisibility);
        _venueDirectory = directory;
        _venueStatus = DataStatus.ready;
        venueError = null;
        notifyListeners();
      },
      onError: (Object error) {
        if (_disposed || !identical(_venueDirectoryLoadToken, token)) return;
        logError('venues', error);
        _venueStatus = DataStatus.error;
        venueError = '$error';
        notifyListeners();
      },
    );
  }

  void retryVenues() {
    if (_venueStatus == DataStatus.connecting) return;
    _venueStatus = DataStatus.connecting;
    venueError = null;
    notifyListeners();
    _subscribeToVenueDirectory();
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
        _venueDirectory = Map.of(_venueDirectory)..remove(id);
        // A directory response already in flight may predate this miss.
        // Restart it so only a fresh server read can restore this venue.
        if (_venueDirectoryRequested) _subscribeToVenueDirectory();
        return;
      }
      _missingVenueDetails.remove(id);
      _venueDetails[id] = detail;
      _venueDirectory = {..._venueDirectory, detail.venue.id: detail.venue};
      _relationshipGigs = {
        ..._relationshipGigs,
        for (final gig in detail.gigs) gig.id: gig,
      };
      final bands = Map.of(_bands);
      for (final entry in detail.bands.entries) {
        final relatedGigIds = [
          for (final gig in detail.gigs)
            if (gig.lineup.contains(entry.key)) gig.id,
        ];
        final existingUpcoming = bands[entry.key]?.upcoming ?? const [];
        bands[entry.key] = entry.value.copyWith(
          upcoming: {...existingUpcoming, ...relatedGigIds}.toList(),
        );
      }
      _bands = bands;
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

  final Memo<
    ({Map<String, Venue> directory, Map<String, Venue> feedVenues}),
    List<Venue>
  >
  _venuesMemo = Memo();

  /// Every venue the app knows: the curated table plus whatever the live feed
  /// carries. Feed rows win on id — they are realtime. Name-ordered, one entry
  /// per id; this is the only venue list any screen reads.
  List<Venue> get venues {
    ensureVenueDirectory();
    final inputs = (directory: _venueDirectory, feedVenues: _venues);
    return _venuesMemo(inputs, () {
      final merged = <String, Venue>{...inputs.directory, ...inputs.feedVenues};
      final venues = merged.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      return List<Venue>.unmodifiable(venues);
    });
  }

  static const _unknownVenue = Venue(
    id: '',
    name: 'Venue unavailable',
    area: '',
    addr: '',
    point: LatLng(0, 0),
  );
}

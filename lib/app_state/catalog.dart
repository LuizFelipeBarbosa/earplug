part of '../app_state.dart';

/// The live gig catalogue: the feed and going-count subscriptions, the
/// boundary and day-rollover timers, every cached gig and band, and the
/// public gig/band loads behind shared links.
mixin _CatalogState on _AppStateCore {
  // ---- requires (declared by sibling mixins or AppState)
  abstract DataStatus _dataStatus;
  abstract List<ScreenEntry> _stack;
  ScreenEntry get current;
  String get bandId;
  Map<String, BandDiscoveryReadiness> get _bandDiscoveryReadiness;
  Set<String> get _bandDiscoveryLoading;
  Set<String> get _bandDiscoveryBoundaryRefreshPending;
  Map<String, VenueDetail> get _venueDetails;
  Map<String, List<Gig>> get _followedBandGigs;
  Map<String, Gig> get _interactionGigs;
  bool isAdminOf(String id);
  Future<void> refreshBandDiscoveryReadiness(String id);
  Future<void> loadBandProfileDetails(String id, {bool refresh = false});

  StreamSubscription<FeedSnapshot>? _feedSubscription;
  StreamSubscription<Map<String, int>>? _goingCountsSubscription;

  StreamSubscription<Gig?>? _publicGigSubscription;

  Timer? _discoveryBoundaryTimer;
  Timer? _dayRolloverTimer;

  String? dataError;

  List<Gig> _allGigs = const [];
  @override
  DateTime? _nextFeedStartsAt;
  bool _hasFeedSnapshot = false;
  bool _goingCountsSettled = false;
  Map<String, Band> _bands = {};
  @override
  Map<String, Venue> _venues = const {};
  Map<String, int> _goingCounts = const {};

  final Map<String, Gig> _relationshipGigs = {};
  final Map<String, Gig> _publicGigs = {};
  final Map<String, String> _publicGigErrors = {};
  final Set<String> _missingPublicGigs = {};
  String? _subscribedPublicGigId;
  bool _publicGigLoading = false;
  int _publicGigGeneration = 0;
  final Set<String> _missingPublicBands = {};
  final Set<String> _loadingPublicBands = {};

  List<String> _mergedUpcoming(
    List<String> feedIds,
    List<String> existingUpcoming,
    Set<String> droppedFeedGigIds,
  ) {
    final merged = List<String>.of(feedIds);
    final seen = feedIds.toSet();
    for (final id in existingUpcoming) {
      if (!droppedFeedGigIds.contains(id) && seen.add(id)) merged.add(id);
    }
    return merged;
  }

  void _subscribeToFeed() {
    _goingCountsSettled = false;
    _feedSubscription = repository.feed().listen(
      _applyFeedSnapshot,
      onError: (Object error) {
        _dataStatus = DataStatus.error;
        dataError = '$error';
        notifyListeners();
      },
    );
    _goingCountsSubscription = repository.goingCounts().listen(
      (incoming) {
        final merged = {..._goingCounts, ...incoming};
        final countsChanged = !mapEquals(_goingCounts, merged);
        if (countsChanged) {
          _goingCounts = Map<String, int>.unmodifiable(merged);
        }

        var readinessChanged = false;
        if (!_goingCountsSettled) {
          _goingCountsSettled = true;
          if (_hasFeedSnapshot && _dataStatus != DataStatus.ready) {
            _dataStatus = DataStatus.ready;
            readinessChanged = true;
          }
        }
        if (countsChanged || readinessChanged) notifyListeners();
      },
      onError: (Object error) {
        logError('goingCounts', error);
        if (_goingCountsSettled) return;
        _goingCountsSettled = true;
        if (_hasFeedSnapshot && _dataStatus != DataStatus.ready) {
          _dataStatus = DataStatus.ready;
          notifyListeners();
        }
      },
    );
  }

  /// Folds one feed snapshot into the caches, keeping band records and
  /// venue-detail invalidation consistent with what the feed dropped.
  void _applyFeedSnapshot(FeedSnapshot snapshot) {
    final hadFeedSnapshot = _hasFeedSnapshot;
    final oldGigsById = {for (final gig in _allGigs) gig.id: gig};
    final oldGigIdsByVenue = <String, Set<String>>{};
    for (final gig in _allGigs) {
      oldGigIdsByVenue.putIfAbsent(gig.venueId, () => {}).add(gig.id);
    }
    if (!hadFeedSnapshot) {
      _hasFeedSnapshot = true;
    }

    final upcomingByBand = <String, List<String>>{};
    final newGigsById = <String, Gig>{};
    final newGigIdsByVenue = <String, Set<String>>{};
    for (final gig in snapshot.gigs) {
      newGigsById[gig.id] = gig;
      for (final bandId in gig.lineup) {
        upcomingByBand.putIfAbsent(bandId, () => []).add(gig.id);
      }
      newGigIdsByVenue.putIfAbsent(gig.venueId, () => {}).add(gig.id);
    }
    final droppedFeedGigIds = oldGigsById.keys.toSet()
      ..removeAll(newGigsById.keys);
    if (hadFeedSnapshot) {
      final changedVenueIds = <String>{};
      for (final venueId in {
        ...oldGigIdsByVenue.keys,
        ...newGigIdsByVenue.keys,
      }) {
        final oldIds = oldGigIdsByVenue[venueId] ?? const <String>{};
        final newIds = newGigIdsByVenue[venueId] ?? const <String>{};
        if (!setEquals(oldIds, newIds) ||
            newIds.any(
              (id) => oldGigsById[id]?.sameListing(newGigsById[id]!) != true,
            )) {
          changedVenueIds.add(venueId);
        }
      }
      _invalidateVenueDetails(changedVenueIds);
    }

    final updatedBands = Map<String, Band>.of(_bands);
    for (final entry in snapshot.bands.entries) {
      final existing = _bands[entry.key];
      final upcoming = _mergedUpcoming(
        upcomingByBand[entry.key] ?? const <String>[],
        existing?.upcoming ?? const <String>[],
        droppedFeedGigIds,
      );
      if (existing != null && !existing.isSummary) {
        final incoming = entry.value;
        final unchanged =
            existing.name == incoming.name &&
            existing.slug == incoming.slug &&
            listEquals(existing.genres, incoming.genres) &&
            existing.area == incoming.area &&
            existing.color == incoming.color &&
            existing.initials == incoming.initials &&
            existing.followers == incoming.followers &&
            existing.avatarUrl == incoming.avatarUrl &&
            existing.avatarUrlResolved == incoming.avatarUrlResolved &&
            existing.profileComplete == incoming.profileComplete &&
            existing.discoveryProfileReady == incoming.discoveryProfileReady &&
            listEquals(existing.upcoming, upcoming);
        updatedBands[entry.key] = unchanged
            ? existing
            : existing.mergeSummary(incoming, upcoming: upcoming);
        continue;
      }
      updatedBands[entry.key] = listEquals(entry.value.upcoming, upcoming)
          ? entry.value
          : entry.value.copyWith(upcoming: upcoming);
    }
    for (final entry in _bands.entries) {
      if (snapshot.bands.containsKey(entry.key)) continue;
      final upcoming = _mergedUpcoming(
        upcomingByBand[entry.key] ?? const <String>[],
        entry.value.upcoming,
        droppedFeedGigIds,
      );
      if (!listEquals(entry.value.upcoming, upcoming)) {
        updatedBands[entry.key] = entry.value.copyWith(upcoming: upcoming);
      }
    }

    _allGigs = List<Gig>.of(snapshot.gigs);
    final retainedGoingCountIds = <String>{
      for (final gig in _allGigs) gig.id,
      ..._relationshipGigs.keys,
      ..._interactionGigs.keys,
    };
    if (_goingCounts.keys.any(
      (gigId) => !retainedGoingCountIds.contains(gigId),
    )) {
      _goingCounts = Map<String, int>.unmodifiable({
        for (final entry in _goingCounts.entries)
          if (retainedGoingCountIds.contains(entry.key)) entry.key: entry.value,
      });
    }
    _nextFeedStartsAt = snapshot.nextStartsAt;
    _syncFollowedBandGigSubscriptions();
    _venues = Map<String, Venue>.of(snapshot.venues);
    _bands = updatedBands;
    _normalizeCustomDateRange();
    if (_goingCountsSettled) {
      _dataStatus = DataStatus.ready;
    } else if (_dataStatus != DataStatus.ready) {
      _dataStatus = DataStatus.connecting;
    }
    dataError = null;
    _scheduleDiscoveryBoundaryRefresh();
    _scheduleDayRollover();
    notifyListeners();
  }

  @override
  void _scheduleDiscoveryBoundaryRefresh() {
    _discoveryBoundaryTimer?.cancel();
    _discoveryBoundaryTimer = null;
    if (_disposed) return;

    final now = _now();
    DateTime? nextBoundary;
    void consider(DateTime boundary) {
      if (!boundary.isAfter(now) ||
          (nextBoundary != null && !boundary.isBefore(nextBoundary!))) {
        return;
      }
      nextBoundary = boundary;
    }

    for (final gig in _allGigs) {
      final creatorId = gig.createdByBand;
      if (creatorId == null ||
          gig.lifecycle != GigLifecycle.published ||
          !gig.discoveryListingReady ||
          _bands[creatorId]?.discoveryProfileReady != true) {
        continue;
      }
      consider(gig.startsAt.subtract(discoveryBoostLead));
      consider(
        gig.startsAt
            .add(discoveryBoostGrace)
            .add(const Duration(milliseconds: 1)),
      );
    }
    for (final entry in _bandDiscoveryReadiness.entries) {
      if (!isAdminOf(entry.key)) continue;
      final window = entry.value.boostWindow;
      if (window == null) continue;
      consider(window.opensAt);
      consider(window.closesAt.add(const Duration(milliseconds: 1)));
    }

    final boundary = nextBoundary;
    if (boundary == null) return;
    _discoveryBoundaryTimer = Timer(
      boundary.difference(now),
      _handleDiscoveryBoundary,
    );
  }

  void _handleDiscoveryBoundary() {
    _discoveryBoundaryTimer = null;
    if (_disposed) return;

    final readinessIds = <String>{
      ..._bandDiscoveryReadiness.keys,
      if (current.screen == Screen.bandDash && bandId.isNotEmpty) bandId,
    };
    for (final id in readinessIds.where(isAdminOf)) {
      if (_bandDiscoveryLoading.contains(id)) {
        _bandDiscoveryBoundaryRefreshPending.add(id);
      } else {
        unawaited(refreshBandDiscoveryReadiness(id));
      }
    }
    _scheduleDiscoveryBoundaryRefresh();
    notifyListeners();
  }

  void _scheduleDayRollover() {
    _dayRolloverTimer?.cancel();
    _dayRolloverTimer = null;
    if (_disposed) return;

    final now = _now();
    final nextMidnight = DateTime(
      now.year,
      now.month,
      now.day + 1,
    ).add(const Duration(seconds: 1));
    _dayRolloverTimer = Timer(nextMidnight.difference(now), _handleDayRollover);
  }

  void _handleDayRollover() {
    _dayRolloverTimer = null;
    if (_disposed) return;

    final now = _now();
    for (var index = 0; index < _allGigs.length; index++) {
      _allGigs[index] = _allGigs[index].relabeled(now: now);
    }
    _relationshipGigs.updateAll((_, gig) => gig.relabeled(now: now));
    _interactionGigs.updateAll((_, gig) => gig.relabeled(now: now));
    _invalidateVenueDetails(_venueDetails.keys.toSet());
    notifyListeners();
    _scheduleDayRollover();
  }

  // ========================= data access =========================

  List<Gig> get allGigs => _allGigs;

  int _gigIndexVersion = -1;
  Map<String, Gig> _gigIndex = const {};

  @override
  Gig? _cachedGig(String id) {
    final direct = _publicGigs[id];
    if (direct != null) return direct;

    if (_gigIndexVersion != _stateVersion) {
      final index = <String, Gig>{};
      for (final gig in allGigs) {
        index.putIfAbsent(gig.id, () => gig);
        index.putIfAbsent(gig.slug, () => gig);
      }
      for (final gigs in _followedBandGigs.values) {
        for (final gig in gigs) {
          index.putIfAbsent(gig.id, () => gig);
        }
      }
      for (final entry in _interactionGigs.entries) {
        index.putIfAbsent(entry.key, () => entry.value);
      }
      for (final entry in _relationshipGigs.entries) {
        index.putIfAbsent(entry.key, () => entry.value);
      }
      _gigIndex = Map<String, Gig>.unmodifiable(index);
      _gigIndexVersion = _stateVersion;
    }
    return _gigIndex[id];
  }

  Gig? gig(String id) {
    final direct = _publicGigs[id];
    if (direct != null) return direct;
    if (_missingPublicGigs.contains(id)) return null;
    final cached = _cachedGig(id);
    if (cached != null) return cached;
    if (!_publicGigErrors.containsKey(id) &&
        (_subscribedPublicGigId != id || !_publicGigLoading)) {
      unawaited(_loadPublicGig(id));
    }
    return null;
  }

  bool publicGigMissing(String id) => _missingPublicGigs.contains(id);

  String? publicGigError(String id) => _publicGigErrors[id];

  void retryPublicGig(String id) {
    _publicGigErrors.remove(id);
    _missingPublicGigs.remove(id);
    unawaited(_loadPublicGig(id, refresh: true));
  }

  void _cancelPublicGigSubscriptionIfHidden() {
    if (current.screen == Screen.gig || _publicGigSubscription == null) return;
    _publicGigGeneration++;
    final subscription = _publicGigSubscription;
    _publicGigSubscription = null;
    _subscribedPublicGigId = null;
    _publicGigLoading = false;
    unawaited(subscription?.cancel());
  }

  @override
  void _syncPublicGigSubscriptionForCurrentScreen() {
    final entry = current;
    if (entry.screen != Screen.gig) {
      _cancelPublicGigSubscriptionIfHidden();
      return;
    }
    final id = entry.param;
    if (id != null &&
        (_subscribedPublicGigId != id || _publicGigSubscription == null)) {
      unawaited(_loadPublicGig(id));
    }
  }

  @override
  Future<void> _loadPublicGig(String id, {bool refresh = false}) async {
    if (!refresh &&
        _subscribedPublicGigId == id &&
        _publicGigSubscription != null) {
      return;
    }
    final generation = ++_publicGigGeneration;
    await _publicGigSubscription?.cancel();
    if (_disposed || generation != _publicGigGeneration) return;
    _subscribedPublicGigId = id;
    _publicGigLoading = true;
    _publicGigErrors.remove(id);
    _missingPublicGigs.remove(id);
    notifyListeners();
    _publicGigSubscription = repository
        .publicGig(id)
        .listen(
          (gig) {
            if (_disposed || generation != _publicGigGeneration) return;
            _publicGigLoading = false;
            _publicGigErrors.remove(id);
            if (gig == null) {
              _publicGigs.remove(id);
              _missingPublicGigs.add(id);
            } else {
              _missingPublicGigs.remove(id);
              _publicGigs[id] = gig;
              _publicGigs[gig.id] = gig;
              _publicGigs[gig.publicRef] = gig;
              if (current.screen == Screen.gig &&
                  current.param == id &&
                  id != gig.publicRef) {
                replaceBrowserPath('/g/${gig.publicRef}');
              }
              for (final bandId in gig.lineup) {
                if (!_bands.containsKey(bandId)) {
                  unawaited(_loadFollowBand(bandId));
                }
              }
            }
            notifyListeners();
          },
          onError: (Object error) {
            if (_disposed || generation != _publicGigGeneration) return;
            logError('publicGig $id', error);
            _publicGigLoading = false;
            _publicGigErrors[id] = genericErrorMessage;
            notifyListeners();
          },
        );
  }

  Band? band(String id) => _bands[id];

  bool publicBandMissing(String ref) => _missingPublicBands.contains(ref);

  Future<void> _loadPublicBand(String slug) async {
    if (!_loadingPublicBands.add(slug)) return;
    _missingPublicBands.remove(slug);
    notifyListeners();
    try {
      final loaded = await repository.bandBySlug(slug);
      if (_disposed) return;
      if (loaded == null) {
        _missingPublicBands.add(slug);
        return;
      }
      _bands[loaded.id] = loaded;
      if (current.screen == Screen.band && current.param == slug) {
        _stack = [
          ..._stack.take(_stack.length - 1),
          ScreenEntry(Screen.band, loaded.id),
        ];
        replaceBrowserPath('/${loaded.slug}');
      }
      unawaited(loadBandProfileDetails(loaded.id));
    } catch (error) {
      logError('bandBySlug $slug', error);
      if (!_disposed) _missingPublicBands.add(slug);
    } finally {
      _loadingPublicBands.remove(slug);
      if (!_disposed) notifyListeners();
    }
  }

  FlyerStyle flyer(String key) => flyerStyles[key] ?? flyerStyles['paper']!;

  void retry() {
    _dataStatus = DataStatus.connecting;
    dataError = null;
    notifyListeners();
    unawaited(_restartFeed());
  }

  Future<void> _restartFeed() async {
    _goingCountsSettled = false;
    await _feedSubscription?.cancel();
    await _goingCountsSubscription?.cancel();
    _subscribeToFeed();
  }
}

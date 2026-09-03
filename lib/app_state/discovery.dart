part of '../app_state.dart';

enum ExploreResultType { all, events, bands, venues }

/// Fan discovery: where the feed is centred, the active filters, the
/// explore query and band directory paging, and the filtered, boosted feed.
mixin _DiscoveryState on _AppStateCore {
  // ---- requires (declared by sibling mixins or AppState)
  set _appliedHomePersonalization(FanCity? value);
  Map<String, Band> get _bands;
  set _bands(Map<String, Band> value);
  List<Gig> get _allGigs;
  List<Gig> get allGigs;
  Map<String, Venue> get _venueDirectory;
  Venue venue(String id);

  // ---- home filters
  bool mapMode = true;
  DiscoveryLocation discoveryLocation = DiscoveryLocation.sf;
  FanCity? _discoveryHomeCity;
  FanCity? get discoveryHomeCity => _discoveryHomeCity;
  LatLng? currentPosition;
  bool locating = false;
  LocationFailure? locationFailure;
  DiscoveryFilters filters = const DiscoveryFilters();
  int _locationRequestGeneration = 0;

  DateFilter get fDate => filters.date;
  DateTimeRange? get fDateRange => filters.dateRange;
  bool get fFree => filters.price == PriceFilter.free;
  Set<String> get fGenres => filters.genres;
  PriceFilter get fPrice => filters.price;
  String? get fVenueId => filters.venueId;
  double? get fMaxDistanceMiles => filters.maxDistanceMiles;
  bool get canFilterByDistance =>
      (discoveryLocation == DiscoveryLocation.current &&
          currentPosition != null) ||
      discoveryLocation == DiscoveryLocation.home;
  int get activeFilterCount => filters.activeCount;

  // ---- explore
  String query = '';
  ExploreResultType exploreResultType = ExploreResultType.all;
  List<String> exploreBandIds = [];
  bool exploreBandsLoading = false;
  bool _exploreBandsRequested = false;
  bool _exploreBandsDone = false;
  bool _exploreBandsRefreshQueued = false;
  String? _exploreBandsCursor;
  String? exploreBandsError;

  bool get hasMoreExploreBands => !_exploreBandsDone;

  Future<void> _loadExploreBandPage() async {
    if (exploreBandsLoading || _exploreBandsDone) return;
    exploreBandsLoading = true;
    exploreBandsError = null;
    notifyListeners();
    try {
      final page = await repository.listBands(cursor: _exploreBandsCursor);
      if (_disposed) return;
      final ids = exploreBandIds.toSet();
      final bands = Map.of(_bands);
      for (final band in page.items) {
        if (ids.add(band.id)) exploreBandIds.add(band.id);
        // Directory rows promote feed summaries to full profiles while the
        // feed remains authoritative for each band's upcoming gig ids. A full
        // cached profile is already at least as rich as the directory row.
        final cached = bands[band.id];
        if (cached == null) {
          bands[band.id] = band;
        } else if (cached.isSummary) {
          bands[band.id] = band.copyWith(upcoming: cached.upcoming);
        }
      }
      _bands = bands;
      _exploreBandsCursor = page.continueCursor;
      _exploreBandsDone = page.isDone;
    } catch (error) {
      logError('listBands', error);
      if (!_disposed) exploreBandsError = '$error';
    } finally {
      if (!_disposed) {
        exploreBandsLoading = false;
        if (_exploreBandsRefreshQueued) {
          _exploreBandsRefreshQueued = false;
          _refreshExploreBands();
        } else {
          notifyListeners();
        }
      }
    }
  }

  /// One-shot page fetch, following the `ensureVenueDirectory` pattern.
  void ensureExploreBands() {
    if (_exploreBandsRequested || _disposed) return;
    _exploreBandsRequested = true;
    unawaited(_loadExploreBandPage());
  }

  void loadMoreExploreBands() => unawaited(_loadExploreBandPage());

  void retryExploreBands() {
    if (exploreBandsLoading) return;
    exploreBandsError = null;
    notifyListeners();
    unawaited(_loadExploreBandPage());
  }

  @override
  void _refreshExploreBands() {
    if (exploreBandsLoading) {
      _exploreBandsRefreshQueued = true;
      return;
    }
    exploreBandIds = [];
    _exploreBandsCursor = null;
    _exploreBandsDone = false;
    exploreBandsError = null;
    unawaited(_loadExploreBandPage());
  }

  // ========================= filters =========================

  void setMapMode(bool on) => _set(() => mapMode = on);

  void setCity(String c) {
    _applyDiscoveryCity(c);
    say(
      c == 'oak'
          ? 'Showing gigs near Temescal.'
          : 'Showing gigs near the Mission.',
    );
  }

  void _applyDiscoveryCity(String c) {
    _appliedHomePersonalization = null;
    _locationRequestGeneration++;
    discoveryLocation = c == 'oak'
        ? DiscoveryLocation.oak
        : DiscoveryLocation.sf;
    _discoveryHomeCity = null;
    currentPosition = null;
    locating = false;
    locationFailure = null;
    filters = filters.copyWith(maxDistanceMiles: null);
  }

  @override
  void _applyFanCity(FanCity selectedCity) {
    _appliedHomePersonalization = null;
    _locationRequestGeneration++;
    discoveryLocation = discoveryLocationForFanCity(selectedCity);
    _discoveryHomeCity = discoveryLocation == DiscoveryLocation.home
        ? selectedCity
        : null;
    currentPosition = null;
    locating = false;
    locationFailure = null;
    filters = filters.copyWith(maxDistanceMiles: null);
  }

  void useCurrentPosition(LatLng position) => _set(() {
    _appliedHomePersonalization = null;
    _locationRequestGeneration++;
    currentPosition = position;
    discoveryLocation = DiscoveryLocation.current;
    _discoveryHomeCity = null;
    locating = false;
    locationFailure = null;
  });

  Future<bool> selectCurrentLocation() async {
    if (locating) return false;
    final requestGeneration = ++_locationRequestGeneration;
    locating = true;
    locationFailure = null;
    notifyListeners();

    try {
      final result = await locationService.requestCurrentLocation().timeout(
        const Duration(seconds: 22),
      );
      if (_disposed || requestGeneration != _locationRequestGeneration) {
        return false;
      }
      switch (result) {
        case LocationSuccess(:final location):
          _appliedHomePersonalization = null;
          currentPosition = LatLng(location.latitude, location.longitude);
          discoveryLocation = DiscoveryLocation.current;
          _discoveryHomeCity = null;
          locationFailure = null;
          say('Showing gigs near your current location.');
          return true;
        case final LocationFailure failure:
          locationFailure = failure;
          notifyListeners();
          return false;
      }
    } on TimeoutException {
      if (!_disposed && requestGeneration == _locationRequestGeneration) {
        locationFailure = const LocationFailure(
          LocationFailureReason.unavailable,
          message: 'Location request timed out. Retry or choose a city.',
        );
        notifyListeners();
      }
      return false;
    } finally {
      if (!_disposed && requestGeneration == _locationRequestGeneration) {
        locating = false;
        notifyListeners();
      }
    }
  }

  Future<bool> openLocationRecoverySettings() {
    return switch (locationFailure?.reason) {
      LocationFailureReason.servicesDisabled =>
        locationService.openLocationSettings(),
      LocationFailureReason.permissionDeniedForever =>
        locationService.openAppSettings(),
      _ => Future.value(false),
    };
  }

  String get locationLabel => switch (discoveryLocation) {
    DiscoveryLocation.current => 'CURRENT LOCATION',
    DiscoveryLocation.home =>
      '${(_discoveryHomeCity ?? FanCity.sf).label.toUpperCase()} SCENE',
    DiscoveryLocation.oak => 'TEMESCAL, OAK',
    DiscoveryLocation.sf => 'MISSION, SF',
  };

  LatLng get discoveryCenter => switch (discoveryLocation) {
    DiscoveryLocation.current =>
      currentPosition ?? const LatLng(37.7599, -122.4148),
    DiscoveryLocation.home => (_discoveryHomeCity ?? FanCity.sf).center,
    DiscoveryLocation.oak => const LatLng(37.8378, -122.2628),
    DiscoveryLocation.sf => const LatLng(37.7599, -122.4148),
  };

  void toggleDateFilter(DateFilter value) => _set(() {
    filters = filters.copyWith(
      date: filters.date == value ? DateFilter.all : value,
      dateRange: null,
    );
  });

  void setDateRange(DateTimeRange range) => _set(() {
    if (!canSelectCustomDate) return;
    final first = firstSelectableDiscoveryDate;
    final last = lastSelectableDiscoveryDate;
    var start = DateTime(range.start.year, range.start.month, range.start.day);
    var end = DateTime(range.end.year, range.end.month, range.end.day);
    if (start.isBefore(first)) start = first;
    if (start.isAfter(last)) start = last;
    if (end.isBefore(start)) end = start;
    if (end.isAfter(last)) end = last;
    filters = filters.copyWith(
      date: DateFilter.custom,
      dateRange: DateTimeRange(start: start, end: end),
    );
  });

  void clearDateFilter() => _set(() {
    filters = filters.copyWith(date: DateFilter.all, dateRange: null);
  });

  void widenDateFilter() => _set(() {
    final range = filters.dateRange;
    if (filters.date == DateFilter.tonight) {
      filters = filters.copyWith(date: DateFilter.week, dateRange: null);
    } else if (filters.date == DateFilter.week) {
      filters = filters.copyWith(date: DateFilter.all, dateRange: null);
    } else if (filters.date == DateFilter.custom && range != null) {
      final earliest = firstSelectableDiscoveryDate;
      final latest = lastSelectableDiscoveryDate;
      final expandedStart = DateTime(
        range.start.year,
        range.start.month,
        range.start.day - 7,
      );
      final expandedEnd = DateTime(
        range.end.year,
        range.end.month,
        range.end.day + 7,
      );
      filters = filters.copyWith(
        dateRange: DateTimeRange(
          start: expandedStart.isBefore(earliest) ? earliest : expandedStart,
          end: expandedEnd.isAfter(latest) ? latest : expandedEnd,
        ),
      );
    }
  });

  DateTime get firstSelectableDiscoveryDate {
    final today = DateTime.now();
    return DateTime(today.year, today.month, today.day);
  }

  bool get canSelectCustomDate => _lastCompleteDiscoveryDate != null;

  DateTime get lastSelectableDiscoveryDate {
    final first = firstSelectableDiscoveryDate;
    return _lastCompleteDiscoveryDate ?? first;
  }

  DateTime? get _lastCompleteDiscoveryDate {
    final first = firstSelectableDiscoveryDate;
    final pickerLimit = DateTime(first.year, first.month, first.day + 365);
    if (_allGigs.isEmpty) {
      return _nextFeedStartsAt == null ? first : null;
    }

    final latestStart = _allGigs
        .map((gig) => gig.startsAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    var lastComplete = DateTime(
      latestStart.year,
      latestStart.month,
      latestStart.day,
    );
    if (_nextFeedStartsAt case final next?) {
      final nextDay = DateTime(next.year, next.month, next.day);
      if (!nextDay.isAfter(lastComplete)) {
        lastComplete = DateTime(
          lastComplete.year,
          lastComplete.month,
          lastComplete.day - 1,
        );
      }
    } else if (lastComplete.isBefore(first)) {
      lastComplete = first;
    }

    if (lastComplete.isBefore(first)) return null;
    return lastComplete.isAfter(pickerLimit) ? pickerLimit : lastComplete;
  }

  @override
  void _normalizeCustomDateRange() {
    if (filters.date != DateFilter.custom) return;
    final range = filters.dateRange;
    if (range == null || !canSelectCustomDate) {
      filters = filters.copyWith(date: DateFilter.all, dateRange: null);
      return;
    }

    final first = firstSelectableDiscoveryDate;
    final last = lastSelectableDiscoveryDate;
    var start = range.start.isBefore(first) ? first : range.start;
    if (start.isAfter(last)) start = last;
    var end = range.end.isAfter(last) ? last : range.end;
    if (end.isBefore(start)) end = start;
    filters = filters.copyWith(
      dateRange: DateTimeRange(start: start, end: end),
    );
  }

  void toggleFree() => setPriceFilter(
    filters.price == PriceFilter.free ? PriceFilter.any : PriceFilter.free,
  );

  void setPriceFilter(PriceFilter price) =>
      _set(() => filters = filters.copyWith(price: price));

  void toggleGenre(String genre) => _set(() {
    final selected = Set<String>.of(filters.genres);
    selected.contains(genre) ? selected.remove(genre) : selected.add(genre);
    filters = filters.copyWith(genres: selected);
  });

  void clearGenreFilters() =>
      _set(() => filters = filters.copyWith(genres: const {}));

  void setVenueFilter(String? venueId) =>
      _set(() => filters = filters.copyWith(venueId: venueId));

  void setDistanceFilter(double? miles) => _set(() {
    filters = filters.copyWith(
      maxDistanceMiles: canFilterByDistance ? miles : null,
    );
  });

  void clearDiscoveryFilters() =>
      _set(() => filters = const DiscoveryFilters());

  void setQuery(String q) => _set(() {
    query = q;
    exploreResultType = ExploreResultType.all;
  });

  void setExploreResultType(ExploreResultType type) =>
      _set(() => exploreResultType = type);

  double? distanceMilesFromCurrent(Venue venue) {
    final origin = currentPosition;
    if (discoveryLocation != DiscoveryLocation.current || origin == null) {
      return null;
    }
    return distanceInMiles(
      startLatitude: origin.latitude,
      startLongitude: origin.longitude,
      endLatitude: venue.point.latitude,
      endLongitude: venue.point.longitude,
    );
  }

  String distanceOf(Venue venue) {
    final calculated = _distanceMilesFromDiscoveryCenter(venue);
    return '${calculated.toStringAsFixed(1)} mi';
  }

  double _distanceMilesFromDiscoveryCenter(Venue venue) => distanceInMiles(
    startLatitude: discoveryCenter.latitude,
    startLongitude: discoveryCenter.longitude,
    endLatitude: venue.point.latitude,
    endLongitude: venue.point.longitude,
  );

  ({
    List<Gig> gigs,
    DiscoveryFilters filters,
    DateTime startOfToday,
    DiscoveryLocation location,
    LatLng? position,
    FanCity? homeCity,
    Map<String, Venue> feedVenues,
    Map<String, Venue> venueDirectory,
    Set<String> boostedGigIds,
  })?
  _feedInputs;
  List<Gig> _cachedFeed = const [];

  /// The filtered, distance-ordered discovery feed. Recomputed only when one
  /// of its inputs changes: the collections compare by identity (they are
  /// replaced, never mutated), the filters by value.
  List<Gig> get feed {
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    final inputs = (
      gigs: allGigs,
      filters: filters,
      startOfToday: startOfToday,
      location: discoveryLocation,
      position: currentPosition,
      homeCity: _discoveryHomeCity,
      feedVenues: _venues,
      venueDirectory: _venueDirectory,
      boostedGigIds: _discoveryBoostedGigIds,
    );
    if (inputs == _feedInputs) return _cachedFeed;

    final endOfTonight = DateTime(today.year, today.month, today.day + 1);
    final endOfWeek = DateTime(today.year, today.month, today.day + 8);
    final filtered = allGigs.where((gig) {
      final startsAt = gig.startsAt;
      switch (filters.date) {
        case DateFilter.all:
          break;
        case DateFilter.tonight:
          if (startsAt.isBefore(startOfToday) ||
              !startsAt.isBefore(endOfTonight)) {
            return false;
          }
        case DateFilter.week:
          if (startsAt.isBefore(startOfToday) ||
              !startsAt.isBefore(endOfWeek)) {
            return false;
          }
        case DateFilter.custom:
          final range = filters.dateRange;
          if (range == null) return false;
          final endExclusive = DateTime(
            range.end.year,
            range.end.month,
            range.end.day + 1,
          );
          if (startsAt.isBefore(range.start) ||
              !startsAt.isBefore(endExclusive)) {
            return false;
          }
      }

      if (filters.price == PriceFilter.free && !gig.free) return false;
      if (filters.price == PriceFilter.paid && gig.free) return false;
      if (filters.genres.isNotEmpty &&
          !gig.genres.any(filters.genres.contains)) {
        return false;
      }
      if (filters.venueId case final String venueId) {
        if (gig.venueId != venueId) return false;
      }
      if (filters.maxDistanceMiles case final double maxMiles) {
        final distance = discoveryLocation == DiscoveryLocation.home
            ? _distanceMilesFromDiscoveryCenter(venue(gig.venueId))
            : distanceMilesFromCurrent(venue(gig.venueId));
        if (distance != null && distance > maxMiles) return false;
      }
      return true;
    }).toList();

    final venueDistanceById = <String, double>{};
    for (final gig in filtered) {
      venueDistanceById.putIfAbsent(
        gig.venueId,
        () => _distanceMilesFromDiscoveryCenter(venue(gig.venueId)),
      );
    }

    _cachedFeed = List<Gig>.unmodifiable(
      orderDiscoveryGigs(
        gigs: filtered,
        distanceMiles: (gig) => venueDistanceById[gig.venueId]!,
        boostedGigIds: inputs.boostedGigIds,
      ),
    );
    _feedInputs = inputs;
    return _cachedFeed;
  }

  ({List<Gig> gigs, Map<String, Band> bands, int second})?
  _discoveryBoostedGigIdsInputs;
  Set<String> _cachedDiscoveryBoostedGigIds = const {};

  /// The gigs inside their discovery boost window right now, re-evaluated at
  /// most once a second. Keeps its instance while membership is unchanged so
  /// [feed] can key on it by identity.
  Set<String> get _discoveryBoostedGigIds {
    final now = _now();
    final inputs = (
      gigs: allGigs,
      bands: _bands,
      second: now.millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond,
    );
    if (inputs == _discoveryBoostedGigIdsInputs) {
      return _cachedDiscoveryBoostedGigIds;
    }
    final boosted = discoveryBoostedGigIds(
      gigs: inputs.gigs,
      bands: inputs.bands,
      now: now,
    );
    if (!setEquals(boosted, _cachedDiscoveryBoostedGigIds)) {
      _cachedDiscoveryBoostedGigIds = Set<String>.unmodifiable(boosted);
    }
    _discoveryBoostedGigIdsInputs = inputs;
    return _cachedDiscoveryBoostedGigIds;
  }

  bool isDiscoveryBoosted(Gig gig, {DateTime? now}) {
    if (now != null) {
      return discoveryBoostedGigIds(
        gigs: allGigs,
        bands: _bands,
        now: now,
      ).contains(gig.id);
    }
    return _discoveryBoostedGigIds.contains(gig.id);
  }
}

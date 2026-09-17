part of '../app_state.dart';

/// The derived state for Explore: recommendations, collections, venue rows,
/// genre chips, and the selected genre page, all memoized by their inputs.
mixin _ExploreState on _AppStateCore {
  // ---- requires (declared by sibling mixins or AppState)
  List<Gig> get allGigs;
  Map<String, Band> get _bands;
  List<Venue> get venues;
  Venue venue(String id);
  Venue? knownVenue(String id);
  @override
  recent_searches.RecentSearchesStore get recentSearchesStore;
  String get query;
  Set<String> get follows;
  Set<String> get saved;
  Set<String> get rsvps;
  UserProfile? get profile;
  bool get authed;
  FanCity? get discoveryHomeCity;
  List<String> get exploreBandIds;
  List<FanHistoryItem> get history;
  List<({Gig gig, List<SocialUserCard> friends})> get friendsGoing;
  Set<String> get userGenres;
  Map<String, Gig> get _interactionGigs;
  Set<String> get _discoveryBoostedGigIds;

  final Memo<
    ({
      List<Gig> allGigs,
      Map<String, Band> bands,
      List<Venue> venues,
      Set<String> follows,
      Set<String> saved,
      Set<String> rsvps,
      UserProfile? profile,
      String genresKey,
      FanCity? homeCity,
      bool authed,
      String dayKey,
      int quarterHourBucket,
      List<String> exploreBandIds,
    }),
    ExploreHome
  >
  _exploreHomeMemo = Memo();

  final Memo<
    ({
      List<Gig> allGigs,
      List<FanHistoryItem> history,
      Map<String, Gig> interactionGigs,
      Map<String, Band> bands,
      Set<String> follows,
      Set<String> saved,
      Set<String> rsvps,
      String genresKey,
      bool authed,
    }),
    List<GenreChip>
  >
  _exploreGenresMemo = Memo();

  final Memo<
    ({
      String genre,
      List<Gig> allGigs,
      Map<String, Band> bands,
      List<String> exploreBandIds,
      Set<String> follows,
      Set<String> saved,
      List<({Gig gig, List<SocialUserCard> friends})> friendsGoing,
      Set<String> boostedGigIds,
      String genresKey,
      FanCity? homeCity,
      int quarterHourBucket,
    }),
    ExploreGenrePage
  >
  _exploreGenrePageMemo = Memo();

  String? _exploreGenre;

  ExploreSignals _signals() {
    return ExploreSignals(
      userGenres: {for (final genre in userGenres) canonicalGenre(genre)},
      followedBandIds: follows,
      savedGigIds: saved,
      rsvpGigIds: rsvps,
      homeCity: discoveryHomeCity ?? profile?.homeLocation,
      signedIn: authed,
      seed: profile?.email ?? 'anon',
      now: _now(),
      friendGigIds: {for (final entry in friendsGoing) entry.gig.id},
      boostedGigIds: _discoveryBoostedGigIds,
    );
  }

  String get _genresKey =>
      (userGenres.map(canonicalGenre).toList()..sort()).join(',');

  ExploreHome get exploreHome {
    final now = _now();
    final inputs = (
      allGigs: allGigs,
      bands: _bands,
      venues: venues,
      follows: follows,
      saved: saved,
      rsvps: rsvps,
      profile: profile,
      genresKey: _genresKey,
      homeCity: discoveryHomeCity,
      authed: authed,
      dayKey: dayKey(now),
      quarterHourBucket: now.millisecondsSinceEpoch ~/ (15 * 60 * 1000),
      exploreBandIds: exploreBandIds,
    );
    return _exploreHomeMemo(inputs, () {
      final signals = _signals();
      final tonight = allGigs
          .where((gig) => gig.when == GigWhen.tonight)
          .toList();
      final week = allGigs.where((gig) => gig.when == GigWhen.week).toList();
      final upcoming = allGigs
          .where((gig) => gig.when == GigWhen.later)
          .toList();
      final recommendedBandIds = rankRecommendedBands(
        bands: _bands,
        feed: allGigs,
        signals: signals,
      );
      final ranked = rankForYou(
        gigs: allGigs,
        bands: _bands,
        signals: signals,
        distanceMiles: (gig) =>
            _distanceMilesFromDiscoveryCenter(venue(gig.venueId)),
      );
      final venues = venuesWithShows(feed: allGigs, venue: venue);
      return ExploreHome(
        recommendedBandIds: recommendedBandIds,
        collections: buildCollections(
          feed: allGigs,
          venue: venue,
          bands: _bands,
          signals: signals,
        ),
        tonight: List.unmodifiable(tonight),
        week: List.unmodifiable(week),
        upcoming: List.unmodifiable(upcoming),
        venues: venues,
        featured: List.unmodifiable(ranked.featured),
        forYou: List.unmodifiable(ranked.forYou),
        discover: List.unmodifiable(discoverRail(
          venues: venues,
          recommendedBandIds: recommendedBandIds,
        )),
        personalised: authed && (userGenres.isNotEmpty || follows.isNotEmpty),
      );
    });
  }

  List<GenreChip> get exploreGenres {
    final inputs = (
      allGigs: allGigs,
      history: history,
      interactionGigs: _interactionGigs,
      bands: _bands,
      follows: follows,
      saved: saved,
      rsvps: rsvps,
      genresKey: _genresKey,
      authed: authed,
    );
    return _exploreGenresMemo(inputs, () {
      final signals = _signals();
      return rankGenres(
        feed: allGigs,
        attendedGigGenres: history.map((item) => item.genres),
        interactionGigs: _interactionGigs.values,
        bands: _bands,
        signals: signals,
      );
    });
  }

  String? get exploreGenre => _exploreGenre;

  void setExploreGenre(String? genre) {
    final canonical = genre == null ? null : canonicalGenre(genre);
    final next = canonical == null || canonical.isEmpty ? null : canonical;
    if (next == _exploreGenre) return;
    _set(() => _exploreGenre = next);
  }

  ExploreGenrePage? get exploreGenrePage {
    final genre = _exploreGenre;
    if (genre == null) return null;
    final now = _now();
    final inputs = (
      genre: genre,
      allGigs: allGigs,
      bands: _bands,
      exploreBandIds: exploreBandIds,
      follows: follows,
      saved: saved,
      friendsGoing: friendsGoing,
      boostedGigIds: _discoveryBoostedGigIds,
      genresKey: _genresKey,
      homeCity: discoveryHomeCity,
      quarterHourBucket: now.millisecondsSinceEpoch ~/ (15 * 60 * 1000),
    );
    return _exploreGenrePageMemo(inputs, () {
      final signals = _signals();
      return buildGenrePage(
        genre: genre,
        feed: allGigs,
        bands: _bands,
        directoryBandIds: exploreBandIds,
        signals: signals,
        distanceMiles: (gig) =>
            _distanceMilesFromDiscoveryCenter(venue(gig.venueId)),
      );
    });
  }

  ExploreCollection? exploreCollection(String key) {
    final home = exploreHome;
    switch (key) {
      case 'tonight':
        return ExploreCollection(
          key: key,
          kind: ExploreCollectionKind.tonight,
          title: 'Tonight',
          gigs: home.tonight,
          score: home.tonight.length,
        );
      case 'week':
        return ExploreCollection(
          key: key,
          kind: ExploreCollectionKind.week,
          title: 'This week',
          gigs: home.week,
          score: home.week.length,
        );
      case 'upcoming':
        return ExploreCollection(
          key: key,
          kind: ExploreCollectionKind.week,
          title: 'Coming up',
          gigs: home.upcoming,
          score: home.upcoming.length,
        );
      case 'just-for-you':
        return ExploreCollection(
          key: key,
          kind: ExploreCollectionKind.following,
          title: 'Just for you',
          gigs: home.forYou,
          score: home.forYou.length,
        );
      case 'featured':
        return ExploreCollection(
          key: key,
          kind: ExploreCollectionKind.following,
          title: 'Featured',
          gigs: home.featured,
          score: home.featured.length,
        );
    }
    for (final collection in home.collections) {
      if (collection.key == key) return collection;
    }
    return null;
  }

  // ---- search
  List<String> _recentSearches = const [];

  /// Newest first, capped at [recent_searches.kRecentSearchLimit].
  List<String> get recentSearches => List.unmodifiable(_recentSearches);

  Future<void> loadRecentSearches() async {
    final saved = await recentSearchesStore.load();
    if (_disposed) return;
    _set(() => _recentSearches = saved);
  }

  Future<void> recordSearch(String q) async {
    _set(
      () => _recentSearches = recent_searches.pushRecentSearch(
        _recentSearches,
        q,
      ),
    );
    await recentSearchesStore.save(_recentSearches);
  }

  Future<void> removeRecentSearch(String q) async {
    _set(
      () => _recentSearches = recent_searches.removeRecentSearch(
        _recentSearches,
        q,
      ),
    );
    await recentSearchesStore.save(_recentSearches);
  }

  ParsedSearch get parsedSearch => parseSearchQuery(query);

  final Memo<
    ({
      String query,
      List<Gig> allGigs,
      List<Venue> venues,
      Map<String, Band> bands,
      List<({Gig gig, List<SocialUserCard> friends})> friendsGoing,
      Set<String> saved,
      int quarterHourBucket,
    }),
    List<SearchHit>
  >
  _searchResultsMemo = Memo();

  /// The ranked search hits for [query]; empty while the query is blank.
  List<SearchHit> get searchResults {
    final now = _now();
    final inputs = (
      query: query,
      allGigs: allGigs,
      venues: venues,
      bands: _bands,
      friendsGoing: friendsGoing,
      saved: saved,
      quarterHourBucket: now.millisecondsSinceEpoch ~/ (15 * 60 * 1000),
    );
    return _searchResultsMemo(inputs, () {
      double? distanceMiles(Gig gig) {
        final gigVenue = knownVenue(gig.venueId);
        return gigVenue == null
            ? null
            : _distanceMilesFromDiscoveryCenter(gigVenue);
      }

      return rankSearchResults(
        parsed: parseSearchQuery(inputs.query),
        gigs: inputs.allGigs,
        band: (id) => inputs.bands[id],
        venue: venue,
        now: now,
        distanceMiles: distanceMiles,
        friendGigIds: {for (final entry in inputs.friendsGoing) entry.gig.id},
        savedGigIds: inputs.saved,
      );
    });
  }

  final Memo<({String query, Map<String, Band> bands}), List<Band>>
  _bandSearchResultsMemo = Memo();

  /// Bands whose name or genres match [query], best first; empty while the
  /// query is blank.
  List<Band> get bandSearchResults => _bandSearchResultsMemo((
    query: query,
    bands: _bands,
  ), () => rankBandResults(query, _bands.values));
}

/// Everything the Explore browse page renders, computed once per input
/// change. `upcoming` is `feed` minus whatever landed in `tonight` or `week`.
class ExploreHome {
  const ExploreHome({
    required this.recommendedBandIds,
    required this.collections,
    required this.tonight,
    required this.week,
    required this.upcoming,
    required this.venues,
    required this.featured,
    required this.forYou,
    required this.discover,
    required this.personalised,
  });

  final List<String> recommendedBandIds;
  final List<ExploreCollection> collections;
  final List<Gig> tonight;
  final List<Gig> week;
  final List<Gig> upcoming;
  final List<VenueWithShows> venues;
  final List<Gig> featured;
  final List<Gig> forYou;
  final List<DiscoverEntry> discover;
  final bool personalised;
}

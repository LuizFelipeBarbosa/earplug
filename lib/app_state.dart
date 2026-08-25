import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateTimeRange, TimeOfDay;
import 'package:latlong2/latlong.dart';

import 'band_media_state.dart';
import 'data/convex_repository.dart';
import 'data/demo_repository.dart';
import 'data/repository.dart';
import 'date_names.dart';
import 'demo_data.dart';
import 'errors.dart';
import 'models.dart';
import 'services/auth_service.dart';
import 'services/location_service.dart';
import 'services/media_picker.dart';
import 'services/media_upload_service.dart';

String _bandInitials(String name) => name
    .split(RegExp(r'\s+'))
    .where((word) => word.isNotEmpty)
    .map((word) => word[0])
    .take(2)
    .join()
    .toUpperCase();

enum Screen {
  home,
  gig,
  band,
  bandPreview,
  bandJoin,
  venue,
  explore,
  myGigs,
  auth,
  bandCreate,
  bandDash,
  bandEdit,
  bandMedia,
  editProfile,
  settings,
  gigMgr,
  gigCreate,
  analytics,
}

class ScreenEntry {
  final Screen screen;
  final String? param; // gig id or band id where relevant

  const ScreenEntry(this.screen, [this.param]);
}

enum DateFilter { all, tonight, week, custom }

enum PriceFilter { any, free, paid }

enum DiscoveryLocation { sf, oak, current }

class DiscoveryFilters {
  const DiscoveryFilters({
    this.date = DateFilter.all,
    this.dateRange,
    this.genres = const {},
    this.price = PriceFilter.any,
    this.venueId,
    this.maxDistanceMiles,
  });

  final DateFilter date;
  final DateTimeRange? dateRange;
  final Set<String> genres;
  final PriceFilter price;
  final String? venueId;
  final double? maxDistanceMiles;

  static const _unset = Object();

  DiscoveryFilters copyWith({
    DateFilter? date,
    Object? dateRange = _unset,
    Set<String>? genres,
    PriceFilter? price,
    Object? venueId = _unset,
    Object? maxDistanceMiles = _unset,
  }) {
    return DiscoveryFilters(
      date: date ?? this.date,
      dateRange: identical(dateRange, _unset)
          ? this.dateRange
          : dateRange as DateTimeRange?,
      genres: genres == null ? this.genres : Set.unmodifiable(genres),
      price: price ?? this.price,
      venueId: identical(venueId, _unset) ? this.venueId : venueId as String?,
      maxDistanceMiles: identical(maxDistanceMiles, _unset)
          ? this.maxDistanceMiles
          : maxDistanceMiles as double?,
    );
  }

  int get activeCount =>
      (date == DateFilter.all ? 0 : 1) +
      (genres.isEmpty ? 0 : 1) +
      (price == PriceFilter.any ? 0 : 1) +
      (venueId == null ? 0 : 1) +
      (maxDistanceMiles == null ? 0 : 1);
}

enum PendingKind { rsvp, follow, save, myGigs, band, join }

enum DataStatus { connecting, ready, error }

enum ExploreResultType { all, events, bands, venues }

class PendingAuth {
  final PendingKind kind;
  final String? id;

  const PendingAuth(this.kind, [this.id]);
}

class AppState extends ChangeNotifier {
  AppState({
    EarplugRepository? repository,
    AuthService? auth,
    LocationService? locationService,
    MediaUploadService? mediaUploadService,
    String? initialJoinToken,
  }) : this._(
         auth ?? FakeAuthService(),
         repository,
         locationService ?? GeolocatorLocationService(),
         mediaUploadService,
         initialJoinToken,
       );

  AppState._(
    AuthService resolvedAuth,
    EarplugRepository? providedRepository,
    this.locationService,
    MediaUploadService? providedMediaUploader,
    String? initialJoinToken,
  ) : auth = resolvedAuth,
      repository = providedRepository ?? DemoRepository(auth: resolvedAuth),
      // Only a real backend has a connection to wait on; the demo data is
      // already in memory, so it must not show the connecting screen.
      _dataStatus = providedRepository is ConvexRepository
          ? DataStatus.connecting
          : DataStatus.ready {
    mediaUploader =
        providedMediaUploader ?? MediaUploadService(repository: repository);
    authed = auth.signedIn;
    if (authed) {
      authStep = 2;
      _authReady = _ensureUser();
      unawaited(_authReady);
    }
    _authSubscription = auth.signedInChanges.listen(_handleAuthChange);
    _subscribeToFeed();
    _interactionsSubscription = repository.myInteractions().listen(
      _cacheInteractions,
      onError: (Object error) => logError('myInteractions', error),
    );
    // Public demo mode may preload membership-shaped sample data, but
    // authenticated routing waits for the post-refresh stream below.
    if (!authed) {
      _bandsSubscription = _listenToMemberships(
        ++_membershipsGeneration,
        requireAuthentication: false,
      );
    }
    final token = initialJoinToken?.trim();
    if (token != null && token.isNotEmpty) {
      _stack = [ScreenEntry(Screen.bandJoin, token)];
      unawaited(_resolveJoinInvite(token));
    }
  }

  final EarplugRepository repository;
  final AuthService auth;
  final LocationService locationService;
  late final MediaUploadService mediaUploader;

  StreamSubscription<bool>? _authSubscription;
  StreamSubscription<FeedSnapshot>? _feedSubscription;
  StreamSubscription<Interactions>? _interactionsSubscription;
  StreamSubscription<List<BandMembership>>? _bandsSubscription;
  final Map<String, StreamSubscription<List<Gig>>>
  _followedBandGigSubscriptions = {};
  final Map<String, Object> _followedBandGigTokens = {};
  final Map<String, List<Gig>> _followedBandGigs = {};
  int _membershipsGeneration = 0;
  int _sessionGeneration = 0;
  bool _disposed = false;

  DataStatus _dataStatus;
  DataStatus get dataStatus => _dataStatus;
  String? dataError;

  List<Gig> _allGigs = const [];
  DateTime? _nextFeedStartsAt;
  bool _hasFeedSnapshot = false;
  Map<String, Band> _bands = {};
  Map<String, Venue> _venues = const {};

  /// The full curated venue table (`venues:list`), including venues no upcoming
  /// gig references. The feed only carries venues its gigs point at.
  Map<String, Venue> _venueDirectory = const {};
  DataStatus _venueStatus = DataStatus.connecting;
  DataStatus get venueStatus => _venueStatus;
  String? venueError;

  final Map<String, String> _bandRoles = {};

  /// Past gigs per band, from `gigs:pastForBand`. Lazily loaded on first read.
  /// Follows `BandMediaController.mediaFor` / `_loadMedia`: a read-triggered
  /// per-band cache with a staleness token and one final notification.
  /// Deliberate deviation: media retries after its own failure rebuild; this
  /// cache gates on the error map until an explicit [refreshBandHistory].
  final Map<String, BandHistory> _bandHistory = {};
  final Map<String, Object> _bandHistoryTokens = {};
  final Map<String, String> _bandHistoryErrors = {};

  /// Aggregated performance data per band, from `analytics:bandRecap`.
  /// Lazily loaded and held on failure until an explicit [refreshBandRecap].
  final Map<String, BandRecap> _bandRecap = {};
  final Map<String, Object> _bandRecapTokens = {};
  final Map<String, String> _bandRecapErrors = {};

  /// Venue relationship payloads are separate from the discovery feed. They
  /// stay cached across rebuilds; feed changes and venue revisits invalidate
  /// the affected key so its next read refetches authoritative relationships.
  final Map<String, VenueDetail> _venueDetails = {};
  final Set<String> _missingVenueDetails = {};
  final Map<String, Object> _venueDetailTokens = {};
  final Map<String, String> _venueDetailErrors = {};
  final Map<String, Gig> _relationshipGigs = {};
  final Map<String, Gig> _interactionGigs = {};

  BandMediaController? _media;

  final Map<String, BandProfileDetails> _bandProfileDetails = {};
  final Set<String> _bandProfileDetailsLoading = {};
  final Map<String, BandSetupStatus> _bandSetupStatuses = {};
  final Set<String> _bandSetupLoading = {};
  final Map<String, BandInvite?> _bandInvites = {};
  final Set<String> _bandInviteLoading = {};

  BandInviteResolution? joinInvite;
  String? joinToken;
  bool joinInviteLoading = false;
  String? joinInviteError;
  bool joinInviteAccepting = false;
  bool joinInviteAccepted = false;

  // ---- navigation
  List<ScreenEntry> _stack = const [ScreenEntry(Screen.home)];
  ScreenEntry get current => _stack.last;
  bool get canGoBack => _stack.length > 1;

  // ---- session
  bool authed = false;
  PendingAuth? pending;
  PendingKind? _authConfirmationKind;
  PendingKind? get authConfirmationKind => _authConfirmationKind;
  int authStep = 1;
  final Set<String> userGenres = {};
  Future<bool>? _authReady;
  Future<void>? _authCommit;
  Future<void> _fanGenreWrite = Future.value();
  Future<void> _profileTutorialWrite = Future.value();

  // ---- fan data
  Set<String> rsvps = {};
  Set<String> follows = {};
  Set<String> saved = {};
  int attended = 0;
  List<FanHistoryItem> history = const [];
  UserProfile? profile;
  bool _profileTutorialReplay = false;
  Object? _fanAvatarSaveOwner;
  bool get fanAvatarSaving => _fanAvatarSaveOwner != null;
  FanCity? _appliedHomePersonalization;
  final Set<String> _loadingFollowBands = {};

  FanOnboarding? get fanOnboarding => profile?.fanOnboarding;

  bool get fanOnboardingComplete {
    final onboarding = fanOnboarding;
    return onboarding != null &&
        onboarding.preferredCity != null &&
        onboarding.genreChoice != FanGenreChoice.pending &&
        saved.isNotEmpty;
  }

  bool get showFanOnboarding => fanOnboarding != null && !fanOnboardingComplete;

  bool get profileTutorialVisible =>
      authed &&
      profile != null &&
      (_profileTutorialReplay || !profile!.profileTutorialCompleted);

  /// Legacy-imported count and RSVP-derived history can disagree; show
  /// whichever credits the fan more.
  int get gigsAttended => attended > history.length ? attended : history.length;

  // ---- home filters
  bool mapMode = true;
  String city = 'sf'; // 'sf' | 'oak'
  DiscoveryLocation discoveryLocation = DiscoveryLocation.sf;
  LatLng? currentPosition;
  bool locating = false;
  LocationFailure? locationFailure;
  DiscoveryFilters filters = const DiscoveryFilters();
  int _locationRequestGeneration = 0;

  DateFilter get fDate => filters.date;
  DateTimeRange? get fDateRange => filters.dateRange;
  bool get fFree => filters.price == PriceFilter.free;
  Set<String> get fGenres => filters.genres;
  String? get fGenre =>
      filters.genres.length == 1 ? filters.genres.single : null;
  PriceFilter get fPrice => filters.price;
  String? get fVenueId => filters.venueId;
  double? get fMaxDistanceMiles => filters.maxDistanceMiles;
  int get activeFilterCount => filters.activeCount;

  // ---- explore
  String query = '';
  ExploreResultType exploreResultType = ExploreResultType.all;
  List<String> exploreBandIds = [];
  bool exploreBandsLoading = false;
  bool _exploreBandsDone = false;
  bool _exploreBandsRefreshQueued = false;
  String? _exploreBandsCursor;
  String? exploreBandsError;

  DataStatus get exploreBandsStatus {
    if (exploreBandIds.isEmpty && exploreBandsError != null) {
      return DataStatus.error;
    }
    if (exploreBandIds.isEmpty && exploreBandsLoading) {
      return DataStatus.connecting;
    }
    return DataStatus.ready;
  }

  bool get hasMoreExploreBands => !_exploreBandsDone;

  // ---- band membership
  List<String> myBands = [];
  String bandId = '';
  bool _membershipsLoaded = false;
  bool get membershipsLoaded => authed && _membershipsLoaded;

  // ---- band create form (the cassette canvas)
  String nbName = '';
  final List<String> nbGenres = []; // insertion order shows on the tape, max 3
  String? nbArea;
  String nbBio = '';
  String nbCredits = '';
  String nbIg = '';
  String nbBc = '';
  String nbYt = '';
  String nbLabel = 'cream';
  PickedMedia? nbPhoto;
  String? nbPhotoError;
  bool nbPhotoUploading = false;
  bool nbCreated = false;

  /// Set once the band lands; later saves update this record instead of
  /// creating another band.
  String? _nbBandId;

  /// The server-issued slug for the created band — unique, and stable across
  /// renames so shared links keep resolving.
  String? _nbCreatedSlug;

  /// Blocks a second create/save while one is already in flight, and puts the
  /// create bar into its pending state so the block is visible rather than
  /// just correct.
  bool _nbSaving = false;
  bool get nbSaving => _nbSaving;

  // ---- gig create form
  String gfName = '';
  DateTime? gfDate;
  TimeOfDay gfDoors = const TimeOfDay(hour: 20, minute: 0);
  String? gfVenueId;
  String gfPrice = 'FREE';
  Ticketing gfTix = Ticketing.rsvp;
  AgeRequirement gfAgeRequirement = AgeRequirement.allAges;
  String gfCap = 'No cap';
  String gfExt = '';
  String gfFly = 'xerox';
  bool gfOverlay = true;
  PickedMedia? gfFlyerArt;
  String? gfFlyerStorageId;
  bool gfFlyerUploading = false;
  bool gfPublished = false;

  // ---- toast
  String toast = '';
  Timer? _toastTimer;

  @override
  void dispose() {
    _disposed = true;
    _membershipsGeneration++;
    _toastTimer?.cancel();
    unawaited(_authSubscription?.cancel());
    unawaited(_feedSubscription?.cancel());
    unawaited(_interactionsSubscription?.cancel());
    unawaited(_bandsSubscription?.cancel());
    _clearFollowedBandGigSubscriptions();
    super.dispose();
  }

  /// Assigns, then notifies — the shape every plain form setter has.
  void _set(void Function() assign) {
    assign();
    notifyListeners();
  }

  void _handleAuthChange(bool signedIn) {
    _sessionGeneration++;
    authed = signedIn;
    if (signedIn) {
      _clearMemberships();
      authStep = 2;
      _authReady = _ensureUser();
      unawaited(_authReady);
    } else {
      _clearSessionSensitiveState();
      unawaited(
        repository.refreshAuth().catchError(
          (Object error) => logError('refreshAuth', error),
        ),
      );
    }
    notifyListeners();
  }

  Future<bool> _ensureUser() async {
    final sessionGeneration = _sessionGeneration;
    try {
      // The websocket must carry the new identity before the mutation runs.
      await repository.refreshAuth();
      if (!_isCurrentSession(sessionGeneration)) return false;
      await repository.ensureUser(name: auth.displayName);
      if (!_isCurrentSession(sessionGeneration)) return false;
      _restartMemberships();
      await _refreshProfile(sessionGeneration: sessionGeneration);
      if (!_isCurrentSession(sessionGeneration)) return false;
      unawaited(_refreshHistory(sessionGeneration: sessionGeneration));
      return true;
    } catch (error) {
      logError('ensureUser', error);
      if (_isCurrentSession(sessionGeneration)) say(genericErrorMessage);
      return false;
    }
  }

  bool _isCurrentSession(int generation) =>
      !_disposed && authed && generation == _sessionGeneration;

  Future<void> _refreshHistory({int? sessionGeneration}) async {
    final requestedSession = sessionGeneration ?? _sessionGeneration;
    try {
      final loaded = await repository.history();
      if (!_isCurrentSession(requestedSession)) return;
      history = loaded;
      notifyListeners();
    } catch (error) {
      logError('history', error);
    }
  }

  Future<bool> _refreshProfile({int? sessionGeneration}) async {
    final requestedSession = sessionGeneration ?? _sessionGeneration;
    try {
      final loadedProfile = await repository.me();
      if (!_isCurrentSession(requestedSession)) return false;
      profile = loadedProfile;
      userGenres
        ..clear()
        ..addAll(loadedProfile?.genres ?? const []);
      FanCity? preferredCity;
      if (loadedProfile?.locationPersonalizationEnabled == true) {
        preferredCity = loadedProfile?.homeLocation;
      } else if (loadedProfile?.homeLocation == null) {
        preferredCity = loadedProfile?.fanOnboarding?.preferredCity;
      }
      if (preferredCity != null) {
        _applyDiscoveryCity(preferredCity.name);
        if (loadedProfile?.locationPersonalizationEnabled == true) {
          _appliedHomePersonalization = preferredCity;
        }
      } else if (_appliedHomePersonalization != null) {
        _applyDiscoveryCity('sf');
      }
      notifyListeners();
      return true;
    } catch (error) {
      logError('me', error);
      return false;
    }
  }

  void _subscribeToFeed() {
    _feedSubscription = repository.feed().listen(
      (snapshot) {
        if (_hasFeedSnapshot) {
          _invalidateVenueDetails({
            for (final gig in _allGigs) gig.venueId,
            for (final gig in snapshot.gigs) gig.venueId,
          });
        } else {
          _hasFeedSnapshot = true;
        }
        _allGigs = List<Gig>.of(snapshot.gigs);
        _nextFeedStartsAt = snapshot.nextStartsAt;
        _venues = Map<String, Venue>.of(snapshot.venues);
        _bands = {
          ..._bands,
          for (final entry in snapshot.bands.entries)
            entry.key: entry.value.copyWith(
              upcoming: [
                for (final gig in snapshot.gigs)
                  if (gig.lineup.contains(entry.key)) gig.id,
              ],
            ),
        };
        _normalizeCustomDateRange();
        _dataStatus = DataStatus.ready;
        dataError = null;
        notifyListeners();
      },
      onError: (Object error) {
        _dataStatus = DataStatus.error;
        dataError = '$error';
        notifyListeners();
      },
    );
    unawaited(_loadExploreBandPage());
    unawaited(_refreshVenueDirectory());
  }

  /// One-shot directory refresh, following the `_refreshExploreBands` pattern.
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

  Future<void> _loadExploreBandPage() async {
    if (exploreBandsLoading || _exploreBandsDone) return;
    exploreBandsLoading = true;
    exploreBandsError = null;
    notifyListeners();
    try {
      final page = await repository.listBands(cursor: _exploreBandsCursor);
      if (_disposed) return;
      final ids = exploreBandIds.toSet();
      for (final band in page.items) {
        if (ids.add(band.id)) exploreBandIds.add(band.id);
        // Feed and membership payloads carry live relationship state that a
        // directory page cannot improve on. Pagination only fills gaps; a
        // duplicate id still belongs in the directory id list, but must not
        // replace the richer cached band.
        _bands.putIfAbsent(band.id, () => band);
      }
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

  void loadMoreExploreBands() => unawaited(_loadExploreBandPage());

  void retryExploreBands() {
    if (exploreBandsLoading) return;
    exploreBandsError = null;
    notifyListeners();
    unawaited(_loadExploreBandPage());
  }

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

  void _cacheInteractions(Interactions interactions) {
    rsvps = Set<String>.of(interactions.rsvpGigIds);
    follows = Set<String>.of(interactions.followBandIds);
    saved = Set<String>.of(interactions.savedGigIds);
    _interactionGigs
      ..clear()
      ..addEntries(interactions.gigs.map((gig) => MapEntry(gig.id, gig)));
    attended = interactions.attendedCount;
    _syncFollowedBandGigSubscriptions();
    for (final bandId in follows) {
      if (!_bands.containsKey(bandId)) unawaited(_loadFollowBand(bandId));
    }
    notifyListeners();
  }

  void _syncFollowedBandGigSubscriptions() {
    if (!authed) {
      _clearFollowedBandGigSubscriptions();
      return;
    }
    final removedBandIds = _followedBandGigSubscriptions.keys
        .where((bandId) => !follows.contains(bandId))
        .toList();
    for (final bandId in removedBandIds) {
      _followedBandGigTokens.remove(bandId);
      _followedBandGigs.remove(bandId);
      unawaited(_followedBandGigSubscriptions.remove(bandId)?.cancel());
    }

    for (final bandId in follows) {
      if (_followedBandGigSubscriptions.containsKey(bandId)) continue;
      final token = Object();
      _followedBandGigTokens[bandId] = token;
      _followedBandGigSubscriptions[bandId] = repository
          .upcomingGigsForBand(bandId)
          .listen(
            (gigs) {
              if (_disposed ||
                  !follows.contains(bandId) ||
                  !identical(_followedBandGigTokens[bandId], token)) {
                return;
              }
              _followedBandGigs[bandId] = List<Gig>.of(gigs);
              notifyListeners();
            },
            onError: (Object error) =>
                logError('upcomingGigsForBand $bandId', error),
          );
    }
  }

  void _clearFollowedBandGigSubscriptions() {
    _followedBandGigTokens.clear();
    _followedBandGigs.clear();
    for (final subscription in _followedBandGigSubscriptions.values) {
      unawaited(subscription.cancel());
    }
    _followedBandGigSubscriptions.clear();
  }

  Future<void> _loadFollowBand(String bandId) async {
    if (!_loadingFollowBands.add(bandId)) return;
    try {
      final loaded = await repository.band(bandId);
      if (loaded == null || _disposed) return;
      _bands[bandId] = loaded.copyWith(
        upcoming: [
          for (final gig in _allGigs)
            if (gig.lineup.contains(bandId)) gig.id,
        ],
      );
      notifyListeners();
    } catch (error) {
      logError('followBand $bandId', error);
    } finally {
      _loadingFollowBands.remove(bandId);
    }
  }

  void _cacheMemberships(List<BandMembership> memberships) {
    _membershipsLoaded = true;
    myBands = [for (final membership in memberships) membership.band.id];
    if (myBands.isEmpty) {
      bandId = '';
    } else if (bandId.isEmpty) {
      bandId = myBands.first;
    }
    for (final membership in memberships) {
      final band = membership.band;
      _bandRoles[band.id] = membership.role;
      _bands[band.id] = band.copyWith(
        upcoming: _bands[band.id]?.upcoming ?? const [],
      );
    }
    notifyListeners();
  }

  void _restartMemberships() {
    final generation = ++_membershipsGeneration;
    final previousSubscription = _bandsSubscription;
    _bandsSubscription = null;
    unawaited(previousSubscription?.cancel());
    if (_disposed || !authed || generation != _membershipsGeneration) return;

    _bandsSubscription = _listenToMemberships(
      generation,
      requireAuthentication: true,
    );
  }

  StreamSubscription<List<BandMembership>> _listenToMemberships(
    int generation, {
    required bool requireAuthentication,
  }) {
    return repository.myBands().listen(
      (memberships) {
        if (_disposed ||
            (requireAuthentication && !authed) ||
            generation != _membershipsGeneration) {
          return;
        }
        _cacheMemberships(memberships);
      },
      onError: (Object error) {
        if (generation == _membershipsGeneration) {
          logError('myBands', error);
        }
      },
    );
  }

  void _clearMemberships() {
    _membershipsGeneration++;
    final subscription = _bandsSubscription;
    _bandsSubscription = null;
    unawaited(subscription?.cancel());
    _membershipsLoaded = false;
    myBands = [];
    bandId = '';
    _bandRoles.clear();
  }

  // ========================= navigation =========================

  void go(Screen s, [String? param]) =>
      _set(() => _stack = [..._stack, ScreenEntry(s, param)]);

  void back() {
    if (_stack.length > 1) {
      _set(() => _stack = _stack.sublist(0, _stack.length - 1));
      _refreshVisibleBandDashboard();
    }
  }

  void resetTo(Screen s) {
    _set(() => _stack = [ScreenEntry(s)]);
    _refreshVisibleBandDashboard();
  }

  void _refreshVisibleBandDashboard() {
    if (current.screen == Screen.bandDash && bandId.isNotEmpty) {
      unawaited(refreshBandSetupStatus(bandId));
    }
  }

  void openGig(String id) {
    if (current.screen == Screen.gig && current.param == id) return;
    go(Screen.gig, id);
  }

  void openBand(String id) {
    go(Screen.band, id);
    unawaited(loadBandProfileDetails(id));
  }

  void previewPublicProfile() {
    final id = bandId;
    if (id.isEmpty) return;
    go(Screen.bandPreview, id);
    unawaited(loadBandProfileDetails(id));
    unawaited(_markBandPreviewed(id));
  }

  void returnToBandDashboard() => resetTo(Screen.bandDash);

  void openBandEditor({String? section}) {
    if (!isAdminOf(bandId)) return;
    go(Screen.bandEdit, section);
    unawaited(loadBandProfileDetails(bandId, refresh: true));
    if (section == 'members') unawaited(refreshBandInvite(bandId));
  }

  void openInvitationPanel() => openBandEditor(section: 'members');

  void openVenue(String id) {
    if (current.screen == Screen.venue && current.param == id) return;
    _invalidateVenueDetails({id});
    go(Screen.venue, id);
  }

  void openBandMedia() => go(Screen.bandMedia, bandId);

  void openMyGigsTab() {
    if (authed) {
      unawaited(_refreshHistory());
      resetTo(Screen.myGigs);
    } else {
      needAuth(const PendingAuth(PendingKind.myGigs));
    }
  }

  void openEditProfile() {
    if (authed && profile != null) {
      go(Screen.editProfile);
    } else if (authed) {
      say('Your profile is still loading.');
      unawaited(_refreshProfile());
    } else {
      needAuth(const PendingAuth(PendingKind.myGigs));
    }
  }

  void openSettings() {
    if (authed) {
      go(Screen.settings);
    } else {
      needAuth(const PendingAuth(PendingKind.myGigs));
    }
  }

  void say(String msg) {
    toast = msg;
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2200), () {
      toast = '';
      notifyListeners();
    });
    notifyListeners();
  }

  void attachMediaController(BandMediaController c) => _media = c;

  // ========================= auth =========================

  void needAuth(PendingAuth p) {
    pending = p;
    _authConfirmationKind = p.kind;
    authStep = 1;
    _authCommit = null;
    _postAuthScreen = null;
    go(Screen.auth);
  }

  Future<void> login() async => auth.signInDemo();

  Future<void> signOut() async {
    await auth.signOut();
    _clearSessionSensitiveState();
    resetTo(Screen.home);
    say('Signed out.');
  }

  Future<bool> deleteAccount() async {
    try {
      // Establish the Convex tombstone while this Clerk session can still
      // authenticate. The eventual user.deleted webhook is only a retry path.
      await repository.deleteCurrentUser();
      await auth.deleteAccount();
    } catch (error) {
      logError('deleteAccount', error);
      say(genericErrorMessage);
      return false;
    }

    _clearSessionSensitiveState();
    resetTo(Screen.home);
    say('Account deleted.');
    return true;
  }

  void _clearSessionSensitiveState() {
    _sessionGeneration++;
    authed = false;
    _clearMemberships();
    rsvps = {};
    follows = {};
    saved = {};
    attended = 0;
    history = const [];
    profile = null;
    userGenres.clear();
    pending = null;
    _authReady = null;
    _authCommit = null;
    _authConfirmationKind = null;
    _postAuthScreen = null;
    authStep = 1;
    _fanGenreWrite = Future.value();
    _profileTutorialWrite = Future.value();
    _profileTutorialReplay = false;
    _fanAvatarSaveOwner = null;
    _appliedHomePersonalization = null;
    _loadingFollowBands.clear();
    _clearFollowedBandGigSubscriptions();
    _interactionGigs.clear();
    _locationRequestGeneration++;
    city = 'sf';
    discoveryLocation = DiscoveryLocation.sf;
    currentPosition = null;
    locating = false;
    locationFailure = null;
    filters = const DiscoveryFilters();
    query = '';
    exploreResultType = ExploreResultType.all;
    _bandSetupStatuses.clear();
    _bandSetupLoading.clear();
    _bandInvites.clear();
    _bandInviteLoading.clear();
    _media?.clearForSignOut();
    _resetBandForm();
    _resetGigForm();
  }

  /// Where [leaveAuth] lands, decided by [commitAuth]; null pops back to
  /// wherever the auth gate was opened from.
  Screen? _postAuthScreen;

  /// The durable half of finishing auth: completes the action that triggered
  /// the gate. Runs before any confirmation delay so
  /// backing out (or being killed) mid-splash can't drop the pending action.
  Future<void> commitAuth() {
    final inProgress = _authCommit;
    if (inProgress != null) return inProgress;
    final commit = _commitAuth();
    _authCommit = commit;
    unawaited(
      commit.catchError((Object _) {
        if (identical(_authCommit, commit)) _authCommit = null;
      }),
    );
    return commit;
  }

  Future<void> _commitAuth() async {
    final ready = await (_authReady ??= _ensureUser());
    if (!ready) {
      _authReady = null;
      throw const AuthException("Couldn't finish sign-in. Try again.");
    }
    final p = pending;
    switch (p?.kind) {
      case PendingKind.rsvp:
        await repository.ensureRsvp(p!.id!);
        rsvps.add(p.id!);
        say("You're on the list. QR is in Profile.");
        _postAuthScreen = null;
      case PendingKind.follow:
        await repository.ensureFollow(p!.id!);
        follows.add(p.id!);
        _syncFollowedBandGigSubscriptions();
        final name = band(p.id!)?.name;
        say(name == null ? 'Band followed.' : 'Following $name.');
        _postAuthScreen = null;
      case PendingKind.save:
        await repository.ensureSave(p!.id!);
        saved.add(p.id!);
        say('Show saved.');
        _postAuthScreen = null;
      case PendingKind.myGigs:
        _postAuthScreen = Screen.myGigs;
        final name = (profile?.name ?? auth.displayName)?.trim();
        say(
          name == null || name.isEmpty
              ? 'Welcome back.'
              : 'Welcome back, ${name.split(' ').first}.',
        );
      case PendingKind.band:
        _resetBandForm();
        _postAuthScreen = Screen.bandCreate;
      case PendingKind.join:
        _postAuthScreen = Screen.bandJoin;
      case null:
        _postAuthScreen = null;
    }
    pending = null;
  }

  /// The navigation half: leaves the auth screen for wherever [commitAuth]
  /// decided. Skipping this (user backed out first) loses nothing.
  void leaveAuth() {
    final destination = _postAuthScreen;
    _postAuthScreen = null;
    if (destination == null) {
      back();
    } else {
      resetTo(destination);
    }
    _authConfirmationKind = null;
  }

  Future<void> finishAuth() async {
    await commitAuth();
    leaveAuth();
  }

  // ========================= fan actions =========================

  /// Flips [id] in [ids] on screen straight away and persists in the
  /// background; a rejected write puts the flip back and says so. Returns
  /// whether [id] ended up on.
  bool _toggleOptimistically(
    Set<String> ids,
    String id,
    Future<void> Function(String) persist, [
    void Function()? onChanged,
  ]) {
    final wasOn = ids.contains(id);
    wasOn ? ids.remove(id) : ids.add(id);
    onChanged?.call();
    notifyListeners();
    unawaited(
      persist(id).catchError((Object error) {
        logError('toggle $id', error);
        wasOn ? ids.add(id) : ids.remove(id);
        onChanged?.call();
        say(genericErrorMessage); // notifies, so the roll-back shows
      }),
    );
    return !wasOn;
  }

  void toggleRsvp(String id) {
    final nowGoing = _toggleOptimistically(rsvps, id, repository.toggleRsvp);
    say(nowGoing ? "You're on the list. QR is in Profile." : 'RSVP removed.');
  }

  void requestRsvp(String id) {
    if (authed) {
      toggleRsvp(id);
    } else {
      needAuth(PendingAuth(PendingKind.rsvp, id));
    }
  }

  void toggleFollow(String id) {
    if (_toggleOptimistically(
      follows,
      id,
      repository.toggleFollow,
      _syncFollowedBandGigSubscriptions,
    )) {
      final name = band(id)?.name;
      say(name == null ? 'Band followed.' : 'Following $name.');
    }
  }

  void requestFollow(String id) {
    if (authed) {
      toggleFollow(id);
    } else {
      needAuth(PendingAuth(PendingKind.follow, id));
    }
  }

  void toggleSave(String id) {
    final nowSaved = _toggleOptimistically(saved, id, repository.toggleSave);
    say(nowSaved ? 'Show saved.' : 'Removed from saved shows.');
  }

  void requestSave(String id) {
    if (authed) {
      toggleSave(id);
    } else {
      needAuth(PendingAuth(PendingKind.save, id));
    }
  }

  /// Starts band creation immediately for members and preserves the attempted
  /// action for everyone else.
  void requestStartBand() {
    if (authed) {
      startBandCreate();
    } else {
      needAuth(const PendingAuth(PendingKind.band));
    }
  }

  Future<bool> saveFanProfile({
    required String name,
    required String? bio,
    required FanCity? homeLocation,
    required List<String> genres,
    required bool locationPersonalizationEnabled,
    required bool followedBandUpdatesEnabled,
  }) async {
    if (!authed) return false;
    final sessionGeneration = _sessionGeneration;
    final savedName = name.trim();
    if (savedName.isEmpty) {
      say('Add your name before saving.');
      return false;
    }
    final savedBio = bio?.trim();
    final normalizedBio = savedBio == null || savedBio.isEmpty
        ? null
        : savedBio;
    final savedGenres = List<String>.unmodifiable(genres);

    try {
      await repository.updateFanProfile(
        name: savedName,
        bio: normalizedBio,
        homeLocation: homeLocation,
        genres: savedGenres,
        locationPersonalizationEnabled: locationPersonalizationEnabled,
        followedBandUpdatesEnabled: followedBandUpdatesEnabled,
      );
    } catch (error) {
      logError('updateFanProfile', error);
      if (_isCurrentSession(sessionGeneration)) say(genericErrorMessage);
      return false;
    }

    if (!_isCurrentSession(sessionGeneration)) return false;
    final currentProfile = profile;
    if (currentProfile != null) {
      profile = currentProfile.copyWith(
        name: savedName,
        bio: normalizedBio,
        homeLocation: homeLocation,
        genres: savedGenres,
        locationPersonalizationEnabled: locationPersonalizationEnabled,
        followedBandUpdatesEnabled: followedBandUpdatesEnabled,
      );
    } else {
      await _refreshProfile(sessionGeneration: sessionGeneration);
      if (!_isCurrentSession(sessionGeneration)) return false;
    }
    userGenres
      ..clear()
      ..addAll(savedGenres);
    if (locationPersonalizationEnabled && homeLocation != null) {
      _applyDiscoveryCity(homeLocation.name);
      _appliedHomePersonalization = homeLocation;
    } else if (_appliedHomePersonalization != null) {
      _applyDiscoveryCity('sf');
    }
    notifyListeners();
    return true;
  }

  Future<bool> updateFanAvatar(PickedMedia media) async {
    if (!authed || fanAvatarSaving) return false;
    final sessionGeneration = _sessionGeneration;
    final saveOwner = Object();
    _fanAvatarSaveOwner = saveOwner;
    notifyListeners();
    try {
      final storageId = await mediaUploader.uploadAvatarRaw(media: media);
      if (!_isCurrentSession(sessionGeneration)) return false;
      await repository.setAvatar(storageId);
      if (!_isCurrentSession(sessionGeneration)) return false;
      await _refreshProfile(sessionGeneration: sessionGeneration);
      return _isCurrentSession(sessionGeneration);
    } catch (error) {
      logError('setAvatar', error);
      if (_isCurrentSession(sessionGeneration)) say(genericErrorMessage);
      return false;
    } finally {
      if (identical(_fanAvatarSaveOwner, saveOwner)) {
        _fanAvatarSaveOwner = null;
        notifyListeners();
      }
    }
  }

  Future<bool> clearFanAvatar() async {
    if (!authed || fanAvatarSaving) return false;
    final sessionGeneration = _sessionGeneration;
    final saveOwner = Object();
    _fanAvatarSaveOwner = saveOwner;
    notifyListeners();
    try {
      await repository.clearAvatar();
      if (!_isCurrentSession(sessionGeneration)) return false;
      profile = profile?.copyWith(avatarUrl: null);
      notifyListeners();
      return true;
    } catch (error) {
      logError('clearAvatar', error);
      if (_isCurrentSession(sessionGeneration)) say(genericErrorMessage);
      return false;
    } finally {
      if (identical(_fanAvatarSaveOwner, saveOwner)) {
        _fanAvatarSaveOwner = null;
        notifyListeners();
      }
    }
  }

  Future<void> completeProfileTutorial() async {
    if (!authed) return;
    final sessionGeneration = _sessionGeneration;
    try {
      await _persistProfileTutorial(true, sessionGeneration);
      if (!_isCurrentSession(sessionGeneration)) return;
      profile = profile?.copyWith(profileTutorialCompleted: true);
      _profileTutorialReplay = false;
      notifyListeners();
    } catch (error) {
      logError('completeProfileTutorial', error);
      if (_isCurrentSession(sessionGeneration)) say(genericErrorMessage);
    }
  }

  void replayProfileTutorial() {
    if (!authed) {
      openMyGigsTab();
      return;
    }
    _set(() {
      _profileTutorialReplay = true;
      _stack = const [ScreenEntry(Screen.myGigs)];
    });
    final sessionGeneration = _sessionGeneration;
    unawaited(
      _persistProfileTutorial(false, sessionGeneration)
          .then((_) {
            if (!_isCurrentSession(sessionGeneration)) return;
            profile = profile?.copyWith(profileTutorialCompleted: false);
            notifyListeners();
          })
          .catchError((Object error) {
            logError('replayProfileTutorial', error);
            if (_isCurrentSession(sessionGeneration)) say(genericErrorMessage);
          }),
    );
  }

  Future<void> _persistProfileTutorial(bool completed, int sessionGeneration) {
    final write = _profileTutorialWrite.then((_) async {
      if (!_isCurrentSession(sessionGeneration)) return;
      await repository.setProfileTutorialCompleted(completed);
    });
    _profileTutorialWrite = write.catchError((Object _) {});
    return write;
  }

  // ========================= fan onboarding =========================

  void _setLocalFanOnboarding(
    FanOnboarding onboarding, {
    List<String>? genres,
  }) {
    final current = profile;
    if (current == null) return;
    final nextGenres = genres ?? current.genres;
    profile = current.copyWith(
      genres: List.unmodifiable(nextGenres),
      fanOnboarding: onboarding,
    );
    userGenres
      ..clear()
      ..addAll(nextGenres);
    notifyListeners();
  }

  void selectFanCity(FanCity preferredCity) {
    final previous = fanOnboarding;
    if (previous == null) return;
    final previousDiscoveryState = (
      city: city,
      location: discoveryLocation,
      position: currentPosition,
      locating: locating,
      failure: locationFailure,
      filters: filters,
    );

    _applyDiscoveryCity(preferredCity.name);
    _setLocalFanOnboarding(
      FanOnboarding(
        preferredCity: preferredCity,
        genreChoice: previous.genreChoice,
        collapsed: previous.collapsed,
      ),
    );
    say(
      preferredCity == FanCity.oak
          ? 'Browsing Oakland shows.'
          : 'Browsing San Francisco shows.',
    );

    unawaited(
      repository.updateFanOnboarding(preferredCity: preferredCity).catchError((
        Object error,
      ) {
        logError('updateFanOnboarding city', error);
        final current = fanOnboarding;
        if (current?.preferredCity == preferredCity) {
          _locationRequestGeneration++;
          city = previousDiscoveryState.city;
          discoveryLocation = previousDiscoveryState.location;
          currentPosition = previousDiscoveryState.position;
          locating = previousDiscoveryState.locating;
          locationFailure = previousDiscoveryState.failure;
          filters = previousDiscoveryState.filters;
          _setLocalFanOnboarding(
            FanOnboarding(
              preferredCity: previous.preferredCity,
              genreChoice: current!.genreChoice,
              collapsed: current.collapsed,
            ),
          );
        }
        say(genericErrorMessage);
      }),
    );
  }

  void toggleFanGenre(String genre) {
    final selected = Set<String>.of(userGenres);
    selected.contains(genre) ? selected.remove(genre) : selected.add(genre);
    _saveFanGenreChoice(
      selected.toList(),
      selected.isEmpty ? FanGenreChoice.pending : FanGenreChoice.selected,
    );
  }

  void chooseOpenGenres() => _saveFanGenreChoice(const [], FanGenreChoice.open);

  void _saveFanGenreChoice(List<String> genres, FanGenreChoice genreChoice) {
    final previous = fanOnboarding;
    if (previous == null) return;
    final previousGenres = List<String>.of(userGenres);
    _setLocalFanOnboarding(
      FanOnboarding(
        preferredCity: previous.preferredCity,
        genreChoice: genreChoice,
        collapsed: previous.collapsed,
      ),
      genres: genres,
    );

    _fanGenreWrite = _fanGenreWrite.then((_) async {
      try {
        await repository.updateFanOnboarding(
          genreChoice: genreChoice,
          genres: genres,
        );
      } catch (error) {
        logError('updateFanOnboarding genres', error);
        final current = fanOnboarding;
        if (current?.genreChoice == genreChoice &&
            setEquals(userGenres, genres.toSet())) {
          _setLocalFanOnboarding(
            FanOnboarding(
              preferredCity: current!.preferredCity,
              genreChoice: previous.genreChoice,
              collapsed: current.collapsed,
            ),
            genres: previousGenres,
          );
        }
        say(genericErrorMessage);
      }
    });
    unawaited(_fanGenreWrite);
  }

  void setFanOnboardingCollapsed(bool collapsed) {
    final previous = fanOnboarding;
    if (previous == null || previous.collapsed == collapsed) return;
    _setLocalFanOnboarding(
      FanOnboarding(
        preferredCity: previous.preferredCity,
        genreChoice: previous.genreChoice,
        collapsed: collapsed,
      ),
    );
    unawaited(
      repository.updateFanOnboarding(collapsed: collapsed).catchError((
        Object error,
      ) {
        logError('updateFanOnboarding collapsed', error);
        final current = fanOnboarding;
        if (current?.collapsed == collapsed) {
          _setLocalFanOnboarding(
            FanOnboarding(
              preferredCity: current!.preferredCity,
              genreChoice: current.genreChoice,
              collapsed: previous.collapsed,
            ),
          );
        }
        say(genericErrorMessage);
      }),
    );
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
    city = c;
    discoveryLocation = c == 'oak'
        ? DiscoveryLocation.oak
        : DiscoveryLocation.sf;
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
    locating = false;
    locationFailure = null;
  });

  Future<bool> selectCurrentLocation() async {
    if (locating) return false;
    final requestGeneration = ++_locationRequestGeneration;
    locating = true;
    locationFailure = null;
    notifyListeners();

    final result = await locationService.requestCurrentLocation();
    if (_disposed || requestGeneration != _locationRequestGeneration) {
      return false;
    }
    locating = false;
    switch (result) {
      case LocationSuccess(:final location):
        _appliedHomePersonalization = null;
        currentPosition = LatLng(location.latitude, location.longitude);
        discoveryLocation = DiscoveryLocation.current;
        locationFailure = null;
        say('Showing gigs near your current location.');
        return true;
      case final LocationFailure failure:
        locationFailure = failure;
        notifyListeners();
        return false;
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
    DiscoveryLocation.oak => 'TEMESCAL, OAK',
    DiscoveryLocation.sf => 'MISSION, SF',
  };

  LatLng get discoveryCenter => switch (discoveryLocation) {
    DiscoveryLocation.current =>
      currentPosition ?? const LatLng(37.7599, -122.4148),
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
    final canFilterByDistance =
        discoveryLocation == DiscoveryLocation.current &&
        currentPosition != null;
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

  // ========================= data access =========================

  List<Gig> get allGigs => _allGigs;

  List<Gig> get followedBandShows {
    if (profile?.followedBandUpdatesEnabled == false || follows.isEmpty) {
      return const [];
    }
    final now = DateTime.now();
    final gigsById = {
      for (final gig in _allGigs) gig.id: gig,
      for (final gigs in _followedBandGigs.values)
        for (final gig in gigs) gig.id: gig,
    };
    final shows = [
      for (final gig in gigsById.values)
        if (!gig.startsAt.isBefore(now) && gig.lineup.any(follows.contains))
          gig,
    ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return List<Gig>.unmodifiable(shows);
  }

  Gig? gig(String id) {
    for (final g in allGigs) {
      if (g.id == id) return g;
    }
    for (final gigs in _followedBandGigs.values) {
      for (final gig in gigs) {
        if (gig.id == id) return gig;
      }
    }
    return _interactionGigs[id] ?? _relationshipGigs[id];
  }

  Band? band(String id) => _bands[id];

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

  /// A band's past gigs, or null until the first load lands. Kicks the load off
  /// on first read; a failed load is not retried until [refreshBandHistory].
  BandHistory? bandHistory(String id) {
    final cached = _bandHistory[id];
    if (cached != null) return cached;
    if (!_bandHistoryTokens.containsKey(id) &&
        !_bandHistoryErrors.containsKey(id)) {
      unawaited(_loadBandHistory(id));
    }
    return null;
  }

  /// Why the last load for [id] failed, or null.
  String? bandHistoryError(String id) => _bandHistoryErrors[id];

  /// Clears any recorded failure and loads again — the RETRY affordance.
  void refreshBandHistory(String id) {
    _bandHistoryErrors.remove(id);
    notifyListeners();
    unawaited(_loadBandHistory(id));
  }

  Future<void> _loadBandHistory(String id) async {
    final token = Object();
    _bandHistoryTokens[id] = token;
    try {
      final loaded = await repository.bandHistory(id);
      if (_disposed || !identical(_bandHistoryTokens[id], token)) return;
      _bandHistory[id] = loaded;
      _bandHistoryErrors.remove(id);
    } catch (error) {
      logError('bandHistory', error);
      if (_disposed || !identical(_bandHistoryTokens[id], token)) return;
      _bandHistoryErrors[id] = '$error';
    } finally {
      if (!_disposed && identical(_bandHistoryTokens[id], token)) {
        _bandHistoryTokens.remove(id);
        notifyListeners();
      }
    }
  }

  /// A band's performance recap, or null until the first load lands. Kicks the
  /// load off on first read; failures wait for [refreshBandRecap].
  BandRecap? bandRecap(String id) {
    final cached = _bandRecap[id];
    if (cached != null) return cached;
    if (!_bandRecapTokens.containsKey(id) &&
        !_bandRecapErrors.containsKey(id)) {
      unawaited(_loadBandRecap(id));
    }
    return null;
  }

  /// Why the last recap load for [id] failed, or null.
  String? bandRecapError(String id) => _bandRecapErrors[id];

  /// Clears any recorded recap failure and loads again — the RETRY affordance.
  void refreshBandRecap(String id) {
    _bandRecapErrors.remove(id);
    notifyListeners();
    unawaited(_loadBandRecap(id));
  }

  Future<void> _loadBandRecap(String id) async {
    final token = Object();
    _bandRecapTokens[id] = token;
    try {
      final loaded = await repository.bandRecap(id);
      if (_disposed || !identical(_bandRecapTokens[id], token)) return;
      _bandRecap[id] = loaded;
      _bandRecapErrors.remove(id);
    } catch (error) {
      logError('bandRecap', error);
      if (_disposed || !identical(_bandRecapTokens[id], token)) return;
      _bandRecapErrors[id] = '$error';
    } finally {
      if (!_disposed && identical(_bandRecapTokens[id], token)) {
        _bandRecapTokens.remove(id);
        notifyListeners();
      }
    }
  }

  String roleFor(String id) => _bandRoles[id] ?? 'member';

  bool isAdminOf(String id) => _bandRoles[id] == 'admin';

  /// Returns only a real feed or directory venue, never the display fallback.
  Venue? knownVenue(String id) => _venues[id] ?? _venueDirectory[id];

  Venue venue(String id) => knownVenue(id) ?? _unknownVenue;

  /// Every venue the app knows: the curated table plus whatever the live feed
  /// carries. Feed rows win on id — they are realtime. Name-ordered, one entry
  /// per id; this is the only venue list any screen reads.
  List<Venue> get venues {
    final merged = <String, Venue>{..._venueDirectory, ..._venues};
    return merged.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  static const _unknownVenue = Venue(
    id: '',
    name: 'Venue unavailable',
    area: '',
    addr: '',
    distSF: '',
    distOak: '',
    point: LatLng(0, 0),
  );

  FlyerStyle flyer(String key) =>
      DemoData.flyers[key] ?? DemoData.flyers['paper']!;

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

  List<Gig> get feed {
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
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
        final distance = distanceMilesFromCurrent(venue(gig.venueId));
        if (distance != null && distance > maxMiles) return false;
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      final proximity = _distanceMilesFromDiscoveryCenter(
        venue(a.venueId),
      ).compareTo(_distanceMilesFromDiscoveryCenter(venue(b.venueId)));
      return proximity != 0 ? proximity : a.startsAt.compareTo(b.startsAt);
    });
    return filtered;
  }

  /// RSVP count shown to bands: base demo count plus this user's RSVP.
  int rsvpCount(Gig g) => g.going + (rsvps.contains(g.id) ? 1 : 0);

  String bioFor(String id) => band(id)?.bio ?? '';

  String linkIgFor(String id) => band(id)?.linkIg ?? '';

  String linkBcFor(String id) => band(id)?.linkBc ?? '';

  String linkYtFor(String id) => band(id)?.linkYt ?? '';

  void retry() {
    _dataStatus = DataStatus.connecting;
    dataError = null;
    notifyListeners();
    unawaited(_restartFeed());
  }

  Future<void> _restartFeed() async {
    await _feedSubscription?.cancel();
    _subscribeToFeed();
  }

  // ========================= band view =========================

  Band? get myBand => band(bandId);

  List<Gig> get myBandGigs =>
      allGigs.where((g) => g.lineup.contains(bandId)).toList();

  String get myBandNames => myBands
      .map((id) => band(id)?.name ?? '')
      .where((n) => n.isNotEmpty)
      .join(' · ');

  void switchToBand(String id) {
    bandId = id;
    resetTo(Screen.bandDash);
    unawaited(refreshBandSetupStatus(id));
  }

  void toFanView() => resetTo(Screen.home);

  BandProfileDetails? profileDetailsFor(String id) {
    final details = _bandProfileDetails[id];
    if (details == null) unawaited(loadBandProfileDetails(id));
    return details;
  }

  Future<void> loadBandProfileDetails(String id, {bool refresh = false}) async {
    if ((!refresh && _bandProfileDetails.containsKey(id)) ||
        !_bandProfileDetailsLoading.add(id)) {
      return;
    }
    try {
      _bandProfileDetails[id] = await repository.bandProfileDetails(id);
    } catch (error) {
      logError('bandProfileDetails', error);
    } finally {
      _bandProfileDetailsLoading.remove(id);
      if (!_disposed) notifyListeners();
    }
  }

  BandSetupStatus? setupStatusFor(String id) {
    final status = _bandSetupStatuses[id];
    if (status == null && isAdminOf(id)) {
      unawaited(refreshBandSetupStatus(id));
    }
    return status;
  }

  bool setupStatusLoadingFor(String id) => _bandSetupLoading.contains(id);

  Future<void> refreshBandSetupStatus(String id) async {
    if (!isAdminOf(id) || !_bandSetupLoading.add(id)) return;
    try {
      _bandSetupStatuses[id] = await repository.bandSetupStatus(id);
    } catch (error) {
      logError('bandSetupStatus', error);
    } finally {
      _bandSetupLoading.remove(id);
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _markBandPreviewed(String id) async {
    try {
      await repository.markBandPreviewed(id);
      await refreshBandSetupStatus(id);
    } catch (error) {
      logError('markBandPreviewed', error);
    }
  }

  Future<void> saveBandProfile(BandProfileUpdate update) async {
    final name = update.name.trim();
    final area = update.area.trim();
    if (name.isEmpty || area.isEmpty || update.genres.isEmpty) {
      throw ArgumentError('Band name, sound, and home base are required.');
    }
    if (update.genres.length > 3) {
      throw ArgumentError('Choose no more than three genres.');
    }

    final normalized = BandProfileUpdate(
      bandId: update.bandId,
      name: name,
      genres: List<String>.of(update.genres),
      area: area,
      bio: update.bio.trim(),
      linkIg: update.linkIg.trim(),
      linkBc: update.linkBc.trim(),
      linkYt: update.linkYt.trim(),
      credits: update.credits.trim(),
    );
    await repository.updateBandProfile(normalized);

    final existing = _bands[update.bandId];
    if (existing != null) {
      _bands[update.bandId] = existing.copyWith(
        name: normalized.name,
        initials: _bandInitials(normalized.name),
        genres: normalized.genres,
        area: normalized.area,
        bio: normalized.bio,
        linkIg: normalized.linkIg,
        linkBc: normalized.linkBc,
        linkYt: normalized.linkYt,
        credits: normalized.credits,
      );
    }
    final currentDetails = _bandProfileDetails[update.bandId];
    _bandProfileDetails[update.bandId] = BandProfileDetails(
      credits: normalized.credits.isEmpty ? null : normalized.credits,
      linkIg: normalized.linkIg.isEmpty ? null : normalized.linkIg,
      linkBc: normalized.linkBc.isEmpty ? null : normalized.linkBc,
      linkYt: normalized.linkYt.isEmpty ? null : normalized.linkYt,
      memberNames: currentDetails?.memberNames ?? const [],
    );
    notifyListeners();
    await refreshBandSetupStatus(update.bandId);
  }

  BandInvite? inviteFor(String id) {
    if (!_bandInvites.containsKey(id) && isAdminOf(id)) {
      unawaited(refreshBandInvite(id));
    }
    return _bandInvites[id];
  }

  bool inviteLoadingFor(String id) => _bandInviteLoading.contains(id);

  Future<void> refreshBandInvite(String id) async {
    if (!isAdminOf(id) || !_bandInviteLoading.add(id)) return;
    try {
      _bandInvites[id] = await repository.bandInvite(id);
    } catch (error) {
      logError('bandInvite', error);
    } finally {
      _bandInviteLoading.remove(id);
      if (!_disposed) notifyListeners();
    }
  }

  Future<BandInvite> createBandInvitation() async {
    final invite = await repository.createBandInvite(bandId);
    _bandInvites[bandId] = invite;
    notifyListeners();
    return invite;
  }

  Future<BandInvite> rotateBandInvitation() async {
    final invite = await repository.rotateBandInvite(bandId);
    _bandInvites[bandId] = invite;
    notifyListeners();
    return invite;
  }

  Future<void> revokeBandInvitation() async {
    final id = bandId;
    await repository.revokeBandInvite(id);
    final current = _bandInvites[id];
    if (current != null) {
      _bandInvites[id] = BandInvite(
        bandId: current.bandId,
        token: current.token,
        expiresAt: current.expiresAt,
        revoked: true,
      );
    }
    notifyListeners();
  }

  Future<void> openJoinInvite(String token) async {
    _stack = [ScreenEntry(Screen.bandJoin, token)];
    notifyListeners();
    await _resolveJoinInvite(token);
  }

  Future<void> _resolveJoinInvite(String token) async {
    joinToken = token;
    joinInvite = null;
    joinInviteError = null;
    joinInviteAccepted = false;
    joinInviteLoading = true;
    notifyListeners();
    try {
      final resolved = await repository.resolveBandInvite(token);
      if (resolved == null) {
        joinInviteError = 'This invitation is invalid, expired, or revoked.';
      } else {
        joinInvite = resolved;
      }
    } catch (error) {
      logError('resolveBandInvite', error);
      joinInviteError = genericErrorMessage;
    } finally {
      joinInviteLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> confirmJoinInvite() async {
    final token = joinToken;
    if (token == null || joinInvite == null || joinInviteAccepting) return;
    if (!authed) {
      needAuth(PendingAuth(PendingKind.join, token));
      return;
    }
    await _acceptJoinInvite(token);
  }

  Future<void> _acceptJoinInvite(String token) async {
    joinInviteAccepting = true;
    joinInviteError = null;
    notifyListeners();
    try {
      final accepted = await repository.acceptBandInvite(token);
      bandId = accepted.bandId;
      joinInviteAccepted = true;
      _restartMemberships();
      unawaited(loadBandProfileDetails(accepted.bandId, refresh: true));
    } catch (error) {
      logError('acceptBandInvite', error);
      joinInviteError = 'This invitation could not be accepted.';
      rethrow;
    } finally {
      joinInviteAccepting = false;
      if (!_disposed) notifyListeners();
    }
  }

  // ========================= band create =========================

  void startBandCreate() {
    _resetBandForm();
    go(Screen.bandCreate);
  }

  void _resetBandForm() {
    nbName = '';
    nbGenres.clear();
    nbArea = null;
    nbBio = '';
    nbCredits = '';
    nbIg = '';
    nbBc = '';
    nbYt = '';
    nbLabel = 'cream';
    nbPhoto = null;
    nbPhotoError = null;
    nbPhotoUploading = false;
    nbCreated = false;
    _nbBandId = null;
    _nbCreatedSlug = null;
  }

  void setNbName(String v) => _set(() => nbName = v);

  void setNbBio(String v) => _set(() => nbBio = v);

  void setNbCredits(String v) => _set(() => nbCredits = v);

  void setNbArea(String v) {
    final area = v.trim();
    if (area.isEmpty) return;
    _set(() => nbArea = area);
  }

  void setNbIg(String v) => _set(() => nbIg = v);

  void setNbBc(String v) => _set(() => nbBc = v);

  void setNbYt(String v) => _set(() => nbYt = v);

  void setNbLabel(String key) => _set(() => nbLabel = key);

  void setNbPhoto(PickedMedia? photo) => _set(() => nbPhoto = photo);

  void toggleNbGenre(String g) {
    if (nbGenres.contains(g)) {
      nbGenres.remove(g);
    } else if (nbGenres.length >= 3) {
      say('Three genres max. It keeps discovery honest.');
      return;
    } else {
      nbGenres.add(g);
    }
    notifyListeners();
  }

  void addNbGenre(String raw) {
    final g = raw.trim().toLowerCase();
    if (g.isEmpty) return;
    if (nbGenres.contains(g)) return;
    if (nbGenres.length >= 3) {
      say('Three genres max.');
      return;
    }
    _set(() => nbGenres.add(g));
  }

  bool get canCreateBand =>
      nbName.trim().isNotEmpty && nbGenres.isNotEmpty && nbArea != null;

  /// What the create bar still asks for, in reading order.
  List<String> get bandMissing => [
    if (nbName.trim().isEmpty) 'a name',
    if (nbGenres.isEmpty) 'a genre',
    if (nbArea == null) 'a home base',
  ];

  /// How full the tape winds: the six setup checklist lines, equally weighted.
  double get nbCompletion {
    final done = [
      nbName.trim().isNotEmpty,
      nbGenres.isNotEmpty,
      nbArea != null,
      nbPhoto != null,
      nbBio.trim().isNotEmpty,
      nbIg.trim().isNotEmpty ||
          nbBc.trim().isNotEmpty ||
          nbYt.trim().isNotEmpty,
    ];
    return done.where((d) => d).length / done.length;
  }

  String get nbSlug {
    final slug = _slugify(nbName.trim().isEmpty ? 'your-band' : nbName);
    return slug.isEmpty ? 'your-band' : slug;
  }

  /// Whether the form is re-editing a band that already landed — the create
  /// bar saves changes then instead of creating another band.
  bool get nbEditingCreated => _nbBandId != null;

  /// The slug shown on shareable URLs: the server-issued one once the band
  /// exists, the client-side preview before that.
  String get nbShareSlug => _nbCreatedSlug ?? nbSlug;

  /// Every area the feed knows (venues and bands), with how much scene lives
  /// there — the home-base sheet offers these before the free-text field.
  List<({String name, String sub})> get knownAreas {
    final bandCounts = <String, int>{};
    for (final id in exploreBandIds) {
      final area = band(id)?.area;
      if (area != null && area.isNotEmpty) {
        bandCounts[area] = (bandCounts[area] ?? 0) + 1;
      }
    }
    final venueCounts = <String, int>{};
    for (final venue in venues) {
      if (venue.area.isNotEmpty) {
        venueCounts[venue.area] = (venueCounts[venue.area] ?? 0) + 1;
      }
    }

    String count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';
    final names = {...bandCounts.keys, ...venueCounts.keys}.toList()
      ..sort((a, b) => (bandCounts[b] ?? 0).compareTo(bandCounts[a] ?? 0));
    return [
      for (final name in names)
        (
          name: name,
          sub:
              '${count(bandCounts[name] ?? 0, 'band')} · '
              '${count(venueCounts[name] ?? 0, 'venue')}',
        ),
      if (nbArea case final area? when !names.contains(area))
        (name: area, sub: 'Added by you'),
    ];
  }

  Future<void> createBand() async {
    if (_nbSaving) return;
    if (!canCreateBand) {
      say('Add ${bandMissing.join(' + ')} first. Tap any line.');
      return;
    }

    _nbSaving = true;
    notifyListeners();
    final name = nbName.trim();
    try {
      if (_nbBandId case final existingId?) {
        // "Keep editing" after a successful create: save onto the same band.
        await saveBandProfile(
          BandProfileUpdate(
            bandId: existingId,
            name: name,
            genres: List.of(nbGenres),
            area: nbArea!,
            bio: nbBio,
            linkIg: nbIg,
            linkBc: nbBc,
            linkYt: nbYt,
            credits: nbCredits,
          ),
        );
      } else {
        final created = await repository.createBand(
          name: name,
          genres: List.of(nbGenres),
          bio: nbBio.trim(),
          area: nbArea!,
          linkIg: nbIg.trim().isEmpty ? null : nbIg.trim(),
          linkBc: nbBc.trim().isEmpty ? null : nbBc.trim(),
          linkYt: nbYt.trim().isEmpty ? null : nbYt.trim(),
          credits: nbCredits.trim().isEmpty ? null : nbCredits.trim(),
        );
        final band = created.band;
        bandId = band.id;
        _bands[band.id] = band;
        _bandRoles[band.id] = 'admin';
        if (!myBands.contains(band.id)) myBands = [...myBands, band.id];
        _nbBandId = band.id;
        _nbCreatedSlug = created.slug;
      }
    } on Exception catch (error) {
      logError('createBand', error);
      say(genericErrorMessage);
      return;
    } finally {
      // Notifies on the failure path too, so the bar leaves its pending state
      // whichever way the save ended.
      _nbSaving = false;
      notifyListeners();
    }

    final photo = nbPhoto;
    final media = _media;
    if (photo != null && media != null) {
      unawaited(_uploadBandPhoto(bandId, photo));
    }
    nbCreated = true;
    notifyListeners();
    unawaited(refreshBandSetupStatus(bandId));
    _refreshExploreBands();
  }

  Future<void> _uploadBandPhoto(String bandId, PickedMedia photo) async {
    final media = _media;
    if (media == null) return;

    nbPhotoUploading = true;
    nbPhotoError = null;
    notifyListeners();

    final mediaId = await media.uploadHeldPhoto(bandId, photo);
    if (mediaId == null) {
      nbPhotoUploading = false;
      nbPhotoError = 'upload failed';
      notifyListeners();
      say("Band's up. The photo didn't upload. Add it from Media.");
      return;
    }

    await media.setHero(bandId, mediaId);
    nbPhotoUploading = false;
    notifyListeners();
    unawaited(refreshBandSetupStatus(bandId));
  }

  Future<void> retryNbPhoto() async {
    final photo = nbPhoto;
    if (photo == null) return;
    await _uploadBandPhoto(bandId, photo);
  }

  /// "Keep editing" — back to the tape with everything still filled in.
  void editCreatedBand() => _set(() => nbCreated = false);

  void makeAnotherBand() => _set(_resetBandForm);

  /// The created view's headline action: straight into posting a gig.
  void postFirstGig() {
    resetTo(Screen.bandDash);
    startGigCreate();
  }

  /// The created view's quiet exit, for people who just want to see the band
  /// they made. The header ✕ is gone on that screen, and web has no system
  /// back, so without this the only ways off are the three loud ones.
  void openCreatedBand() => resetTo(Screen.bandDash);

  // ========================= gig create =========================

  void startGigCreate() {
    _resetGigForm();
    go(Screen.gigCreate);
  }

  void setGfName(String v) => _set(() => gfName = v);

  /// Tapping the selected day again clears it, as in the design.
  void setGfDate(DateTime? v) =>
      _set(() => gfDate = v == null || v == gfDate ? null : v);

  void setGfDoors(TimeOfDay v) => _set(() => gfDoors = v);

  void setGfVenue(String v) => _set(() => gfVenueId = v);

  void setGfPrice(String v) => _set(() => gfPrice = v);

  void setGfTix(Ticketing t) => _set(() => gfTix = t);

  void setGfAgeRequirement(AgeRequirement value) =>
      _set(() => gfAgeRequirement = value);

  void setGfCap(String v) => _set(() => gfCap = v);

  void setGfExt(String v) => _set(() => gfExt = v);

  void setGfFly(String key) => _set(() => gfFly = key);

  void setGfFlyerArt(PickedMedia? art) => _set(() {
    gfFlyerArt = art;
    gfFlyerStorageId = null;
  });

  void setGfFlyerUploading(bool v) => _set(() => gfFlyerUploading = v);

  void setGfFlyerStorageId(String? id) => _set(() => gfFlyerStorageId = id);

  void toggleGfOverlay() => _set(() => gfOverlay = !gfOverlay);

  /// Band-supplied art rather than one of the presses.
  bool get gfCustomFlyer => gfFly == 'custom';

  /// Presses always print the details; uploaded art can show clean.
  bool get gfShowOverlay => !gfCustomFlyer || gfOverlay;

  String get gfDoorsLabel => timeLabel(gfDoors);

  /// "Sat Aug 15", or empty until a day is picked.
  String get gfDateLabel => gfDate == null ? '' : dateLabel(gfDate!);

  bool get canPublishGig =>
      gfName.trim().isNotEmpty &&
      gfDate != null &&
      gfVenueId != null &&
      (!gfCustomFlyer || gfFlyerStorageId != null);

  /// What the publish bar still asks for, in reading order.
  List<String> get gigMissing => [
    if (gfName.trim().isEmpty) 'a name',
    if (gfDate == null) 'a date',
    if (gfVenueId == null) 'a venue',
    if (gfCustomFlyer && gfFlyerStorageId == null) 'your flyer art',
  ];

  String get gigUrl {
    final slug = _slugify(gfName.trim().isEmpty ? 'your-gig' : gfName.trim());
    return 'earplug.app/g/${slug.isEmpty ? 'your-gig' : slug}';
  }

  Future<void> publishGig() async {
    if (gfFlyerUploading) {
      say('Still uploading your flyer. One sec.');
      return;
    }

    final date = gfDate;
    if (!canPublishGig || date == null) {
      say('Add ${gigMissing.join(' + ')} first. Tap any card.');
      return;
    }

    final venueId = gfVenueId!;
    try {
      await repository.publishGig(
        bandId: bandId,
        title: gfName.trim(),
        venueId: venueId,
        price: gfPrice == 'FREE' ? 0 : int.parse(gfPrice.substring(1)),
        startsAt: DateTime(
          date.year,
          date.month,
          date.day,
          gfDoors.hour,
          gfDoors.minute,
        ).millisecondsSinceEpoch,
        doorsTime: gfDoorsLabel,
        flyKey: gfFly,
        flyStorageId: gfFlyerStorageId,
        ticketing: gfTix,
        ageRequirement: gfAgeRequirement,
        externalUrl: gfExt.isEmpty ? null : gfExt,
        cap: gfCap,
      );
    } on Exception catch (error) {
      logError('publishGig', error);
      say(genericErrorMessage);
      return;
    }

    // A publish beyond the bounded global feed may not change its payload, so
    // do not rely on the feed subscription alone to retire this venue cache.
    _invalidateVenueDetails({venueId});
    gfPublished = true;
    notifyListeners();
    unawaited(refreshBandSetupStatus(bandId));
  }

  /// "Keep editing" — back to the form with everything still filled in.
  void editPublishedGig() => _set(() => gfPublished = false);

  void makeAnotherGig() => _set(_resetGigForm);

  /// The ✕ in the header: done here, back to the gig manager.
  void closeGigCreate() => _set(() {
    _resetGigForm();
    _stack = const [ScreenEntry(Screen.gigMgr)];
  });

  void _resetGigForm() {
    gfName = '';
    gfDate = null;
    gfDoors = const TimeOfDay(hour: 20, minute: 0);
    gfVenueId = null;
    gfPrice = 'FREE';
    gfTix = Ticketing.rsvp;
    gfAgeRequirement = AgeRequirement.allAges;
    gfCap = 'No cap';
    gfExt = '';
    gfFly = 'xerox';
    gfOverlay = true;
    gfFlyerArt = null;
    gfFlyerStorageId = null;
    gfFlyerUploading = false;
    gfPublished = false;
  }
}

/// The URL form of a name: lowercased, with every run of anything else a dash.
String _slugify(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

/// "Sat Aug 15".
String dateLabel(DateTime d) =>
    '${weekdayNames[d.weekday - 1]} ${monthNames[d.month - 1]} ${d.day}';

/// "Aug 2026".
String monthLabel(DateTime d) => '${monthNames[d.month - 1]} ${d.year}';

/// "8PM" / "9:30PM" — the form the rest of the app stores doors times in.
String timeLabel(TimeOfDay t) {
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final minutes = t.minute == 0
      ? ''
      : ':${t.minute.toString().padLeft(2, '0')}';
  return '$hour$minutes${t.hour < 12 ? 'AM' : 'PM'}';
}

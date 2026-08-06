import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
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
import 'services/media_picker.dart';

enum Screen {
  home,
  gig,
  band,
  explore,
  myGigs,
  auth,
  bandCreate,
  bandDash,
  bandEdit,
  bandMedia,
  gigMgr,
  gigCreate,
  analytics,
}

class ScreenEntry {
  final Screen screen;
  final String? param; // gig id or band id where relevant

  const ScreenEntry(this.screen, [this.param]);
}

enum DateFilter { all, tonight, week }

enum PendingKind { rsvp, follow, myGigs, band }

enum DataStatus { connecting, ready, error }

/// The band-profile fields the edit screen writes one keystroke at a time.
enum _BandField { bio, linkIg, linkBc }

class PendingAuth {
  final PendingKind kind;
  final String? id;

  const PendingAuth(this.kind, [this.id]);
}

class AppState extends ChangeNotifier {
  AppState({EarplugRepository? repository, AuthService? auth})
    : this._(auth ?? FakeAuthService(), repository);

  AppState._(AuthService resolvedAuth, EarplugRepository? providedRepository)
    : auth = resolvedAuth,
      repository = providedRepository ?? DemoRepository(auth: resolvedAuth),
      // Only a real backend has a connection to wait on; the demo data is
      // already in memory, so it must not show the connecting screen.
      _dataStatus = providedRepository is ConvexRepository
          ? DataStatus.connecting
          : DataStatus.ready {
    authed = auth.signedIn;
    if (authed) {
      authStep = 2;
      unawaited(_ensureUser());
    }
    _authSubscription = auth.signedInChanges.listen(_handleAuthChange);
    _subscribeToFeed();
    _interactionsSubscription = repository.myInteractions().listen(
      _cacheInteractions,
      onError: (Object error) => logError('myInteractions', error),
    );
    _bandsSubscription = repository.myBands().listen(
      _cacheMemberships,
      onError: (Object error) => logError('myBands', error),
    );
  }

  final EarplugRepository repository;
  final AuthService auth;

  StreamSubscription<bool>? _authSubscription;
  StreamSubscription<FeedSnapshot>? _feedSubscription;
  StreamSubscription<Interactions>? _interactionsSubscription;
  StreamSubscription<List<BandMembership>>? _bandsSubscription;
  bool _disposed = false;

  DataStatus _dataStatus;
  DataStatus get dataStatus => _dataStatus;
  String? dataError;

  List<Gig> _allGigs = const [];
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

  BandMediaController? _media;

  /// What the user typed into the band-edit fields, shown until the server has
  /// it. Dropped if the write fails, so nothing on screen looks saved when it
  /// isn't.
  final Map<(String bandId, _BandField field), String> _bandEdits = {};

  /// One pending write per field. Typing restarts it, so a burst of keystrokes
  /// costs one mutation instead of one each.
  final Map<(String bandId, _BandField field), Timer> _bandEditTimers = {};

  static const _bandEditDebounce = Duration(milliseconds: 400);

  // ---- navigation
  List<ScreenEntry> _stack = const [ScreenEntry(Screen.home)];
  ScreenEntry get current => _stack.last;
  bool get canGoBack => _stack.length > 1;

  // ---- session
  bool authed = false;
  PendingAuth? pending;
  int authStep = 1;
  final Set<String> userGenres = {};

  // ---- fan data
  Set<String> rsvps = {};
  Set<String> follows = {};
  Set<String> saved = {};
  int attended = 0;
  List<PastGig> history = const [];
  UserProfile? profile;

  /// Legacy-imported count and RSVP-derived history can disagree; show
  /// whichever credits the fan more.
  int get gigsAttended => attended > history.length ? attended : history.length;

  // ---- home filters
  bool mapMode = false;
  String city = 'sf'; // 'sf' | 'oak'
  DateFilter fDate = DateFilter.all;
  bool fFree = false;
  String? fGenre;

  // ---- explore
  String query = '';
  List<String> exploreBandIds = [];

  // ---- band membership
  List<String> myBands = [];
  String bandId = '';

  // ---- band create form (the cassette canvas)
  String nbName = '';
  final List<String> nbGenres = []; // insertion order shows on the tape, max 3
  String? nbArea;
  String nbBio = '';
  final List<String> nbInvites = [];
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
    _toastTimer?.cancel();
    for (final timer in _bandEditTimers.values) {
      timer.cancel();
    }
    _bandEditTimers.clear();
    unawaited(_authSubscription?.cancel());
    unawaited(_feedSubscription?.cancel());
    unawaited(_interactionsSubscription?.cancel());
    unawaited(_bandsSubscription?.cancel());
    super.dispose();
  }

  /// Assigns, then notifies — the shape every plain form setter has.
  void _set(void Function() assign) {
    assign();
    notifyListeners();
  }

  void _handleAuthChange(bool signedIn) {
    authed = signedIn;
    if (signedIn) {
      authStep = 2;
      unawaited(_ensureUser());
    } else {
      profile = null;
      unawaited(
        repository.refreshAuth().catchError(
          (Object error) => logError('refreshAuth', error),
        ),
      );
    }
    notifyListeners();
  }

  Future<void> _ensureUser() async {
    try {
      // The websocket must carry the new identity before the mutation runs.
      await repository.refreshAuth();
      await repository.ensureUser(name: auth.displayName);
      await _refreshProfile();
      unawaited(_refreshHistory());
    } catch (error) {
      logError('ensureUser', error);
      say(genericErrorMessage);
    }
  }

  Future<void> _refreshHistory() async {
    try {
      final loaded = await repository.history();
      if (!authed) return;
      history = loaded;
      notifyListeners();
    } catch (error) {
      logError('history', error);
    }
  }

  Future<void> _refreshProfile() async {
    try {
      final loadedProfile = await repository.me();
      if (!authed) return;
      profile = loadedProfile;
      notifyListeners();
    } catch (error) {
      logError('me', error);
    }
  }

  void _subscribeToFeed() {
    _feedSubscription = repository.feed().listen(
      (snapshot) {
        _allGigs = List<Gig>.of(snapshot.gigs);
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
    unawaited(_refreshExploreBands());
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

  Future<void> _refreshExploreBands() async {
    try {
      final bands = await repository.searchBands('');
      exploreBandIds = [for (final band in bands) band.id];
      for (final band in bands) {
        _bands[band.id] = band.copyWith(
          upcoming: _bands[band.id]?.upcoming ?? const [],
        );
      }
      notifyListeners();
    } catch (error) {
      logError('searchBands', error);
    }
  }

  void _cacheInteractions(Interactions interactions) {
    rsvps = Set<String>.of(interactions.rsvpGigIds);
    follows = Set<String>.of(interactions.followBandIds);
    saved = Set<String>.of(interactions.savedGigIds);
    attended = interactions.attendedCount;
    notifyListeners();
  }

  void _cacheMemberships(List<BandMembership> memberships) {
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

  // ========================= navigation =========================

  void go(Screen s, [String? param]) =>
      _set(() => _stack = [..._stack, ScreenEntry(s, param)]);

  void back() {
    if (_stack.length > 1) {
      _set(() => _stack = _stack.sublist(0, _stack.length - 1));
    }
  }

  void resetTo(Screen s) => _set(() => _stack = [ScreenEntry(s)]);

  void openGig(String id) {
    if (current.screen == Screen.gig && current.param == id) return;
    go(Screen.gig, id);
  }

  void openBand(String id) => go(Screen.band, id);

  void openBandMedia() => go(Screen.bandMedia, bandId);

  void openMyGigsTab() {
    if (authed) {
      unawaited(_refreshHistory());
      resetTo(Screen.myGigs);
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
    authStep = 1;
    go(Screen.auth);
  }

  Future<void> login() async => auth.signInDemo();

  Future<void> signOut() async {
    await auth.signOut();
    rsvps = {};
    follows = {};
    saved = {};
    attended = 0;
    history = const [];
    profile = null;
    authed = false;
    // Per-band caches outlive the session otherwise, so signing in as someone
    // else in the same process would show the previous user's unsaved edits —
    // or, worse, write them to their band.
    for (final timer in _bandEditTimers.values) {
      timer.cancel();
    }
    _bandEditTimers.clear();
    _bandEdits.clear();
    _bandRoles.clear();
    _media?.clearForSignOut();
    resetTo(Screen.home);
    say('Signed out.');
  }

  void toggleUserGenre(String g) => _set(
    () => userGenres.contains(g) ? userGenres.remove(g) : userGenres.add(g),
  );

  /// Where [leaveAuth] lands, decided by [commitAuth]; null pops back to
  /// wherever the auth gate was opened from.
  Screen? _postAuthScreen;

  /// The durable half of finishing auth: persists genre picks and completes
  /// the action that triggered the gate. Runs before any celebration delay so
  /// backing out (or being killed) mid-splash can't drop the pending action.
  void commitAuth() {
    unawaited(
      repository.setGenres(userGenres.toList()).catchError((Object error) {
        logError('setGenres', error);
        say(genericErrorMessage);
      }),
    );

    final p = pending;
    pending = null;
    switch (p?.kind) {
      case PendingKind.rsvp:
        _postAuthScreen = null;
        toggleRsvp(p!.id!);
      case PendingKind.follow:
        _postAuthScreen = null;
        toggleFollow(p!.id!);
      case PendingKind.myGigs:
        _postAuthScreen = Screen.myGigs;
        final name = (profile?.name ?? auth.displayName)?.trim();
        say(
          name == null || name.isEmpty
              ? 'Welcome back.'
              : 'Welcome back, ${name.split(' ').first}.',
        );
      case PendingKind.band:
        _postAuthScreen = Screen.bandDash;
      case null:
        _postAuthScreen = null;
    }
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
  }

  void finishAuth() {
    commitAuth();
    leaveAuth();
  }

  // ========================= fan actions =========================

  /// Flips [id] in [ids] on screen straight away and persists in the
  /// background; a rejected write puts the flip back and says so. Returns
  /// whether [id] ended up on.
  bool _toggleOptimistically(
    Set<String> ids,
    String id,
    Future<void> Function(String) persist,
  ) {
    final wasOn = ids.contains(id);
    wasOn ? ids.remove(id) : ids.add(id);
    notifyListeners();
    unawaited(
      persist(id).catchError((Object error) {
        logError('toggle $id', error);
        wasOn ? ids.add(id) : ids.remove(id);
        say(genericErrorMessage); // notifies, so the roll-back shows
      }),
    );
    return !wasOn;
  }

  void toggleRsvp(String id) {
    final nowGoing = _toggleOptimistically(rsvps, id, repository.toggleRsvp);
    say(nowGoing ? "You're on the list. QR is in My Gigs." : 'RSVP removed.');
  }

  void requestRsvp(String id) {
    if (authed) {
      toggleRsvp(id);
    } else {
      needAuth(PendingAuth(PendingKind.rsvp, id));
    }
  }

  void toggleFollow(String id) {
    if (_toggleOptimistically(follows, id, repository.toggleFollow)) {
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
    _toggleOptimistically(saved, id, repository.toggleSave);
  }

  // ========================= filters =========================

  void setMapMode(bool on) => _set(() => mapMode = on);

  void setCity(String c) {
    city = c;
    say(
      c == 'oak'
          ? 'Showing gigs near Temescal.'
          : 'Showing gigs near the Mission.',
    );
  }

  void toggleDateFilter(DateFilter f) =>
      _set(() => fDate = fDate == f ? DateFilter.all : f);

  void toggleFree() => _set(() => fFree = !fFree);

  void toggleGenre(String g) => _set(() => fGenre = fGenre == g ? null : g);

  void setQuery(String q) => _set(() => query = q);

  // ========================= data access =========================

  List<Gig> get allGigs => _allGigs;

  Gig? gig(String id) {
    for (final g in allGigs) {
      if (g.id == id) return g;
    }
    return null;
  }

  Band? band(String id) => _bands[id];

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

  Venue venue(String id) => _venues[id] ?? _venueDirectory[id] ?? _unknownVenue;

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

  String distanceOf(Venue v) => city == 'oak' ? v.distOak : v.distSF;

  List<Gig> get feed => allGigs.where((g) {
    if (fDate == DateFilter.tonight && g.when != GigWhen.tonight) return false;
    if (fDate == DateFilter.week && g.when == GigWhen.later) return false;
    if (fFree && !g.free) return false;
    if (fGenre != null && !g.genres.contains(fGenre)) return false;
    return true;
  }).toList();

  /// RSVP count shown to bands: base demo count plus this user's RSVP.
  int rsvpCount(Gig g) => g.going + (rsvps.contains(g.id) ? 1 : 0);

  /// The user's own unsaved edit if there is one, else what the server holds.
  String _bandFieldFor(String id, _BandField field, String? stored) =>
      _bandEdits[(id, field)] ?? stored ?? '';

  String bioFor(String id) => _bandFieldFor(id, _BandField.bio, band(id)?.bio);

  String linkIgFor(String id) =>
      _bandFieldFor(id, _BandField.linkIg, band(id)?.linkIg);

  String linkBcFor(String id) =>
      _bandFieldFor(id, _BandField.linkBc, band(id)?.linkBc);

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
  }

  void toFanView() => resetTo(Screen.home);

  void setBandBio(String v) => _editBandField(_BandField.bio, v);

  void setLinkIg(String v) => _editBandField(_BandField.linkIg, v);

  void setLinkBc(String v) => _editBandField(_BandField.linkBc, v);

  /// Shows what was typed at once, then persists once typing pauses. These are
  /// wired to `onChanged`, so writing on every keystroke would be one mutation
  /// per character.
  void _editBandField(_BandField field, String value) {
    final id = bandId;
    if (id.isEmpty) return;

    final key = (id, field);
    _bandEdits[key] = value;
    notifyListeners();

    _bandEditTimers.remove(key)?.cancel();
    _bandEditTimers[key] = Timer(_bandEditDebounce, () {
      _bandEditTimers.remove(key);
      unawaited(_persistBandField(id, field, value));
    });
  }

  Future<void> _persistBandField(
    String id,
    _BandField field,
    String value,
  ) async {
    try {
      await switch (field) {
        _BandField.bio => repository.updateBandProfile(bandId: id, bio: value),
        _BandField.linkIg => repository.updateBandProfile(
          bandId: id,
          linkIg: value,
        ),
        _BandField.linkBc => repository.updateBandProfile(
          bandId: id,
          linkBc: value,
        ),
      };
    } catch (error) {
      logError('updateBandProfile', error);
      // Keeping the override would leave text on screen that was never saved.
      // Dropping it falls back to the server's value, so what is shown is what
      // exists — unless the user has typed on since, which supersedes this.
      if (_bandEdits[(id, field)] == value) _bandEdits.remove((id, field));
      say(genericErrorMessage); // notifies, so the drop shows
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
    nbInvites.clear();
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
      say('Three genres max — it keeps discovery honest.');
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

  void addNbInvite(String raw) {
    final n = raw.trim();
    if (n.isEmpty) return;
    final handle = n.startsWith('@') ? n : '@$n';
    if (nbInvites.contains(handle)) return;
    _set(() => nbInvites.add(handle));
  }

  void removeNbInvite(String handle) => _set(() => nbInvites.remove(handle));

  bool get canCreateBand =>
      nbName.trim().isNotEmpty && nbGenres.isNotEmpty && nbArea != null;

  /// What the create bar still asks for, in reading order.
  List<String> get bandMissing => [
    if (nbName.trim().isEmpty) 'a name',
    if (nbGenres.isEmpty) 'a genre',
    if (nbArea == null) 'a home base',
  ];

  /// How full the tape winds: the five liner-note lines, equally weighted.
  double get nbCompletion {
    final done = [
      nbName.trim().isNotEmpty,
      nbGenres.isNotEmpty,
      nbArea != null,
      nbBio.trim().isNotEmpty,
      nbInvites.isNotEmpty ||
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
      say('Add ${bandMissing.join(' + ')} first — tap any line.');
      return;
    }

    _nbSaving = true;
    notifyListeners();
    final name = nbName.trim();
    try {
      if (_nbBandId case final existingId?) {
        // "Keep editing" after a successful create: save onto the same band.
        await repository.updateBandProfile(
          bandId: existingId,
          name: name,
          genres: List.of(nbGenres),
          area: nbArea,
          bio: nbBio.trim(),
          inviteHandles: List.of(nbInvites),
          linkIg: nbIg.trim(),
          linkBc: nbBc.trim(),
          linkYt: nbYt.trim(),
        );
      } else {
        final created = await repository.createBand(
          name: name,
          genres: List.of(nbGenres),
          bio: nbBio.trim(),
          inviteHandles: List.of(nbInvites),
          area: nbArea,
          linkIg: nbIg.trim().isEmpty ? null : nbIg.trim(),
          linkBc: nbBc.trim().isEmpty ? null : nbBc.trim(),
          linkYt: nbYt.trim().isEmpty ? null : nbYt.trim(),
        );
        bandId = created.bandId;
        _nbBandId = created.bandId;
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
    unawaited(_refreshExploreBands());
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
      say("Band's up. The photo didn't upload — add it from Media.");
      return;
    }

    await media.setHero(bandId, mediaId);
    nbPhotoUploading = false;
    notifyListeners();
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
      say('Still uploading your flyer — one sec.');
      return;
    }

    final date = gfDate;
    if (!canPublishGig || date == null) {
      say('Add ${gigMissing.join(' + ')} first — tap any card.');
      return;
    }

    try {
      await repository.publishGig(
        bandId: bandId,
        title: gfName.trim(),
        venueId: gfVenueId!,
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
        externalUrl: gfExt.isEmpty ? null : gfExt,
        cap: gfCap,
      );
    } on Exception catch (error) {
      logError('publishGig', error);
      say(genericErrorMessage);
      return;
    }

    gfPublished = true;
    notifyListeners();
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

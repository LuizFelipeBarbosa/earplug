import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:latlong2/latlong.dart';

import 'data/convex_repository.dart';
import 'data/demo_repository.dart';
import 'data/repository.dart';
import 'demo_data.dart';
import 'models.dart';
import 'services/auth_service.dart';

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
      onError: (_) {},
    );
    _bandsSubscription = repository.myBands().listen(
      _cacheMemberships,
      onError: (_) {},
    );
  }

  final EarplugRepository repository;
  final AuthService auth;

  StreamSubscription<bool>? _authSubscription;
  StreamSubscription<FeedSnapshot>? _feedSubscription;
  StreamSubscription<Interactions>? _interactionsSubscription;
  StreamSubscription<List<BandMembership>>? _bandsSubscription;

  DataStatus _dataStatus;
  DataStatus get dataStatus => _dataStatus;
  String? dataError;

  List<Gig> _allGigs = const [];
  Map<String, Band> _bands = {};
  Map<String, Venue> _venues = const {};
  final Map<String, String> _bandBioOverrides = {};
  final Map<String, String> _bandLinkIgOverrides = {};
  final Map<String, String> _bandLinkBcOverrides = {};
  final Map<String, List<VideoClip>> _videoCache = {};
  final Set<String> _videoLoads = {};

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
  UserProfile? profile;

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

  // ---- band create wizard
  int nbStep = 1;
  String nbName = '';
  final Set<String> nbGenres = {};
  String nbBio = '';
  final List<String> nbInvites = [];

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
  bool gfPublished = false;

  // ---- toast
  String toast = '';
  Timer? _toastTimer;

  @override
  void dispose() {
    _toastTimer?.cancel();
    unawaited(_authSubscription?.cancel());
    unawaited(_feedSubscription?.cancel());
    unawaited(_interactionsSubscription?.cancel());
    unawaited(_bandsSubscription?.cancel());
    super.dispose();
  }

  void _handleAuthChange(bool signedIn) {
    authed = signedIn;
    if (signedIn) {
      authStep = 2;
      unawaited(_ensureUser());
    } else {
      profile = null;
      unawaited(_refreshConvexAuth());
    }
    notifyListeners();
  }

  Future<void> _refreshConvexAuth() async {
    final repo = repository;
    if (repo is ConvexRepository) await repo.refreshAuth();
  }

  Future<void> _ensureUser() async {
    try {
      // The websocket must carry the new identity before the mutation runs.
      await _refreshConvexAuth();
      await repository.ensureUser(name: auth.displayName);
      await _refreshProfile();
    } catch (_) {
      say('Something broke — try again.');
    }
  }

  Future<void> _refreshProfile() async {
    try {
      final repo = repository;
      if (repo is ConvexRepository) {
        final loadedProfile = await repo.me();
        if (!authed) return;
        profile = loadedProfile;
        notifyListeners();
      }
    } catch (_) {}
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
    } catch (_) {}
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
      _bands[band.id] = band.copyWith(
        upcoming: _bands[band.id]?.upcoming ?? const [],
      );
    }
    notifyListeners();
  }

  // ========================= navigation =========================

  void go(Screen s, [String? param]) {
    _stack = [..._stack, ScreenEntry(s, param)];
    notifyListeners();
  }

  void back() {
    if (_stack.length > 1) {
      _stack = _stack.sublist(0, _stack.length - 1);
      notifyListeners();
    }
  }

  void resetTo(Screen s) {
    _stack = [ScreenEntry(s)];
    notifyListeners();
  }

  void openGig(String id) {
    if (current.screen == Screen.gig && current.param == id) return;
    go(Screen.gig, id);
  }

  void openBand(String id) => go(Screen.band, id);

  void openMyGigsTab() {
    if (authed) {
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

  // ========================= auth =========================

  void needAuth(PendingAuth p) {
    pending = p;
    authStep = 1;
    go(Screen.auth);
  }

  String get authTitle => switch (pending?.kind) {
    PendingKind.rsvp => 'Create an account to RSVP',
    PendingKind.follow => 'Create an account to follow bands',
    PendingKind.myGigs => 'Log in to see your gigs',
    PendingKind.band => 'Log in to run your band',
    null => 'Join the scene',
  };

  Future<void> login() async => await auth.signInDemo();

  Future<void> signOut() async {
    await auth.signOut();
    rsvps = {};
    follows = {};
    saved = {};
    attended = 0;
    authed = false;
    resetTo(Screen.home);
    say('Signed out.');
  }

  void toggleUserGenre(String g) {
    userGenres.contains(g) ? userGenres.remove(g) : userGenres.add(g);
    notifyListeners();
  }

  void finishAuth() {
    if (repository is ConvexRepository) {
      unawaited(
        repository.setGenres(userGenres.toList()).catchError((Object _) {
          say('Something broke — try again.');
        }),
      );
    }

    final p = pending;
    pending = null;
    switch (p?.kind) {
      case PendingKind.rsvp:
        back();
        toggleRsvp(p!.id!);
      case PendingKind.follow:
        back();
        toggleFollow(p!.id!);
      case PendingKind.myGigs:
        resetTo(Screen.myGigs);
        say('Welcome back, Sam.');
      case PendingKind.band:
        resetTo(Screen.bandDash);
      case null:
        back();
    }
  }

  // ========================= fan actions =========================

  void toggleRsvp(String id) {
    final wasOn = rsvps.contains(id);
    wasOn ? rsvps.remove(id) : rsvps.add(id);
    notifyListeners();
    say(wasOn ? 'RSVP removed.' : "You're on the list. QR is in My Gigs.");
    unawaited(
      repository.toggleRsvp(id).catchError((Object _) {
        wasOn ? rsvps.add(id) : rsvps.remove(id);
        say('Something broke — try again.');
        notifyListeners();
      }),
    );
  }

  void requestRsvp(String id) {
    if (authed) {
      toggleRsvp(id);
    } else {
      needAuth(PendingAuth(PendingKind.rsvp, id));
    }
  }

  void toggleFollow(String id) {
    final wasOn = follows.contains(id);
    wasOn ? follows.remove(id) : follows.add(id);
    notifyListeners();
    if (!wasOn) {
      final name = band(id)?.name;
      say(name == null ? 'Band followed.' : 'Following $name.');
    }
    unawaited(
      repository.toggleFollow(id).catchError((Object _) {
        wasOn ? follows.add(id) : follows.remove(id);
        say('Something broke — try again.');
        notifyListeners();
      }),
    );
  }

  void requestFollow(String id) {
    if (authed) {
      toggleFollow(id);
    } else {
      needAuth(PendingAuth(PendingKind.follow, id));
    }
  }

  void toggleSave(String id) {
    final wasOn = saved.contains(id);
    wasOn ? saved.remove(id) : saved.add(id);
    notifyListeners();
    unawaited(
      repository.toggleSave(id).catchError((Object _) {
        wasOn ? saved.add(id) : saved.remove(id);
        say('Something broke — try again.');
        notifyListeners();
      }),
    );
  }

  // ========================= filters =========================

  void setMapMode(bool on) {
    mapMode = on;
    notifyListeners();
  }

  void setCity(String c) {
    city = c;
    say(
      c == 'oak'
          ? 'Showing gigs near Temescal.'
          : 'Showing gigs near the Mission.',
    );
  }

  void toggleDateFilter(DateFilter f) {
    fDate = fDate == f ? DateFilter.all : f;
    notifyListeners();
  }

  void toggleFree() {
    fFree = !fFree;
    notifyListeners();
  }

  void toggleGenre(String g) {
    fGenre = fGenre == g ? null : g;
    notifyListeners();
  }

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  // ========================= data access =========================

  List<Gig> get allGigs => _allGigs;

  Gig? gig(String id) {
    for (final g in allGigs) {
      if (g.id == id) return g;
    }
    return null;
  }

  Band? band(String id) => _bands[id];

  Venue venue(String id) => _venues[id] ?? _unknownVenue;

  /// Every venue the feed knows about — shared records bands pick from.
  List<Venue> get venues => _venues.values.toList();

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

  List<VideoClip> videosFor(String bandId) {
    final cached = _videoCache[bandId];
    if (cached != null) return cached;

    if (_videoLoads.add(bandId)) {
      unawaited(_loadVideos(bandId));
    }
    return const <VideoClip>[];
  }

  String bioFor(String id) {
    return _bandBioOverrides[id] ?? band(id)?.bio ?? '';
  }

  String linkIgFor(String id) {
    return _bandLinkIgOverrides[id] ?? band(id)?.linkIg ?? '';
  }

  String linkBcFor(String id) {
    return _bandLinkBcOverrides[id] ?? band(id)?.linkBc ?? '';
  }

  Future<void> _loadVideos(String bandId) async {
    try {
      _videoCache[bandId] = await repository.videosFor(bandId);
      notifyListeners();
    } catch (_) {
    } finally {
      _videoLoads.remove(bandId);
    }
  }

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
  bool get bandIsNew => bandId.startsWith('nb');

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

  void setBandBio(String v) {
    if (bandId.isEmpty) return;
    _bandBioOverrides[bandId] = v;
    unawaited(
      repository
          .updateBandProfile(bandId: bandId, bio: v)
          .catchError((Object _) {}),
    );
    notifyListeners();
  }

  void setLinkIg(String v) {
    if (bandId.isEmpty) return;
    _bandLinkIgOverrides[bandId] = v;
    unawaited(
      repository
          .updateBandProfile(bandId: bandId, linkIg: v)
          .catchError((Object _) {}),
    );
    notifyListeners();
  }

  void setLinkBc(String v) {
    if (bandId.isEmpty) return;
    _bandLinkBcOverrides[bandId] = v;
    unawaited(
      repository
          .updateBandProfile(bandId: bandId, linkBc: v)
          .catchError((Object _) {}),
    );
    notifyListeners();
  }

  void pinVideo(int index) {
    final activeBandId = bandId;
    if (activeBandId.isEmpty) return;
    final vids = videosFor(activeBandId);
    if (index < 0 || index >= vids.length) return;
    unawaited(_pinVideo(activeBandId, vids[index].id));
  }

  void moveVideo(int index, int delta) {
    final activeBandId = bandId;
    if (activeBandId.isEmpty) return;
    final vids = videosFor(activeBandId);
    if (index < 0 || index >= vids.length) return;
    final direction = delta < 0 ? 'up' : 'down';
    unawaited(_moveVideo(activeBandId, vids[index].id, direction));
  }

  Future<void> _pinVideo(String bandId, String videoId) async {
    try {
      await repository.pinVideo(videoId);
      _videoCache[bandId] = await repository.videosFor(bandId);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _moveVideo(
    String bandId,
    String videoId,
    String direction,
  ) async {
    try {
      await repository.moveVideo(videoId, direction);
      _videoCache[bandId] = await repository.videosFor(bandId);
      notifyListeners();
    } catch (_) {}
  }

  // ========================= band create =========================

  void startBandCreate() {
    nbStep = 1;
    nbName = '';
    nbGenres.clear();
    nbBio = '';
    nbInvites.clear();
    go(Screen.bandCreate);
  }

  void setNbName(String v) {
    nbName = v;
    notifyListeners();
  }

  void setNbBio(String v) {
    nbBio = v;
    notifyListeners();
  }

  void toggleNbGenre(String g) {
    nbGenres.contains(g) ? nbGenres.remove(g) : nbGenres.add(g);
    notifyListeners();
  }

  void nbNext() {
    if (nbName.trim().isEmpty) return;
    nbStep = 2;
    notifyListeners();
  }

  void addNbInvite(String raw) {
    final n = raw.trim();
    if (n.isEmpty) return;
    nbInvites.add(n.startsWith('@') ? n : '@$n');
    notifyListeners();
  }

  String get nbSlug {
    final s = (nbName.isEmpty ? 'your-band' : nbName).toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '-',
    );
    return s.length > 20 ? s.substring(0, 20) : s;
  }

  Future<void> createBand() async {
    final name = nbName.trim();
    final createdBandId = await repository.createBand(
      name: name,
      genres: nbGenres.isEmpty ? const ['punk'] : nbGenres.toList(),
      bio: nbBio,
      inviteHandles: nbInvites,
    );
    bandId = createdBandId;
    await _refreshExploreBands();
    resetTo(Screen.bandDash);
    say('$name created — you are admin.');
  }

  // ========================= gig create =========================

  void startGigCreate() {
    _resetGigForm();
    go(Screen.gigCreate);
  }

  void setGfName(String v) {
    gfName = v;
    notifyListeners();
  }

  /// Tapping the selected day again clears it, as in the design.
  void setGfDate(DateTime? v) {
    gfDate = v == null || v == gfDate ? null : v;
    notifyListeners();
  }

  void setGfDoors(TimeOfDay v) {
    gfDoors = v;
    notifyListeners();
  }

  void setGfVenue(String v) {
    gfVenueId = v;
    notifyListeners();
  }

  void setGfPrice(String v) {
    gfPrice = v;
    notifyListeners();
  }

  void setGfTix(Ticketing t) {
    gfTix = t;
    notifyListeners();
  }

  void setGfCap(String v) {
    gfCap = v;
    notifyListeners();
  }

  void setGfExt(String v) {
    gfExt = v;
    notifyListeners();
  }

  void setGfFly(String key) {
    gfFly = key;
    notifyListeners();
  }

  void toggleGfOverlay() {
    gfOverlay = !gfOverlay;
    notifyListeners();
  }

  /// Band-supplied art rather than one of the presses.
  bool get gfCustomFlyer => gfFly == 'custom';

  /// Presses always print the details; uploaded art can show clean.
  bool get gfShowOverlay => !gfCustomFlyer || gfOverlay;

  String get gfDoorsLabel => timeLabel(gfDoors);

  /// "Sat Aug 15", or empty until a day is picked.
  String get gfDateLabel => gfDate == null ? '' : dateLabel(gfDate!);

  bool get canPublishGig =>
      gfName.trim().isNotEmpty && gfDate != null && gfVenueId != null;

  /// What the publish bar still asks for, in reading order.
  List<String> get gigMissing => [
    if (gfName.trim().isEmpty) 'a name',
    if (gfDate == null) 'a date',
    if (gfVenueId == null) 'a venue',
  ];

  String get gigUrl {
    final slug = (gfName.trim().isEmpty ? 'your-gig' : gfName.trim())
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return 'earplug.app/g/${slug.isEmpty ? 'your-gig' : slug}';
  }

  Future<void> publishGig() async {
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
        ticketing: gfTix,
        externalUrl: gfExt.isEmpty ? null : gfExt,
        cap: gfCap,
      );
    } on Exception catch (error) {
      debugPrint('publishGig failed: $error');
      say('Something broke — try again.');
      return;
    }

    gfPublished = true;
    notifyListeners();
  }

  /// "Keep editing" — back to the form with everything still filled in.
  void editPublishedGig() {
    gfPublished = false;
    notifyListeners();
  }

  void makeAnotherGig() {
    _resetGigForm();
    notifyListeners();
  }

  /// The ✕ in the header: done here, back to the gig manager.
  void closeGigCreate() {
    _resetGigForm();
    _stack = const [ScreenEntry(Screen.gigMgr)];
    notifyListeners();
  }

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
    gfPublished = false;
  }
}

const _weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "Sat Aug 15".
String dateLabel(DateTime d) =>
    '${_weekdayNames[d.weekday - 1]} ${_monthNames[d.month - 1]} ${d.day}';

/// "Aug 2026".
String monthLabel(DateTime d) => '${_monthNames[d.month - 1]} ${d.year}';

/// "8PM" / "9:30PM" — the form the rest of the app stores doors times in.
String timeLabel(TimeOfDay t) {
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final minutes = t.minute == 0
      ? ''
      : ':${t.minute.toString().padLeft(2, '0')}';
  return '$hour$minutes${t.hour < 12 ? 'AM' : 'PM'}';
}
